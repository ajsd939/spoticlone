import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

// Transport to yt_bridge.py. Android uses Chaquopy over a
// MethodChannel; desktop spawns the local Python interpreter as a
// subprocess running desktop/python/cli.py (same yt_bridge logic).
// Both sides exchange JSON *strings* (never raw maps).
abstract class YtBridge {
  Future<String> invoke(String method, Map<String, String> args);
}

class AndroidYtBridge implements YtBridge {
  static const _ch = MethodChannel('app/yt_dlp');

  @override
  Future<String> invoke(String method, Map<String, String> args) async {
    final raw = await _ch.invokeMethod<String>(method, args);
    if (raw == null) throw Exception('empty bridge response');
    return raw;
  }
}

class DesktopYtBridge implements YtBridge {
  final String pythonExe;
  final String cliPath;
  DesktopYtBridge({required this.pythonExe, required this.cliPath});

  @override
  Future<String> invoke(String method, Map<String, String> args) async {
    final r = await Process.run(
        pythonExe, [cliPath, method, jsonEncode(args)],
        runInShell: true);
    if (r.exitCode != 0) {
      throw Exception('bridge failed: ${(r.stderr as String).trim()}');
    }
    return (r.stdout as String).trim();
  }

  /// Locate cli.py (release bundle next to the exe, or dev tree)
  /// and a Python 3 with yt-dlp + ytmusicapi (pip-installs on demand).
  static Future<DesktopYtBridge> create() async {
    final sep = Platform.pathSeparator;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    String? cli;
    for (final c in [
      '$exeDir${sep}python${sep}cli.py',
      '${Directory.current.path}${sep}desktop${sep}python${sep}cli.py',
    ]) {
      if (File(c).existsSync()) {
        cli = c;
        break;
      }
    }
    if (cli == null) {
      throw Exception(
          'bridge cli.py not found next to the exe or in desktop/python/');
    }
    final exe = await _findPython();
    // Smoke-test the backend once so failures surface at startup.
    final probe = await Process.run(
        exe, [cli, 'search', jsonEncode({'query': '__probe__'})],
        runInShell: true);
    if (probe.exitCode != 0) {
      throw Exception(
          'bridge probe failed: ${(probe.stderr as String).trim()}');
    }
    return DesktopYtBridge(pythonExe: exe, cliPath: cli);
  }

  static Future<String> _findPython() async {
    const candidates = [
      ['py', '-3'],
      ['python'],
      ['python3'],
    ];
    for (final cmd in candidates) {
      try {
        final v = await Process.run(cmd[0],
            [...cmd.sublist(1), '-c', 'import sys; print(sys.executable)'],
            runInShell: true);
        if (v.exitCode != 0) continue;
        final exe = (v.stdout as String).trim().split('\n').last.trim();
        if (exe.isEmpty) continue;
        final hasDeps = await Process.run(
            exe, ['-c', 'import yt_dlp, ytmusicapi'],
            runInShell: true);
        if (hasDeps.exitCode == 0) return exe;
        final pip = await Process.run(exe,
            ['-m', 'pip', 'install', 'yt-dlp', 'ytmusicapi'],
            runInShell: true);
        if (pip.exitCode == 0) return exe;
      } catch (_) {
        // try next candidate
      }
    }
    throw Exception(
        'Python 3 with yt-dlp + ytmusicapi is required (tried py -3, python, python3)');
  }
}
