import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/stream_service.dart';

// Single background handler: just_audio (ExoPlayer) does gapless
// decoding, audio_service exposes MediaItem + notification / lock-screen.
class AppAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();
  final _stream = StreamService();
  // Generation counter: a slow yt-dlp resolve must never hijack audio
  // after the user already tapped a newer track.
  int _playGen = 0;

  AppAudioHandler() {
    _player.playbackEventStream.map(_toState).pipe(playbackState);
  }

  PlaybackState _toState(PlaybackEvent e) => PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: e.currentIndex,
      );

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  Future<void> playTrack(Track t) async {
    final gen = ++_playGen;
    // NOTE: mediaItem is added only AFTER resolve succeeds. Adding it
    // eagerly leaves the new track's title/art stuck in the mini-player,
    // notification and lock-screen when resolve fails, while the full
    // player still shows the previous song.
    await _player.stop();
    if (gen != _playGen) return; // superseded while stopping
    final s = await _stream.resolve(t); // yt-dlp direct URL, fresh each play
    if (gen != _playGen) return; // superseded during resolve: don't hijack
    mediaItem.add(MediaItem(
      id: t.videoId,
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: Duration(seconds: t.durationSec),
      artUri: Uri.tryParse(t.artworkUrl),
    ));
    await _player.setAudioSource(
      AudioSource.uri(Uri.parse(s.url), tag: mediaItem.value),
      preload: true,
    );
    if (gen != _playGen) return;
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
  @override
  Future<void> stop() => _player.stop();
}
