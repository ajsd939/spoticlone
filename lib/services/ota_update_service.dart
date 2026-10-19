import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'update_service.dart';

enum WindowsInstallationType {
  installed, // NSIS installed in %LOCALAPPDATA%\Nocrift
  portable,  // Running standalone from unzipped folder
}

// Downloads a GitHub release artifact with progress and hands it to
// the OS installer. Android: APK via system package installer
// (REQUEST_INSTALL_PACKAGES requested at runtime).
// Windows: detects installed vs portable and downloads either the
// Setup.exe (runs with /S silent update) or Portable.zip (extracts and updates).
class OtaUpdateService {
  /// Detects whether the Windows app was installed via NSIS installer
  /// or is running as a portable zip build.
  static WindowsInstallationType detectWindowsInstallationType() {
    if (!Platform.isWindows) return WindowsInstallationType.portable;
    try {
      final exePath = Platform.resolvedExecutable.toLowerCase();
      // NSIS installer defaults to %LOCALAPPDATA%\Nocrift\spoticlone.exe
      final localAppData =
          Platform.environment['LOCALAPPDATA']?.toLowerCase() ?? '';
      if (localAppData.isNotEmpty &&
          exePath.contains('$localAppData\\nocrift')) {
        return WindowsInstallationType.installed;
      }
      // Check if Uninstall.exe exists in the same directory as the executable
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final uninstaller =
          File('$exeDir${Platform.pathSeparator}Uninstall.exe');
      if (uninstaller.existsSync()) {
        return WindowsInstallationType.installed;
      }
    } catch (_) {}
    return WindowsInstallationType.portable;
  }

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
    final client = http.Client();
    try {
      final res = await client.send(req);
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
    } catch (_) {
      // Never leave a corrupt partial file behind for install() to open.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Opens the downloaded artifact with the OS default handler:
  /// package installer on Android, runs the Setup / Updater on Windows.
  Future<void> install(File file) async {
    if (Platform.isAndroid) {
      // Android 8+ unknown-sources install needs explicit consent.
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        final req = await Permission.requestInstallPackages.request();
        if (!req.isGranted) {
          throw Exception(
              'Allow "Install unknown apps" for Nocrift to update');
        }
      }
      final r = await OpenFilex.open(file.path);
      if (r.type != ResultType.done) {
        throw Exception('could not open installer: ${r.message}');
      }
    } else if (Platform.isWindows) {
      final isExe = file.path.toLowerCase().endsWith('.exe');
      final isZip = file.path.toLowerCase().endsWith('.zip');

      if (isExe) {
        // Run NSIS installer silently
        final result = await Process.start(
          file.path,
          ['/S'], // NSIS silent update flag
          runInShell: true,
        );
        if (result.pid == 0) {
          throw Exception('Failed to start installer');
        }
        // Exit app so installer can overwrite running files
        exit(0);
      } else if (isZip) {
        // Portable update: launch PowerShell script to unzip over current folder upon exit
        final currentExeDir = File(Platform.resolvedExecutable).parent.path;
        final currentExeName =
            Platform.resolvedExecutable.split(Platform.pathSeparator).last;
        final zipPath = file.path;

        final script = '''
Start-Sleep -Seconds 2
Expand-Archive -Path "$zipPath" -DestinationPath "$currentExeDir" -Force
Remove-Item "$zipPath" -Force -ErrorAction SilentlyContinue
Start-Process "$currentExeDir\\$currentExeName"
''';

        final scriptFile = File('$currentExeDir\\update_portable.ps1');
        await scriptFile.writeAsString(script);

        await Process.start(
          'powershell',
          ['-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', scriptFile.path],
          runInShell: true,
        );
        exit(0);
      } else {
        final r = await OpenFilex.open(file.path);
        if (r.type != ResultType.done) {
          throw Exception('could not open installer: ${r.message}');
        }
      }
    }
  }

  /// Full flow for the asset matching this platform & Windows build type.
  ReleaseAsset? assetForPlatform(ReleaseInfo rel) {
    if (Platform.isAndroid) {
      return rel.apk;
    } else if (Platform.isWindows) {
      final type = detectWindowsInstallationType();
      if (type == WindowsInstallationType.installed) {
        return rel.setupExe ?? rel.portableZip;
      } else {
        return rel.portableZip ?? rel.setupExe;
      }
    }
    return rel.setupExe ?? rel.apk;
  }
}
