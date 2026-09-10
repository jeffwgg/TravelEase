#!/usr/bin/env python3
"""Run a sign video through the app's TFLite model and print the prediction.

The mobile twin of the on-device pipeline: decodes the video, extracts
MediaPipe landmarks (face 468 + pose 33 + hands 21x2) into the same 543x3
layout `buildGislrTensor` produces, feeds the whole sequence to
assets/models/model.tflite in one call (predictSequence equivalent) and
prints the top-5 words.

Usage:
    python test_sign_video.py VIDEO [VIDEO ...]

The expected word is taken from the file name (e.g. book.mp4 -> "book");
videos whose word is outside the model's 250-sign vocabulary are still
scored, just without a PASS/FAIL verdict.

Requires: pip install ai-edge-litert mediapipe opencv-python-headless numpy
MediaPipe task models are downloaded once to the system temp directory.
"""
import contextlib
import glob
import json
import os
import sys
import tempfile
import urllib.request
from pathlib import Path

import cv2
import numpy as np

# Quiet the native MediaPipe / TFLite logging before those libraries load.
os.environ.setdefault("GLOG_minloglevel", "3")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")


@contextlib.contextmanager
def muted_native_stderr():
    """Silence C++-level log spam (MediaPipe/TFLite write straight to fd 2).

    Python tracebacks still print normally: fd 2 is restored before an
    exception escapes this block, so the interpreter prints them afterwards.
    """
    saved = os.dup(2)
    with open(os.devnull, "w") as devnull:
        os.dup2(devnull.fileno(), 2)
        try:
            yield
        finally:
            os.dup2(saved, 2)
            os.close(saved)

MODEL_PATH = Path(__file__).resolve().parent.parent / "assets" / "models" / "model.tflite"
LABEL_PATH = Path(__file__).resolve().parent.parent / "assets" / "models" / "sign_to_prediction_index_map.json"

MP_MODELS = {
    "face_landmarker.task": "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task",
    "pose_landmarker_full.task": "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task",
    "hand_landmarker.task": "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task",
}
MAX_FRAMES = 96  # long clips are evenly sub-sampled, mirroring the app's window cap


def ensure_mediapipe_models(cache_dir: Path) -> Path:
    cache_dir.mkdir(parents=True, exist_ok=True)
    for name, url in MP_MODELS.items():
        target = cache_dir / name
        if not target.exists():
            print(f"downloading {name} ...")
            urllib.request.urlretrieve(url, target)
    return cache_dir


def extract_landmarks(video_path: str, models_dir: Path) -> np.ndarray | None:
    """Decode the video into a (T, 543, 3) float array, NaN where undetected.

    Layout matches the GISLR training data: face 0-467, left hand 468-488,
    pose 489-521, right hand 522-542. Hands are assigned to anatomical slots
    by nearest pose wrist, the same strategy the Flutter extractor uses.
    """
    import mediapipe as mp
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision

    face = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(models_dir / "face_landmarker.task")),
        running_mode=vision.RunningMode.VIDEO, num_faces=1))
    pose = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(models_dir / "pose_landmarker_full.task")),
        running_mode=vision.RunningMode.VIDEO))
    hand = vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(models_dir / "hand_landmarker.task")),
        running_mode=vision.RunningMode.VIDEO, num_hands=2))

    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(frame)
    cap.release()
    if not frames:
        return None
    if len(frames) > MAX_FRAMES:
        idx = np.linspace(0, len(frames) - 1, MAX_FRAMES).round().astype(int)
        frames = [frames[i] for i in idx]

    out = np.full((len(frames), 543, 3), np.nan, dtype=np.float32)
    for i, frame in enumerate(frames):
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        ts = i * 1000 // int(fps) + i  # strictly increasing ms
        p = pose.detect_for_video(img, ts).pose_landmarks
        f = face.detect_for_video(img, ts).face_landmarks
        h = hand.detect_for_video(img, ts)
        if p:
            out[i, 489:522] = [(lm.x, lm.y, lm.z) for lm in p[0]]
        if f:
            out[i, 0:468] = [(lm.x, lm.y, lm.z) for lm in f[0][:468]]
        wrists = None
        if p:
            wrists = {15: (p[0][15].x, p[0][15].y), 16: (p[0][16].x, p[0][16].y)}
        for lms, handed in zip(h.hand_landmarks, h.handedness):
            pts = np.array([(lm.x, lm.y, lm.z) for lm in lms], np.float32)
            if wrists:
                left = wrists[15][0] if wrists[15] else 2.0
                right = wrists[16][0] if wrists[16] else -1.0
                slot = 468 if abs(pts[:, 0].mean() - left) <= abs(pts[:, 0].mean() - right) else 522
            else:
                slot = 468 if handed[0].category_name == "Left" else 522
            out[i, slot:slot + 21] = pts
    return out


def predict_sequence(interp, seq: np.ndarray) -> np.ndarray:
    """One call per window, like AslTfliteService.predictSequence."""
    interp.resize_tensor_input(0, (seq.shape[0], 543, 3))
    interp.allocate_tensors()
    interp.set_tensor(0, np.ascontiguousarray(seq, dtype=np.float32))
    interp.invoke()
    return interp.get_tensor(interp.get_output_details()[0]["index"]).copy()


VIDEO_EXTS = {".mp4", ".mov", ".webm", ".avi"}


def resolve_video_args(args):
    """Expand wildcards and folders ourselves so PowerShell/cmd work too.

    PowerShell passes `*.mp4` through literally (no shell expansion), so the
    script does its own globbing; a directory argument picks up every video
    inside it.
    """
    files = []
    for arg in args:
        matches = [m for m in sorted(glob.glob(arg)) if Path(m).suffix.lower() in VIDEO_EXTS]
        if matches:
            files.extend(matches)
        elif Path(arg).is_dir():
            files.extend(str(p) for p in sorted(Path(arg).iterdir())
                         if p.suffix.lower() in VIDEO_EXTS)
        else:
            files.append(arg)  # not found — cv2 will report it below
    return files


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    sign2idx = json.loads(LABEL_PATH.read_text())
    idx2sign = {v: k for k, v in sign2idx.items()}
    models_dir = ensure_mediapipe_models(Path(tempfile.gettempdir()) / "mp_tasks_models")

    from ai_edge_litert.interpreter import Interpreter
    interp = Interpreter(model_path=str(MODEL_PATH), num_threads=2)

    hits = total = 0
    for arg in resolve_video_args(sys.argv[1:]):
        path = Path(arg)
        expected = path.stem.lower().split("_")[0]
        with muted_native_stderr():
            seq = extract_landmarks(str(path), models_dir)
            if seq is not None:
                logits = predict_sequence(interp, seq)
        if seq is None:
            print(f"{path.name:<22} could not decode any frames")
            continue
        order = np.argsort(logits)[::-1][:5]
        top = [(idx2sign.get(int(i), f"#{int(i)}"), float(logits[i])) for i in order]
        verdict = ""
        if expected in sign2idx:
            total += 1
            if top[0][0] == expected:
                hits += 1
                verdict = "PASS"
            elif expected in [t[0] for t in top]:
                verdict = "top5"
            else:
                verdict = "MISS"
        pretty = ", ".join(f"{w} {c:.2f}" for w, c in top)
        print(f"{path.name:<22} {verdict:<5} expected={expected:<10} top5: {pretty}")

    if total:
        print(f"\ntop-1: {hits}/{total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
