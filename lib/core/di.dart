import 'package:get_it/get_it.dart';
import '../models/playlist.dart';

final getIt = GetIt.instance;
bool _locatorReady = false;

/// Register cross-cutting singletons before runApp (both entries).
/// Safe to call twice (second call is a no-op).
Future<void> setupLocator() async {
  if (_locatorReady || getIt.isRegistered<PlaylistService>()) {
    _locatorReady = true;
    return;
  }
  final playlists = PlaylistService();
  await playlists.load();
  if (!getIt.isRegistered<PlaylistService>()) {
    getIt.registerSingleton<PlaylistService>(playlists);
  }
  _locatorReady = true;
}
