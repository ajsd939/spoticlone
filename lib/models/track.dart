// Track + LyricLine models. Keep JSON parsing in services, not here.
class Track {
  final String videoId;
  final String title;
  final String artist;
  final String artistId; // YouTube Music channel id, '' when unknown
  final String album;
  final String artworkUrl;
  final int durationSec;

  const Track({
    required this.videoId,
    required this.title,
    required this.artist,
    this.artistId = '',
    this.album = '',
    this.artworkUrl = '',
    this.durationSec = 0,
  });

  /// Handed to yt-dlp for resolution (spec: title + artist only).
  String get searchQuery => '$title $artist';

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'artistId': artistId,
        'album': album,
        'artworkUrl': artworkUrl,
        'durationSec': durationSec,
      };

  /// Playlist persistence uses the same keys fromBridge reads.
  factory Track.fromJson(Map m) => Track.fromBridge(m);

  factory Track.fromPiped(Map<String, dynamic> e) {
    final url = (e['url'] ?? '') as String; // e.g. /watch?v=xxx
    final id = url.contains('=') ? url.split('=').last : url;
    return Track(
      videoId: id,
      title: (e['title'] ?? 'Unknown') as String,
      artist: (e['uploaderName'] ?? 'Unknown') as String,
      artworkUrl: (e['thumbnail'] ?? '') as String,
      durationSec: ((e['duration'] ?? 0) as num).toInt(),
    );
  }

  /// From yt_bridge.py JSON (all values coerced to String/int there,
  /// but stay defensive: any shape mismatch must not crash).
  factory Track.fromBridge(Map m) {
    int secs(dynamic v) {
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    return Track(
      videoId: (m['videoId'] ?? '').toString(),
      title: (m['title'] ?? 'Unknown').toString(),
      artist: (m['artist'] ?? 'Unknown').toString(),
      artistId: (m['artistId'] ?? '').toString(),
      album: (m['album'] ?? '').toString(),
      artworkUrl: (m['artworkUrl'] ?? '').toString(),
      durationSec: secs(m['durationSec']),
    );
  }
}

class LyricLine {
  final Duration time;
  final String text;
  const LyricLine(this.time, this.text);
}
