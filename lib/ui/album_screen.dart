import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../services/artist_service.dart';
import '../core/theme.dart';
import '../audio/player_facade.dart';
import '../services/yt_bridge.dart';
import 'mini_player.dart';
import 'playlist_screen.dart';

// Album page: cover header + numbered track rows (Spotify style).
// Track taps play via HomeScreen's _play.
class AlbumScreen extends StatefulWidget {
  final PlayerFacade handler;
  final String albumId;
  final YtBridge? bridge;
  final Future<void> Function(List<Track>, int) onPlayQueue;
  const AlbumScreen(
      {super.key,
      required this.handler,
      required this.albumId,
      this.bridge,
      required this.onPlayQueue});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  late final Future<Album> _future;

  @override
  void initState() {
    super.initState();
    _future = ArtistService(bridge: widget.bridge).getAlbum(widget.albumId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background),
      // Current-song bar: pushed pages cover Home's panel, so the
      // mini-player is repeated here (tap pops back to Home).
      bottomNavigationBar: MiniPlayer(
        handler: widget.handler,
        onTap: () =>
            Navigator.popUntil(context, (r) => r.isFirst),
      ),
      body: FutureBuilder<Album>(
        future: _future,
        builder: (c, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child:
                    CircularProgressIndicator(color: AppColors.green));
          }
          if (snap.hasError || !snap.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load album.\n${snap.error ?? ''}',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: AppColors.grey)),
              ),
            );
          }
          final a = snap.data!;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: a.artworkUrl,
                          width: 140,
                          height: 140,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                              width: 140,
                              height: 140,
                              color: AppColors.cardLight,
                              child: const Icon(Icons.album,
                                  size: 56,
                                  color: Colors.white54)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(a.title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                                [a.artist, a.year]
                                    .where((s) => s.isNotEmpty)
                                    .join(' • '),
                                style: const TextStyle(
                                    color: AppColors.grey,
                                    fontSize: 13)),
                            const SizedBox(height: 10),
                            if (a.tracks.isNotEmpty)
                              GestureDetector(
                                onTap: () => widget.onPlayQueue(
                                    a.tracks, 0),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration:
                                      const BoxDecoration(
                                    color: AppColors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.play_arrow,
                                      color: Colors.black, size: 30),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (c, i) {
                    final t = a.tracks[i];
                    return ListTile(
                      leading: SizedBox(
                        width: 28,
                        child: Text('${i + 1}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.grey,
                                fontWeight: FontWeight.w600)),
                      ),
                      title: Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500)),
                      subtitle: Text(t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.grey, fontSize: 13)),
                      trailing: Text(
                          '${t.durationSec ~/ 60}:${(t.durationSec % 60).toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              color: AppColors.grey, fontSize: 12)),
                      onTap: () =>
                          widget.onPlayQueue(a.tracks, i),
                      onLongPress: () =>
                          showAddToPlaylist(context, t),
                    );
                  },
                  childCount: a.tracks.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}
