import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../audio/player_facade.dart';

// Collapsed bar: art + title/artist + play/pause, with a thin
// Spotify-style progress line pinned to its bottom edge.
class MiniPlayer extends StatelessWidget {
  final PlayerFacade handler;
  final VoidCallback onTap;
  const MiniPlayer({super.key, required this.handler, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (c, snap) {
        final m = snap.data;
        if (m == null) {
          return const SizedBox(
            height: 64,
            child: Center(
                child: Text('Search and pick a track',
                    style: TextStyle(color: Colors.white54))),
          );
        }
        final total = m.duration ?? Duration.zero;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            height: 64,
            margin:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black54,
                    blurRadius: 8,
                    offset: Offset(0, 2)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        CachedNetworkImage(
                          imageUrl: m.artUri?.toString() ?? '',
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                              width: 52,
                              height: 52,
                              color: Colors.white10,
                              child: const Icon(Icons.music_note,
                                  color: Colors.white54)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(m.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              Text(m.artist ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                        StreamBuilder<PlaybackState>(
                          stream: handler.playbackState,
                          builder: (c, s) {
                            final playing =
                                s.data?.playing ?? false;
                            return IconButton(
                              icon: Icon(
                                  playing
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  size: 30,
                                  color: Colors.white),
                              onPressed: () => playing
                                  ? handler.pause()
                                  : handler.play(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // Thin progress line (Spotify signature).
                  StreamBuilder<Duration>(
                    stream: handler.positionStream,
                    builder: (c, pos) {
                      final p = pos.data ?? Duration.zero;
                      final v = total.inMilliseconds <= 0
                          ? 0.0
                          : (p.inMilliseconds /
                                  total.inMilliseconds)
                              .clamp(0.0, 1.0);
                      return LinearProgressIndicator(
                        value: v,
                        minHeight: 2,
                        backgroundColor: Colors.white10,
                        valueColor:
                            const AlwaysStoppedAnimation(Colors.white),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
