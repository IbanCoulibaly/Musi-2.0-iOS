#!/usr/bin/env python3
"""Measure how fast the audio server answers the app.

For each YouTube URL it records:

* cold    - first /get_audio_url request (yt-dlp extracts and downloads)
* hot     - repeat requests once the file and title are cached
* ttfb    - time to the first byte of a 64 KB range request (what the
            player asks for before it starts playing)
* full    - time to transfer the whole file, and its size

Usage:
    python3 benchmark.py --server http://127.0.0.1:5001 URL [URL ...]

Only the standard library is needed. Results print as a table and are
written to benchmark-results.json next to this script.
"""

import argparse
import json
import statistics
import time
import urllib.parse
import urllib.request
from pathlib import Path


def timed_get(url, headers=None, read_bytes=None):
    request = urllib.request.Request(url, headers=headers or {})
    start = time.perf_counter()
    with urllib.request.urlopen(request, timeout=300) as response:
        first = response.read(1)
        ttfb = time.perf_counter() - start
        rest = response.read() if read_bytes is None else response.read(read_bytes)
        total = time.perf_counter() - start
        return response.status, first + rest, ttfb, total


def audio_url(server, media_url):
    query = urllib.parse.urlencode({"url": media_url})
    return f"{server.rstrip('/')}/get_audio_url?{query}"


def bench(server, media_url, hot_runs):
    _, body, _, cold = timed_get(audio_url(server, media_url))
    payload = json.loads(body)

    hot = [timed_get(audio_url(server, media_url))[3] for _ in range(hot_runs)]

    file_url = payload["audio_url"]
    _, _, ttfb, _ = timed_get(file_url, headers={"Range": "bytes=0-65535"}, read_bytes=65535)
    _, data, _, full = timed_get(file_url)

    return {
        "url": media_url,
        "title": payload.get("title"),
        "cold_s": round(cold, 3),
        "hot_median_ms": round(statistics.median(hot) * 1000, 2),
        "range_ttfb_ms": round(ttfb * 1000, 2),
        "full_transfer_ms": round(full * 1000, 2),
        "size_mb": round(len(data) / 1_000_000, 2),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("urls", nargs="+")
    parser.add_argument("--server", default="http://127.0.0.1:5001")
    parser.add_argument("--hot-runs", type=int, default=10)
    args = parser.parse_args()

    results = [bench(args.server, url, args.hot_runs) for url in args.urls]

    header = f"{'title':42} {'cold s':>7} {'hot ms':>7} {'ttfb ms':>8} {'full ms':>8} {'MB':>6}"
    print(header)
    print("-" * len(header))
    for row in results:
        print(f"{(row['title'] or '')[:42]:42} {row['cold_s']:>7} {row['hot_median_ms']:>7} "
              f"{row['range_ttfb_ms']:>8} {row['full_transfer_ms']:>8} {row['size_mb']:>6}")

    out = Path(__file__).with_name("benchmark-results.json")
    out.write_text(json.dumps(results, indent=2, ensure_ascii=False))
    print(f"\nSaved {out.name}")


if __name__ == "__main__":
    main()
