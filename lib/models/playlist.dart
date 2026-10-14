import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'track.dart';

// On-device library: Liked Songs + user playlists, persisted as JSON
// in SharedPreferences (works on Android and Windows, no account).
// All mutations notifyListeners; widgets rebuild via ListenableBuilder.
class Playlist {
  final String id;
  String name;
  final List<Track> tracks;
  final DateTime createdAt;

  Playlist(
      {required this.id,
      required this.name,
      List<Track>? tracks,
      DateTime? createdAt})
      : tracks = tracks ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory Playlist.fromJson(Map m) => Playlist(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? 'Untitled').toString(),
        createdAt:
            DateTime.tryParse((m['createdAt'] ?? '').toString()) ??
                DateTime.now(),
        tracks: ((m['tracks'] ?? []) as List)
            .whereType<Map>()
            .map(Track.fromJson)
            .where((t) => t.videoId.isNotEmpty)
            .toList(),
      );
}

class PlaylistService extends ChangeNotifier {
  static const likedId = 'liked';
  static const _prefsKey = 'spoticlone.playlists.v1';

  final List<Playlist> _playlists = [];
  SharedPreferences? _prefs;

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  Playlist get liked =>
      _playlists.firstWhere((p) => p.id == likedId);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _playlists.clear();
    final raw = _prefs!.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded.whereType<Map>()) {
            final p = Playlist.fromJson(e);
            if (p.id.isNotEmpty) _playlists.add(p);
          }
        }
      } catch (_) {
        // Corrupt cache: start fresh rather than crash.
        _playlists.clear();
      }
    }
    if (!_playlists.any((p) => p.id == likedId)) {
      _playlists.insert(
          0, Playlist(id: likedId, name: 'Liked Songs'));
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await _prefs?.setString(_prefsKey,
        jsonEncode(_playlists.map((p) => p.toJson()).toList()));
  }

  Playlist? byId(String id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<Playlist> createPlaylist(String name) async {
    final p = Playlist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'My Playlist' : name.trim(),
    );
    _playlists.add(p);
    notifyListeners();
    await _save();
    return p;
  }

  Future<void> deletePlaylist(String id) async {
    if (id == likedId) return; // Liked Songs can't be deleted
    _playlists.removeWhere((p) => p.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> addToPlaylist(String id, Track t) async {
    final p = byId(id);
    if (p == null) return;
    if (p.tracks.any((e) => e.videoId == t.videoId)) return;
    p.tracks.add(t);
    notifyListeners();
    await _save();
  }

  Future<void> removeFromPlaylist(String id, String videoId) async {
    final p = byId(id);
    if (p == null) return;
    p.tracks.removeWhere((e) => e.videoId == videoId);
    notifyListeners();
    await _save();
  }

  bool isLiked(Track t) =>
      liked.tracks.any((e) => e.videoId == t.videoId);

  Future<void> toggleLike(Track t) async {
    if (isLiked(t)) {
      await removeFromPlaylist(likedId, t.videoId);
    } else {
      await addToPlaylist(likedId, t);
    }
  }
}
