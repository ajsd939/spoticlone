import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spoticlone/services/lyrics_service.dart';
import 'package:spoticlone/models/track.dart';
import 'package:spoticlone/models/artist.dart';
import 'package:spoticlone/models/playlist.dart';
import 'package:spoticlone/services/update_service.dart';
import 'package:spoticlone/services/downloads_service.dart';
import 'package:spoticlone/audio/playback_queue.dart';
import 'package:spoticlone/audio/player_facade.dart' show QueueRepeat;

void main() {
  test('LRC parser extracts timestamps', () {
    const lrc = '[00:12.34] Hello\n[00:15.00] World\n';
    final lines = LyricsService().parseLrc(lrc);
    expect(lines.length, 2);
    expect(lines[0].text, 'Hello');
    expect(lines[0].time, const Duration(seconds: 12, milliseconds: 340));
  });

  test('Track searchQuery combines title and artist', () {
    const t = Track(videoId: 'x', title: 'Song', artist: 'Artist');
    expect(t.searchQuery, 'Song Artist');
  });

  test('Artist parses page JSON defensively', () {
    final a = Artist.fromMap({
      'artistId': 'UC123',
      'name': 'Kendrick Lamar',
      'artworkUrl': 'https://img',
      'topTracks': [
        {'videoId': 'v1', 'title': 'HUMBLE.', 'artist': 'Kendrick Lamar',
         'artistId': 'UC123', 'durationSec': 177},
      ],
      'albums': [
        {'albumId': 'ALB1', 'title': 'DAMN.', 'year': '2017'},
      ],
      'singles': 'not-a-list',
    });
    expect(a.name, 'Kendrick Lamar');
    expect(a.topTracks.length, 1);
    expect(a.topTracks.first.artistId, 'UC123');
    expect(a.albums.first.title, 'DAMN.');
    expect(a.singles, isEmpty);
  });

  test('Album parses with fallback artwork for tracks', () {
    final al = Album.fromMap({
      'albumId': 'ALB1',
      'title': 'DAMN.',
      'artist': 'Kendrick Lamar',
      'year': '2017',
      'artworkUrl': 'https://cover',
      'tracks': [
        {'videoId': 'v1', 'title': 'DNA.', 'artist': 'Kendrick Lamar',
         'durationSec': 105},
        'junk-entry',
      ],
    });
    expect(al.tracks.length, 1);
    expect(al.tracks.first.title, 'DNA.');
  });

  test('SearchResults splits songs, artists and albums', () {
    final r = SearchResults.fromMap({
      'songs': [
        {'videoId': 'v1', 'title': 'HUMBLE.', 'artist': 'Kendrick Lamar',
         'artistId': 'UC123', 'durationSec': 177},
        {'videoId': '', 'title': 'Bad', 'artist': 'Nobody'},
      ],
      'artists': [
        {'artistId': 'UC123', 'name': 'Kendrick Lamar'},
        {'name': 'NoId'},
      ],
      'albums': [
        {'albumId': 'ALB1', 'title': 'DAMN.', 'year': '2017'},
      ],
    });
    expect(r.songs.length, 1);
    expect(r.artists.length, 1);
    expect(r.artists.first.name, 'Kendrick Lamar');
    expect(r.albums.first.title, 'DAMN.');
    expect(r.isEmpty, isFalse);
    expect(SearchResults.empty.isEmpty, isTrue);
  });

  test('PlaylistService CRUD, likes and persistence', () async {    SharedPreferences.setMockInitialValues({});
    final svc = PlaylistService();
    await svc.load();
    expect(svc.playlists.length, 1); // Liked Songs auto-created
    expect(svc.liked.name, 'Liked Songs');

    const t = Track(videoId: 'v1', title: 'Song', artist: 'Artist');
    await svc.toggleLike(t);
    expect(svc.isLiked(t), isTrue);
    await svc.toggleLike(t);
    expect(svc.isLiked(t), isFalse);

    final pl = await svc.createPlaylist('Roadtrip');
    expect(svc.playlists.length, 2);
    await svc.addToPlaylist(pl.id, t);
    await svc.addToPlaylist(pl.id, t); // no duplicates
    expect(svc.byId(pl.id)!.tracks.length, 1);
    await svc.removeFromPlaylist(pl.id, 'v1');
    expect(svc.byId(pl.id)!.tracks, isEmpty);

    // Reload from the same mock store: data survives.
    await svc.addToPlaylist(pl.id, t);
    final svc2 = PlaylistService();
    await svc2.load();
    expect(svc2.byId(pl.id)!.tracks.length, 1);

    await svc2.deletePlaylist(pl.id);
    expect(svc2.byId(pl.id), isNull);
    await svc2.deletePlaylist(PlaylistService.likedId); // protected
    expect(svc2.byId(PlaylistService.likedId), isNotNull);
  });

  test('UpdateService version compare + asset picking', () {    expect(UpdateService.isNewer('v1.2.0', '1.1.9'), isTrue);
    expect(UpdateService.isNewer('v1.2.0', '1.2.0'), isFalse);
    expect(UpdateService.isNewer('1.0.0', '1.0.1'), isFalse);
    expect(UpdateService.isNewer('v2.0', '1.9.9'), isTrue);
    const rel = ReleaseInfo(
      tag: 'v1.2.0',
      name: 'Release v1.2.0',
      notes: '- fixes',
      assets: [
        ReleaseAsset(name: 'app-release.apk', downloadUrl: 'https://a/apk'),
        ReleaseAsset(
            name: 'Spoticlone-Setup-1.2.0.exe',
            downloadUrl: 'https://a/setup'),
      ],
    );
    expect(rel.apk!.downloadUrl, 'https://a/apk');
    expect(rel.setupExe!.downloadUrl, 'https://a/setup');
    expect(
        const ReleaseInfo(tag: 'v1', name: '', notes: '').apk, isNull);
  });

  test('UpdateService compare strips suffixes; Piped parsing tolerates shapes',
      () {
    expect(UpdateService.isNewer('v1.2.0', '1.2.0-beta'), isFalse);
    expect(UpdateService.isNewer('v1.2.1-beta', '1.2.0'), isTrue);
    final t = Track.fromPiped({
      'url': '/watch?v=abc123',
      'title': 'Song',
      'uploaderName': 'Artist',
      'thumbnail': 'https://img',
      'duration': '215', // Piped sometimes sends strings
    });
    expect(t.videoId, 'abc123');
    expect(t.durationSec, 215);
  });

  test('PlaylistService keeps good entries past a corrupt one', () async {    SharedPreferences.setMockInitialValues({
      'spoticlone.playlists.v1': '[{"id":"liked","name":"Liked Songs",'
          '"createdAt":"2026-01-01T00:00:00.000","tracks":[]},'
          '{"id":42,"tracks":"not-a-list"}]',
    });
    final svc = PlaylistService();
    await svc.load();
    expect(svc.byId('liked')!.name, 'Liked Songs');
    expect(svc.playlists.length, 1);
  });

  test('Lyrics query helpers normalize credits', () {    expect(LyricsService.firstArtist('Kendrick Lamar, SZA'),
        'Kendrick Lamar');
    expect(LyricsService.firstArtist('Drake'), 'Drake');
    expect(LyricsService.stripTitle('HUMBLE. (feat. Someone)'), 'HUMBLE.');
    expect(LyricsService.stripTitle('Song - Remaster'), 'Song - Remaster');
    expect(LyricsService.stripTitle('Plain Title'), 'Plain Title');
  });

  List<Track> demoTracks(int n) => List.generate(
      n,
      (i) => Track(
          videoId: 'v$i', title: 'Song $i', artist: 'Artist'));

  test('PlaybackQueue order, advance, wrap and shuffle', () {
    final q = PlaybackQueue();
    q.setQueue(demoTracks(4), startIndex: 1);
    expect(q.current!.videoId, 'v1');
    expect(q.advance(), isTrue);
    expect(q.current!.videoId, 'v2');
    expect(q.advance(), isTrue);
    expect(q.current!.videoId, 'v3');
    expect(q.advance(), isFalse); // end, repeat off
    q.cycleRepeat();
    expect(q.repeat, QueueRepeat.all);
    expect(q.advance(), isTrue);
    expect(q.current!.videoId, 'v0'); // wrapped
    expect(q.back(), isTrue);
    expect(q.current!.videoId, 'v3'); // wrapped back
    q.cycleRepeat(); // all -> one
    q.cycleRepeat(); // one -> off (finite walk below)
    expect(q.repeat, QueueRepeat.off);
    // Shuffle keeps the current track first, covers everything once.
    q.setShuffle(true);
    expect(q.shuffle, isTrue);
    expect(q.current!.videoId, 'v3');
    final seen = <String>{};
    seen.add(q.current!.videoId);
    while (q.advance()) {
      expect(seen.add(q.current!.videoId), isTrue,
          reason: 'no repeats before covering all');
    }
    expect(seen.length, 4);
    final lastWalked = q.current!.videoId;
    q.setShuffle(false);
    expect(q.shuffle, isFalse);
    // Unshuffling keeps whatever is playing, in natural order.
    expect(q.current!.videoId, lastWalked);
    expect(q.tracks[q.index].videoId, lastWalked);
  });

  test('PlaybackQueue.updateTrack swaps metadata in place', () {    final q = PlaybackQueue();
    q.setQueue([
      const Track(videoId: 'v1', title: 'A', artist: 'Unknown'),
      const Track(videoId: 'v2', title: 'B', artist: 'Known'),
    ]);
    q.updateTrack(
        0,
        const Track(
            videoId: 'v1', title: 'A', artist: 'Real Artist'));
    expect(q.tracks[0].artist, 'Real Artist');
    expect(q.index, 0);
    expect(q.current!.artist, 'Real Artist');
    q.updateTrack(99,
        const Track(videoId: 'x', title: 'X', artist: 'Y')); // no-op
    expect(q.tracks.length, 2);
  });

  test('DownloadsService register/delete/persist with temp dir',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dir =
        await Directory.systemTemp.createTemp('nocrift-dl-test');
    final svc = DownloadsService(directory: dir);
    await svc.load();
    expect(svc.count, 0);
    const t = Track(videoId: 'v9', title: 'Song', artist: 'Artist');
    final f = File('${dir.path}/v9.m4a');
    await f.writeAsBytes([1, 2, 3]);
    await svc.registerDownload(t, f.path);
    expect(svc.isDownloaded('v9'), isTrue);
    expect(svc.localPath('v9'), f.path);
    expect(svc.tracks.first.title, 'Song');
    // A vanished file drops the entry lazily.
    await f.delete();
    expect(svc.localPath('v9'), isNull);
    expect(svc.isDownloaded('v9'), isFalse);
    // Persistence round-trip.
    await f.writeAsBytes([1, 2, 3]);
    await svc.registerDownload(t, f.path);
    final svc2 = DownloadsService(directory: dir);
    await svc2.load();
    expect(svc2.isDownloaded('v9'), isTrue);
    await svc2.delete('v9');
    expect(svc2.isDownloaded('v9'), isFalse);
    expect(await f.exists(), isFalse);
    await dir.delete(recursive: true);
  });
}
