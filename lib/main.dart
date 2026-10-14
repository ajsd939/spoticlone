import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'core/theme.dart';
import 'core/di.dart';
import 'audio/audio_handler.dart';
import 'audio/player_facade.dart';
import 'ui/home_screen.dart';

late AppAudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupLocator();
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
