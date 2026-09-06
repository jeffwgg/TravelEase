"""Real-time inference: webcam -> record one sign (hold SPACE 0.8-2.5s)
-> keypoints -> LSTM (trim + mirror-orientation ensemble) -> template sentence.

Usage:  python infer.py [--model ../data/best_model.pt]
Keys:   SPACE hold = capture a sign, c = clear sentence, q = quit
"""

import argparse
import os
import sys
import time

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from dataset import (BIMSignDataset, FIXED_FRAMES, flip_keypoints,  # noqa: E402
                     normalize_keypoints, trim_idle)
from templates import glosses_to_utterance  # noqa: E402

import torch  # noqa: E402
from train_lstm import SignLSTM  # noqa: E402

try:
    import mediapipe as mp
    HAS_MEDIAPIPE = True
except ImportError:
    HAS_MEDIAPIPE = False

CONF_THRESHOLD = 0.55
CAPTURE_MIN_S, CAPTURE_MAX_S = 0.8, 2.5


def extract_keypoints_live(frame, holistic) -> np.ndarray:
    """(258,) per-frame layout matching the dataset: pose 33*4, hands 2*21*3."""
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    res = holistic.process(rgb)
    kps = np.zeros(258, dtype=np.float32)
    if res.pose_landmarks:
        for i, lm in enumerate(res.pose_landmarks.landmark):
            kps[i * 4:i * 4 + 3] = (lm.x, lm.y, lm.z)
            kps[i * 4 + 3] = lm.visibility
    for offset, lm_key in ((132, res.left_hand_landmarks),
                           (195, res.right_hand_landmarks)):
        if lm_key:
            for i, lm in enumerate(lm_key.landmark):
                kps[offset + i * 3:offset + i * 3 + 3] = (lm.x, lm.y, lm.z)
    return kps


def _normalize_like_train(seq, mean, std):
    """Shoulder-center normalization + per-feature standardization with the
    saved training stats (which carry batch dims (1, 1, D) — squeeze)."""
    return (normalize_keypoints(seq) - mean[0, 0]) / std[0, 0]


def predict_probs(seq, model, mean, std, device):
    """Trim + mirror-orientation ensemble over the raw keypoint clip."""
    best = None
    for base in (trim_idle(seq), seq):
        for cand in (base, flip_keypoints(base)):
            idx = np.linspace(0, len(cand) - 1, FIXED_FRAMES)
            resampled = np.stack(
                [np.interp(idx, np.arange(len(cand)), cand[:, d])
                 for d in range(258)], axis=1).astype(np.float32)
            resampled = _normalize_like_train(resampled, mean, std)
            with torch.no_grad():
                logits = model(torch.from_numpy(resampled[None]).to(device))
                probs = torch.softmax(logits[0], dim=0).cpu().numpy()
            if best is None or probs.max() > best.max():
                best = probs
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=os.path.join(
        os.path.dirname(__file__), "..", "data", "best_model.pt"))
    ap.add_argument("--cam", type=int, default=0)
    ap.add_argument("--topk", type=int, default=3)
    args = ap.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    data_dir = os.path.join(os.path.dirname(__file__), "..", "data")
    ds = BIMSignDataset(data_dir, split="test")
    id2gloss = {i: g for i, g in ds.vocab.items()}

    model = SignLSTM(258, ds.num_classes).to(device)
    model.load_state_dict(torch.load(args.model, map_location=device,
                                     weights_only=True))
    model.eval()
    print(f"model loaded: {ds.num_classes} classes")

    stats = np.load(os.path.join(data_dir, "norm_stats.npz"))
    mean, std = stats["mean"], stats["std"]

    holistic = mp.solutions.holistic.Holistic(
        model_complexity=1, min_detection_confidence=0.5,
        min_tracking_confidence=0.5) if HAS_MEDIAPIPE else None
    if not HAS_MEDIAPIPE:
        print("WARNING: mediapipe not installed — live keypoints unavailable. "
              "pip install mediapipe")

    cap = cv2.VideoCapture(args.cam)
    glosses_in_sentence = []
    recording, frames = False, []

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        mirror = cv2.flip(frame, 1)

        if recording:
            frames.append(extract_keypoints_live(frame, holistic))
            el = time.time() - start
            cv2.putText(mirror, f"REC {el:.1f}s", (10, 60),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 255), 2)

        sentence = " ".join(glosses_in_sentence)
        cv2.putText(mirror, sentence or "(SPACE to sign, C clear, Q quit)",
                    (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7,
                    (0, 255, 0), 2)
        cv2.imshow("BIM travel translator", mirror)
        key = cv2.waitKey(1) & 0xFF

        if key == ord(" ") and not recording and HAS_MEDIAPIPE:
            recording, frames, start = True, [], time.time()
        elif key == ord(" ") and recording:
            recording = False
            dur = time.time() - start
            if not (CAPTURE_MIN_S <= dur <= CAPTURE_MAX_S and frames):
                print(f"clip {dur:.1f}s discarded")
                frames = []
                continue
            probs = predict_probs(np.stack(frames).astype(np.float32),
                                  model, mean, std, device)
            top = probs.argsort()[::-1][:args.topk]
            word = id2gloss[int(top[0])]
            conf = float(probs[top[0]])
            if conf >= CONF_THRESHOLD:
                glosses_in_sentence.append(word)
                print(f"'{word}' {conf:.0%} | alternatives: "
                      f"{', '.join(f'{id2gloss[int(i)]} {probs[i]:.0%}' for i in top[1:])}")
                u = glosses_to_utterance(glosses_in_sentence)
                print(f"  -> [{u.malay}] [{u.chinese}]")
            else:
                print(f"low confidence ({conf:.0%}), sign again")
            frames = []
        elif key == ord("c"):
            glosses_in_sentence = []
        elif key == ord("q"):
            break
    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
