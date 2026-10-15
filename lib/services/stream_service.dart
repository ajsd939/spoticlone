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

  Future<({String url, int duration, String ext})> resolve(Track t) async {
    final raw = await _bridge.invoke('getStream', {
      'query': t.searchQuery, // fallback if videoId missing/invalid
      'videoId': t.videoId, // exact tapped video: no re-search drift
    });
    final m = _decodeMap(raw);
    if (m['error'] != null) throw Exception('yt-dlp: ${m['error']}');
    final url = (m['url'] ?? '').toString();
    if (url.isEmpty) throw Exception('yt-dlp returned no stream URL');
    var ext = (m['ext'] ?? 'm4a').toString().toLowerCase();
    if (!RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext)) ext = 'm4a';
    return (
      url: url,
      duration: _toInt(m['duration'], t.durationSec),
      ext: ext
    );
  }

  /// Fill gaps for search items missing artist/duration (ATV uploads
  /// carry neither). Returns the input untouched when complete, so the
  /// common path costs zero extra bridge calls.
  Future<Track> enrich(Track t) async {
    final needsArtist =
        t.artist.isEmpty || t.artist == 'Unknown' || t.artistId.isEmpty;
    if (!needsArtist && t.durationSec > 0) return t;
    final raw = await _bridge.invoke('song', {'videoId': t.videoId});
    final m = _decodeMap(raw);
    if (m['error'] != null) return t;
    String str(dynamic v) => (v ?? '').toString();
    final artist = str(m['artist']);
    final title = str(m['title']);
    final dur = _toInt(m['duration'], 0);
    return Track(
      videoId: t.videoId,
      title: title.isNotEmpty ? title : t.title,
      artist: artist.isNotEmpty && artist != 'Unknown'
          ? artist
          : t.artist,
      artistId: str(m['artistId']).isNotEmpty
          ? str(m['artistId'])
          : t.artistId,
      album: t.album,
      artworkUrl: t.artworkUrl,
      durationSec: dur > 0 ? dur : t.durationSec,
    );
  }

  Future<SearchResults> pythonSearch(String q) async {    final raw = await _bridge.invoke('search', {'query': q});
    final decoded = _decodeAny(raw);
    if (decoded is Map && decoded['error'] != null) {
      throw Exception('search: ${decoded['error']}');
    }
    if (decoded is List) return SearchResults.fromSongsList(decoded);
    if (decoded is! Map) throw Exception('bad search response');
    return SearchResults.fromMap(decoded as Map<String, dynamic>);
  }

  /// Bridge bugs must surface as catchable Exceptions, never raw
  /// FormatException/TypeError (those skip our snackbars/fallbacks).
  static Map<String, dynamic> _decodeMap(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) return m;
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (_) {}
    throw Exception('bad bridge response');
  }

  static dynamic _decodeAny(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      throw Exception('bad bridge response');
    }
  }

  static int _toInt(dynamic v, int fallback) {
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }
}
