import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/track.dart';

// Pure-Dart search fallback so the search bar works even before
// Chaquopy warms up. Primary path is ytmusicapi over the
// MethodChannel (see StreamService); this Piped fallback keeps
// metadata + cover art available with zero native deps.
// NOTE: public Piped instances rotate -> self-host or configure mirrors.
class SearchService {
  final String base;
  SearchService({this.base = 'https://pipedapi.kavin.rocks'});

  Future<List<Track>> search(String q) async {
    final uri = Uri.parse('$base/search?q=${Uri.encodeComponent(q)}&filter=music_songs');
    final r = await http.get(uri);
    if (r.statusCode != 200) return [];
    final items = (jsonDecode(r.body)['items'] ?? []) as List;
    return items
        .whereType<Map<String, dynamic>>()
        .map(Track.fromPiped)
        .toList();
  }
}
