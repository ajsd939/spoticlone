import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import '../models/track.dart';
import '../models/artist.dart';
import '../models/playlist.dart';
import '../core/di.dart';
import '../services/search_service.dart';
import '../services/stream_service.dart';
import '../services/update_service.dart';
import '../services/ota_update_service.dart';
import '../services/downloads_service.dart';
import '../services/notification_permission_service.dart';
import '../core/theme.dart';
import '../audio/player_facade.dart';
import '../services/yt_bridge.dart';
import 'mini_player.dart';
import 'full_player.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import 'playlist_screen.dart';

// Single-screen Spotify-style home: greeting header, search,
// quick-pick grid, horizontal Top-results carousel, track list,
// plus the sticky mini-player expanding into the full player.
class HomeScreen extends StatefulWidget {
  final PlayerFacade handler;
  final YtBridge? bridge; // null = Android Chaquopy bridge
  const HomeScreen({super.key, required this.handler, this.bridge});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = SearchService();
  late final StreamService _stream;
  final _panel = PanelController();
  final _query = TextEditingController();
  List<Track> _results = [];
  List<ArtistRef> _artists = [];
  List<AlbumSummary> _albums = [];
  Track? _current;
  bool _loading = false;
  bool _resolving = false;
  // Which track the in-flight resolve belongs to (spinner), plus a
  // generation counter so a stale slow resolve can't overwrite _current
  // with the previously tapped song.
  String? _resolvingId;
  int _playGen = 0;
  int _searchGen = 0;
  StreamSubscription<int>? _indexSub;

  static const _shortcuts = [
    ('Top Hits', 'top hits 2026', Color(0xFFE13300), Icons.local_fire_department),
    ('Pop', 'pop hits', Color(0xFF8D67AB), Icons.mic),
    ('Hip-Hop', 'hip hop rap', Color(0xFFBA5D07), Icons.graphic_eq),
    ('Rock', 'rock classics', Color(0xFF777777), Icons.electric_bolt),
    ('Chill', 'chill acoustic', Color(0xFF477D95), Icons.waves),
    ('Party', 'party dance', Color(0xFF148A08), Icons.celebration),
  ];

  @override
  void initState() {
    super.initState();
    _stream = StreamService(bridge: widget.bridge);
    // Follow queue advances (auto-next, notification buttons) so the
    // UI never shows a stale track while another one plays.
    _indexSub = widget.handler.queueIndexStream.listen((i) {
      final q = widget.handler.trackQueue;
      if (!mounted || i < 0 || i >= q.length) return;
      // Always follow: enrichment can change artist/duration in place
      // without changing the videoId.
      setState(() => _current = q[i]);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      NotificationPermissionService.ensureRequested(context);
    });
    _checkUpdate();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _checkUpdate() async {
    final rel = await UpdateService().newerRelease();
    if (rel == null || !mounted) return;
    final ota = OtaUpdateService();
    final asset = ota.assetForPlatform(rel);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Update ${rel.tag} available'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
                rel.notes.isNotEmpty
                    ? rel.notes
                    : 'Bug fixes and improvements.',
                style: const TextStyle(fontSize: 13)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Later')),
          if (asset != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                _startOta(ota, rel, asset);
              },
              child: const Text('Download & Install'),
            ),
        ],
      ),
    );
  }

  Future<void> _startOta(
      OtaUpdateService ota, ReleaseInfo rel, ReleaseAsset asset) async {
    final progress = ValueNotifier<double>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text('Downloading ${rel.tag}'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (c, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v),
              const SizedBox(height: 8),
              Text('${(v * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    );
    try {
      final ext =
          asset.name.toLowerCase().endsWith('.apk') ? '.apk' : '.exe';
      final file = await ota.download(asset,
          filename: 'nocrift-\${rel.tag}$ext',
          onProgress: (v) => progress.value = v);
      if (!mounted) return;
      Navigator.pop(context); // close progress
      await ota.install(file);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')));
    } finally {
      progress.dispose();
    }
  }

  Future<void> _doSearch(String q) async {
    if (q.trim().isEmpty) return;
    // Generation guard: fast typing fires overlapping searches and the
    // slowest (oldest query) must not overwrite the newest results.
    final gen = ++_searchGen;
    setState(() => _loading = true);
    try {
      try {
        final r = await _stream.pythonSearch(q);
        if (gen != _searchGen) return; // superseded by newer keystrokes
        _results = r.songs;
        _artists = r.artists;
        _albums = r.albums;
      } catch (_) {
        if (gen != _searchGen) return;
        _results = await _search.search(q);
        if (gen != _searchGen) return;
        _artists = [];
        _albums = [];
      }
      if (_results.isEmpty &&
          _artists.isEmpty &&
          _albums.isEmpty &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No results found')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    } finally {
      if (gen == _searchGen && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Library subtitle: permanent saves plus the disposable cache.
  String _downloadSubtitle() {
    final svc = getIt<DownloadsService>();
    final saved = svc.count;
    final cached = svc.cache?.count ?? 0;
    if (saved == 0 && cached == 0) return 'Songs play offline automatically';
    final parts = <String>[
      if (saved > 0) '$saved saved',
      if (cached > 0) '$cached cached',
    ];
    return parts.join(' • ');
  }

  /// Play [list] from [index] through the end (album order, or
  /// shuffled when shuffle is on). Replaces _play everywhere.
  Future<void> _playQueue(List<Track> list, int index) async {
    if (list.isEmpty) return;
    final i = index.clamp(0, list.length - 1);
    final gen = ++_playGen;
    final prev = _current;
    final t = list[i];
    // Optimistic UI: the tapped track shows instantly. Waiting for the
    // 15s resolve left the old song on screen in silence, which read as
    // "stuck on the last song". Rolled back below on failure.
    setState(() {
      _resolving = true;
      _resolvingId = t.videoId;
      _current = t;
    });
    try {
      await widget.handler.playTracks(list, startIndex: i);
      if (gen != _playGen || !mounted) return; // a newer tap won
    } catch (e) {
      if (gen != _playGen || !mounted) return;
      setState(() => _current = prev); // roll back to what was playing
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playback failed: $e')),
      );
    } finally {
      if (gen == _playGen && mounted) {
        setState(() {
          _resolving = false;
          _resolvingId = null;
        });
      }
    }
  }

  void _openArtist(String artistId) {
    if (artistId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArtistScreen(
          handler: widget.handler,
          artistId: artistId,
          bridge: widget.bridge,
          onPlayQueue: _playQueue,
        ),
      ),
    );
  }

  void _openAlbum(String albumId) {
    if (albumId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlbumScreen(
          handler: widget.handler,
          albumId: albumId,
          bridge: widget.bridge,
          onPlayQueue: _playQueue,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _indexSub?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SlidingUpPanel(
        controller: _panel,
        minHeight: 76,
        maxHeight: MediaQuery.of(context).size.height,
        parallaxEnabled: true,
        backdropEnabled: true,
        color: AppColors.background,
        collapsed: MiniPlayer(
          handler: widget.handler,
          onTap: () => _panel.open(),
        ),
        panel: _current == null
            ? const Center(
                child: Text('Pick a track to open player',
                    style: TextStyle(color: Colors.white54)))
            : FullPlayer(
                handler: widget.handler,
                track: _current!,
                onCollapse: () => _panel.close(),
                onArtistTap: _openArtist,
              ),
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              // Greeting header.
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_greeting,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                          icon: const Icon(
                              Icons.notifications_none,
                              color: Colors.white),
                          onPressed: () {}),
                      IconButton(
                          icon: const Icon(Icons.history,
                              color: Colors.white),
                          onPressed: () {}),
                      IconButton(
                          icon: const Icon(Icons.settings_outlined,
                              color: Colors.white),
                          onPressed: () {}),
                    ],
                  ),
                ),
              ),
              // Search bar.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: SearchBar(
                    controller: _query,
                    hintText: 'What do you want to listen to?',
                    leading: const Icon(Icons.search),
                    backgroundColor:
                        const WidgetStatePropertyAll(Colors.white),
                    hintStyle: const WidgetStatePropertyAll(TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600)),
                    textStyle: const WidgetStatePropertyAll(TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600)),
                    onSubmitted: _doSearch,
                  ),
                ),
              ),
              if (_loading || _resolving)
                const SliverToBoxAdapter(
                  child: LinearProgressIndicator(
                      color: AppColors.accent,
                      backgroundColor: Colors.transparent),
                ),
              // Quick-pick grid: results first, else genre shortcuts.
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      mainAxisExtent: 56,
                    ),
                    itemCount: 6,
                    itemBuilder: (c, i) {
                      if (_results.length > i) {
                        final t = _results[i];
                        return _quickCard(
                          title: t.title,
                          artUrl: t.artworkUrl,
                          onTap: () => _playQueue(_results, i),
                        );
                      }
                      final s = _shortcuts[i];
                      return _quickCard(
                        title: s.$1,
                        color: s.$3,
                        icon: s.$4,
                        onTap: () {
                          _query.text = s.$2;
                          _doSearch(s.$2);
                        },
                      );
                    },
                  ),
                ),
              ),
              // Your Library: Liked Songs + user playlists.
              SliverToBoxAdapter(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    getIt<PlaylistService>(),
                    getIt<DownloadsService>(),
                    if (getIt<DownloadsService>().cache != null)
                      getIt<DownloadsService>().cache!,
                  ]),
                  builder: (c, _) {
                    final svc = getIt<PlaylistService>();
                    return Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              16, 20, 8, 4),
                          child: Row(
                            children: [
                              const Text('Your Library',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight:
                                          FontWeight.w700)),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.add,
                                    color: Colors.white54),
                                onPressed: () async {
                                  final name =
                                      await showNewPlaylistDialog(
                                          context);
                                  if (name == null) return;
                                  await svc
                                      .createPlaylist(name);
                                },
                              ),
                            ],
                          ),
                        ),
                        // Offline downloads entry.
                        ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(8),
                              color: AppColors.accent
                                  .withValues(alpha: 0.15),
                            ),
                            child: const Icon(
                                Icons.download_done,
                                color: AppColors.accent),
                          ),
                          title: const Text('Downloads',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500)),
                          subtitle: Text(
                              _downloadSubtitle(),
                              style: const TextStyle(
                                  color: AppColors.grey,
                                  fontSize: 13)),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DownloadsScreen(
                                handler: widget.handler,
                                onPlayQueue: _playQueue,
                              ),
                            ),
                          ),
                        ),
                        ...svc.playlists.map((p) => ListTile(
                              leading:
                                  PlaylistScreen.art(p, 48),
                              title: Text(p.name,
                                  maxLines: 1,
                                  overflow:
                                      TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight:
                                          FontWeight.w500)),
                              subtitle: Text(
                                  '${p.tracks.length} song${p.tracks.length == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                      color: AppColors.grey,
                                      fontSize: 13)),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PlaylistScreen(
                                    handler: widget.handler,
                                    playlistId: p.id,
                                    onPlayQueue: _playQueue,
                                  ),
                                ),
                              ),
                            )),
                      ],
                    );
                  },
                ),
              ),
              // Artists row (circles, Spotify style).
              if (_artists.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding:
                            EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: Text('Artists',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700)),
                      ),
                      SizedBox(
                        height: 140,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16),
                          itemCount: _artists.length,
                          itemBuilder: (c, i) {
                            final ar = _artists[i];
                            return GestureDetector(
                              onTap: () =>
                                  _openArtist(ar.id),
                              child: Container(
                                width: 96,
                                margin: const EdgeInsets.only(
                                    right: 12),
                                child: Column(
                                  children: [
                                    ClipOval(
                                      child: CachedNetworkImage(
                                        imageUrl: ar.artworkUrl,
                                        width: 96,
                                        height: 96,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            Container(
                                                width: 96,
                                                height: 96,
                                                color: AppColors
                                                    .cardLight,
                                                child: const Icon(
                                                    Icons.person,
                                                    size: 40,
                                                    color: Colors
                                                        .white54)),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(ar.name,
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight:
                                                FontWeight.w600)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              // Albums carousel from search.
              if (_albums.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding:
                            EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: Text('Albums',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700)),
                      ),
                      SizedBox(
                        height: 190,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16),
                          itemCount: _albums.length,
                          itemBuilder: (c, i) {
                            final al = _albums[i];
                            return GestureDetector(
                              onTap: () =>
                                  _openAlbum(al.id),
                              child: Container(
                                width: 132,
                                margin: const EdgeInsets.only(
                                    right: 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      child: CachedNetworkImage(
                                        imageUrl: al.artworkUrl,
                                        width: 132,
                                        height: 132,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            Container(
                                                width: 132,
                                                height: 132,
                                                color: AppColors
                                                    .cardLight,
                                                child: const Icon(
                                                    Icons.album,
                                                    color: Colors
                                                        .white54)),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(al.title,
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight:
                                                FontWeight.w600)),
                                    Text(al.year,
                                        style: const TextStyle(
                                            color: AppColors.grey,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              // Horizontal Top-results carousel.
              if (_results.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding:
                            EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: Text('Top results',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700)),
                      ),
                      SizedBox(
                        height: 190,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16),
                          itemCount: _results.length
                              .clamp(0, 10),
                          itemBuilder: (c, i) {
                            final t = _results[i];
                            return GestureDetector(
                              onTap: () => _playQueue(_results, i),
                              child: Container(
                                width: 132,
                                margin: const EdgeInsets.only(
                                    right: 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      child: CachedNetworkImage(
                                        imageUrl: t.artworkUrl,
                                        width: 132,
                                        height: 132,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            Container(
                                                width: 132,
                                                height: 132,
                                                color: AppColors
                                                    .cardLight,
                                                child: const Icon(
                                                    Icons.music_note,
                                                    color: Colors
                                                        .white54)),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(t.title,
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight:
                                                FontWeight.w600)),
                                    Text(t.artist,
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: AppColors.grey,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              // Full track list.
              if (_results.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
                    child: Text('Tracks',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (c, i) {
                    final t = _results[i];
                    final active =
                        _current?.videoId == t.videoId;
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
                          style: TextStyle(
                              color: active
                                  ? AppColors.accent
                                  : Colors.white,
                              fontWeight: FontWeight.w500)),
                      subtitle: GestureDetector(
                        onTap: t.artistId.isNotEmpty
                            ? () => _openArtist(t.artistId)
                            : null,
                        child: Text(t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: t.artistId.isNotEmpty
                                    ? Colors.white70
                                    : AppColors.grey,
                                fontSize: 13)),
                      ),
                      trailing: _resolvingId == t.videoId
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent))
                          : Text(
                              _fmtDur(t.durationSec),
                              style: const TextStyle(
                                  color: AppColors.grey,
                                  fontSize: 12)),
                      onTap: () => _playQueue(_results, i),
                      onLongPress: () =>
                          showAddToPlaylist(context, t),
                    );
                  },
                  childCount: _results.length,
                ),
              ),
              const SliverToBoxAdapter(
                  child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  // Small rounded quick-pick tile (artwork or gradient + icon).
  Widget _quickCard(
      {required String title,
      String artUrl = '',
      Color? color,
      IconData? icon,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardLight.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                color: color ?? AppColors.cardLight,
                child: artUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: artUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Icon(
                            icon ?? Icons.music_note,
                            color: Colors.white),
                      )
                    : Icon(icon ?? Icons.music_note,
                        color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDur(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
