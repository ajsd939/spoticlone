import 'package:flutter/material.dart';

// Nocrift dark theme: #121212 canvas, #%FFC600 brand-yellow accents.
final spotifyTheme = ThemeData.dark().copyWith(
  scaffoldBackgroundColor: const Color(0xFF121212),
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFFFFC600),
    surface: Color(0xFF121212),
  ),
  // Yellow buttons need dark text to stay readable.
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(foregroundColor: Colors.black),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF121212),
    elevation: 0,
  ),
  textTheme: const TextTheme(
    titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
    bodyMedium: TextStyle(color: Color(0xFFB3B3B3)),
  ),
  cardTheme: CardThemeData(
    color: const Color(0xFF181818),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  sliderTheme: SliderThemeData(
    activeTrackColor: Colors.white,
    inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
    thumbColor: Colors.white,
    overlayColor: Colors.white.withValues(alpha: 0.1),
    trackHeight: 3,
  ),
);

class AppConstants {
  static const ytDlpChannel = 'app/yt_dlp';
  // Placeholder until user provides owner/repo for GitHub Releases check.
  static const updateOwner = 'OWNER';
  static const updateRepo = 'REPO';
}

// Nocrift palette tokens reused across widgets.
class AppColors {
  static const background = Color(0xFF121212);
  static const card = Color(0xFF181818);
  static const cardLight = Color(0xFF282828);
  static const grey = Color(0xFFB3B3B3);
  static const accent = Color(0xFFFFC600);
}
