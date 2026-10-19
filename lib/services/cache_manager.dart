import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';

/// A song kept in the disposable streaming cache. Not a user download.
class CachedTrack {
  final Track track;
  final String path;
  final DateTime cachedAt;
  const CachedTrack(
      {required this.track, required this.path, required this.cachedAt});
}

/// Owns the temporary audio cache — completely separate from
/// permanent downloads. Nothing here is exempt from cleanup:
///
///  * when playback moves to another song, the previous file gets a
///    15-second grace timer; returning with "previous" cancels it;
///  * the whole cache is wiped on startup and on app detach/exit;
///  * deletions retry for a few seconds so a still-open player handle
///    (notably on Windows) doesn't leave junk behind.
///
/// Permanent files live under `downloads/` (DownloadsService) and are
/// never touched by this class.
class CacheManager extends ChangeNotifier with WidgetsBindingObserver {
  static const gracePeriod = Duration(seconds: 15);
  static const _retryDelay = Duration(seconds: 2);
  static const _maxAttempts = 3;

  final Directory? _overrideDir; // tests
  Directory? _dir;
  final Map<String, CachedTrack> _items = {};
  final Map<String, Timer> _timers = {};
  String? _nowPlaying;
  bool _observing = false;
  bool _disposed = false;

  CacheManager({Directory? directory}) : _overrideDir = directory;

  /// Songs currently cached, newest first.
  List<CachedTrack> get tracks {
    final all = _items.values.toList()
      ..sort((a, b) => b.cachedAt.compareTo(a.cachedAt));
    return all;
  }

  int get count => _items.length;
  String? get nowPlaying => _nowPlaying;

  bool has(String videoId) => _items.containsKey(videoId);

  /// Existing temp file path or null (drops stale registry entries).
  String? pathFor(String videoId) {
    final e = _items[videoId];
    if (e == null) return null;
    if (!File(e.path).existsSync()) {
      _items.remove(videoId);
      _notify();
      return null;
    }
    return e.path;
  }

  /// Creates (and clears) the cache directory, then watches app
  /// lifecycle so a killed/closed app leaves no temp files behind.
  Future<void> init({bool wipe = true}) async {
    _dir = await _resolveDir();
    if (wipe) await clearAll();
    if (!_observing) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _observing = true;
      } catch (_) {}
    }
  }

  Future<Directory> ensureDir() async {
    _dir ??= await _resolveDir();
    return _dir!;
  }

  /// Reserve a path inside the temp cache. The caller writes the bytes.
  Future<File> allocate(Track track, String ext) async {
    final dir = await ensureDir();
    final safeExt = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : 'm4a';
    return File(
        '${dir.path}${Platform.pathSeparator}${track.videoId}.$safeExt');
  }

  /// Records a completed temp download and cancels any pending delete.
  Future<void> register(Track track, File file) async {
    _timers.remove(track.videoId)?.cancel();
    _items[track.videoId] = CachedTrack(
        track: track, path: file.path, cachedAt: DateTime.now());
    _notify();
  }

  /// Marks the song that is playing right now and rescues it from an
  /// already-running grace timer (the "previous" button case).
  void beginPlayback(String videoId) {
    _nowPlaying = videoId;
    _timers.remove(videoId)?.cancel();
  }

  /// Called once the new song actually starts: every other cached
  /// song begins its 15-second countdown.
  void scheduleDeleteOthers(String keepVideoId) {
    _nowPlaying = keepVideoId;
    _timers.remove(keepVideoId)?.cancel();
    for (final id in _items.keys.toList()) {
      if (id != keepVideoId) scheduleDelete(id);
    }
  }

  /// Starts/restarts the grace timer for one cached file.
  void scheduleDelete(String videoId,
      {Duration grace = gracePeriod}) {
    _timers.remove(videoId)?.cancel();
    _timers[videoId] = Timer(grace, () => deleteNow(videoId));
  }

  void cancelDelete(String videoId) {
    _timers.remove(videoId)?.cancel();
  }

  /// Delete now unless it is the current song. Retries around open
  /// handles instead of throwing.
  Future<void> deleteNow(String videoId) async {
    if (videoId == _nowPlaying) return; // don't pull the file in use
    _timers.remove(videoId)?.cancel();
    final item = _items[videoId];
    if (item == null) return;
    final ok = await _deleteWithRetry(File(item.path));
    if (ok) {
      _items.remove(videoId);
      _notify();
    } else {
      // Handle still locked: one more attempt shortly.
      scheduleDelete(videoId, grace: _retryDelay);
    }
  }

  /// Removes a temp copy (used after an explicit permanent download).
  Future<void> removeTemp(String videoId) async {
    if (!_items.containsKey(videoId)) return;
    if (videoId == _nowPlaying) {
      scheduleDelete(videoId);
    } else {
      await deleteNow(videoId);
    }
  }

  /// Wipes every temporary file. Safe to call at startup / shutdown.
  Future<void> clearAll() async {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _items.clear();
    final dir = _dir;
    if (dir != null && await dir.exists()) {
      try {
        await for (final e in dir.list(followLinks: false)) {
          await _deleteWithRetry(FileSystemEntity.isDirectorySync(e.path)
              ? Directory(e.path)
              : File(e.path));
        }
      } catch (e) {
        debugPrint('CacheManager: wipe failed: $e');
      }
    }
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // Best-effort; startup wipe still covers hard kills.
      unawaited(clearAll());
    }
  }

  Future<Directory> _resolveDir() async {
    final od = _overrideDir;
    if (od != null) {
      if (!await od.exists()) await od.create(recursive: true);
      return od;
    }
    final base = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
    if (base == null) throw Exception('no storage directory');
    final d =
        Directory('${base.path}${Platform.pathSeparator}temp_cache');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<bool> _deleteWithRetry(FileSystemEntity entity) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        if (await entity.exists()) {
          await entity.delete(recursive: true);
        }
        return true;
      } on FileSystemException catch (e) {
        debugPrint(
            'CacheManager: delete attempt $attempt failed (${e.message}); '
            'file may be locked by the player');
        if (attempt == _maxAttempts) return false;
        await Future.delayed(_retryDelay);
      } catch (e) {
        debugPrint('CacheManager: delete failed: $e');
        return false;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    if (_observing) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _observing = false;
    }
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
