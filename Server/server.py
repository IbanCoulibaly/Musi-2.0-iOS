import os
import subprocess
import sys
import logging
import shutil
import threading
from functools import lru_cache
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
from urllib.parse import parse_qs, urlparse

SERVER_RUNTIME_DIR = Path.home() / "Library/Application Support/SaucyMusiServer"
SERVER_VENV_DIR = SERVER_RUNTIME_DIR / "venv"
SERVER_VENV_PYTHON = SERVER_VENV_DIR / "bin/python"
MINIMUM_YT_DLP_VERSION = (2026, 8, 19)


def version_tuple(value):
    return tuple(int(part) for part in value.replace('-', '.').split('.') if part.isdigit())


def ensure_server_runtime():
    if Path(sys.prefix).resolve() == SERVER_VENV_DIR.resolve():
        try:
            if version_tuple(version("yt-dlp")) >= MINIMUM_YT_DLP_VERSION:
                return
        except PackageNotFoundError:
            pass

        requirements_path = Path(__file__).resolve().with_name("requirements.txt")
        subprocess.check_call([
            sys.executable, "-m", "pip", "install", "--upgrade",
            "-r", str(requirements_path),
        ])
        os.execv(sys.executable, [sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]])
        return

    SERVER_RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    requirements_path = Path(__file__).resolve().with_name("requirements.txt")

    if not SERVER_VENV_PYTHON.exists():
        subprocess.check_call([sys.executable, "-m", "venv", str(SERVER_VENV_DIR)])

    try:
        installed_version = subprocess.check_output(
            [
                str(SERVER_VENV_PYTHON),
                "-c",
                "import yt_dlp; print(yt_dlp.version.__version__)",
            ],
            text=True,
        ).strip()
        needs_update = version_tuple(installed_version) < MINIMUM_YT_DLP_VERSION
    except (subprocess.CalledProcessError, FileNotFoundError):
        needs_update = True

    if needs_update:
        subprocess.check_call([
            str(SERVER_VENV_PYTHON), "-m", "pip", "install", "--upgrade",
            "-r", str(requirements_path),
        ])

    os.execv(
        str(SERVER_VENV_PYTHON),
        [str(SERVER_VENV_PYTHON), str(Path(__file__).resolve()), *sys.argv[1:]],
    )


ensure_server_runtime()

import yt_dlp
from flask import Flask, request, jsonify, send_from_directory, url_for

app = Flask(__name__)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

DEFAULT_AUDIO_FOLDER = str(SERVER_RUNTIME_DIR / "downloads")
AUDIO_FOLDER = os.environ.get("SAUCY_MUSIC_DOWNLOADS", DEFAULT_AUDIO_FOLDER)
os.makedirs(AUDIO_FOLDER, exist_ok=True)
SUPPORTED_AUDIO_EXTENSIONS = ("m4a", "mp3")
TITLE_CACHE = {}


@lru_cache(maxsize=128)
def download_lock(media_url):
    return threading.Lock()


def cached_audio_path(video_id):
    for extension in SUPPORTED_AUDIO_EXTENSIONS:
        candidate = os.path.join(AUDIO_FOLDER, f"{video_id}.{extension}")
        if os.path.isfile(candidate) and os.path.getsize(candidate) > 0:
            return candidate
    return None


def youtube_video_id(media_url):
    parsed = urlparse(media_url)
    host = (parsed.hostname or '').lower().removeprefix('www.').removeprefix('m.')
    path_parts = [part for part in parsed.path.split('/') if part]

    if host == 'youtu.be' and path_parts:
        return path_parts[0]
    if host in ('youtube.com', 'music.youtube.com'):
        if parsed.path == '/watch':
            return parse_qs(parsed.query).get('v', [None])[0]
        if len(path_parts) >= 2 and path_parts[0] in ('shorts', 'embed', 'live'):
            return path_parts[1]
    return None


def audio_payload(audio_path, title):
    return {
        "audio_url": url_for(
            'serve_audio',
            filename=os.path.basename(audio_path),
            _external=True,
        ),
        "title": title,
    }


def find_executable(name):
    detected_path = shutil.which(name)
    if detected_path:
        return detected_path

    for directory in ('/usr/local/bin', '/opt/homebrew/bin'):
        candidate = os.path.join(directory, name)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate

    return None

@app.route('/get_audio_url', methods=['GET'])
def get_audio_url():
    video_url = request.args.get('url', '').strip()

    if not video_url:
        logger.error("No URL provided")
        return jsonify({"error": "No URL provided"}), 400

    parsed_url = urlparse(video_url)
    if parsed_url.scheme not in ('http', 'https') or not parsed_url.netloc:
        logger.error("Invalid media URL: %s", video_url)
        return jsonify({"error": "A valid http or https media URL is required"}), 400

    ydl_opts = {
        # Prefer an iOS-native AAC/M4A stream. This normally avoids a costly
        # audio transcode and preserves the source quality bit-for-bit.
        'format': 'bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio/best',
        'outtmpl': f'{AUDIO_FOLDER}/%(id)s.%(ext)s',
        'quiet': True,
        'no_warnings': True,
        'noplaylist': True,
        'writethumbnail': False,
        'embedthumbnail': False,
        'writeinfojson': False,
        'writesubtitles': False,
        'writeautomaticsub': False,
        'concurrent_fragment_downloads': 4,
        'retries': 3,
        'fragment_retries': 3,
        'postprocessors': [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': 'm4a',
            'preferredquality': '192',
        }],
    }

    if ffmpeg_path := find_executable('ffmpeg'):
        ydl_opts['ffmpeg_location'] = ffmpeg_path

    if node_path := find_executable('node'):
        ydl_opts['js_runtimes'] = {'node': {'path': node_path}}
        ydl_opts['remote_components'] = {'ejs:npm'}

    try:
        known_video_id = youtube_video_id(video_url)
        if known_video_id:
            cached_path = cached_audio_path(known_video_id)
            cached_title = TITLE_CACHE.get(known_video_id)
            if cached_path and cached_title:
                return jsonify(audio_payload(cached_path, cached_title))

        with download_lock(known_video_id or video_url):
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                # One metadata request is reused for downloading, avoiding the
                # duplicate extraction that ydl.download() would perform.
                info_dict = ydl.extract_info(video_url, download=False)
                video_id = info_dict.get("id")
                video_title = info_dict.get('title', 'Untitled')

                if not video_id:
                    return jsonify({"error": "The media ID could not be determined"}), 502

                TITLE_CACHE[video_id] = video_title

                audio_path = cached_audio_path(video_id)
                if audio_path is None:
                    ydl.process_ie_result(info_dict, download=True)
                    audio_path = cached_audio_path(video_id)

                if audio_path is None:
                    logger.error("Audio file not found after processing: %s", video_id)
                    return jsonify({"error": "Audio file not found"}), 500

                filename = os.path.basename(audio_path)
                logger.info("Audio ready: %s", filename)
                return jsonify(audio_payload(audio_path, video_title))

    except Exception:
        # Enhanced error logging
        logger.exception("Error extracting audio URL")
        return jsonify({
            "error": "The audio server could not extract this video. Update yt-dlp and try again."
        }), 502

@app.route('/audio/<filename>')
def serve_audio(filename):
    try:
        # Ensure the file exists before serving it
        file_path = os.path.join(AUDIO_FOLDER, filename)
        if os.path.exists(file_path):
            response = send_from_directory(
                AUDIO_FOLDER,
                filename,
                conditional=True,
                max_age=31536000,
            )
            response.headers['Accept-Ranges'] = 'bytes'
            response.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
            return response
        else:
            logger.error(f"Audio file not found: {filename}")
            return jsonify({"error": "Audio file not found"}), 404
    except Exception as e:
        logger.error(f"Error serving audio file: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=False, host='0.0.0.0', port=5001, threaded=True)
