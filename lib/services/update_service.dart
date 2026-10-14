import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

// Lightweight startup check against GitHub Releases API.
// Returns APK download URL when remote tag > installed version.
class UpdateService {
  Future<String?> newerApkUrl({required String owner, required String repo}) async {
    if (owner == 'OWNER') return null; // placeholder, not configured
    final r = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'),
    );
    if (r.statusCode != 200) return null;
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final tag = ((body['tag_name'] ?? '') as String).replaceAll(RegExp(r'^v'), '');
    final cur = (await PackageInfo.fromPlatform()).version;
    if (!_isNewer(tag, cur)) return null;
    final assets = (body['assets'] ?? []) as List;
    if (assets.isEmpty) return body['html_url'] as String?;
    final apk = assets.cast<Map<String, dynamic>>().firstWhere(
          (a) => ((a['name'] ?? '') as String).endsWith('.apk'),
          orElse: () => assets.first as Map<String, dynamic>,
        );
    return apk['browser_download_url'] as String?;
  }

  bool _isNewer(String a, String b) {
    List<int> p(String v) => v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pa = p(a), pb = p(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
