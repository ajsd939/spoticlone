import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../audio/player_facade.dart';
import '../core/di.dart';
import '../core/theme.dart';
import 'lyrics_view.dart';

// Expanded full-screen player in Spotify layout: context header,
// big rounded cover over an animated cover-art gradient, title row
// with like button, slider, shuffle/repeat controls, lyrics preview
// card. The Lyrics tab (spec) sits behind the second tab.
class FullPlayer extends StatefulWidget {
  final PlayerFacade handler;
  final Track track;
  final VoidCallback onCollapse;
  final void Function(String artistId)? onArtistTap;
  const FullPlayer(
      {super.key,
      required this.handler,
      required this.track,
      required this.onCollapse,
      this.onArtistTap});

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends State<FullPlayer>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Color _dominant = const Color(0xFF2A2A2A);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _extractColor();
  }

  @override
  void didUpdateWidget(FullPlayer old) {
    super.didUpdateWidget(old);
    if (old.track.videoId != widget.track.videoId) {
      _extractColor();
    }
  }

  Future<void> _extractColor() async {
    final id = widget.track.videoId;
    if (widget.track.artworkUrl.isEmpty) {
      // No art: drop the previous track's gradient instead of keeping it.
      if (_dominant != const Color(0xFF2A2A2A) && mounted) {
        setState(() => _dominant = const Color(0xFF2A2A2A));
      }
      return;
    }
    try {
      final p = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(widget.track.artworkUrl),
        maximumColorCount: 8,
      );
      // Drop stale results: a newer track may have arrived mid-fetch.
      if (mounted &&
          id == widget.track.videoId &&
          p.dominantColor != null) {
        setState(() => _dominant = p.dominantColor!.color);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_dominant.withValues(alpha: 0.9), AppColors.background],
          stops: const [0.0, 0.6],
        ),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          color: Colors.black.withValues(alpha: 0.35),
          child: SafeArea(
            child: Column(
              children: [
                // Context header.
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down,
                              color: Colors.white, size: 28),
                          onPressed: widget.onCollapse),
                      Expanded(
                        child: Column(
                          children: [
                            const Text('PLAYING FROM SEARCH',
                                style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                    letterSpacing: 1.5)),
                            Text(widget.track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      IconButton(
                          icon: const Icon(Icons.more_vert,
                              color: Colors.white),
                          onPressed: () {}),
                    ],
                  ),
                ),
                // Compact tab switch (Cover | Lyrics).
                TabBar(
                    controller: _tabs,
                    indicatorColor: Colors.white,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(fontSize: 12),
                    tabs: const [
                      Tab(text: 'Cover'),
                      Tab(text: 'Lyrics')
                    ]),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _coverTab(),
                      // Keyed by track: switching songs fully resets the
                      // lyrics state (fresh fetch + scroll to top) instead
                      // of flashing the previous song's lines.
                      LyricsView(
                          key: ValueKey(widget.track.videoId),
                          handler: widget.handler,
                          track: widget.track),
                    ],
                  ),
                ),
                _controls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverTab() => ListView(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: widget.track.artworkUrl,
                width: 320,
                height: 320,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                    width: 320,
                    height: 320,
                    color: Colors.white10,
                    child: const Icon(Icons.music_note,
                        size: 80, color: Colors.white54)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Title + like row.
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: widget.track.artistId.isNotEmpty &&
                              widget.onArtistTap != null
                          ? () => widget
                              .onArtistTap!(widget.track.artistId)
                          : null,
                      child: Text(widget.track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.grey,
                              fontSize: 15,
                              decoration:
                                  TextDecoration.underline)),
                    ),
                  ],
                ),
              ),
              ListenableBuilder(
                listenable: getIt<PlaylistService>(),
                builder: (c, _) {
                  final liked = getIt<PlaylistService>()
                      .isLiked(widget.track);
                  return IconButton(
                    icon: Icon(
                        liked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: liked
                            ? AppColors.green
                            : Colors.white54,
                        size: 26),
                    onPressed: () => getIt<PlaylistService>()
                        .toggleLike(widget.track),
                  );
                },
              ),
            ],
          ),
          // Lyrics preview card -> jumps to Lyrics tab.
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _tabs.animateTo(1),
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text('Lyrics',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text('Synced line-by-line',
                            style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: Colors.white54),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _controls() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<MediaItem?>(
              stream: widget.handler.mediaItem,
              builder: (c, mm) {
                // Real audio duration wins: metadata is often 0, which
                // froze the total at 0:00 while the song played.
                final md = mm.data?.duration;
                final total = (md != null && md.inMilliseconds > 0)
                    ? md
                    : Duration(seconds: widget.track.durationSec);
                return StreamBuilder<Duration>(
                  stream: widget.handler.positionStream,
                  builder: (c, pos) {
                    final p = pos.data ?? Duration.zero;
                    return Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: p.inMilliseconds
                            .clamp(0, total.inMilliseconds)
                            .toDouble(),
                        max: total.inMilliseconds
                            .toDouble()
                            .clamp(1, 1e12),
                        activeColor: Colors.white,
                        inactiveColor:
                            Colors.white.withValues(alpha: 0.3),
                        onChanged: (v) => widget.handler.seek(
                            Duration(milliseconds: v.toInt())),
                      ),
                    ),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(p),
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11)),
                        Text(_fmt(total),
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11)),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
            StreamBuilder<PlaybackState>(
              stream: widget.handler.playbackState,
              builder: (c, s) {
                final playing = s.data?.playing ?? false;
                final loading = s.data?.processingState ==
                        AudioProcessingState.loading ||
                    s.data?.processingState ==
                        AudioProcessingState.buffering;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    StreamBuilder<bool>(
                      stream: widget.handler.shuffleStream,
                      builder: (c, sh) => IconButton(
                          icon: Icon(Icons.shuffle,
                              color: (sh.data ?? false)
                                  ? AppColors.green
                                  : Colors.white54),
                          onPressed: () =>
                              widget.handler.toggleShuffle()),
                    ),
                    IconButton(
                        icon: const Icon(Icons.skip_previous,
                            color: Colors.white, size: 38),
                        onPressed: () =>
                            widget.handler.skipToPrevious()),
                    const SizedBox(width: 8),
                    loading
                        ? const SizedBox(
                            width: 60,
                            height: 60,
                            child: Center(
                                child:
                                    CircularProgressIndicator(
                                        color: Colors.white)))
                        : IconButton(
                            icon: Icon(
                                playing
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_filled,
                                color: Colors.white,
                                size: 64),
                            onPressed: () => playing
                                ? widget.handler.pause()
                                : widget.handler.play(),
                          ),
                    const SizedBox(width: 8),
                    IconButton(
                        icon: const Icon(Icons.skip_next,
                            color: Colors.white, size: 38),
                        onPressed: () =>
                            widget.handler.skipToNext()),
                    StreamBuilder<QueueRepeat>(
                      stream: widget.handler.repeatStream,
                      builder: (c, rp) {
                        final mode = rp.data ?? QueueRepeat.off;
                        return IconButton(
                            icon: Icon(
                                mode == QueueRepeat.one
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                                color: mode == QueueRepeat.off
                                    ? Colors.white54
                                    : AppColors.green),
                            onPressed: () =>
                                widget.handler.cycleRepeat());
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
