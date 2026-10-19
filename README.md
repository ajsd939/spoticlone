# Nocrift

A **free Spotify alternative** for Android and Windows. Search millions of songs,
play them with gapless background audio, save them offline, read synced lyrics,
browse artists and albums, and keep your own playlists — no account, no
subscription, no ads.

![platforms](https://img.shields.io/badge/Android APK-black) ![platforms](https://img.shields.io/badge/Windows Setup-blue)
[![release](https://img.shields.io/github/v/release/ajsd939/spoticlone)](https://github.com/ajsd939/spoticlone/releases/latest)

## Features

- **Search everything** — songs, artists and albums from the YouTube Music
  catalog, with cover art, in one search bar.
- **Gapless background playback** — music keeps playing with the screen off,
  plus lock-screen / notification controls (Android) and taskbar flyout
  controls (Windows).
- **Offline downloads** — songs you play are cached automatically so they keep
  playing without a connection. Skip away and the old file is cleaned up after
  15 seconds; hit Download (single song, whole playlist or album) to keep it
  permanently — permanent saves are never auto-deleted. Lyrics are stored with
  the song too.
- **Synced lyrics** — line-by-line highlighting from the free LRCLIB database,
  with a small translation under each line in your device language.
- **Artist pages** — photo header, top tracks, complete albums and singles
  discographies (not just the top 10).
- **Album pages** — cover header, full numbered track list, one-tap play.
- **Playlists** — Liked Songs plus unlimited custom playlists, stored
  on-device and shared across every screen (long-press any song to add it).
- **Spotify-style dark UI** — `#121212` theme, mini-player that expands into a
  full player, cover-art-driven animated gradients, glassmorphism lyrics view.
- **OTA auto-updates** — the app checks GitHub Releases on startup and can
  download + install new versions itself (APK on Android, Setup on Windows).
- **100% free stack** — no paid APIs, no analytics, no ads.

## How it works

```
Search (ytmusicapi) ──> metadata: tracks, artists, albums, cover art
Resolve (yt-dlp) ─────> exact-video audio stream URL, fetched at play-time
Play ─────────────────> just_audio + audio_service (Android)
                        media_kit / libmpv (Windows)
Lyrics (LRCLIB) ──────> synced LRC rendered against playback position
```

- **Android** runs `yt-dlp` + `ytmusicapi` on-device via Chaquopy (embedded
  Python 3.11), bridged over a MethodChannel that passes JSON strings.
- **Windows** runs the same Python code as a subprocess next to the exe.
- Stream URLs expire within hours, so they are resolved fresh on every play
  and never cached. Tapping a result always plays that exact video — search
  ranking can never swap in a compilation or interlude.

## Install

Get the latest release from the
[Releases page](https://github.com/ajsd939/spoticlone/releases/latest):

| Platform | File | Install |
|----------|------|---------|
| Android  | `app-release.apk` | `adb install -r app-release.apk`, or open it on-device |
| Windows  | `Nocrift-Setup-*.exe` (latest) | Run it (per-user, no admin needed) |
| Windows portable | `Nocrift-Portable-*.zip` (latest) | Unzip anywhere, run `Nocrift.exe` |

Android needs a phone with free storage (~150 MB for the Python runtime);
Windows needs Python 3 from [python.org](https://www.python.org) on PATH
(the app pip-installs its two backend packages on first launch).

## Build from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(stable) plus, for Android, the SDK platform + build-tools
(`sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"`).

```powershell
git clone https://github.com/ajsd939/spoticlone.git
cd spoticlone
flutter pub get

# Android APK (Chaquopy bakes yt-dlp/ytmusicapi in at build time)
flutter build apk --release

# Windows app (needs VS Build Tools + Developer Mode for symlinks)
flutter build windows -t lib/main_desktop.dart --release
Copy-Item -Recurse desktop\python build\windows\x64\runner\Release\python
```

Run the Windows dev loop with `flutter run -d windows -t lib/main_desktop.dart`.

## Releasing

One command builds everything and publishes it (drives the in-app updater):

```powershell
.\tool\release.ps1 -Version 1.1.0 -Notes "What changed"
```

It stamps `pubspec.yaml`, builds the APK + Windows exe + NSIS installer, and
runs `gh release create v1.1.0` with all artifacts attached. Add `-Draft` to
review before publishing, `-SkipWindows` for an Android-only hotfix.

## Project layout

```
lib/
  main.dart / main_desktop.dart   Android + Windows entries
  core/theme.dart, core/di.dart   Spotify theme, service locator
  models/                         Track, Artist/Album, Playlist, SearchResults
  services/                       search, stream (yt-dlp), lyrics (LRCLIB),
                                  artist/album, playlists, OTA updater, bridge
  audio/                          audio_service handler, media_kit desktop
                                  player, shared PlayerFacade
  ui/                             home, mini/full player, lyrics, artist,
                                  album, playlist screens
android/.../MainActivity.kt       Chaquopy bridge (MethodChannel)
android/.../python/yt_bridge.py   yt-dlp + ytmusicapi backend
desktop/python/                   same backend + subprocess CLI wrapper
installer/spoticlone.nsi          Nullsoft installer script
tool/release.ps1                  automated release pipeline
```

## Notes

- Playlists and likes live **on each device** (no cloud sync — that would
  need accounts, deliberately out of scope).
- `flutter analyze` is clean and `flutter test` covers parsers, playlists
  and the updater's version logic.
- YouTube/YouTube Music content belongs to its owners; this project is for
  personal use. Be kind to the free APIs it relies on (LRCLIB, InnerTube).
