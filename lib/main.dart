import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'core/theme.dart';
import 'core/di.dart';
import 'models/playlist.dart';
import 'audio/audio_handler.dart';
import 'audio/player_facade.dart';
import 'ui/home_screen.dart';

late AppAudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await setupLocator();
  } catch (_) {
    // Storage unreadable: start with an empty in-memory library
    // rather than a black screen.
    getIt.registerSingleton<PlaylistService>(PlaylistService());
  }
  // Duck other audio, handle noisy (headphones unplugged) correctly.
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  audioHandler = await AudioService.init(
    builder: () => AppAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.spoticlone.audio',
      androidNotificationChannelName: 'Spoticlone playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(const SpoticloneApp());
}

class SpoticloneApp extends StatelessWidget {
  const SpoticloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spoticlone',
      theme: spotifyTheme,
      home: HomeScreen(handler: AudioServiceFacade(audioHandler)),
    );
  }
}
