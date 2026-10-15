import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme.dart';
import 'core/di.dart';
import 'audio/desktop_player.dart';
import 'services/yt_bridge.dart';
import 'ui/home_screen.dart';

// Windows/Linux/macOS entry: media_kit audio + local Python backend.
// Build with: flutter build windows -t lib/main_desktop.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(480, 850),
      minimumSize: Size(380, 650),
      title: 'Nocrift',
      backgroundColor: AppColors.background,
    ),
    () async => windowManager.show(),
  );

  // Boot splash first: pip-installing the backend on first run can
  // take minutes with otherwise a blank window.
  runApp(const _BootApp());
  late final DesktopYtBridge bridge;
  try {
    bridge = await DesktopYtBridge.create();
    await setupLocator(bridge: bridge);
  } catch (e) {
    runApp(_FatalErrorApp(message: e.toString()));
    return;
  }
  final player = DesktopPlayer(bridge: bridge);
  runApp(NocriftDesktopApp(player: player, bridge: bridge));
}

class _BootApp extends StatelessWidget {
  const _BootApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('Nocrift',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 16),
              CircularProgressIndicator(color: AppColors.accent),
              SizedBox(height: 12),
              Text('Starting music backend…',
                  style: TextStyle(color: AppColors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class NocriftDesktopApp extends StatelessWidget {
  final DesktopPlayer player;
  final DesktopYtBridge bridge;
  const NocriftDesktopApp(
      {super.key, required this.player, required this.bridge});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nocrift',
      theme: spotifyTheme,
      home: HomeScreen(handler: player, bridge: bridge),
    );
  }
}

// Shown when no usable Python backend exists (guides the fix).
class _FatalErrorApp extends StatelessWidget {
  final String message;
  const _FatalErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.red, size: 48),
                const SizedBox(height: 16),
                const Text('Music backend unavailable',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(message,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: AppColors.grey)),
                const SizedBox(height: 8),
                const Text(
                    'Install Python 3 from python.org (check "Add to PATH"), then restart.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
