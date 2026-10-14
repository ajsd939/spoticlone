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
  StreamSubscription? _sub;

  DesktopPlayer({required YtBridge bridge})
      : _stream = StreamService(bridge: bridge) {
    // Mirror playback state into audio_service-shaped updates.
    _sub = Rx.combineLatest2<bool, bool, void>(
      _player.stream.playing,
      _player.stream.completed,
      (playing, completed) {
        final cur = _state.value;
        _state.add(cur.copyWith(
          playing: playing && !completed,
          processingState: completed
              ? AudioProcessingState.completed
              : AudioProcessingState.ready,
        ));
      },
    ).listen((_) {});
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
    await _player.stop();
    if (gen != _gen) return;
    final s = await _stream.resolve(t);
    if (gen != _gen) return;
    final item = MediaItem(
      id: t.videoId,
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: Duration(seconds: t.durationSec),
      artUri: Uri.tryParse(t.artworkUrl),
    );
    _mediaItem.add(item);
    await _player.open(mk.Media(s.url));
    if (gen != _gen) return;
    await _player.play();
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
    await _sub?.cancel();
    await _player.dispose();
    await _mediaItem.close();
    await _state.close();
  }
}
