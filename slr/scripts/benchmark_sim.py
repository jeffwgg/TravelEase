"""Benchmark the trained model under simulated real-webcam conditions.

Reproduces the failure modes observed in live testing: leading/trailing
stillness, mirror flip (Gradio webcam), and landmark jitter at the scale
MediaPipe produces. Reports accuracy of the full inference path
(trim_idle + mirror-orientation selection) per condition.

Usage:  python benchmark_sim.py [--words 10] [--reps 2]
"""

import argparse
import csv
import io
import os
import sys
import zipfile

import numpy as np
import torch

sys.path.insert(0, os.path.dirname(__file__))
from dataset import FIXED_FRAMES, flip_keypoints, normalize_keypoints  # noqa: E402
from demo import MEAN, STD, model  # noqa: E402

DATA = os.path.join(os.path.dirname(__file__), "..", "data")


def load_clip(z, gloss, cid):
    return np.load(io.BytesIO(z.read(f"keypoints_258/{gloss}/{cid}.npy"))).astype(np.float32)


def predict_one(seq):
    idx = np.linspace(0, len(seq) - 1, FIXED_FRAMES)
    r = np.stack([np.interp(idx, np.arange(len(seq)), seq[:, d])
                  for d in range(258)], axis=1)
    r = (normalize_keypoints(r) - MEAN[0, 0]) / STD[0, 0]
    with torch.no_grad():
        return torch.softmax(model(torch.from_numpy(r[None])), 1)[0].numpy()


def predict_user(seq):
    """Full demo.py inference path: trim + orientation choice + view average."""
    from dataset import trim_idle
    views = {}
    for name, base in (("orig", trim_idle(seq)), ("flip", flip_keypoints(trim_idle(seq)))):
        ps = [predict_one(base), predict_one(seq)]
        views[name] = ps
    best_ori = max(views, key=lambda k: max(p.max() for p in views[k]))
    return np.mean(views[best_ori], axis=0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--words", type=int, default=10)
    ap.add_argument("--reps", type=int, default=2)
    args = ap.parse_args()

    z = zipfile.ZipFile(os.path.join(DATA, "keypoints_258.zip"))
    rows = list(csv.DictReader(open(os.path.join(
        DATA, "metadata", "gloss_vocabulary.csv"), encoding="utf-8")))
    id2g = {int(r["gloss_id"]): r["gloss_malay"] for r in rows}

    travel = ["tandas", "mana", "tolong", "berapa", "duit", "hospital",
              "air", "makan", "bas", "terima_kasih", "pergi", "jangan",
              "boleh", "kafetaria", "polis", "kesakitan", "apa_khabar",
              "selamat_pagi", "bila", "arah"][: args.words]

    # one fresh test clip per word (test split: *_0004 pattern is not
    # guaranteed; pick by split assignment)
    test_ids = {}
    with open(os.path.join(DATA, "metadata", "splits", "test.txt"),
              encoding="utf-8") as f:
        for line in f:
            p = line.strip().split("\t")
            if len(p) >= 2 and p[1] in travel and p[1] not in test_ids:
                test_ids[p[1]] = p[0]

    rng = np.random.RandomState(11)
    wins = confs = n = 0
    print(f"{'word':14s} {'pred':14s} {'conf':>5s}  condition")
    for g, cid in test_ids.items():
        clip = load_clip(z, g, cid)
        for rep in range(args.reps):
            for cond in ("normal", "mirrored"):
                idle_a = np.tile(clip[0], (20, 1)) + rng.randn(20, 258).astype(np.float32) * 0.002
                idle_b = np.tile(clip[-1], (20, 1)) + rng.randn(20, 258).astype(np.float32) * 0.002
                user = np.concatenate([idle_a, clip, idle_b])
                if cond == "mirrored":
                    user = flip_keypoints(user)
                p = predict_user(user)
                ok = id2g[int(p.argmax())] == g
                wins += ok
                confs += p.max()
                n += 1
                print(f"{g:14s} {id2g[int(p.argmax())]:14s} {p.max():4.0%}  {cond}{' OK' if ok else ' MISS'}")

    print(f"\nTOTAL: {wins}/{n} correct ({wins / n:.0%}), avg conf {confs / n:.0%}")


if __name__ == "__main__":
    main()
