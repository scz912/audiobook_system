"""Step 4 of the Quran voicepack build: publish it as a GitHub release.

Creates the release <tag> on the repo (if it doesn't exist yet) and uploads
every file in <build_dir>/release as a release asset. Assets that are
already there with the same size are skipped, so a failed run can simply be
started again. GitHub release assets can be up to 2 GB each, which is why the
pack lives here and not in the git history.

The token is read from the GITHUB_TOKEN environment variable (needs
Contents: write on the repo). It is never printed.

Usage:  python -I upload_release.py <build_dir> [--tag quran-pack-v1] [--repo owner/name]
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.github.com"
UPLOADS = "https://uploads.github.com"
TYPES = {".zip": "application/zip", ".gif": "image/gif", ".json": "application/json"}


def call(method, url, token, body=None, content_type="application/json"):
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "quran-pack-uploader",
    }
    data = None
    if body is not None:
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"null")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("build_dir")
    ap.add_argument("--tag", default="quran-pack-v1")
    ap.add_argument("--repo", default="scz912/audiobook_system")
    args = ap.parse_args()

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        sys.exit("GITHUB_TOKEN is not set")
    release_dir = Path(args.build_dir) / "release"
    manifest = json.loads((release_dir / "quran_manifest.json").read_text(encoding="utf-8"))

    total = sum(p.stat().st_size for p in release_dir.iterdir() if p.is_file())
    body = (
        "Downloadable Al-Quran recitation pack for the Audiobook for Autism app.\n\n"
        f"- {len(manifest['chapters'])} chapters, one zip each (verse-by-verse MP3 + verses.json)\n"
        f"- Recitation: {manifest['reciter']}, {manifest['bitrate_kbps']} kbps\n"
        f"- Total size: {total / 1e6:.0f} MB\n\n"
        "The app reads quran_manifest.json (also bundled in the app) and downloads only the chapters "
        "the caregiver picks.\n\n"
        "Sources: recitation audio and API by AlQuran Cloud / Islamic Network (free for non-commercial "
        "redistribution, copyright with the reciter); Arabic text by the Tanzil Project (CC BY 3.0, "
        "verbatim; no translations are included); nature GIFs from "
        "Wikimedia Commons under the licences listed in quran_manifest.json."
    )
    status, release = call("GET", f"{API}/repos/{args.repo}/releases/tags/{args.tag}", token)
    if status == 404:
        status, release = call("POST", f"{API}/repos/{args.repo}/releases", token, {
            "tag_name": args.tag,
            "target_commitish": "main",
            "name": "Al-Quran recitation pack (v1)",
            "body": body,
            "draft": False,
            "prerelease": False,
        })
        if status != 201:
            sys.exit(f"could not create release: {status} {release}")
        print(f"created release {args.tag}")
    elif status == 200:
        # Keep the description in step with what the pack now contains.
        call("PATCH", f"{API}/repos/{args.repo}/releases/{release['id']}", token, {"body": body})
    else:
        sys.exit(f"could not read release: {status} {release}")

    existing = {}
    page = 1
    while True:
        status, assets = call("GET", f"{API}/repos/{args.repo}/releases/{release['id']}/assets?per_page=100&page={page}", token)
        if status != 200 or not assets:
            break
        existing.update({a["name"]: a for a in assets})
        page += 1

    # Upload the manifest last, so it never points at assets that aren't up yet.
    files = sorted(p for p in release_dir.iterdir() if p.is_file() and p.name != "quran_manifest.json")
    files.append(release_dir / "quran_manifest.json")
    for i, path in enumerate(files, 1):
        size = path.stat().st_size
        old = existing.get(path.name)
        if old and old["size"] == size and old.get("state") == "uploaded":
            continue
        if old:
            call("DELETE", f"{API}/repos/{args.repo}/releases/assets/{old['id']}", token)
        url = f"{UPLOADS}/repos/{args.repo}/releases/{release['id']}/assets?name={urllib.parse.quote(path.name)}"
        status, res = call("POST", url, token, path.read_bytes(), TYPES.get(path.suffix, "application/octet-stream"))
        if status != 201:
            sys.exit(f"upload of {path.name} failed: {status} {res}")
        print(f"[{i}/{len(files)}] {path.name} ({size / 1e6:.1f} MB)", flush=True)

    print(f"done: https://github.com/{args.repo}/releases/tag/{args.tag}")


if __name__ == "__main__":
    main()
