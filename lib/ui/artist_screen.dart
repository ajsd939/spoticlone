import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../services/artist_service.dart';
import '../core/theme.dart';
import '../audio/player_facade.dart';
import '../services/yt_bridge.dart';
import 'album_screen.dart';
import 'playlist_screen.dart';

// Artist page: header art + name, top tracks, albums/singles
// carousels. Track taps play via HomeScreen's _play (keeps the
// mini-player + _current in sync); albums push AlbumScreen.
class ArtistScreen extends StatefulWidget {
  final PlayerFacade handler;
  final String artistId;
  final YtBridge? bridge;
  final Future<void> Function(List<Track>, int) onPlayQueue;
  const ArtistScreen(
      {super.key,
      required this.handler,
      required this.artistId,
      this.bridge,
      required this.onPlayQueue});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late final Future<Artist> _future;

  @override
  void initState() {
    super.initState();
    _future = ArtistService(bridge: widget.bridge).getArtist(widget.artistId);
  }

  void _openAlbum(AlbumSummary a) {
    if (a.id.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlbumScreen(
          handler: widget.handler,
          albumId: a.id,
          bridge: widget.bridge,
          onPlayQueue: widget.onPlayQueue,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background),
      body: FutureBuilder<Artist>(
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
                child: Text('Could not load artist.\n${snap.error ?? ''}',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: AppColors.grey)),
              ),
            );
          }
          final a = snap.data!;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header(a)),
              if (a.topTracks.isNotEmpty) ...[
                _section('Top tracks'),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (c, i) {
                      final t = a.topTracks[i];
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
                        subtitle: Text(t.album.isNotEmpty ? t.album : t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.grey, fontSize: 13)),
                        onTap: () =>
                            widget.onPlayQueue(a.topTracks, i),
                        onLongPress: () =>
                            showAddToPlaylist(context, t),
                      );
                    },
                    childCount: a.topTracks.length,
                  ),
                ),
              ],
              if (a.albums.isNotEmpty) ...[
                _section('Albums'),
                _carousel(a.albums),
              ],
              if (a.singles.isNotEmpty) ...[
                _section('Singles'),
                _carousel(a.singles),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  Widget _header(Artist a) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          children: [
            ClipOval(
              child: CachedNetworkImage(
                imageUrl: a.artworkUrl,
                width: 140,
                height: 140,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                    width: 140,
                    height: 140,
                    color: AppColors.cardLight,
                    child: const Icon(Icons.person,
                        size: 64, color: Colors.white54)),
              ),
            ),
            const SizedBox(height: 12),
            Text(a.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700)),
            const Text('Artist',
                style: TextStyle(color: AppColors.grey, fontSize: 13)),
          ],
        ),
      );

  SliverToBoxAdapter _section(String title) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
        ),
      );

  SliverToBoxAdapter _carousel(List<AlbumSummary> items) =>
      SliverToBoxAdapter(
        child: SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (c, i) {
              final al = items[i];
              return GestureDetector(
                onTap: () => _openAlbum(al),
                child: Container(
                  width: 132,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: al.artworkUrl,
                          width: 132,
                          height: 132,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                              width: 132,
                              height: 132,
                              color: AppColors.cardLight,
                              child: const Icon(Icons.album,
                                  color: Colors.white54)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(al.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(al.year,
                          style: const TextStyle(
                              color: AppColors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
}
