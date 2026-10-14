import 'track.dart';

// Artist page + album data from yt_bridge.py (get_artist/get_album).
// All parsing is defensive: unknown shapes must not crash.
class AlbumSummary {
  final String id; // browseId, '' when unknown
  final String title;
  final String year;
  final String artworkUrl;

  const AlbumSummary(
      {required this.id,
      required this.title,
      this.year = '',
      this.artworkUrl = ''});

  factory AlbumSummary.fromMap(Map m) => AlbumSummary(
        id: (m['albumId'] ?? '').toString(),
        title: (m['title'] ?? 'Unknown').toString(),
        year: (m['year'] ?? '').toString(),
        artworkUrl: (m['artworkUrl'] ?? '').toString(),
      );
}

// Lightweight artist hit from unfiltered search (circle row).
class ArtistRef {
  final String id; // channel/browse id
  final String name;
  final String artworkUrl;

  const ArtistRef(
      {required this.id, required this.name, this.artworkUrl = ''});

  factory ArtistRef.fromMap(Map m) => ArtistRef(
        id: (m['artistId'] ?? '').toString(),
        name: (m['name'] ?? 'Unknown').toString(),
        artworkUrl: (m['artworkUrl'] ?? '').toString(),
      );
}

class Artist {
  final String id;
  final String name;
  final String artworkUrl;
  final List<Track> topTracks;
  final List<AlbumSummary> albums;
  final List<AlbumSummary> singles;

  const Artist(
      {required this.id,
      required this.name,
      this.artworkUrl = '',
      this.topTracks = const [],
      this.albums = const [],
      this.singles = const []});

  static List<T> _list<T>(dynamic v, T Function(Map m) f) {
    if (v is! List) return [];
    return v.whereType<Map>().map(f).toList();
  }

  factory Artist.fromMap(Map<String, dynamic> m) => Artist(
        id: (m['artistId'] ?? '').toString(),
        name: (m['name'] ?? 'Unknown').toString(),
        artworkUrl: (m['artworkUrl'] ?? '').toString(),
        topTracks: _list(m['topTracks'], Track.fromBridge),
        albums: _list(m['albums'], AlbumSummary.fromMap),
        singles: _list(m['singles'], AlbumSummary.fromMap),
      );
}

class Album {
  final String id;
  final String title;
  final String artist;
  final String year;
  final String artworkUrl;
  final List<Track> tracks;

  const Album(
      {required this.id,
      required this.title,
      this.artist = '',
      this.year = '',
      this.artworkUrl = '',
      this.tracks = const []});

  factory Album.fromMap(Map<String, dynamic> m) => Album(
        id: (m['albumId'] ?? '').toString(),
        title: (m['title'] ?? 'Unknown').toString(),
        artist: (m['artist'] ?? '').toString(),
        year: (m['year'] ?? '').toString(),
        artworkUrl: (m['artworkUrl'] ?? '').toString(),
        tracks: Artist._list(m['tracks'], Track.fromBridge),
      );
}

// Unfiltered search payload: songs + artists + albums in one call.
class SearchResults {
  final List<Track> songs;
  final List<ArtistRef> artists;
  final List<AlbumSummary> albums;

  const SearchResults(
      {this.songs = const [],
      this.artists = const [],
      this.albums = const []});

  static const empty = SearchResults();

  bool get isEmpty =>
      songs.isEmpty && artists.isEmpty && albums.isEmpty;

  factory SearchResults.fromMap(Map<String, dynamic> m) => SearchResults(
        songs: Artist._list(m['songs'], Track.fromBridge)
            .where((t) => t.videoId.isNotEmpty)
            .toList(),
        artists: Artist._list(m['artists'], ArtistRef.fromMap)
            .where((a) => a.id.isNotEmpty)
            .toList(),
        albums: Artist._list(m['albums'], AlbumSummary.fromMap)
            .where((a) => a.id.isNotEmpty)
            .toList(),
      );

  // Tolerates a legacy list-only payload (songs).
  factory SearchResults.fromSongsList(List l) => SearchResults(
        songs: l.whereType<Map>().map(Track.fromBridge).toList(),
      );
}
