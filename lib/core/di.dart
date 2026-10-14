import 'package:get_it/get_it.dart';
import '../models/playlist.dart';

final getIt = GetIt.instance;

/// Register cross-cutting singletons before runApp (both entries).
Future<void> setupLocator() async {
  if (!getIt.isRegistered<PlaylistService>()) {
    final playlists = PlaylistService();
    await playlists.load();
    getIt.registerSingleton<PlaylistService>(playlists);
  }
}
