import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
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

  DownloadsService({YtBridge? bridge, Directory? directory})
      : _bridge = bridge,
        _overrideDir = directory;

  List<Track> get tracks =>
      _items.values.map((e) => e.track).toList();
  int get count => _items.length;

  bool isDownloaded(String videoId) =>
      _items.containsKey(videoId);

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

  Future<File> download(Track track,
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
    return file;
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
