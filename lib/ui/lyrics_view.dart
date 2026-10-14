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
  int _lastActive = -1;

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
    }
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
            // Auto-scroll only when the active line actually changes:
            // animating on every position tick fights user scrolling.
            if (active != _lastActive) {
              _lastActive = active;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || !_scroll.hasClients) return;
                _scroll.animateTo(
                  (active * 44.0).clamp(
                      0.0, _scroll.position.maxScrollExtent),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                );
              });
            }
            return StreamBuilder<MediaItem?>(
              stream: widget.handler.mediaItem,
              builder: (c, m) => ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: 24),
                itemCount: lines.length,
                itemBuilder: (c, i) => GestureDetector(
                  // Tapping a line jumps playback to its timestamp.
                  onTap: () =>
                      widget.handler.seek(lines[i].time),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 24),
                    child: Text(
                      lines[i].text,
                      style: TextStyle(
                        fontSize: i == active ? 20 : 16,
                        fontWeight: i == active
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color:
                            i == active ? Colors.white : Colors.white38,
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
