# Music Server Setup

This server allows you to download and stream YouTube audio from anywhere.

## Features

- Download iPhone-native M4A audio without unnecessary transcoding
- Continue serving previously cached MP3 audio
- Stream audio directly to your iOS app
- Configurable server URL in the iOS app settings
- Reuse cached audio for much faster repeat playback
- Support resumable byte-range transfers
- Proper error handling and logging

## Server Setup

### Prerequisites

- Python 3.10 or higher
- pip (Python package manager)

### Installation

1. From the repository root, move into the server directory:

```bash
cd Server
```

2. Start the server. The script creates an isolated environment under
   `~/Library/Application Support/SaucyMusiServer`. The server installs or
   updates dependencies only when needed:
```bash
./start_server.sh
```

### Running the Server

#### Manual Start

Use `./start_server.sh` for manual starts so the required dependencies stay current.

The server will start on `http://0.0.0.0:5000` and will be accessible from your local network.

#### Connect the iPhone app

The server prints its local-network address when it starts. Enter that address,
including `http://` and port `5000`, in the app’s Settings → Audio Server field.
