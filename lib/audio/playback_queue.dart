import '../models/track.dart';
import 'player_facade.dart' show QueueRepeat;

// Pure-Dart queue state machine shared by both players (unit-tested).
// Tracks stay in insertion order; [_order] maps play position to
// track index so shuffle never mutates the list the UI holds.
class PlaybackQueue {
  List<Track> _tracks = const [];
  List<int> _order = const [];
  int _pos = 0;
  bool _shuffle = false;
  QueueRepeat _repeat = QueueRepeat.off;

  List<Track> get tracks => _tracks;
  bool get shuffle => _shuffle;
  QueueRepeat get repeat => _repeat;
  bool get isEmpty => _tracks.isEmpty;

  /// Track index currently addressed.
  int get index => _tracks.isEmpty ? 0 : _order[_pos];
  Track? get current => _tracks.isEmpty ? null : _tracks[index];

  void setQueue(List<Track> tracks, {int startIndex = 0}) {
    _tracks = List<Track>.of(tracks);
    if (_tracks.isEmpty) {
      _order = const [];
      _pos = 0;
      return;
    }
    final start = startIndex.clamp(0, _tracks.length - 1);
    if (_shuffle) {
      _order = _shuffledFrom(start);
      _pos = 0;
    } else {
      _order = List<int>.generate(_tracks.length, (i) => i);
      _pos = start;
    }
  }

  List<int> _shuffledFrom(int start) {
    final rest = List<int>.generate(_tracks.length, (i) => i)
      ..remove(start)
      ..shuffle();
    return [start, ...rest];
  }

  /// Move to next. False = end of queue with repeat off (stop).
  /// Repeat-one is handled by the player (re-seek), not here.
  bool advance() {
    if (_tracks.isEmpty) return false;
    if (_pos + 1 < _order.length) {
      _pos++;
      return true;
    }
    if (_repeat == QueueRepeat.all) {
      _pos = 0;
      return true;
    }
    return false;
  }

  /// Move to previous. False = already at head (player seeks to 0).
  bool back() {
    if (_tracks.isEmpty) return false;
    if (_pos > 0) {
      _pos--;
      return true;
    }
    if (_repeat == QueueRepeat.all) {
      _pos = _order.length - 1;
      return true;
    }
    return false;
  }

  void setShuffle(bool v) {
    if (_tracks.isEmpty) {
      _shuffle = v;
      return;
    }
    if (v == _shuffle) return;
    final cur = index;
    _shuffle = v;
    if (v) {
      _order = _shuffledFrom(cur);
      _pos = 0;
    } else {
      _order = List<int>.generate(_tracks.length, (i) => i);
      _pos = cur;
    }
  }

  void cycleRepeat() {
    _repeat =
        QueueRepeat.values[(_repeat.index + 1) % QueueRepeat.values.length];
  }
}
