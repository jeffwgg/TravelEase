"""Render the app's BIM reference clips from real dataset signer trajectories.

For each requested gloss, picks the dataset clip with the best keypoint
visibility and a sensible length (24-100 frames), renders it as a
stick-figure h264 mp4 via animate.py, and writes it to
``mobile/assets/signs/bim/<slug>.mp4`` — the exact path/naming
SignWordVideoLibrary resolves for BIM playback.

These are the reference videos to practice and test against (the same
signers the model was trained on). Re-run after a finetune vocab change:
    C:/venvs/slr312/Scripts/python.exe scripts/export_reference_clips.py
"""

import csv
import io
import os
import shutil
import sys
import zipfile

import numpy as np

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(SCRIPTS, "..")
DATA = os.path.join(ROOT, "data")
OUT_DIR = os.path.normpath(os.path.join(
    ROOT, "..", "mobile", "assets", "signs", "bim"))

sys.path.insert(0, SCRIPTS)

# Travel-relevant subset of the 117-word vocabulary, aligned with the words
# the app's phrase cards actually use (and the ASL reference set's spirit).
WORDS = [
    "assalamualaikum", "selamat_pagi", "apa_khabar", "khabar_baik",
    "terima_kasih", "tolong", "saya", "awak",
    "tandas", "hospital", "polis", "bomba",
    "bas", "keretapi", "kereta", "teksi", "pergi", "berjalan", "sampai",
    "arah", "mana",
    "kedai", "kafetaria", "makan", "minum", "air", "beli", "berapa", "duit",
    "pinjam", "hilang_habis", "kesakitan", "tanya", "sekolah",
]


def slugify(token: str) -> str:
    """Mirror mobile SignWordVideoLibrary.slugify (lowercase a-z0-9 kept,
    other runs collapse to one '_', trimmed)."""
    out, last_sep = [], False
    for ch in token.lower():
        if ch.isascii() and ch.isalnum():
            out.append(ch)
            last_sep = False
        elif out and not last_sep:
            out.append("_")
            last_sep = True
    slug = "".join(out)
    return slug.rstrip("_")


def ensure_ffmpeg_on_path():
    """animate.py transcodes mp4v→h264 via `shutil.which('ffmpeg')`; the
    bundled slr/bin copy of imageio-ffmpeg satisfies that (and the demo)."""
    bindir = os.path.join(ROOT, "bin")
    exe = os.path.join(bindir, "ffmpeg.exe")
    if not os.path.exists(exe):
        import imageio_ffmpeg
        os.makedirs(bindir, exist_ok=True)
        shutil.copy(imageio_ffmpeg.get_ffmpeg_exe(), exe)
    os.environ["PATH"] = bindir + os.pathsep + os.environ["PATH"]


def load_index():
    """gloss -> [canonical clip ids], from all official splits."""
    by_gloss = {}
    for split in ("train", "val", "test"):
        with open(os.path.join(DATA, "metadata", "splits", f"{split}.txt"),
                  encoding="utf-8") as f:
            for line in f:
                parts = line.strip().split("\t")
                if len(parts) >= 2:
                    by_gloss.setdefault(parts[1], []).append(parts[0])
    return by_gloss


def pick_clip(z, members, ids, rng):
    """Best of a few random candidates: high pose visibility, 24-100 frames."""
    picks = [ids[i] for i in rng.choice(len(ids), size=min(6, len(ids)),
                                        replace=False)]
    best, best_score = None, -1.0
    for cid in picks:
        member = members.get(cid)
        if member is None:
            continue
        with z.open(member) as f:
            seq = np.load(io.BytesIO(f.read()))
        t = len(seq)
        if not (24 <= t <= 100):
            continue
        vis = seq[:, 3::4][:, :33].mean()
        score = vis - abs(t - 48) / 200.0  # prefer ~2s clips, clean tracking
        if score > best_score:
            best, best_score = (cid, seq.astype(np.float32)), score
    if best is None:  # no length fit — take any with the best visibility
        for cid in picks:
            member = members.get(cid)
            if member is None:
                continue
            with z.open(member) as f:
                seq = np.load(io.BytesIO(f.read()))
            vis = seq[:, 3::4][:, :33].mean()
            if vis > best_score:
                best, best_score = (cid, seq.astype(np.float32)), vis
    return best


def main():
    from animate import animate

    ensure_ffmpeg_on_path()
    os.makedirs(OUT_DIR, exist_ok=True)
    by_gloss = load_index()
    with zipfile.ZipFile(os.path.join(DATA, "keypoints_258.zip")) as z:
        members = {os.path.splitext(os.path.basename(n))[0]: n
                   for n in z.namelist() if n.endswith(".npy")}
        rng = np.random.default_rng(11)
        missing = []
        for word in WORDS:
            ids = by_gloss.get(word, [])
            out = os.path.join(OUT_DIR, f"{slugify(word)}.mp4")
            picked = pick_clip(z, members, ids, rng) if ids else None
            if picked is None:
                missing.append(word)
                print(f"  !! {word}: no dataset clip found")
                continue
            cid, seq = picked
            animate(seq, out, fps=12)
            size_kb = os.path.getsize(out) / 1024
            print(f"  {slugify(word):22s} <- {cid:26s} "
                  f"{len(seq):3d}f  {size_kb:6.0f} KB")
    total = sum(os.path.getsize(os.path.join(OUT_DIR, f))
                for f in os.listdir(OUT_DIR) if f.endswith(".mp4"))
    print(f"\nwrote {len(WORDS) - len(missing)} clips "
          f"({total / 1e6:.1f} MB total) -> {OUT_DIR}")
    if missing:
        print("missing:", ", ".join(missing))


if __name__ == "__main__":
    main()
