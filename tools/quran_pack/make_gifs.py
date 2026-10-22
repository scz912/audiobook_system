"""Step 2 of the Quran voicepack build: make the nature-element GIFs.

For each element in elements.json, download its source from Wikimedia
Commons (an animated GIF, or a short CC-licensed video when Commons has no
good GIF of that scene) and turn it into a small looping GIF:
  - at most 480 px wide, 10 fps, one shared 256-colour palette
  - video sources: a few seconds cut out, with the end cross-faded into the
    start so the loop has no visible jump

Needs ffmpeg; `pip install imageio-ffmpeg` provides one.

Usage:  python -I make_gifs.py <build_dir>
"""
import json
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import imageio_ffmpeg

HERE = Path(__file__).resolve().parent
UA = {"User-Agent": "AudiobookForAutism-FYP/1.0 (https://github.com/scz912/audiobook_system; one-off asset download)"}
WIDTH = 480
FPS = 10


def download(url: str, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size > 0:
        return
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=300) as r:
                data = r.read()
            dest.write_bytes(data)
            time.sleep(10)  # be gentle with upload.wikimedia.org
            return
        except Exception as e:
            print(f"  retry {url} ({e})", flush=True)
            time.sleep(30 * (attempt + 1))
    raise SystemExit(f"could not download {url}")


def convert(ffmpeg: str, src: Path, dest: Path, e: dict) -> None:
    start = float(e.get("start", 0))
    duration = e.get("duration")
    fade = float(e.get("crossfade", 0))
    scale = f"scale='min({WIDTH},iw)':-2:flags=lanczos"
    if e.get("crop"):  # e.g. trim letterbox bars: "iw:ih*0.74"
        scale = f"crop={e['crop']},{scale}"
    palette = "split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5"

    cmd = [ffmpeg, "-y", "-loglevel", "error"]
    if fade > 0:
        # Take duration + fade seconds; play from `fade` onwards and blend
        # the last `fade` seconds into the clip's first `fade` seconds, so
        # the final frame flows straight into the first one.
        length = float(duration) + fade
        cmd += ["-ss", str(start), "-t", str(length), "-i", str(src)]
        graph = (
            f"[0:v]fps={FPS},{scale},setsar=1,split[x][y];"
            f"[x]trim=start={fade},setpts=PTS-STARTPTS,fps={FPS}[a];"
            f"[y]trim=end={fade},setpts=PTS-STARTPTS,fps={FPS}[b];"
            f"[a][b]xfade=transition=fade:duration={fade}:offset={float(duration) - fade},{palette}"
        )
    else:
        if start:
            cmd += ["-ss", str(start)]
        if duration:
            cmd += ["-t", str(duration)]
        cmd += ["-i", str(src)]
        graph = f"[0:v]fps={FPS},{scale},setsar=1,{palette}"
    cmd += ["-filter_complex", graph, "-loop", "0", str(dest)]
    subprocess.run(cmd, check=True)


def main() -> None:
    build = Path(sys.argv[1])
    src_dir = build / "element_sources"
    out_dir = build / "elements"
    src_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()

    for e in json.loads((HERE / "elements.json").read_text(encoding="utf-8")):
        url = e["file_url"]
        src = src_dir / f"{e['id']}{Path(url).suffix.lower()}"
        download(url, src)
        dest = out_dir / f"{e['id']}.gif"
        convert(ffmpeg, src, dest, e)
        # Some source GIFs are already small and tightly optimised; if ours
        # came out bigger, ship the original instead.
        if src.suffix == ".gif" and src.stat().st_size < dest.stat().st_size:
            shutil.copyfile(src, dest)
        print(f"{e['id']:<10} {src.stat().st_size / 1e6:6.2f} MB source -> {dest.stat().st_size / 1e6:5.2f} MB gif", flush=True)


if __name__ == "__main__":
    main()
