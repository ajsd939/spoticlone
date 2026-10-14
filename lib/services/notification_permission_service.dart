import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

// Android 13+ (SDK 33) requires runtime POST_NOTIFICATIONS consent.
// Without it the audio_service foreground notification can't show
// and the OS may kill background playback. Call once on startup.
class NotificationPermissionService {
  static Future<void> ensureRequested(BuildContext context) async {
    if (!Platform.isAndroid) return;
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    if (sdk < 33) return; // granted at install time below 13

    var status = await Permission.notification.status;
    if (status.isGranted) return;

    status = await Permission.notification.request();
    if (status.isGranted || !context.mounted) return;

    // Denied: explain why, offer retry / settings shortcut.
    if (status.isPermanentlyDenied) {
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Enable notifications'),
          content: const Text(
              'Spoticlone keeps playing in the background via a '
              'persistent player notification. Please allow '
              'notifications, otherwise playback may stop.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Later')),
            FilledButton(
              onPressed: () {
                openAppSettings();
                Navigator.pop(c);
              },
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
    }
  }
}
