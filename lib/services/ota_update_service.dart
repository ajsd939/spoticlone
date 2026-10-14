import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'update_service.dart';

// Downloads a GitHub release artifact with progress and hands it to
// the OS installer. Android: APK via system package installer
// (REQUEST_INSTALL_PACKAGES requested at runtime). Desktop: runs the
// Setup exe from Downloads.
class OtaUpdateService {
  /// 0.0..1 progress. Returns the saved file.
  Future<File> download(
    ReleaseAsset asset, {
    required String filename,
    void Function(double progress)? onProgress,
  }) async {
    final dir = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getDownloadsDirectory();
    if (dir == null) throw Exception('no storage directory');
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    final req = http.Request('GET', Uri.parse(asset.downloadUrl));
    final res = await http.Client().send(req);
    if (res.statusCode != 200) {
      throw Exception('download failed: HTTP ${res.statusCode}');
    }
    final total = res.contentLength ?? asset.size;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }
    onProgress?.call(1.0);
    return file;
  }

  /// Opens the downloaded artifact with the OS default handler:
  /// package installer on Android, runs the Setup on desktop.
  Future<void> install(File file) async {
    if (Platform.isAndroid) {
      // Android 8+ unknown-sources install needs explicit consent.
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        final req = await Permission.requestInstallPackages.request();
        if (!req.isGranted) {
          throw Exception(
              'Allow "Install unknown apps" for Spoticlone to update');
        }
      }
    }
    final r = await OpenFilex.open(file.path);
    if (r.type != ResultType.done) {
      throw Exception('could not open installer: ${r.message}');
    }
  }

  /// Full flow for the asset matching this platform, or null when the
  /// release carries no usable artifact.
  ReleaseAsset? assetForPlatform(ReleaseInfo rel) =>
      Platform.isAndroid ? rel.apk : rel.setupExe;
}
