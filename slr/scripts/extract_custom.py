"""Extract (T, 258) MediaPipe Holistic keypoints from supplementary recorded
clips (data_custom/{word}/{signer}/*.mp4) so they match BIM-SIGN Pose format,
and emit a merge manifest for training.

Usage:  python extract_custom.py
Output: data_custom/custom_keypoints/{word}/{signer}/{nnn}.npy
        data_custom/custom_manifest.csv
"""

import csv
import os
import sys

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from infer import extract_keypoints_live  # noqa: E402

import mediapipe as mp  # noqa: E402

CUSTOM_ROOT = os.path.join(os.path.dirname(__file__), "..", "data_custom")


def main():
    holistic = mp.solutions.holistic.Holistic(
        model_complexity=1, min_detection_confidence=0.5,
        min_tracking_confidence=0.5)
    rows = []
    for word in sorted(os.listdir(CUSTOM_ROOT)):
        word_dir = os.path.join(CUSTOM_ROOT, word)
        if not os.path.isdir(word_dir) or word == "custom_keypoints":
            continue
        for signer in sorted(os.listdir(word_dir)):
            signer_dir = os.path.join(word_dir, signer)
            if not os.path.isdir(signer_dir):
                continue
            out_dir = os.path.join(CUSTOM_ROOT, "custom_keypoints",
                                   word, signer)
            os.makedirs(out_dir, exist_ok=True)
            for fname in sorted(os.listdir(signer_dir)):
                if not fname.endswith(".mp4"):
                    continue
                cap = cv2.VideoCapture(os.path.join(signer_dir, fname))
                seq = []
                while True:
                    ok, frame = cap.read()
                    if not ok:
                        break
                    seq.append(extract_keypoints_live(frame, holistic))
                cap.release()
                if len(seq) < 5:
                    print(f"skip {word}/{signer}/{fname}: too short")
                    continue
                arr = np.stack(seq)
                np.save(os.path.join(out_dir, fname.replace(".mp4", ".npy")),
                        arr)
                rows.append({
                    "canonical_id": f"custom_{word}_{signer}_{fname[:-4]}",
                    "gloss": word,
                    "signer": signer,
                    "frames": len(seq),
                    "path": os.path.relpath(
                        os.path.join(out_dir, fname.replace(".mp4", ".npy")),
                        CUSTOM_ROOT),
                })
                print(f"{word}/{signer}/{fname}: {len(seq)} frames")

    with open(os.path.join(CUSTOM_ROOT, "custom_manifest.csv"), "w",
              newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"\nmanifest: {len(rows)} clips")


if __name__ == "__main__":
    main()
