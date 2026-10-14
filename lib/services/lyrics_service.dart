import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/track.dart';

// Free LRCLIB API, no key. Pass artist + track + duration for
// exact-match synced lyrics. See https://lrclib.net/docs
class LyricsService {
  Future<List<LyricLine>> fetchSynced(Track t) async {
    // Fallback chain: exact credit first, then progressively looser
    // queries (LRCLIB misses on "A, B" multi-artists, "(feat. X)"
    // titles and strict durations).
    final seen = <String>{};
    for (final q in _candidates(t)) {
      final key = '${q.$1}|${q.$2}|${q.$3}';
      if (!seen.add(key)) continue;
      final lines =
          await _fetchOnce(q.$1, q.$2, q.$3 ? t.durationSec : 0);
      if (lines.isNotEmpty) return lines;
    }
    return [];
  }

  /// (artist, title, withDuration) attempts, most exact first.
  List<(String, String, bool)> _candidates(Track t) => [
        (t.artist, t.title, t.durationSec > 0),
        (firstArtist(t.artist), t.title, t.durationSec > 0),
        (t.artist, stripTitle(t.title), t.durationSec > 0),
        (firstArtist(t.artist), stripTitle(t.title), t.durationSec > 0),
        (t.artist, t.title, false),
      ];

  /// "Kendrick Lamar, SZA" -> "Kendrick Lamar".
  static String firstArtist(String artist) {
    final m = RegExp(r'^[^,&/]+').firstMatch(artist.trim());
    final first = (m?.group(0) ?? artist).trim();
    final feat = RegExp(r'\s+[xX]\s+|\s+feat\.?.*$', caseSensitive: false);
    return first.split(feat).first.trim();
  }

  /// "HUMBLE. (feat. ...)" / "Song - Remaster" -> base title.
  static String stripTitle(String title) {
    var s = title
        .replaceAll(
            RegExp(
                r'\s*[\(\[].*\b(feat|ft|explicit|remaster|radio edit|sped up|slowed|live|cover)\b.*$',
                caseSensitive: false),
            '')
        .trim();
    if (s.isEmpty) s = title.trim();
    return s;
  }

  Future<List<LyricLine>> _fetchOnce(
      String artist, String title, int durationSec) async {
    final params = <String, String>{
      'artist_name': artist,
      'track_name': title,
    };
    // duration=0 actively harms matching: omit it instead.
    if (durationSec > 0) params['duration'] = durationSec.toString();
    final uri = Uri.https('lrclib.net', '/api/get', params);
    final r = await http.get(uri);
    if (r.statusCode != 200) return [];
    dynamic body;
    try {
      body = jsonDecode(r.body);
    } catch (_) {
      return [];
    }
    if (body is! Map) return [];
    final synced = (body['syncedLyrics'] ?? '').toString();
    if (synced.isEmpty) return [];
    return parseLrc(synced);
  }

  // [mm:ss.xx] line  -> LyricLine. Tolerates .xx / .xxx / no millis.
  List<LyricLine> parseLrc(String lrc) {
    final re = RegExp(r'\[(\d+):(\d+)(?:\.(\d+))?\]');
    final out = <LyricLine>[];
    for (final line in const LineSplitter().convert(lrc)) {
      final m = re.firstMatch(line);
      if (m == null) continue;
      final millis = m.group(3) ?? '0';
      final ms = int.parse(m.group(1)!) * 60000 +
          int.parse(m.group(2)!) * 1000 +
          int.parse(millis.padRight(3, '0').substring(0, 3));
      final text = line.replaceAll(re, '').trim();
      if (text.isEmpty) continue;
      out.add(LyricLine(Duration(milliseconds: ms), text));
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }
}
