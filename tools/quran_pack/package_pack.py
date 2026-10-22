"""Step 3 of the Quran voicepack build: package everything for release.

Reads what fetch_quran.py (text + audio) and make_gifs.py (element GIFs)
left in <build_dir>, and writes <build_dir>/release/:

  surah_001.zip ... surah_114.zip   one per chapter:
      verses.json      Arabic text per verse (Tanzil Uthmani). No translations:
                       their copyright holders haven't licensed redistribution
      001001.mp3 ...   one recitation clip per verse (SSSAAA.mp3)
      bismillah.mp3    played before verse 1 (all chapters except 1 and 9)
  element_<id>.gif                  the nature scene for each element
  quran_manifest.json               chapter list, element per chapter, sizes,
                                    download URLs and source credits

The manifest is also copied into the Flutter app's assets, so the app can
list every chapter with its download size before anything is downloaded.

Usage:  python -I package_pack.py <build_dir> [--bitrate 64] [--tag quran-pack-v1]
"""
import argparse
import json
import random
import shutil
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
APP_MANIFEST = REPO / "frontend" / "assets" / "quran" / "quran_manifest.json"
GITHUB_REPO = "scz912/audiobook_system"

# Chapters whose name or best-known passage is about a nature element.
# Every other chapter gets a random element (seeded, so rebuilds match).
THEMED = {
    1: "sunrise",     # Al-Fatiha, The Opening
    10: "ocean",      # Yunus - Jonah and the sea
    11: "rain",       # Hud - the flood: "O sky, withhold [your rain]" (11:44)
    13: "thunder",    # Ar-Ra'd, The Thunder
    14: "forest",     # Ibrahim - the parable of the good tree (14:24)
    15: "mountain",   # Al-Hijr, The Rocky Tract
    16: "forest",     # An-Nahl, The Bee - trees, plants and fruits (16:10-11)
    17: "night_sky",  # Al-Isra, The Night Journey
    18: "mountain",   # Al-Kahf, The Cave
    20: "fire",       # Taha - Moses sees a fire (20:10)
    21: "fire",       # Al-Anbiya - "O fire, be coolness" (21:69)
    24: "sunrise",    # An-Nur, The Light
    28: "fire",       # Al-Qasas - the fire at the mount (28:29)
    30: "clouds",     # Ar-Rum - winds raise the clouds (30:48)
    34: "river",      # Saba - the flood of the dam and the gardens (34:15-16)
    35: "ocean",      # Fatir - the two seas (35:12)
    36: "moon",       # Ya-Sin - the moon's phases and orbits (36:39-40)
    37: "night_sky",  # As-Saffat - the sky adorned with stars (37:6)
    44: "clouds",     # Ad-Dukhan, The Smoke
    46: "desert",     # Al-Ahqaf, The Wind-Curved Sandhills
    50: "rain",       # Qaf - blessed rain from the sky (50:9)
    51: "clouds",     # Adh-Dhariyat, The Winnowing Winds
    52: "mountain",   # At-Tur, The Mount
    53: "night_sky",  # An-Najm, The Star
    54: "moon",       # Al-Qamar, The Moon
    55: "ocean",      # Ar-Rahman - the two seas meet (55:19)
    67: "night_sky",  # Al-Mulk - the sky adorned with lamps (67:5)
    71: "rain",       # Nuh - rain in abundance (71:11)
    76: "river",      # Al-Insan - gardens and springs
    77: "thunder",    # Al-Mursalat - the storm winds
    78: "mountain",   # An-Naba - mountains as pegs (78:7)
    80: "forest",     # 'Abasa - gardens, olives, palms (80:27-32)
    81: "night_sky",  # At-Takwir - the stars fall
    82: "ocean",      # Al-Infitar - the seas burst forth (82:3)
    84: "moon",       # Al-Inshiqaq - the twilight and the full moon (84:16-18)
    85: "night_sky",  # Al-Buruj, The Mansions of the Stars
    86: "night_sky",  # At-Tariq, The Night Comer (the piercing star)
    87: "forest",     # Al-A'la - the green pasture (87:4-5)
    88: "desert",     # Al-Ghashiyah - camels, sky, mountains, earth (88:17-20)
    89: "sunrise",    # Al-Fajr, The Dawn
    91: "sunrise",    # Ash-Shams, The Sun
    92: "night_sky",  # Al-Layl, The Night
    93: "sunrise",    # Ad-Duha, The Morning Hours
    95: "forest",     # At-Tin, The Fig
    97: "night_sky",  # Al-Qadr - the night until dawn
    99: "mountain",   # Az-Zalzalah, The Earthquake
    100: "desert",    # Al-'Adiyat - the chargers raising dust
    101: "fire",      # Al-Qari'ah - the blazing fire (101:11)
    103: "sunrise",   # Al-'Asr, The Declining Day
    104: "fire",      # Al-Humazah - the fire of Allah (104:6)
    105: "desert",    # Al-Fil, The Elephant
    106: "desert",    # Quraysh - the caravans of winter and summer
    108: "river",     # Al-Kawthar - the river of abundance
    111: "fire",      # Al-Masad - the blazing flame (111:3)
    113: "sunrise",   # Al-Falaq, The Daybreak
}

SURAH_PREFIX = "سُورَةُ "


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def clean(text: str) -> str:
    # The API puts a byte-order mark on the very first verse.
    return text.replace("﻿", "").strip()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("build_dir")
    ap.add_argument("--bitrate", type=int, default=64)
    ap.add_argument("--tag", default="quran-pack-v1")
    args = ap.parse_args()

    build = Path(args.build_dir)
    text_dir = build / "text"
    audio_dir = build / "audio" / f"{args.bitrate}kbps"
    gif_dir = build / "elements"
    out = build / "release"
    out.mkdir(parents=True, exist_ok=True)

    elements = load(HERE / "elements.json")
    element_ids = [e["id"] for e in elements]
    for chapter, element in THEMED.items():
        assert element in element_ids, (chapter, element)

    meta = load(text_dir / "meta.json")["surahs"]["references"]
    arabic = load(text_dir / "quran-uthmani.json")["surahs"]

    rng = random.Random(args.tag)
    bismillah = audio_dir / "0001.mp3"  # 1:1 is the Bismillah itself
    chapters = []
    for s in meta:
        n = s["number"]
        ar = arabic[n - 1]
        assert len(ar["ayahs"]) == s["numberOfAyahs"]

        has_bismillah = n not in (1, 9)
        verses = []
        files = []
        for a in ar["ayahs"]:
            clip = f"{n:03d}{a['numberInSurah']:03d}.mp3"
            src = audio_dir / f"{a['number']:04d}.mp3"
            if not src.exists():
                raise SystemExit(f"missing audio for verse {a['number']} - run fetch_quran.py again")
            files.append((src, clip))
            verses.append({
                "n": a["numberInSurah"],
                "ar": clean(a["text"]),
                "audio": clip,
            })
        if has_bismillah:
            files.append((bismillah, "bismillah.mp3"))

        zip_name = f"surah_{n:03d}.zip"
        zip_path = out / zip_name
        payload = {
            "number": n,
            "bismillah_audio": "bismillah.mp3" if has_bismillah else None,
            "verses": verses,
        }
        payload_bytes = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        # MP3s are already compressed, so store them; only squeeze the JSON.
        with zipfile.ZipFile(zip_path, "w") as z:
            z.writestr("verses.json", payload_bytes, compress_type=zipfile.ZIP_DEFLATED)
            for src, name in files:
                z.write(src, name, compress_type=zipfile.ZIP_STORED)
        installed = len(payload_bytes) + sum(src.stat().st_size for src, _ in files)

        themed = n in THEMED
        element = THEMED[n] if themed else rng.choice(element_ids)
        chapters.append({
            "number": n,
            "name_ar": s["name"].removeprefix(SURAH_PREFIX),
            "name_en": s["englishName"],
            "meaning_en": s["englishNameTranslation"],
            "revelation": s["revelationType"],
            "verses": s["numberOfAyahs"],
            "element": element,
            "element_reason": "theme" if themed else "random",
            "file": zip_name,
            "bytes": zip_path.stat().st_size,
            "installed_bytes": installed,
        })
        print(f"{zip_name}: {s['englishName']:<16} {element:<10} {zip_path.stat().st_size / 1e6:7.2f} MB")

    manifest_elements = []
    for e in elements:
        src = gif_dir / f"{e['id']}.gif"
        if not src.exists():
            raise SystemExit(f"missing {src} - run make_gifs.py first")
        dest_name = f"element_{e['id']}.gif"
        shutil.copyfile(src, out / dest_name)
        manifest_elements.append({
            "id": e["id"],
            "name_en": e["name_en"],
            "name_ms": e["name_ms"],
            "file": dest_name,
            "bytes": src.stat().st_size,
            "credit": e["credit"],
            "license": e["license"],
            "source_url": e["source_url"],
        })

    manifest = {
        "version": 1,
        "pack_id": args.tag,
        "base_url": f"https://github.com/{GITHUB_REPO}/releases/download/{args.tag}/",
        "reciter": "Mishary Rashid Alafasy",
        "bitrate_kbps": args.bitrate,
        "elements": manifest_elements,
        "chapters": chapters,
        "sources": [
            {
                "title": "Recitation audio: Mishary Rashid Alafasy (verse by verse)",
                "detail": f"{args.bitrate} kbps MP3 from the AlQuran Cloud audio CDN (Islamic Network). "
                          "Copyright remains with the reciter; free for non-commercial redistribution.",
                "url": "https://alquran.cloud/cdn",
                "license": "AlQuran Cloud terms: https://alquran.cloud/terms-and-conditions",
            },
            {
                "title": "Arabic text: Tanzil Quran Text (Uthmani), via the AlQuran Cloud API",
                "detail": "Tanzil Quran Text (Uthmani), Copyright (C) 2007-2021 Tanzil Project. "
                          "Verbatim copy - the text has not been changed.",
                "url": "https://tanzil.net",
                "license": "Creative Commons Attribution 3.0 (Tanzil terms: https://tanzil.net/docs/text_license)",
            },
            {
                "title": "Chapter names and verse data: AlQuran Cloud API",
                "detail": "An Islamic Network project.",
                "url": "https://alquran.cloud/api",
                "license": "",
            },
        ],
    }
    text = json.dumps(manifest, ensure_ascii=False, indent=1)
    (out / "quran_manifest.json").write_text(text, encoding="utf-8")
    APP_MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    APP_MANIFEST.write_text(text, encoding="utf-8")

    zips = sum(c["bytes"] for c in chapters)
    gifs = sum(e["bytes"] for e in manifest_elements)
    print(f"\n{len(chapters)} chapters: {zips / 1e6:.1f} MB of zips + {gifs / 1e6:.1f} MB of GIFs "
          f"= {(zips + gifs) / 1e6:.1f} MB to download")
    print(f"manifest -> {out / 'quran_manifest.json'} and {APP_MANIFEST}")


if __name__ == "__main__":
    main()
