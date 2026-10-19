import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import 'lyrics_service.dart';
import 'stream_service.dart';
import 'yt_bridge.dart';

// Offline downloads: audio files saved to app storage + a persisted
// registry. Players prefer the local file when present (no network,
// no resolve wait). Works on Android and Windows (app-scoped dirs
// need no storage permissions).
class DownloadedTrack {
  final Track track;
  final String path;
  final DateTime downloadedAt;
  const DownloadedTrack(
      {required this.track,
      required this.path,
      required this.downloadedAt});

  Map<String, dynamic> toJson() => {
        'track': track.toJson(),
        'path': path,
        'downloadedAt': downloadedAt.toIso8601String(),
      };

  factory DownloadedTrack.fromJson(Map m) => DownloadedTrack(
        track: Track.fromJson(m['track'] as Map? ?? {}),
        path: (m['path'] ?? '').toString(),
        downloadedAt:
            DateTime.tryParse((m['downloadedAt'] ?? '').toString()) ??
                DateTime.now(),
      );
}

class DownloadsService extends ChangeNotifier {
  static const _prefsKey = 'spoticlone.downloads.v1';

  final YtBridge? _bridge;
  final Directory? _overrideDir; // tests
  SharedPreferences? _prefs;
  final Map<String, DownloadedTrack> _items = {};

  // Downloads queued or running right now (auto-save + batches).
  final Set<String> _busy = {};
  // Auto-saves run one at a time so playback never competes for
  // bandwidth with a burst of downloads.
  Future<void> _autoChain = Future.value();

  DownloadsService({YtBridge? bridge, Directory? directory})
      : _bridge = bridge,
        _overrideDir = directory;

  /// Newest first, so a song you just played is visible at the top.
  List<Track> get tracks {
    final all = _items.values.toList()
      ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return all.map((e) => e.track).toList();
  }

  int get count => _items.length;

  bool isDownloaded(String videoId) =>
      _items.containsKey(videoId);

  bool isDownloading(String videoId) => _busy.contains(videoId);

  /// Local file path, or null. Drops stale entries whose file vanished.
  String? localPath(String videoId) {
    final e = _items[videoId];
    if (e == null) return null;
    if (!File(e.path).existsSync()) {
      _items.remove(videoId);
      notifyListeners();
      _save();
      return null;
    }
    return e.path;
  }

  Future<Directory> _dir() async {
    final od = _overrideDir;
    if (od != null) {
      if (!await od.exists()) {
        await od.create(recursive: true);
      }
      return od;
    }
    final base = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
    if (base == null) throw Exception('no storage directory');
    final d = Directory(
        '${base.path}${Platform.pathSeparator}downloads');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _items.clear();
    final raw = _prefs!.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded.whereType<Map>()) {
            try {
              final d = DownloadedTrack.fromJson(e);
              if (d.track.videoId.isNotEmpty) {
                _items[d.track.videoId] = d;
              }
            } catch (_) {}
          }
        }
      } catch (_) {
        _items.clear();
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await _prefs?.setString(_prefsKey,
        jsonEncode(_items.values.map((e) => e.toJson()).toList()));
  }

  /// Used by download() and tests to register an entry.
  Future<void> registerDownload(Track track, String path) async {
    _items[track.videoId] = DownloadedTrack(
        track: track, path: path, downloadedAt: DateTime.now());
    notifyListeners();
    await _save();
  }

  /// Silent download kicked off whenever a song starts playing. This is
  /// what makes streamed songs show up in the offline library. Queued
  /// serially, best-effort: failures are ignored and retried next play.
  void autoSave(Track track) {
    if (track.videoId.isEmpty) return;
    if (isDownloaded(track.videoId) || _busy.contains(track.videoId)) return;
    _busy.add(track.videoId);
    notifyListeners();
    _autoChain = _autoChain.then((_) async {
      try {
        if (!isDownloaded(track.videoId)) await download(track, quiet: true);
      } catch (_) {
        // offline/stream hiccup: leave it out of the library
      } finally {
        _busy.remove(track.videoId);
        notifyListeners();
      }
    });
  }

  Future<File> download(Track track,
      {void Function(double progress)? onProgress,
      bool quiet = false}) async {
    final existing = _items[track.videoId];
    if (existing != null && File(existing.path).existsSync()) {
      return File(existing.path);
    }
    if (!quiet) {
      _busy.add(track.videoId);
      notifyListeners();
    }
    try {
      return await _downloadNow(track, onProgress: onProgress);
    } finally {
      if (!quiet) {
        _busy.remove(track.videoId);
        notifyListeners();
      }
    }
  }

  Future<File> _downloadNow(Track track,
      {void Function(double progress)? onProgress}) async {
    final dir = await _dir();
    final s = await StreamService(bridge: _bridge).resolve(track);
    final file = File(
        '${dir.path}${Platform.pathSeparator}${track.videoId}.${s.ext}');
    final req = http.Request('GET', Uri.parse(s.url));
    final client = http.Client();
    try {
      final res = await client.send(req);
      if (res.statusCode != 200) {
        throw Exception('download failed: HTTP ${res.statusCode}');
      }
      final total = res.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      onProgress?.call(1.0);
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
    await registerDownload(track, file.path);
    // Pull lyrics with the audio so the Lyrics tab works offline too.
    unawaited(LyricsService().cacheFor(track));
    return file;
  }

  /// Downloads every track not already offline, one at a time, and
  /// reports how many finished. Used for whole playlists and albums.
  Future<({int ok, int failed})> downloadMany(
    List<Track> tracks, {
    void Function(int done, int total)? onProgress,
  }) async {
    var ok = 0, failed = 0;
    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      if (isDownloaded(t.videoId)) {
        ok++;
      } else {
        try {
          await download(t);
          ok++;
        } catch (_) {
          failed++;
        }
      }
      onProgress?.call(i + 1, tracks.length);
    }
    return (ok: ok, failed: failed);
  }

  Future<void> delete(String videoId) async {
    final e = _items.remove(videoId);
    if (e != null) {
      try {
        final f = File(e.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    notifyListeners();
    await _save();
  }
}
