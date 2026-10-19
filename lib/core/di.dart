import 'package:get_it/get_it.dart';
import '../models/playlist.dart';
import '../services/cache_manager.dart';
import '../services/downloads_service.dart';
import '../services/yt_bridge.dart';

final getIt = GetIt.instance;
bool _locatorReady = false;

/// Register cross-cutting singletons before runApp (both entries).
/// Safe to call twice (second call is a no-op).
Future<void> setupLocator({YtBridge? bridge}) async {
  if (_locatorReady || getIt.isRegistered<PlaylistService>()) {
    _locatorReady = true;
    return;
  }
  final playlists = PlaylistService();
  await playlists.load();
  if (!getIt.isRegistered<PlaylistService>()) {
    getIt.registerSingleton<PlaylistService>(playlists);
  }
  final cache = CacheManager();
  try {
    // Wipes temp_cache/ so a previous crash leaves nothing behind.
    await cache.init();
  } catch (_) {
    // No writable storage: auto-cache stays disabled, playback works.
  }
  if (!getIt.isRegistered<CacheManager>()) {
    getIt.registerSingleton<CacheManager>(cache);
  }
  final downloads = DownloadsService(bridge: bridge, cache: cache);
  await downloads.load();
  if (!getIt.isRegistered<DownloadsService>()) {
    getIt.registerSingleton<DownloadsService>(downloads);
  }
  _locatorReady = true;
}
