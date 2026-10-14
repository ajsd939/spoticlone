import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/track.dart';

// Free LRCLIB API, no key. Pass artist + track + duration for
// exact-match synced lyrics. See https://lrclib.net/docs
class LyricsService {
  Future<List<LyricLine>> fetchSynced(Track t) async {
    final uri = Uri.https('lrclib.net', '/api/get', {
      'artist_name': t.artist,
      'track_name': t.title,
      'duration': t.durationSec.toString(),
    });
    final r = await http.get(uri);
    if (r.statusCode != 200) return [];
    final synced = (jsonDecode(r.body)['syncedLyrics'] ?? '') as String;
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
