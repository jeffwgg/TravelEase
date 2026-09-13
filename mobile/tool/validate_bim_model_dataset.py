#!/usr/bin/env python3
"""Score the exported BIM TFLite model on the official BIM-SIGN Pose test split.

The dataset (Zenodo record 21631884) ships MediaPipe Holistic keypoints, not
videos — the per-clip `.npy` in keypoints_258.zip IS what the model saw of the
source video. This downloads only the members listed in metadata/splits/test.txt
(via HTTP range requests against the zip central directory — the 750 MB archive
is never fetched whole), replays dataset.py's exact preprocessing
(normalize_keypoints -> resample 64 -> standardize) and reports top-1/top-5
accuracy per gloss and overall.

The exported model is trained/validated on this convention, so a low score here
means an export bug, while a high score proves bim_model.tflite is fine and any
on-device inaccuracy comes from the app's live input pipeline.

Usage:
    python validate_bim_model_dataset.py            # all test clips (~1.6k)
    python validate_bim_model_dataset.py --limit 200 --cache-dir C:/bim_cache
"""
import argparse
import csv
import io
import json
import os
import struct
import sys
import time
import urllib.error
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path

import numpy as np

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

HERE = Path(__file__).resolve().parent
MODELS_DIR = HERE.parent / "assets" / "models"
META_DIR = Path(os.path.expanduser("~/bimsign_meta/metadata"))
ZIP_URL = "https://zenodo.org/api/records/21631884/files/keypoints_258.zip/content"
FIXED_FRAMES = 64
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/127.0"}


# ---------------------------------------------------------------------------
# dataset.py helpers (training-time conventions, verbatim ports)
# ---------------------------------------------------------------------------

def resample(seq: np.ndarray, target: int) -> np.ndarray:
    t = len(seq)
    if t == target:
        return seq
    idx = np.linspace(0, t - 1, num=target)
    out = np.empty((target, seq.shape[1]), dtype=np.float32)
    for d in range(seq.shape[1]):
        out[:, d] = np.interp(idx, np.arange(t), seq[:, d])
    return out


def normalize_keypoints(seq: np.ndarray) -> np.ndarray:
    seq = seq.astype(np.float32).copy()
    l_sh = seq[:, 11 * 4: 11 * 4 + 2]
    r_sh = seq[:, 12 * 4: 12 * 4 + 2]
    center = (l_sh + r_sh) / 2
    scale = np.maximum(np.linalg.norm(l_sh - r_sh, axis=1, keepdims=True), 1e-6)
    seq[:, :2] -= center
    seq[:, :2] /= scale
    return seq


# ---------------------------------------------------------------------------
# selective zip fetch over HTTP ranges
# ---------------------------------------------------------------------------

def http_range(url: str, start: int, end: int) -> bytes:
    """Range GET with zenodo-friendly backoff (429/5xx retried, others raise)."""
    import time
    delay = 1.0
    for attempt in range(6):
        req = urllib.request.Request(url, headers={**UA, "Range": f"bytes={start}-{end}"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code not in (429, 500, 502, 503, 504) or attempt == 5:
                raise
            time.sleep(delay + attempt)
            delay *= 2
    raise RuntimeError("unreachable")


def build_index(url: str) -> dict:
    """Parse the zip central directory: name -> (local_off, comp_size, uncomp_size, method)."""
    req = urllib.request.Request(url, headers={**UA, "Range": "bytes=0-1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        total = int(r.headers["Content-Range"].split("/")[-1])
    tail = http_range(url, max(0, total - 65557), total - 1)
    eocd = tail.rfind(b"PK\x05\x06")
    sig, disk, cd_disk, n_this, n_total, cd_size, cd_off, cmt_len = struct.unpack(
        "<4sHHHHIIH", tail[eocd:eocd + 22])
    cd = http_range(url, cd_off, cd_off + cd_size - 1)
    index, p = {}, 0
    while p < len(cd) and cd[p:p + 4] == b"PK\x01\x02":
        (ver_made, ver_need, flags, comp_m, dos_t, dos_d, crc,
         comp_sz, uncomp_sz, name_len, extra_len, comment_len, disk_start,
         int_attr, ext_attr, local_off) = struct.unpack(
            "<HHHHHHIIIHHHHHII", cd[p + 4:p + 46])
        name = cd[p + 46: p + 46 + name_len].decode("utf-8")
        index[name] = (local_off, comp_sz, uncomp_sz, comp_m)
        p += 46 + name_len + extra_len + comment_len
    return index


def fetch_member(url: str, index: dict, name: str) -> np.ndarray:
    local_off, comp_sz, uncomp_sz, method = index[name]
    hdr = http_range(url, local_off, local_off + 29)
    n_len, e_len = struct.unpack("<HH", hdr[26:30])
    data_start = local_off + 30 + n_len + e_len
    blob = http_range(url, data_start, data_start + comp_sz - 1)
    if method == 8:  # deflate
        import zlib
        blob = zlib.decompress(blob, -15)
    return np.load(io.BytesIO(blob))


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="only first N clips (smoke test)")
    ap.add_argument("--cache-dir", default=os.path.expanduser("~/bimsign_test_clips"))
    args = ap.parse_args()

    stats = json.loads((MODELS_DIR / "bim_norm_stats.json").read_text())
    mean = np.asarray(stats["mean"], np.float32)
    std = np.asarray(stats["std"], np.float32)
    gloss_by_idx = {v: k for k, v in json.loads(
        (MODELS_DIR / "bim_sign_to_prediction_index_map.json").read_text()).items()}

    cache = Path(args.cache_dir)
    cache.mkdir(parents=True, exist_ok=True)

    # test.txt: canonical_id \t gloss \t gloss_id
    rows = [line.strip().split("\t") for line in (META_DIR / "splits/test.txt").read_text(encoding="utf-8").splitlines() if line.strip()]
    if args.limit:
        rows = rows[: args.limit]
    print(f"test split clips: {len(rows)}")

    # Map canonical ids to zip member names from the central directory.
    index = build_index(ZIP_URL)
    base = {os.path.splitext(os.path.basename(n))[0]: n for n in index if n.endswith(".npy")}

    from ai_edge_litert.interpreter import Interpreter
    interp = Interpreter(model_path=str(MODELS_DIR / "bim_model.tflite"), num_threads=4)
    interp.allocate_tensors()
    in_idx = interp.get_input_details()[0]["index"]
    out_idx = interp.get_output_details()[0]["index"]

    hits = total = 0
    per_class = defaultdict(lambda: [0, 0])
    misses = []
    for n, (cid, gloss, gid) in enumerate(rows):
        member = base.get(cid)
        if member is None:
            continue
        f = cache / f"{cid}.npy"
        try:
            if f.exists():
                seq = np.load(f)
            else:
                seq = fetch_member(ZIP_URL, index, member)
                np.save(f, seq)
                time.sleep(0.08)  # be polite to zenodo between range fetches
        except Exception as exc:
            print(f"  ! fetch failed {cid}: {exc}")
            continue
        x = ((resample(normalize_keypoints(seq), FIXED_FRAMES) - mean) / std).astype(np.float32)
        interp.reset_all_variables()
        interp.set_tensor(in_idx, x[None])
        interp.invoke()
        logits = interp.get_tensor(out_idx)[0].astype(np.float64)
        e = np.exp(logits - logits.max())
        probs = e / e.sum()
        pred = gloss_by_idx[int(probs.argmax())]
        top5 = probs.argsort()[::-1][:5]
        total += 1
        ok = pred == gloss
        per_class[gloss][1] += 1
        if ok:
            hits += 1
            per_class[gloss][0] += 1
        elif float(probs[top5[0]]) >= 0.5:  # confident-and-wrong: the interesting failures
            misses.append(f"{cid}: {pred} {probs[top5[0]]:.2f}")
        if (n + 1) % 200 == 0:
            print(f"  {n + 1}/{len(rows)} ... running top-1 {hits}/{total} ({hits / total:.1%})")

    print(f"\nOFFICIAL TEST SPLIT top-1: {hits}/{total} = {hits / total:.1%}")
    if misses:
        print(f"\nconfident errors ({len(misses)}):")
        for m in misses[:25]:
            print("  " + m)
    worst = sorted(per_class.items(), key=lambda kv: kv[1][0] / max(kv[1][1], 1))[:12]
    print("\nworst glosses:")
    for g, (h, t) in worst:
        print(f"  {g:20s} {h}/{t}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
