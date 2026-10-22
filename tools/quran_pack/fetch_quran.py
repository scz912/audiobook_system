"""Step 1 of the Quran voicepack build: download the text and the audio.

Everything comes from the AlQuran Cloud API (https://alquran.cloud):
  - chapter metadata       api.alquran.cloud/v1/meta
  - Arabic text (Uthmani)  api.alquran.cloud/v1/quran/quran-uthmani   (Tanzil.net text)
  - verse-by-verse audio   cdn.islamic.network/quran/audio/<kbps>/ar.alafasy/<n>.mp3
                           (Mishary Rashid Alafasy, n = 1..6236)

The run is resumable: files that already exist are skipped, so it can be
stopped and started again.

Usage:  python -I fetch_quran.py <build_dir> [--bitrate 64] [--workers 8]
"""
import argparse
import json
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

API = "https://api.alquran.cloud/v1"
CDN = "https://cdn.islamic.network/quran/audio/{kbps}/ar.alafasy/{n}.mp3"
UA = {"User-Agent": "AudiobookForAutism-FYP/1.0 (quran voicepack builder)"}
# Arabic only. Translations were dropped: their publishers keep copyright
# and haven't licensed redistributing the full text.
TEXT_EDITIONS = ["quran-uthmani"]
TOTAL_VERSES = 6236


def http_get(url: str, attempts: int = 5) -> bytes:
    for i in range(attempts):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except Exception as e:  # network blips, 429s, timeouts
            if i == attempts - 1:
                raise
            wait = 2 ** i
            print(f"  retry {url} in {wait}s ({e})", flush=True)
            time.sleep(wait)
    raise RuntimeError("unreachable")


def fetch_json(url: str, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size > 0:
        print(f"skip {dest.name}")
        return
    data = json.loads(http_get(url))
    if data.get("code") != 200:
        raise RuntimeError(f"{url} -> {data.get('status')}")
    dest.write_text(json.dumps(data["data"], ensure_ascii=False), encoding="utf-8")
    print(f"saved {dest.name}")


def fetch_audio(n: int, kbps: int, audio_dir: Path) -> int:
    dest = audio_dir / f"{n:04d}.mp3"
    if dest.exists() and dest.stat().st_size > 0:
        return 0
    body = http_get(CDN.format(kbps=kbps, n=n))
    if len(body) < 1000 or not (body[:3] == b"ID3" or body[0] == 0xFF):
        raise RuntimeError(f"verse {n}: response is not an mp3 ({len(body)} bytes)")
    tmp = dest.with_suffix(".part")
    tmp.write_bytes(body)
    tmp.replace(dest)
    return len(body)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("build_dir")
    ap.add_argument("--bitrate", type=int, default=64)
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    build = Path(args.build_dir)
    text_dir = build / "text"
    audio_dir = build / "audio" / f"{args.bitrate}kbps"
    text_dir.mkdir(parents=True, exist_ok=True)
    audio_dir.mkdir(parents=True, exist_ok=True)

    fetch_json(f"{API}/meta", text_dir / "meta.json")
    for edition in TEXT_EDITIONS:
        fetch_json(f"{API}/quran/{edition}", text_dir / f"{edition}.json")

    done = sum(1 for p in audio_dir.glob("*.mp3") if p.stat().st_size > 0)
    print(f"audio: {done}/{TOTAL_VERSES} already present", flush=True)
    failed = []
    downloaded = 0
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(fetch_audio, n, args.bitrate, audio_dir): n
            for n in range(1, TOTAL_VERSES + 1)
        }
        for i, fut in enumerate(as_completed(futures), 1):
            n = futures[fut]
            try:
                downloaded += fut.result()
            except Exception as e:
                failed.append(n)
                print(f"FAILED verse {n}: {e}", flush=True)
            if i % 250 == 0:
                print(f"  {i}/{TOTAL_VERSES} checked, {downloaded / 1e6:.1f} MB new", flush=True)

    total = sum(p.stat().st_size for p in audio_dir.glob("*.mp3"))
    print(f"done: {TOTAL_VERSES - len(failed)}/{TOTAL_VERSES} verses, {total / 1e6:.1f} MB on disk")
    if failed:
        print(f"re-run to retry {len(failed)} failed verses: {failed[:20]}...")
        sys.exit(1)


if __name__ == "__main__":
    main()
