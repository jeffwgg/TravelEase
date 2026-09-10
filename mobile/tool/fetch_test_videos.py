#!/usr/bin/env python3
"""Download labeled ASL sign videos for testing the recognition model.

Words are resolved against the model's 250-sign vocabulary using the WLASL
dataset metadata (2000 glosses -> source video URLs). Only instances with
direct video-file URLs are used. Sources are public ASL dictionaries
(aslbricks, SigningSavvy, Handspeak, SpreadTheSign, StartASL, ASL Signbank)
collected by the WLASL project — fine for local testing; check the source
site's terms before redistributing clips in the app.

Usage:
    python fetch_test_videos.py book cat yes          # fetch specific words
    python fetch_test_videos.py --list                # show fetchable words
Videos are saved as <word>.mp4 into --out (default ./sign_test_videos).
"""
import json
import os
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

WLASL_JSON_URL = "https://huggingface.co/datasets/aipieces/WLASL100/resolve/main/WLASL_v0.3.json"
VIDEO_EXTS = (".mp4", ".mov", ".webm", ".avi")
MAX_TRIES_PER_WORD = 3


def load_metadata() -> dict:
    cache = Path(tempfile.gettempdir()) / "wlasl_v03.json"
    if not cache.exists():
        print("downloading WLASL metadata (~12MB, once) ...")
        urllib.request.urlretrieve(WLASL_JSON_URL, cache)
    meta = json.loads(cache.read_text(encoding="utf-8"))
    direct = {}
    for entry in meta:
        gloss = entry["gloss"]
        urls = [i.get("url", "") for i in entry.get("instances", [])]
        direct[gloss] = [u for u in urls if u.lower().split("?")[0].endswith(VIDEO_EXTS)]
    return direct


def main() -> int:
    direct = load_metadata()
    vocab = set(json.loads((Path(__file__).resolve().parent.parent
                            / "assets/models/sign_to_prediction_index_map.json").read_text()).keys())

    if "--list" in sys.argv:
        fetchable = sorted(w for w in vocab if direct.get(w))
        print(f"{len(fetchable)} of {len(vocab)} vocabulary words have direct video URLs:")
        print("  " + ", ".join(fetchable))
        return 0

    words = [w.lower() for w in sys.argv[1:]]
    if not words:
        print(__doc__)
        return 1

    out_dir = Path(os.getcwd()) / "sign_test_videos"
    out_dir.mkdir(exist_ok=True)

    ok = 0
    for word in words:
        if word not in vocab:
            print(f"SKIP {word:<12} not in the model's 250-sign vocabulary")
            continue
        target = out_dir / f"{word}.mp4"
        if target.exists():
            print(f"KEEP {word:<12} already downloaded")
            ok += 1
            continue
        done = False
        for url in direct.get(word, [])[:MAX_TRIES_PER_WORD]:
            subprocess.run(["curl", "-skL", "--max-time", "40", "-o", str(target), url],
                           capture_output=True)
            if target.exists() and target.stat().st_size > 30_000:
                print(f"OK   {word:<12} {target.stat().st_size // 1024}KB  <- {url[:60]}")
                ok += 1
                done = True
                break
            if target.exists():
                target.unlink()
        if not done:
            print(f"MISS {word:<12} no reachable direct URL")

    print(f"\n{ok}/{len(words)} saved to {out_dir}")
    print(f"test them:  python tool/test_sign_video.py {out_dir}/*.mp4")
    return 0


if __name__ == "__main__":
    sys.exit(main())
