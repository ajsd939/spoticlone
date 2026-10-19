import 'dart:convert';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Free, keyless lyric translation via Google's public translate endpoint.
// Lines are batched into a single request per ~1500 characters, and the
// result is cached per song + language so it also works offline after
// the first view.
class TranslationService {
  static const _prefsKey = 'spoticlone.lyrics.tr.v1';

  /// Device language to translate into, or null when it is English.
  static String? deviceTarget() {
    final code =
        PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    if (code.isEmpty || code == 'en') return null;
    if (code == 'zh') return 'zh-CN';
    return code;
  }

  /// Returns translations keyed by the original line index. Never throws:
  /// lyrics simply stay English when the network/service is unavailable.
  Future<Map<int, String>> translateLines(
    String cacheKey,
    List<String> lines,
    String target,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefsKey.$cacheKey.$target';
    final cached = prefs.getString(key);
    if (cached != null && cached.isNotEmpty) {
      try {
        final m = jsonDecode(cached);
        if (m is Map) {
          return {
            for (final e in m.entries)
              if (int.tryParse(e.key.toString()) != null)
                int.parse(e.key.toString()): e.value.toString(),
          };
        }
      } catch (_) {}
    }

    final indices = <int>[];
    final texts = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.isEmpty || _isInstrumental(t)) continue;
      indices.add(i);
      texts.add(t);
    }
    if (texts.isEmpty) return {};

    final out = <int, String>{};
    try {
      var start = 0;
      for (final chunk in _chunk(texts)) {
        final translated = await _translateChunk(chunk, target);
        for (var j = 0; j < chunk.length; j++) {
          final tr = j < translated.length ? translated[j].trim() : '';
          if (tr.isNotEmpty) out[indices[start + j]] = tr;
        }
        start += chunk.length;
      }
    } catch (_) {
      return out;
    }

    if (out.isNotEmpty) {
      try {
        await prefs.setString(
          key,
          jsonEncode({for (final e in out.entries) '${e.key}': e.value}),
        );
      } catch (_) {}
    }
    return out;
  }

  static bool _isInstrumental(String s) =>
      s.replaceAll(RegExp(r'[♪♫\s]'), '').isEmpty;

  /// Split into batches that keep the request URL/body comfortably small.
  static List<List<String>> _chunk(List<String> lines) {
    final chunks = <List<String>>[];
    var cur = <String>[];
    var size = 0;
    for (final l in lines) {
      if (cur.isNotEmpty && size + l.length > 1500) {
        chunks.add(cur);
        cur = <String>[];
        size = 0;
      }
      cur.add(l);
      size += l.length + 1;
    }
    if (cur.isNotEmpty) chunks.add(cur);
    return chunks;
  }

  Future<List<String>> _translateChunk(
      List<String> lines, String target) async {
    final joined = lines.join('\n');
    final text = await _request(joined, target);
    var parts = text.split('\n').map((s) => s.trim()).toList();
    while (parts.isNotEmpty && parts.last.isEmpty) {
      parts.removeLast();
    }
    if (parts.length == lines.length) return parts;

    // Line alignment can break if the service merges sentences; fall
    // back to one request per line so timings always stay matched.
    final out = <String>[];
    for (final l in lines) {
      try {
        out.add(await _request(l, target));
      } catch (_) {
        out.add('');
      }
    }
    return out;
  }

  Future<String> _request(String text, String target) async {
    final r = await http
        .post(
          Uri.https('translate.googleapis.com', '/translate_a/single'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'client': 'gtx',
            'sl': 'auto',
            'tl': target,
            'dt': 't',
            'q': text,
          },
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) {
      throw Exception('translate failed: HTTP ${r.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    if (decoded is! List || decoded.isEmpty) return '';
    final segments = decoded[0];
    if (segments is! List) return '';
    final buf = StringBuffer();
    for (final s in segments) {
      if (s is List && s.isNotEmpty) buf.write((s[0] ?? '').toString());
    }
    return buf.toString();
  }
}
