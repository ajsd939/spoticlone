import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import '../models/track.dart';
import '../services/stream_service.dart';
import '../core/di.dart';
import '../services/downloads_service.dart';
import 'playback_queue.dart';
import 'player_facade.dart' show QueueRepeat;

// Single background handler: just_audio (ExoPlayer) decodes,
// audio_service exposes MediaItem + notification / lock-screen.
// Queue: the next track's URL is resolved while the current one
// plays (resolve-ahead), so album/context play-through stays tight.
class AppAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  // Large buffers ride out throughput dips without rebuffer pauses.
  // Audio-only, so even minutes of buffer are just a few MB. Resume
  // thresholds stay low so seeks/line-taps restart almost instantly.
  final _player = AudioPlayer(
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: Duration(seconds: 60),
        maxBufferDuration: Duration(minutes: 5),
        bufferForPlaybackDuration: Duration(milliseconds: 1500),
        bufferForPlaybackAfterRebufferDuration:
            Duration(seconds: 3),
      ),
    ),
  );
  final _stream = StreamService();
  final _queue = PlaybackQueue();
  // Generation counter: a slow yt-dlp resolve must never hijack audio
  // after the user already tapped a newer track.
  int _playGen = 0;
  // Resolved stream URLs by videoId (survives queue switches).
  final _resolved = <String, ({String url, int duration, String ext})>{};
  final _queueIndex = BehaviorSubject<int>.seeded(0);
  final _shuffleState = BehaviorSubject<bool>.seeded(false);
  final _repeatState =
      BehaviorSubject<QueueRepeat>.seeded(QueueRepeat.off);

  AppAudioHandler() {
    _player.playbackEventStream.map(_toState).pipe(playbackState);
    // Ground-truth duration: metadata is often 0/wrong, which froze
    // the UI/notification total at 0:00 while audio played fine.
    _player.durationStream.listen((d) {
      final cur = mediaItem.value;
      if (d != null &&
          d.inMilliseconds > 0 &&
          cur != null &&
          cur.duration != d) {
        mediaItem.add(cur.copyWith(duration: d));
      }
    });
    // Track end: repeat-one re-seeks, otherwise advance the queue.
    _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onCompleted();
    });
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

  List<Track> get trackQueue => _queue.tracks;
  Stream<int> get queueIndexStream => _queueIndex.stream;
  Stream<bool> get shuffleStream => _shuffleState.stream;
  Stream<QueueRepeat> get repeatStream => _repeatState.stream;

  Future<void> playTrack(Track t) => playTracks([t]);

  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    final gen = ++_playGen;
    if (tracks.isEmpty) return;
    _queue.setQueue(tracks, startIndex: startIndex);
    await _playCurrent(gen);
  }

  Future<void> _playCurrent(int gen) async {
    var t = _queue.current;
    if (t == null) return;
    // NOTE: mediaItem is added only AFTER resolve succeeds. Adding it
    // eagerly leaves the new track's title/art stuck in the mini-player,
    // notification and lock-screen when resolve fails, while the full
    // player still shows the previous song.
    await _player.stop();
    if (gen != _playGen) return; // superseded while stopping
    // Fill artist/duration gaps (ATV uploads) before anything
    // observes this track, so UI, lyrics and notification agree.
    t = await _enrichIfNeeded(t);
    if (gen != _playGen) return;
    _queue.updateTrack(_queue.index, t);
    _queueIndex.add(_queue.index);
    // Offline first: a downloaded file plays instantly, no resolve.
    final local = _localFile(t);
    final s = local != null
        ? (url: Uri.file(local).toString(), duration: t.durationSec, ext: 'dl')
        : await _resolveCached(t);
    if (gen != _playGen) return; // superseded during resolve: don't hijack
    // Prefer the resolved stream duration (metadata is often 0/wrong);
    // the notification total would otherwise read 0:00 while playing.
    final totalSec = s.duration > 0 ? s.duration : t.durationSec;
    mediaItem.add(MediaItem(
      id: t.videoId,
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: Duration(seconds: totalSec),
      artUri: Uri.tryParse(t.artworkUrl),
    ));
    await _player.setAudioSource(
      AudioSource.uri(Uri.parse(s.url), tag: mediaItem.value),
      preload: true,
    );
    if (gen != _playGen) return;
    await _player.play();
    // Resolve the next track while this one plays (gapless-ish).
    _prefetchNext(gen);
  }

  Future<({String url, int duration, String ext})> _resolveCached(Track t) async {
    final hit = _resolved[t.videoId];
    if (hit != null && hit.url.isNotEmpty) return hit;
    final s = await _stream.resolve(t); // yt-dlp URL, fresh each play
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
      return getIt<DownloadsService>().localPath(t.videoId);
    } catch (_) {
      return null;
    }
  }

  void _prefetchNext(int gen) {
    final order = _upcomingIndices();
    if (order.isEmpty) return;
    final next = _queue.tracks[order.first];
    if (_resolved.containsKey(next.videoId)) return;
    if (_localFile(next) != null) return; // offline: nothing to fetch
    // Fire-and-forget: guarded so a queue switch drops the result.
    _stream.resolve(next).then((s) {
      if (gen == _playGen) _resolved[next.videoId] = s;
    }).catchError((_) {
      // Prefetch failure is silent: the real attempt retries on advance.
    });
  }

  /// Track index that will play after the current one (repeat-aware).
  /// Peeked on a scratch copy so the live queue is never mutated.
  List<int> _upcomingIndices() {
    final scratch = PlaybackQueue()
      ..setQueue(_queue.tracks, startIndex: _queue.index);
    if (_queue.shuffle) scratch.setShuffle(true);
    // scratch starts at current; step once to peek next.
    if (_queue.repeat == QueueRepeat.one) return [scratch.index];
    if (scratch.advance()) return [scratch.index];
    return [];
  }

  Future<void> _onCompleted() async {
    final gen = _playGen;
    if (_queue.repeat == QueueRepeat.one) {
      await _player.seek(Duration.zero);
      if (gen == _playGen) await _player.play();
      return;
    }
    if (_queue.advance()) {
      await _playCurrent(gen);
    }
    // Else: end of queue with repeat off. The completed state
    // surfaces through playbackState; UI stays on the last track.
  }

  Future<void> toggleShuffle() async {
    _queue.setShuffle(!_queue.shuffle);
    _shuffleState.add(_queue.shuffle);
  }

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
    // Standard behavior: restart when well into the track.
    if (_player.position > const Duration(seconds: 3)) {
      return _player.seek(Duration.zero);
    }
    if (_queue.back()) {
      final gen = ++_playGen;
      await _playCurrent(gen);
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.advance()) {
      final gen = ++_playGen;
      await _playCurrent(gen);
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> stop() => _player.stop();
}
