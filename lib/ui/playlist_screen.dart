import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../core/di.dart';
import '../core/theme.dart';
import '../audio/player_facade.dart';
import '../services/downloads_service.dart';
import 'mini_player.dart';

// Playlist detail: header + removable track rows. Rebuilds live via
// ListenableBuilder so add/remove anywhere reflects instantly.
class PlaylistScreen extends StatelessWidget {
  final PlayerFacade handler;
  final String playlistId;
  final Future<void> Function(List<Track>, int) onPlayQueue;
  const PlaylistScreen(
      {super.key,
      required this.handler,
      required this.playlistId,
      required this.onPlayQueue});

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
              if (p.tracks.isNotEmpty)
                IconButton(
                  tooltip: 'Download playlist',
                  icon: const Icon(Icons.download_outlined),
                  onPressed: () => startDownloadCollection(
                      context, p.name, p.tracks),
                ),
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
          // Current-song bar (pushed pages cover Home's panel).
          bottomNavigationBar: MiniPlayer(
            handler: handler,
            onTap: () =>
                Navigator.popUntil(context, (r) => r.isFirst),
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
                                    onPlayQueue(p.tracks, 0),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration:
                                      const BoxDecoration(
                                    color: AppColors.accent,
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
                      onTap: () => onPlayQueue(p.tracks, i),
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
            // Offline download row (state follows the service).
            ListenableBuilder(
              listenable: getIt<DownloadsService>(),
              builder: (c, _) {
                final dl = getIt<DownloadsService>();
                final done = dl.isDownloaded(track.videoId);
                return ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: done
                          ? AppColors.accent.withValues(alpha: 0.2)
                          : AppColors.cardLight,
                    ),
                    child: Icon(
                        done
                            ? Icons.download_done
                            : Icons.download_outlined,
                        color: done
                            ? AppColors.accent
                            : Colors.white),
                  ),
                  title: Text(done ? 'Downloaded' : 'Download',
                      style:
                          const TextStyle(color: Colors.white)),
                  subtitle: Text(
                      done
                          ? 'Playable offline • tap to delete'
                          : 'Save for offline listening',
                      style: const TextStyle(
                          color: AppColors.grey, fontSize: 12)),
                  onTap: () async {
                    Navigator.pop(c);
                    if (done) {
                      await dl.delete(track.videoId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                                content:
                                    Text('Download deleted')));
                      }
                    } else {
                      await startDownload(context, track);
                    }
                  },
                );
              },
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
                            color: AppColors.accent)
                        : const Icon(Icons.add,
                            color: Colors.white54),
                    onTap: () async {
                      await svc.addToPlaylist(p.id, track);
                      if (c.mounted) {
                        Navigator.pop(c);
                        ScaffoldMessenger.of(c).showSnackBar(
                            SnackBar(
                                content:
                                    Text('Added to ${p.name}')));
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
                Navigator.pop(c);
                final name = await showNewPlaylistDialog(c);
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

// Download [track] with a blocking progress dialog.
Future<void> startDownload(BuildContext context, Track track) async {
  final svc = getIt<DownloadsService>();
  final progress = ValueNotifier<double>(0);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Downloading',
          style: TextStyle(color: Colors.white)),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (c, v, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: v),
            const SizedBox(height: 8),
            Text('${(v * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    ),
  );
  try {
    await svc.download(track,
        onProgress: (v) => progress.value = v);
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved for offline listening')));
  } catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')));
  } finally {
    progress.dispose();
  }
}

// Download every song in a playlist/album with a progress dialog.
Future<void> startDownloadCollection(
    BuildContext context, String label, List<Track> tracks) async {
  final svc = getIt<DownloadsService>();
  final messenger = ScaffoldMessenger.of(context);
  final todo =
      tracks.where((t) => !svc.isDownloaded(t.videoId)).toList();
  if (todo.isEmpty) {
    messenger.showSnackBar(
        SnackBar(content: Text('$label is already offline')));
    return;
  }
  final progress = ValueNotifier<(int, int)>((0, todo.length));
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Downloading $label',
          style: const TextStyle(color: Colors.white, fontSize: 18)),
      content: ValueListenableBuilder<(int, int)>(
        valueListenable: progress,
        builder: (c, v, _) {
          final done = v.$1, total = v.$2;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total),
              const SizedBox(height: 10),
              Text('$done of $total songs',
                  style: const TextStyle(color: Colors.white70)),
            ],
          );
        },
      ),
    ),
  );
  try {
    final r = await svc.downloadMany(todo,
        onProgress: (done, total) => progress.value = (done, total));
    if (!context.mounted) return;
    Navigator.pop(context);
    final failed = r.failed;
    messenger.showSnackBar(SnackBar(
      content: Text(failed == 0
          ? '$label saved offline (${r.ok} songs)'
          : '$label saved (${r.ok} of ${r.ok + failed} songs, $failed failed)'),
    ));
  } catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(
        SnackBar(content: Text('Download failed: $e')));
  } finally {
    progress.dispose();
  }
}

// Name prompt for a new playlist. Returns null on cancel.
Future<String?> showNewPlaylistDialog(BuildContext context) {  final ctrl = TextEditingController();
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

// Offline library: downloaded tracks with delete + tap-to-play.
class DownloadsScreen extends StatelessWidget {
  final PlayerFacade handler;
  final Future<void> Function(List<Track>, int) onPlayQueue;
  const DownloadsScreen(
      {super.key, required this.handler, required this.onPlayQueue});

  @override
  Widget build(BuildContext context) {
    final svc = getIt<DownloadsService>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Downloads'),
      ),
      // Current-song bar (pushed pages cover Home's panel).
      bottomNavigationBar: MiniPlayer(
        handler: handler,
        onTap: () =>
            Navigator.popUntil(context, (r) => r.isFirst),
      ),
      body: ListenableBuilder(
        listenable: svc,
        builder: (c, _) {
          final tracks = svc.tracks;
          if (tracks.isEmpty) {
            return const Center(
              child: Text(
                  'Nothing downloaded yet.\nLong-press a song, then Download.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.grey)),
            );
          }
          return ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (c, i) {
              final t = tracks[i];
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
                        color: AppColors.grey, fontSize: 13)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.download_done,
                        color: AppColors.accent, size: 18),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white54, size: 20),
                      onPressed: () =>
                          svc.delete(t.videoId),
                    ),
                  ],
                ),
                onTap: () => onPlayQueue(tracks, i),
              );
            },
          );
        },
      ),
    );
  }
}
