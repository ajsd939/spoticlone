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
    // Full paths, no shell: user queries pass through untouched
    // (spaces/quotes would otherwise be re-split by cmd).
    final r = await Process.run(
        pythonExe, [cliPath, method, jsonEncode(args)],
        runInShell: false);
    if (r.exitCode != 0) {
      throw Exception('bridge failed: ${r.stderr.toString().trim()}');
    }
    return r.stdout.toString().trim();
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
    // Smoke-test the backend. Exit code alone is not enough: logic
    // errors come back as {"error": ...} JSON with exit 0, so require
    // a well-formed search payload before declaring healthy.
    final probe = await Process.run(
        exe, [cli, 'search', jsonEncode({'query': '__probe__'})],
        runInShell: false);
    if (probe.exitCode != 0) {
      throw Exception(
          'bridge probe failed: ${probe.stderr.toString().trim()}');
    }
    try {
      final decoded = jsonDecode(probe.stdout.toString());
      if (decoded is Map && decoded['error'] != null) {
        throw Exception('bridge probe: ${decoded['error']}');
      }
      if (decoded is! Map<String, dynamic> ||
          !decoded.containsKey('songs')) {
        throw Exception('bridge probe: unexpected payload');
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('bridge probe')) rethrow;
      throw Exception('bridge probe: unreadable response');
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
