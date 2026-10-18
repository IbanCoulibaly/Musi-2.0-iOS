# Saucy Musi

A personal iPhone music player built in SwiftUI, paired with a small self-hosted
Python server. Search YouTube from the app, pull the audio down to your own
server, and keep a local library you can play offline, organize into playlists
and share as real audio files.

<p align="center">
  <img src="docs/screenshots/library.png" width="250" alt="Library">
  &nbsp;
  <img src="docs/screenshots/search.png" width="250" alt="YouTube search">
  &nbsp;
  <img src="docs/screenshots/settings.png" width="250" alt="Settings">
</p>

## Features

**Playback**
- Background audio with lock-screen / Control Center controls and Now Playing info
- Queue with shuffle and repeat, "Up Next" view
- AirPlay output
- Handles interruptions (calls, Siri) and headphone unplugging gracefully

**Library**
- Songs stored locally on the device and visible in the Files app
- Playlists, swipe actions and context menus
- Fuzzy search across your library
- Trash with restore / empty
- Share a song as an actual `.m4a` / `.mp3` file (AirDrop, Messages, Files),
  named `Artist - Title`

**Smart metadata**
- Guesses artist and title from messy YouTube video names
  (`Artist - Title`, `「Title」`, `feat.` bylines, `|` and `/` separators, …)
- Confirms or corrects guesses with Apple's public iTunes Search API
  (no account or key; only the song title is sent, and it can be turned off)
- Groups anime openings, endings and OSTs under their show rather than
  scattering them across dozens of artists
- Romanizes Japanese artist names

**Look and feel**
- Animated video wallpaper
- Choice of typeface (SF Pro, SF Rounded, New York, SF Mono or the bundled
  Ubuntu font) and adjustable text size

## How it works

```
┌──────────────┐  search   ┌──────────────────┐
│  iPhone app  │ ────────▶ │ YouTube Data API │
│  (SwiftUI)   │           └──────────────────┘
│              │  /get_audio_url?url=…   ┌───────────────────────┐
│              │ ──────────────────────▶ │  Server (Flask +      │
│              │ ◀── audio file ──────── │  yt-dlp, on your Mac) │
└──────────────┘                         └───────────────────────┘
```

The app never downloads from YouTube directly. It asks your server, which uses
[yt-dlp](https://github.com/yt-dlp/yt-dlp) to fetch iPhone-native M4A audio,
caches it, and serves it back with byte-range support. Downloaded songs then
live on the phone and play offline.

## Project layout

```
SaucyMusi/              iOS app source
├── SaucyMusiApp.swift  App entry point
├── Views/              Home (now playing), Library, Playlists, Artists, YouTube search, Settings
├── Services/           AudioManager, storage, metadata parsing, artist lookup, show catalog
├── Navigation/         Tab bar and tab definitions
├── Design/             Typography, theming, video wallpaper
├── Assets.xcassets/    App icon and images
├── Fonts/              Ubuntu font family
├── Resources/          Wallpaper video
└── PreviewContent/     SwiftUI preview assets
SaucyMusiTests/         Unit tests
SaucyMusiUITests/       UI tests
Server/                 Flask + yt-dlp audio server (see Server/README.md)
Config/                 Info.plist and example secrets
```

## Getting started

### Requirements

- Xcode 26 or later, iOS 26 SDK
- A Mac (or any machine) with Python 3.10+ to run the server
- A [YouTube Data API v3](https://console.cloud.google.com/apis/credentials) key

### 1. Add your API key

```bash
cp Config/Secrets.swift.example SaucyMusi/Services/Secrets.swift
```

Then open `SaucyMusi/Services/Secrets.swift` and paste in your key. The file is
git-ignored, so the key stays on your machine.

### 2. Start the server

```bash
cd Server
./start_server.sh
```

The script sets up its own virtual environment on first run and prints the
server's local network address (port `5001`). To keep it running in the
background on macOS, edit the paths in `Server/com.saucymusi.server.plist` and load
it with `launchctl`. More detail in [Server/README.md](Server/README.md).

### 3. Run the app

1. Open `SaucyMusi.xcodeproj` in Xcode.
2. Select your own team under **Signing & Capabilities**.
3. Build and run on an iPhone or the simulator.
4. In the app, open **Settings → Audio Server** and enter the address the
   server printed, e.g. `http://192.168.1.20:5001`.

## Tech stack

- **App:** Swift, SwiftUI, AVFoundation, MediaPlayer, CoreTransferable
- **Server:** Python, Flask, yt-dlp
- **APIs:** YouTube Data API v3 (search), iTunes Search API (artist lookup)

## Note

This is a personal project for learning and private use. Only download content
you have the right to download.

## Credits

The [Ubuntu font family](https://design.ubuntu.com/font) is used under the
Ubuntu Font License; see [LICENSES/Ubuntu-Font-License.txt](LICENSES/Ubuntu-Font-License.txt).
