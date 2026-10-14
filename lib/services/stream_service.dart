import 'dart:convert';
import '../models/artist.dart';
import '../models/track.dart';
import 'yt_bridge.dart';

// Bridge to Chaquopy Python (yt-dlp) on Android, or a local Python
// subprocess on desktop. Dart never parses YouTube pages itself; it
// just sends "<title> <artist>" + videoId and gets back a direct
// googlevideo URL. Resolve at play-time, never cache.
class StreamService {
  final YtBridge _bridge;
  StreamService({YtBridge? bridge})
      : _bridge = bridge ?? AndroidYtBridge();

  Future<({String url, int duration})> resolve(Track t) async {
    final raw = await _bridge.invoke('getStream', {
      'query': t.searchQuery, // fallback if videoId missing/invalid
      'videoId': t.videoId, // exact tapped video: no re-search drift
    });
    final m = jsonDecode(raw) as Map<String, dynamic>;
    if (m['error'] != null) throw Exception('yt-dlp: ${m['error']}');
    final url = (m['url'] ?? '').toString();
    if (url.isEmpty) throw Exception('yt-dlp returned no stream URL');
    return (url: url, duration: _toInt(m['duration'], t.durationSec));
  }

  Future<SearchResults> pythonSearch(String q) async {
    final raw = await _bridge.invoke('search', {'query': q});
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['error'] != null) {
      throw Exception('search: ${decoded['error']}');
    }
    if (decoded is List) return SearchResults.fromSongsList(decoded);
    if (decoded is! Map) return SearchResults.empty;
    return SearchResults.fromMap(decoded as Map<String, dynamic>);
  }

  static int _toInt(dynamic v, int fallback) {
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }
}
