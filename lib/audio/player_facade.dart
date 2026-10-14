import 'package:audio_service/audio_service.dart';
import '../models/track.dart';
import 'audio_handler.dart';

// UI-facing player API shared by mobile (audio_service foreground
// service) and desktop (media_kit). Reuses audio_service's plain
// data types (MediaItem/PlaybackState) on both platforms so the
// widgets stay identical.
abstract class PlayerFacade {
  Stream<MediaItem?> get mediaItem;
  Stream<PlaybackState> get playbackState;
  Stream<Duration> get positionStream;
  Future<void> playTrack(Track t);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> skipToPrevious();
  Future<void> skipToNext();
}

// Thin delegate: lets existing widgets take PlayerFacade while the
// real work stays in AppAudioHandler.
class AudioServiceFacade implements PlayerFacade {
  final AppAudioHandler _h;
  AudioServiceFacade(this._h);

  @override
  Stream<MediaItem?> get mediaItem => _h.mediaItem;
  @override
  Stream<PlaybackState> get playbackState => _h.playbackState;
  @override
  Stream<Duration> get positionStream => _h.positionStream;
  @override
  Future<void> playTrack(Track t) => _h.playTrack(t);
  @override
  Future<void> play() => _h.play();
  @override
  Future<void> pause() => _h.pause();
  @override
  Future<void> seek(Duration position) => _h.seek(position);
  @override
  Future<void> skipToPrevious() => _h.skipToPrevious();
  @override
  Future<void> skipToNext() => _h.skipToNext();
}
