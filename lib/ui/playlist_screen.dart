import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../core/di.dart';
import '../core/theme.dart';
import '../audio/player_facade.dart';

// Playlist detail: header + removable track rows. Rebuilds live via
// ListenableBuilder so add/remove anywhere reflects instantly.
class PlaylistScreen extends StatelessWidget {
  final PlayerFacade handler;
  final String playlistId;
  final Future<void> Function(Track) onPlay;
  const PlaylistScreen(
      {super.key,
      required this.handler,
      required this.playlistId,
      required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final svc = getIt<PlaylistService>();
    return ListenableBuilder(
      listenable: svc,
      builder: (c, _) {
        final p = svc.byId(playlistId);
        if (p == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(backgroundColor: AppColors.background),
            body: const Center(
                child: Text('Playlist deleted',
                    style: TextStyle(color: AppColors.grey))),
          );
        }
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            title: Text(p.name),
            actions: [
              if (p.id != PlaylistService.likedId)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await svc.deletePlaylist(p.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      art(p, 96),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700)),
                            Text(
                                '${p.tracks.length} song${p.tracks.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                    color: AppColors.grey)),
                            const SizedBox(height: 10),
                            if (p.tracks.isNotEmpty)
                              GestureDetector(
                                onTap: () =>
                                    onPlay(p.tracks.first),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration:
                                      const BoxDecoration(
                                    color: AppColors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                      Icons.play_arrow,
                                      color: Colors.black,
                                      size: 28),
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
                    final t = p.tracks[i];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: t.artworkUrl,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                              width: 48,
                              height: 48,
                              color: AppColors.cardLight,
                              child: const Icon(Icons.music_note,
                                  color: Colors.white54)),
                        ),
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
                              color: AppColors.grey,
                              fontSize: 13)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white54, size: 20),
                        onPressed: () => svc.removeFromPlaylist(
                            p.id, t.videoId),
                      ),
                      onTap: () => onPlay(t),
                    );
                  },
                  childCount: p.tracks.length,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget art(Playlist p, double size) {
    if (p.id == PlaylistService.likedId) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            colors: [Color(0xFF450AF5), Color(0xFFC4B5FD)],
          ),
        ),
        child: Icon(Icons.favorite,
            color: Colors.white, size: size * 0.45),
      );
    }
    final art = p.tracks
        .map((t) => t.artworkUrl)
        .firstWhere((u) => u.isNotEmpty, orElse: () => '');
    if (art.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: art,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) =>
              _fallbackIcon(size),
        ),
      );
    }
    return _fallbackIcon(size);
  }

  static Widget _fallbackIcon(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: AppColors.cardLight,
        ),
        child: Icon(Icons.queue_music,
            color: Colors.white54, size: size * 0.45),
      );
}

// Bottom sheet: pick a playlist (or create one) for [track].
Future<void> showAddToPlaylist(BuildContext context, Track track) {
  final svc = getIt<PlaylistService>();
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (c) => ListenableBuilder(
      listenable: svc,
      builder: (c, _) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Add to playlist',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: svc.playlists.length,
                itemBuilder: (c, i) {
                  final p = svc.playlists[i];
                  final has = p.tracks.any(
                      (e) => e.videoId == track.videoId);
                  return ListTile(
                    leading: PlaylistScreen.art(p, 44),
                    title: Text(p.name,
                        style: const TextStyle(
                            color: Colors.white)),
                    subtitle: Text('${p.tracks.length} songs',
                        style: const TextStyle(
                            color: AppColors.grey,
                            fontSize: 12)),
                    trailing: has
                        ? const Icon(Icons.check,
                            color: AppColors.green)
                        : const Icon(Icons.add,
                            color: Colors.white54),
                    onTap: () async {
                      await svc.addToPlaylist(p.id, track);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(
                                content: Text(
                                    'Added to ${p.name}')));
                      }
                    },
                  );
                },
              ),
            ),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.cardLight,
                ),
                child: const Icon(Icons.add,
                    color: Colors.white),
              ),
              title: const Text('New playlist',
                  style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final name = await showNewPlaylistDialog(context);
                if (name == null) return;
                final p = await svc.createPlaylist(name);
                await svc.addToPlaylist(p.id, track);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

// Name prompt for a new playlist. Returns null on cancel.
Future<String?> showNewPlaylistDialog(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('New playlist',
          style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Playlist name',
          hintStyle: TextStyle(color: Colors.white38),
        ),
        onSubmitted: (_) =>
            Navigator.pop(c, ctrl.text),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctrl.text),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}
