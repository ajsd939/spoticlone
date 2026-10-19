import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:rxdart/rxdart.dart';
import '../models/track.dart';
import '../services/stream_service.dart';
import '../services/yt_bridge.dart';
import '../core/di.dart';
import '../services/downloads_service.dart';
import 'playback_queue.dart';
import 'player_facade.dart';

// Windows/Linux/macOS player: media_kit (libmpv) gives gapless-ish
// audio plus native OS media integration (Windows SMTC: taskbar
// flyout + lock-screen controls). Same PlayerFacade the widgets use,
// so all UI is shared with mobile.
class DesktopPlayer implements PlayerFacade {
  // 128 MB demuxer cache (libmpv default is 32) absorbs throttling dips.
  final mk.Player _player = mk.Player(
    configuration:
        const mk.PlayerConfiguration(bufferSize: 128 * 1024 * 1024),
  );
  final StreamService _stream;
  final _queue = PlaybackQueue();
  final _mediaItem = BehaviorSubject<MediaItem?>();
  final _state =
      BehaviorSubject<PlaybackState>.seeded(_idleState(false));
  final _queueIndex = BehaviorSubject<int>.seeded(0);
  final _shuffleState = BehaviorSubject<bool>.seeded(false);
  final _repeatState =
      BehaviorSubject<QueueRepeat>.seeded(QueueRepeat.off);
  final _resolved = <String, ({String url, int duration, String ext})>{};
  int _gen = 0;
  bool _completed = false;
  StreamSubscription? _playingSub;
  StreamSubscription? _completedSub;
  StreamSubscription? _durationSub;

  DesktopPlayer({required YtBridge bridge})
      : _stream = StreamService(bridge: bridge) {
    // Mirror playback state into audio_service-shaped updates.
    // Separate listeners (not combineLatest): `completed` may never
    // emit before first play, which would stall state updates.
    _playingSub = _player.stream.playing.listen((playing) {
      final completed = _completed;
      _state.add(_state.value.copyWith(
        playing: playing && !completed,
        processingState: completed
            ? AudioProcessingState.completed
            : AudioProcessingState.ready,
      ));
    });
    _completedSub = _player.stream.completed.listen((completed) {
      _completed = completed;
      if (completed) {
        _onCompleted();
      } else {
        _state.add(_state.value.copyWith(
          playing: _player.state.playing,
          processingState: AudioProcessingState.ready,
        ));
      }
    });
    // Ground-truth duration for the taskbar/notification total.
    _durationSub = _player.stream.duration.listen((d) {
      final cur = _mediaItem.value;
      if (d.inMilliseconds > 0 && cur != null && cur.duration != d) {
        _mediaItem.add(cur.copyWith(duration: d));
      }
    });
  }

  static PlaybackState _idleState(bool playing) => PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.idle,
        playing: playing,
        updatePosition: Duration.zero,
        speed: 1.0,
      );

  void _setResolving() {
    _state.add(_state.value.copyWith(
      processingState: AudioProcessingState.buffering,
    ));
  }

  @override
  Stream<MediaItem?> get mediaItem => _mediaItem.stream;
  @override
  Stream<PlaybackState> get playbackState => _state.stream;
  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  List<Track> get trackQueue => _queue.tracks;
  @override
  Stream<int> get queueIndexStream => _queueIndex.stream;
  @override
  Stream<bool> get shuffleStream => _shuffleState.stream;
  @override
  Stream<QueueRepeat> get repeatStream => _repeatState.stream;

  @override
  Future<void> playTrack(Track t) => playTracks([t]);

  @override
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    final gen = ++_gen;
    if (tracks.isEmpty) return;
    _queue.setQueue(tracks, startIndex: startIndex);
    await _playCurrent(gen);
  }

  Future<void> _playCurrent(int gen) async {
    var t = _queue.current;
    if (t == null) return;
    // A returning "previous" cancels this song's pending cache delete.
    _markPlaying(t);
    _setResolving();
    try {
      await _player.stop();
      if (gen != _gen) return;
      // Fill artist/duration gaps (ATV uploads) before anything
      // observes this track, so UI, lyrics and taskbar agree.
      t = await _enrichIfNeeded(t);
      if (gen != _gen) return;
      _queue.updateTrack(_queue.index, t);
      _queueIndex.add(_queue.index);
      // Offline first: a downloaded file plays instantly, no resolve.
      final local = _localFile(t);
      final s = local != null
          ? (
              url: Uri.file(local).toString(),
              duration: t.durationSec,
              ext: 'dl'
            )
          : await _resolveCached(t);
      if (gen != _gen) return;
      // Item published only once open() succeeds: a failed resolve
      // must not strand the new title in taskbar/SMTC with silence.
      await _player.open(mk.Media(s.url));
      if (gen != _gen) return;
      final totalSec = s.duration > 0 ? s.duration : t.durationSec;
      _mediaItem.add(MediaItem(
        id: t.videoId,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: Duration(seconds: totalSec),
        artUri: Uri.tryParse(t.artworkUrl),
      ));
      await _player.play();
      // Auto-save every song you play so it also shows up under
      // Downloads (silent, serialized, never blocks playback).
      _autoSave(t);
      // New song is audible: start the grace timer for the previous one.
      _markStarted(t);
      _prefetchNext(gen);
    } catch (_) {
      // Drop the stuck buffering state so the spinner can't hang.
      if (gen == _gen) {
        _state.add(_idleState(false));
      }
      rethrow;
    }
  }

  Future<({String url, int duration, String ext})> _resolveCached(Track t) async {
    final hit = _resolved[t.videoId];
    if (hit != null && hit.url.isNotEmpty) return hit;
    final s = await _stream.resolve(t);
    _resolved[t.videoId] = s;
    return s;
  }

  /// Best-effort gap fill; never throws (falls back to input).
  Future<Track> _enrichIfNeeded(Track t) async {
    try {
      return await _stream.enrich(t);
    } catch (_) {
      return t;
    }
  }

  /// Downloaded file path or null (service missing/corrupt safe).
  String? _localFile(Track t) {
    try {
      return getIt<DownloadsService>().playablePath(t.videoId);
    } catch (_) {
      return null;
    }
  }

  /// Background offline copy of the song that just started playing.
  void _autoSave(Track t) {
    if (_localFile(t) != null) return;
    try {
      getIt<DownloadsService>().autoSave(t);
    } catch (_) {}
  }

  /// Playback is starting: rescue this song from a grace timer.
  void _markPlaying(Track t) {
    try {
      getIt<DownloadsService>().onPlaybackStart(t.videoId);
    } catch (_) {}
  }

  /// Playback actually began: start the 15s cleanup for the last song.
  void _markStarted(Track t) {
    try {
      getIt<DownloadsService>().onPlaybackStarted(t.videoId);
    } catch (_) {}
  }

  void _prefetchNext(int gen) {
    final next = _peekNext();
    if (next == null || _resolved.containsKey(next.videoId)) return;
    if (_localFile(next) != null) return; // offline: nothing to fetch
    _stream.resolve(next).then((s) {
      if (gen == _gen) _resolved[next.videoId] = s;
    }).catchError((_) {
      // Silent: the real attempt retries on advance.
    });
  }

  Track? _peekNext() {
    final scratch = PlaybackQueue()
      ..setQueue(_queue.tracks, startIndex: _queue.index);
    if (_queue.shuffle) scratch.setShuffle(true);
    if (_queue.repeat == QueueRepeat.one) return scratch.current;
    if (scratch.advance()) return scratch.current;
    return null;
  }

  Future<void> _onCompleted() async {
    final gen = _gen;
    if (_queue.repeat == QueueRepeat.one) {
      await _player.seek(Duration.zero);
      if (gen == _gen) await _player.play();
      return;
    }
    if (_queue.advance()) {
      await _playCurrent(gen);
    } else {
      _state.add(_state.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.completed,
      ));
    }
  }

  @override
  Future<void> toggleShuffle() async {
    _queue.setShuffle(!_queue.shuffle);
    _shuffleState.add(_queue.shuffle);
  }

  @override
  Future<void> cycleRepeat() async {
    _queue.cycleRepeat();
    _repeatState.add(_queue.repeat);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> skipToPrevious() async {
    if (_player.state.position > const Duration(seconds: 3)) {
      return _player.seek(Duration.zero);
    }
    if (_queue.back()) {
      final gen = ++_gen;
      await _playCurrent(gen);
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.advance()) {
      final gen = ++_gen;
      await _playCurrent(gen);
    } else {
      await _player.seek(Duration.zero);
    }
  }

  Future<void> dispose() async {
    await _playingSub?.cancel();
    await _completedSub?.cancel();
    await _durationSub?.cancel();
    await _player.dispose();
    await _mediaItem.close();
    await _state.close();
    await _queueIndex.close();
    await _shuffleState.close();
    await _repeatState.close();
  }
}
