import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

// GitHub Releases metadata for the OTA updater. Dependency-free,
// ad-free: plain api.github.com JSON, no third-party services.
class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;
  const ReleaseAsset(
      {required this.name, required this.downloadUrl, this.size = 0});

  factory ReleaseAsset.fromMap(Map<String, dynamic> m) => ReleaseAsset(
        name: (m['name'] ?? '').toString(),
        downloadUrl: (m['browser_download_url'] ?? '').toString(),
        size: (m['size'] ?? 0) as int? ?? 0,
      );
}

class ReleaseInfo {
  final String tag; // e.g. v1.2.0
  final String name;
  final String notes; // release body (markdown)
  final List<ReleaseAsset> assets;
  const ReleaseInfo(
      {required this.tag,
      required this.name,
      required this.notes,
      this.assets = const []});

  /// Android sideload artifact.
  ReleaseAsset? get apk {
    for (final a in assets) {
      if (a.name.toLowerCase().endsWith('.apk')) return a;
    }
    return null;
  }

  /// Windows Nullsoft installer artifact.
  ReleaseAsset? get setupExe {
    for (final a in assets) {
      final n = a.name.toLowerCase();
      if (n.endsWith('.exe') &&
          (n.contains('setup') || n.contains('installer'))) {
        return a;
      }
    }
    // Fallback: any exe (e.g. portable build).
    for (final a in assets) {
      if (a.name.toLowerCase().endsWith('.exe')) return a;
    }
    return null;
  }
}

class UpdateService {
  static const owner = 'ajsd939';
  static const repo = 'spoticlone';

  /// Latest published release, or null on network/parse failure.
  Future<ReleaseInfo?> latestRelease() async {
    try {
      final r = await http.get(Uri.parse(
          'https://api.github.com/repos/$owner/$repo/releases/latest'));
      if (r.statusCode != 200) return null;
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final assets = (body['assets'] ?? []) as List;
      return ReleaseInfo(
        tag: ((body['tag_name'] ?? '') as String).trim(),
        name: ((body['name'] ?? '') as String),
        notes: ((body['body'] ?? '') as String),
        assets: assets
            .whereType<Map<String, dynamic>>()
            .map(ReleaseAsset.fromMap)
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Release info when the remote tag is newer than the installed
  /// version, else null. Pure version logic lives in [isNewer] so it
  /// is unit-testable without network.
  Future<ReleaseInfo?> newerRelease() async {
    final rel = await latestRelease();
    if (rel == null || rel.tag.isEmpty) return null;
    final cur = (await PackageInfo.fromPlatform()).version;
    if (!isNewer(rel.tag, cur)) return null;
    return rel;
  }

  /// Legacy helper used by older UI: direct APK url or null.
  Future<String?> newerApkUrl() async {
    final r = await newerRelease();
    return r?.apk?.downloadUrl;
  }

  /// True when tag (e.g. "v1.2.0") is a newer semver than current
  /// ("1.1.9"). Non-numeric suffixes are ignored.
  static bool isNewer(String tag, String current) {
    List<int> parts(String v) => v
        .replaceAll(RegExp(r'^v'), '')
        .split('.')
        .map((e) => int.tryParse(RegExp(r'\d+').stringMatch(e) ?? '') ?? 0)
        .toList();
    final a = parts(tag), b = parts(current);
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
