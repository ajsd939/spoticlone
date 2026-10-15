import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import '../models/track.dart';
import '../services/lyrics_service.dart';
import '../audio/player_facade.dart';

// Synced lyrics: highlights active line from position stream,
// auto-scrolls. Shows fallback text when instrumental / missing.
class LyricsView extends StatefulWidget {
  final PlayerFacade handler;
  final Track track;
  const LyricsView({super.key, required this.handler, required this.track});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  late Future<List<LyricLine>> _future;
  final _scroll = ScrollController();
  // Measured per-line keys: pixel estimates drift with wrapped text,
  // so the active line is scrolled via ensureVisible instead.
  final _keys = <int, GlobalKey>{};
  int _lastActive = -1;
  // While the user is manually reading, auto-scroll backs off.
  DateTime? _userHoldUntil;

  @override
  void initState() {
    super.initState();
    _future = LyricsService().fetchSynced(widget.track);
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.track.videoId != widget.track.videoId) {
      _future = LyricsService().fetchSynced(widget.track);
      _lastActive = -1;
      _userHoldUntil = null;
      _keys.clear();
    }
  }

  /// Scroll the measured line widget into view (no pixel math,
  /// so wrapped/long lines can never drift out of sight).
  void _ensureVisible(int i, {bool fast = false}) {
    if (!mounted) return;
    final ctx = _keys[i]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.35,
      duration: Duration(milliseconds: fast ? 200 : 400),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LyricLine>>(
      future: _future,
      builder: (c, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final lines = snap.data ?? [];
        if (lines.isEmpty) {
          return const Center(
            child: Text('No synced lyrics found',
                style: TextStyle(color: Colors.white54)),
          );
        }
        return StreamBuilder<Duration>(
          stream: widget.handler.positionStream,
          builder: (c, pos) {
            final now = pos.data ?? Duration.zero;
            var active = 0;
            for (var i = 0; i < lines.length; i++) {
              if (lines[i].time <= now) active = i;
            }
            // Auto-scroll only when the active line actually changes,
            // and never while the user is manually reading.
            if (active != _lastActive) {
              _lastActive = active;
              final hold = _userHoldUntil;
              if (hold == null || DateTime.now().isAfter(hold)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _ensureVisible(active);
                });
              }
            }
            return StreamBuilder<MediaItem?>(
              stream: widget.handler.mediaItem,
              builder: (c, m) =>
                  NotificationListener<UserScrollNotification>(
                onNotification: (_) {
                  // Back off auto-scroll for a while after a manual drag.
                  _userHoldUntil =
                      DateTime.now().add(const Duration(seconds: 8));
                  return false;
                },
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  itemCount: lines.length,
                  itemBuilder: (c, i) => GestureDetector(
                    // Tapping a line jumps playback to its timestamp.
                    // Feedback is instant (highlight + scroll move now);
                    // the audio follows as soon as the seek lands.
                    onTap: () {
                      _lastActive = i;
                      _userHoldUntil = null;
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) {
                        _ensureVisible(i, fast: true);
                      });
                      widget.handler.seek(lines[i].time);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      key: _keys.putIfAbsent(i, () => GlobalKey()),
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 24),
                      child: Text(
                        lines[i].text,
                        style: TextStyle(
                          fontSize: i == active ? 20 : 16,
                          fontWeight: i == active
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: i == active
                              ? Colors.white
                              : Colors.white38,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
