import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:rxdart/rxdart.dart';
import '../models/track.dart';
import '../services/stream_service.dart';
import '../services/yt_bridge.dart';
import 'player_facade.dart';

// Windows/Linux/macOS player: media_kit (libmpv) gives gapless-ish
// audio plus native OS media integration (Windows SMTC: taskbar
// flyout + lock-screen controls). Same PlayerFacade the widgets use,
// so all UI is shared with mobile.
class DesktopPlayer implements PlayerFacade {
  final mk.Player _player = mk.Player();
  final StreamService _stream;
  final _mediaItem = BehaviorSubject<MediaItem?>();
  final _state =
      BehaviorSubject<PlaybackState>.seeded(_idleState(false));
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
      _state.add(_state.value.copyWith(
        playing: _player.state.playing && !completed,
        processingState: completed
            ? AudioProcessingState.completed
            : AudioProcessingState.ready,
      ));
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
  Future<void> playTrack(Track t) async {
    final gen = ++_gen;
    _setResolving();
    try {
      await _player.stop();
      if (gen != _gen) return;
      final s = await _stream.resolve(t);
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
    } catch (_) {
      // Drop the stuck buffering state so the spinner can't hang.
      if (gen == _gen) {
        _state.add(_idleState(false));
      }
      rethrow;
    }
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> skipToPrevious() => _player.seek(Duration.zero);
  @override
  Future<void> skipToNext() => _player.seek(Duration.zero);

  Future<void> dispose() async {
    await _playingSub?.cancel();
    await _completedSub?.cancel();
    await _durationSub?.cancel();
    await _player.dispose();
    await _mediaItem.close();
    await _state.close();
  }
}
