# Al-Quran voicepack builder

Builds the downloadable Al-Quran pack used by the **Al-Quran** tab in
Content Management, and publishes it as a GitHub release. The app only ships
a small manifest (`frontend/assets/quran/quran_manifest.json`); the audio
(~860 MB at 64 kbps) and nature GIFs are downloaded on the device, one
chapter at a time, from the release.

## What's in the pack

| Part | Source | Licence / terms |
|---|---|---|
| Verse-by-verse recitation, Mishary Rashid Alafasy | AlQuran Cloud audio CDN (`cdn.islamic.network/quran/audio/64/ar.alafasy/<n>.mp3`) | Free non-commercial redistribution; copyright stays with the reciter ([terms](https://alquran.cloud/terms-and-conditions)) |
| Arabic text (Uthmani) | Tanzil Project, via `api.alquran.cloud/v1/quran/quran-uthmani` | CC BY 3.0, verbatim only ([licence](https://tanzil.net/docs/text_license)) |
| Nature GIFs | Wikimedia Commons (see `elements.json`) | Per file: CC0 / public domain / CC BY / CC BY-SA |

All of this is listed again under **Sources & credits** at the end of the
Al-Quran page in the app.

## Elements

Each chapter is shown over one looping nature scene. Chapters whose name or
best-known passage is about nature use that element (e.g. 13 Ar-Ra'd → thunder,
54 Al-Qamar → moon, 111 Al-Masad → fire); the list with the reason for each is
`THEMED` in `package_pack.py`. Every other chapter gets a random element,
seeded with the release tag so a rebuild gives the same result.

## Building

Run from the repo root. Output goes to `quran_pack_build/` (git-ignored).

```powershell
# 1. Text + all 6,236 verse clips (resumable; ~860 MB)
python -I tools/quran_pack/fetch_quran.py quran_pack_build --bitrate 64

# 2. Element GIFs (needs ffmpeg: pip install imageio-ffmpeg)
python -I tools/quran_pack/make_gifs.py quran_pack_build

# 3. One zip per chapter + quran_manifest.json (also copied into the app)
python -I tools/quran_pack/package_pack.py quran_pack_build --tag quran-pack-v1

# 4. Publish as release assets (GITHUB_TOKEN needs Contents: write)
$env:GITHUB_TOKEN = "<token>"
python -I tools/quran_pack/upload_release.py quran_pack_build --tag quran-pack-v1
```

To publish a changed pack, use a new tag (e.g. `quran-pack-v2`) so devices
that already downloaded v1 aren't mixed with v2 files, then rebuild the app
with the new manifest.

## In the app

- `frontend/lib/services/quran_pack_service.dart`: download queue (two at a
  time, with progress), unzip, remove one chapter or everything.
- `frontend/lib/pages/caregiver/quran_library_section.dart`: the chapter list,
  sizes, download/remove buttons and the sources section.
- `frontend/lib/pages/child/quran_player_page.dart`: the player.
- `AppConfig.quranAutoDownload`: when `true` (current setting, for the test
  emulator) the whole pack downloads in the background after sign-in, skipping
  chapters the caregiver removed. Set it to `false` for release builds.
