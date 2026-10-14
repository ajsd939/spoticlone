import 'dart:convert';
import '../models/artist.dart';
import 'yt_bridge.dart';

// Artist/album pages over the same bridge (Chaquopy on Android,
// local Python on desktop). Python returns JSON strings.
class ArtistService {
  final YtBridge _bridge;
  ArtistService({YtBridge? bridge})
      : _bridge = bridge ?? AndroidYtBridge();

  Future<Artist> getArtist(String artistId) async {
    final raw = await _bridge.invoke(
        'artist', {'query': '', 'videoId': artistId});
    final m = _decodeMap(raw);
    if (m['error'] != null) throw Exception('artist: ${m['error']}');
    return Artist.fromMap(m);
  }

  Future<Album> getAlbum(String albumId) async {
    final raw = await _bridge.invoke(
        'album', {'query': '', 'videoId': albumId});
    final m = _decodeMap(raw);
    if (m['error'] != null) throw Exception('album: ${m['error']}');
    return Album.fromMap(m);
  }

  static Map<String, dynamic> _decodeMap(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) return m;
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (_) {}
    throw Exception('bad bridge response');
  }
}
