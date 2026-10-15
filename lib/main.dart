import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'core/theme.dart';
import 'core/di.dart';
import 'models/playlist.dart';
import 'services/downloads_service.dart';
import 'audio/audio_handler.dart';
import 'audio/player_facade.dart';
import 'ui/home_screen.dart';

late AppAudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await setupLocator();
  } catch (_) {
    // Storage unreadable: start with empty in-memory stores
    // rather than a black screen.
    if (!getIt.isRegistered<PlaylistService>()) {
      getIt.registerSingleton<PlaylistService>(PlaylistService());
    }
    if (!getIt.isRegistered<DownloadsService>()) {
      getIt.registerSingleton<DownloadsService>(DownloadsService());
    }
  }
  // Duck other audio, handle noisy (headphones unplugged) correctly.
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  audioHandler = await AudioService.init(
    builder: () => AppAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.nocrift.audio',
      androidNotificationChannelName: 'Nocrift playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(const NocriftApp());
}

class NocriftApp extends StatelessWidget {
  const NocriftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nocrift',
      theme: spotifyTheme,
      home: HomeScreen(handler: AudioServiceFacade(audioHandler)),
    );
  }
}
