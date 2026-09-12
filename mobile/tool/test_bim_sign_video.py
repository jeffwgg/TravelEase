#!/usr/bin/env python3
"""Score BIM (Bahasa Isyarat Malaysia) sign videos against the on-device TFLite model.

Twin of the app's on-device BIM pipeline
(lib/services/bim_tflite_service.dart + buildBimTensor in sign_frame_data.dart):
decodes the video, extracts MediaPipe landmarks into the 258-channel layout
(pose 33x(x,y,z,vis) + 21x3 per hand), then replays the classification
pipeline — guards, trim_idle, 2 orientations x [trimmed|full] x 3 time
scales (1.0/0.55/1.6) = 12 views, standardize with bim_norm_stats.json,
softmax per view, orientation chosen by max-confidence, probabilities averaged
over the 6 winning views.

Two modes:

  --mode app    (default) faithful to the SHIPPED APP: MediaPipe Tasks pose +
                hand extractors, presence->visibility=1.0 like ML Kit, hands
                slot by nearest-pose-wrist proximity (_assignHandSides),
                shoulder normalization of ALL 33 pose landmarks
                (_normalizeInPlace), one fresh interpreter per clip whose LSTM
                state chains across the 12 views (the app cannot reset state;
                tflite_flutter's resetVariableTensors is broken upstream).

  --mode demo   faithful to the desktop reference the model was TRAINED and
                tuned against (slr/scripts demo.py/dataset.py/infer.py, kept
                in git history): MediaPipe Holistic landmarks with real
                visibility values, anatomical hand slots, normalization that
                touches only channels 0-1, and a zeroed LSTM state before
                EVERY view. Compare the two: a gap isolates exactly how far
                the app's port drifted from the training-time input convention.

Usage:
    python test_bim_sign_video.py                      # app mode, all clips
    python test_bim_sign_video.py --mode demo          # training-parity mode
    python test_bim_sign_video.py --mode demo pintu.mp4 ...

Expected gloss = file stem (terima_kasih.mp4 -> "terima_kasih"); clips whose
gloss is outside the model's 117 classes are scored but not judged.

Requires: pip install ai-edge-litert mediapipe opencv-python-headless numpy
MediaPipe task models are downloaded once to the system temp directory.
"""
import contextlib
import glob
import json
import math
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

TOOLS_DIR = Path(__file__).resolve().parent
MODELS_DIR = TOOLS_DIR.parent / "assets" / "models"
BIM_MODEL = MODELS_DIR / "bim_model.tflite"
BIM_LABELS = MODELS_DIR / "bim_sign_to_prediction_index_map.json"
BIM_STATS = MODELS_DIR / "bim_norm_stats.json"
BIM_VIDEOS_DIR = TOOLS_DIR.parent / "assets" / "signs" / "bim"

MP_MODELS = {
    "pose_landmarker_full.task": "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task",
    "hand_landmarker.task": "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task",
}

# BimTfliteService constants — keep in lockstep with the Dart.
FIXED_FRAMES = 64
POSE_VIS_FLOOR = 0.15
HAND_MOTION_FLOOR = 0.01
TIME_SCALES = (1.0, 0.55, 1.6)
MAX_FRAMES_APP = 64  # app windows are live camera frames; cap clips toward that cadence

K_POS_LEFT_WRIST, K_POS_RIGHT_WRIST = 15, 16


@contextlib.contextmanager
def muted_native_stderr():
    """Silence C++-level log spam (MediaPipe/TFLite write straight to fd 2)."""
    saved = os.dup(2)
    with open(os.devnull, "w") as devnull:
        os.dup2(devnull.fileno(), 2)
        try:
            yield
        finally:
            os.dup2(saved, 2)
            os.close(saved)


def ensure_mediapipe_models(cache_dir: Path) -> Path:
    cache_dir.mkdir(parents=True, exist_ok=True)
    for name, url in MP_MODELS.items():
        target = cache_dir / name
        if not target.exists():
            print(f"downloading {name} ...")
            urllib.request.urlretrieve(url, target)
    return cache_dir


def read_frames(video_path: str):
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(frame)
    cap.release()
    return frames, fps


# ---------------------------------------------------------------------------
# landmark extraction: app mode (Tasks API + proximity slotting) and
# demo mode (Holistic, identical to the desktop training/inference extractor)
# ---------------------------------------------------------------------------

def _dist2d(a, b) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def _wrist_anchor_dist(hand_pts, lw, rw) -> float:
    """_wristAnchorDist: sentinel 9.0 for a missing pose wrist, 0.0 for both."""
    if lw is None and rw is None:
        return 0.0
    w0 = hand_pts[0]
    dl = 9.0 if lw is None else _dist2d(w0, lw)
    dr = 9.0 if rw is None else _dist2d(w0, rw)
    return min(dl, dr)


def _is_left_wrist(w, lw, rw) -> bool:
    """_assignHandSides.isLeft: nearest pose wrist, else screen side x > 0.5."""
    if lw is not None and rw is not None:
        return _dist2d(w, lw) <= _dist2d(w, rw)
    return w[0] > 0.5


def build_bim_frame(pose33, hands) -> np.ndarray:
    """App-mode (258,) frame: buildBimTensor + _assignHandSides port.

    pose33: 33 (x, y, z, present) tuples — ML Kit reports landmarks as
    present/absent, and the Dart writes vis=1.0 for each present one;
    hands: up to two (21, 3) arrays in extractor order.
    """
    t = np.zeros(258, np.float32)
    for i, (x, y, z, present) in enumerate(pose33[:33]):
        if present:
            t[i * 4: i * 4 + 4] = (x, y, z, 1.0)

    lw = (t[15 * 4], t[15 * 4 + 1]) if pose33[K_POS_LEFT_WRIST][3] else None
    rw = (t[16 * 4], t[16 * 4 + 1]) if pose33[K_POS_RIGHT_WRIST][3] else None

    if hands:
        hand_pts = list(hands)
        if len(hand_pts) == 2:  # primary = nearer a pose wrist (extractor order)
            if _wrist_anchor_dist(hand_pts[1], lw, rw) < _wrist_anchor_dist(hand_pts[0], lw, rw):
                hand_pts = [hand_pts[1], hand_pts[0]]
        primary_left = _is_left_wrist(hand_pts[0][0], lw, rw)
        slots = [132 if primary_left else 195]
        if len(hand_pts) == 2:
            secondary_left = _is_left_wrist(hand_pts[1][0], lw, rw)
            if secondary_left == primary_left:
                secondary_left = not primary_left
            slots.append(132 if secondary_left else 195)
        for pts, base in zip(hand_pts, slots):  # secondary written last, as in Dart
            t[base: base + 63] = pts[:21, :3].reshape(-1)
    return t


def extract_sequence_app(video_path: str, models_dir: Path) -> np.ndarray | None:
    """MediaPipe Tasks pose + hand, slots by wrist proximity — the app twin."""
    import mediapipe as mp
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision

    pose_l = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(models_dir / "pose_landmarker_full.task")),
        running_mode=vision.RunningMode.VIDEO))
    hand_l = vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(models_dir / "hand_landmarker.task")),
        running_mode=vision.RunningMode.VIDEO, num_hands=2))

    frames, fps = read_frames(video_path)
    if not frames:
        return None
    if len(frames) > MAX_FRAMES_APP:
        idx = np.linspace(0, len(frames) - 1, MAX_FRAMES_APP).round().astype(int)
        frames = [frames[i] for i in idx]

    out = np.zeros((len(frames), 258), np.float32)
    for i, frame in enumerate(frames):
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        ts = i * 1000 // int(fps) + i  # strictly increasing ms
        p = pose_l.detect_for_video(img, ts).pose_landmarks
        pose33 = [(lm.x, lm.y, lm.z, lm.visibility > 0.5) for lm in p[0][:33]] if p else []
        pose33 += [(0.0, 0.0, 0.0, False)] * (33 - len(pose33))
        h = hand_l.detect_for_video(img, ts).hand_landmarks
        hands = [np.array([(lm.x, lm.y, lm.z) for lm in lms[:21]], np.float32) for lms in h]
        out[i] = build_bim_frame(pose33, hands)
    return out


def extract_sequence_demo(video_path: str) -> np.ndarray | None:
    """MediaPipe Holistic with real visibility — infer.py extract_keypoints_live."""
    import mediapipe as mp

    holistic = mp.solutions.holistic.Holistic(
        model_complexity=1, min_detection_confidence=0.5,
        min_tracking_confidence=0.5)
    frames, _ = read_frames(video_path)
    if not frames:
        holistic.close()
        return None

    out = np.zeros((len(frames), 258), np.float32)
    try:
        for i, frame in enumerate(frames):
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            res = holistic.process(rgb)
            kps = out[i]
            if res.pose_landmarks:
                for j, lm in enumerate(res.pose_landmarks.landmark[:33]):
                    kps[j * 4: j * 4 + 3] = (lm.x, lm.y, lm.z)
                    kps[j * 4 + 3] = lm.visibility
            for offset, lms in ((132, res.left_hand_landmarks),
                                (195, res.right_hand_landmarks)):
                if lms:
                    for j, lm in enumerate(lms.landmark[:21]):
                        kps[offset + j * 3: offset + j * 3 + 3] = (lm.x, lm.y, lm.z)
    finally:
        holistic.close()
    return out


# ---------------------------------------------------------------------------
# the BimTfliteService pipeline, ported function-for-function
# ---------------------------------------------------------------------------

def std_of_blocks(seq: np.ndarray, start: int) -> float:
    """_stdOfBlocks: population std of the block's x channels pooled over frames."""
    return float(np.std(seq[:, start: start + 63: 3]))


def trim_idle(seq: np.ndarray) -> np.ndarray:
    """_trimIdle: cumulative-motion cut, low=0.05 high=0.95 pad=5, min 10."""
    if len(seq) < 12:
        return seq
    motion = np.abs(np.diff(seq, axis=0)).sum(axis=1)
    total = float(motion.sum())
    if total < 1e-6:
        return seq
    cum = np.cumsum(motion) / total
    i0 = max(0, int(np.searchsorted(cum, 0.05)) - 5)
    i1 = min(len(seq), int(np.searchsorted(cum, 0.95)) + 1 + 5)
    return seq[i0:i1] if i1 - i0 >= 10 else seq


def resample(seq: np.ndarray, target: int) -> np.ndarray:
    """_resample / dataset.resample: linear time interp to `target` frames."""
    t = len(seq)
    if t == target:
        return seq.copy()
    pos = np.arange(target) * (t - 1) / (target - 1)
    lo = np.floor(pos).astype(int)
    hi = np.ceil(pos).astype(int)
    f = (pos - lo)[:, None]
    return (seq[lo] * (1.0 - f) + seq[hi] * f).astype(np.float32)


def flip_keypoints(seq: np.ndarray) -> np.ndarray:
    """_flipKeypoints / dataset.flip_keypoints: x -> 1 - x, swap hand blocks."""
    out = seq.copy()
    out[:, 0:132:4] = 1.0 - out[:, 0:132:4]
    out[:, 132:195:3] = 1.0 - out[:, 132:195:3]
    out[:, 195:258:3] = 1.0 - out[:, 195:258:3]
    tmp = out[:, 132:195].copy()
    out[:, 132:195] = out[:, 195:258]
    out[:, 195:258] = tmp
    return out


def normalize_keypoints_app(seq: np.ndarray) -> np.ndarray:
    """Dart _normalizeInPlace: shoulder-center the x/y of ALL 33 pose landmarks."""
    out = seq.copy()
    for f in out:
        lx, ly, rx, ry = f[11 * 4], f[11 * 4 + 1], f[12 * 4], f[12 * 4 + 1]
        cx, cy = (lx + rx) / 2.0, (ly + ry) / 2.0
        scale = max(math.hypot(lx - rx, ly - ry), 1e-6)
        idx = np.arange(33) * 4
        f[idx] = (f[idx] - cx) / scale
        f[idx + 1] = (f[idx + 1] - cy) / scale
    return out


def normalize_keypoints_demo(seq: np.ndarray) -> np.ndarray:
    """dataset.py normalize_keypoints: only channels 0-1 are centered/scaled."""
    out = seq.astype(np.float32)
    l_sh = out[:, 11 * 4: 11 * 4 + 2]
    r_sh = out[:, 12 * 4: 12 * 4 + 2]
    center = (l_sh + r_sh) / 2.0
    scale = np.maximum(np.linalg.norm(l_sh - r_sh, axis=1, keepdims=True), 1e-6)
    out[:, :2] -= center
    out[:, :2] /= scale
    return out


def build_views(trimmed: np.ndarray, arr: np.ndarray, mean, std, normalize) -> list[np.ndarray]:
    """buildSeqs / demo.py view loop: 2 candidates x 3 time scales to 64 frames."""
    seqs = []
    for candidate in (trimmed, arr):
        for scale in TIME_SCALES:
            l = int(len(candidate) * scale)
            sub = candidate if l == len(candidate) else resample(candidate, max(10, l))
            seq = normalize(resample(sub, FIXED_FRAMES))
            seqs.append(((seq - mean) / std).astype(np.float32))
    return seqs


def recognize(arr: np.ndarray, model_path: Path, mean, std, mode: str):
    """_prepareViews + _aggregate for one clip; returns
    (probs, poseVis, handMotion, None) or (None, poseVis, handMotion, reason)."""
    pose_vis = float(arr[:, 3: 132: 4].mean())
    hand_motion = max(std_of_blocks(arr, 132), std_of_blocks(arr, 195))
    if len(arr) < 5:
        return None, pose_vis, hand_motion, "recording too short"
    if pose_vis < POSE_VIS_FLOOR:
        return None, pose_vis, hand_motion, "pose visibility guard"
    if hand_motion < HAND_MOTION_FLOOR:
        return None, pose_vis, hand_motion, "hand-motion guard"

    from ai_edge_litert.interpreter import Interpreter

    normalize = normalize_keypoints_app if mode == "app" else normalize_keypoints_demo
    reset = mode == "demo"  # torch SignLSTM starts from zero state every forward

    interp = Interpreter(model_path=str(model_path), num_threads=2)
    interp.allocate_tensors()  # app: fresh per clip; demo: fresh per view via reset

    def view_probs(seq):
        if reset:
            interp.reset_all_variables()
        inp = interp.get_input_details()[0]
        interp.set_tensor(inp["index"], seq[None, ...])
        interp.invoke()
        out = interp.get_tensor(interp.get_output_details()[0]["index"])[0].astype(np.float64)
        e = np.exp(out - out.max())
        return e / e.sum()

    trimmed = trim_idle(arr)
    orig = [view_probs(s) for s in build_views(trimmed, arr, mean, std, normalize)]
    flip = [view_probs(s) for s in
            build_views(flip_keypoints(trimmed), flip_keypoints(arr), mean, std, normalize)]

    views = flip if max(v.max() for v in flip) > max(v.max() for v in orig) else orig
    probs = np.mean(views, axis=0)
    return probs, pose_vis, hand_motion, None


# ---------------------------------------------------------------------------
# runner
# ---------------------------------------------------------------------------

VIDEO_EXTS = {".mp4", ".mov", ".webm", ".avi"}


def resolve_video_args(args):
    """Expand wildcards and folders ourselves so PowerShell/cmd work too."""
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
    argv = sys.argv[1:]
    mode = "app"
    if "--mode" in argv:
        i = argv.index("--mode")
        try:
            mode = argv[i + 1].lower()
        except IndexError:
            mode = ""
        if mode not in ("app", "demo"):
            print("usage: --mode app|demo")
            return 1
        argv = argv[:i] + argv[i + 2:]

    for p in (BIM_MODEL, BIM_LABELS, BIM_STATS):
        if not p.exists():
            print(f"missing asset: {p}")
            return 1

    gloss_by_idx = {v: k for k, v in json.loads(BIM_LABELS.read_text()).items()}
    stats = json.loads(BIM_STATS.read_text())
    mean = np.asarray(stats["mean"], np.float32)
    std = np.asarray(stats["std"], np.float32)
    if mean.shape != (258,) or std.shape != (258,):
        print("bim_norm_stats.json must hold 258-value arrays")
        return 1

    args = argv or [str(BIM_VIDEOS_DIR)]
    mp_dir = (ensure_mediapipe_models(Path(tempfile.gettempdir()) / "mp_tasks_models")
              if mode == "app" else None)

    print(f"mode={mode}  ({'app: mirrors BimTfliteService' if mode == 'app' else 'demo: mirrors slr demo.py training parity'})\n")
    hits = total = 0
    for arg in resolve_video_args(args):
        path = Path(arg)
        expected = path.stem.lower()  # BIM glosses keep underscores: terima_kasih
        with muted_native_stderr():
            arr = (extract_sequence_app(str(path), mp_dir) if mode == "app"
                   else extract_sequence_demo(str(path)))
            if arr is None:
                print(f"{path.name:<22} could not decode any frames")
                continue
            probs, pose_vis, hand_motion, rejected = recognize(arr, BIM_MODEL, mean, std, mode)
        if probs is None:
            print(f"{path.name:<22} REJECT  {rejected} (pose vis {pose_vis:.2f}, "
                  f"hand motion {hand_motion:.3f})")
            continue
        order = np.argsort(probs)[::-1][:5]
        top = [(gloss_by_idx.get(int(i), f"#{int(i)}"), float(probs[i])) for i in order]
        margin = probs[order[0]] - probs[order[1]] if len(order) > 1 else probs[order[0]]
        verdict = ""
        if expected in gloss_by_idx.values():
            total += 1
            if top[0][0] == expected:
                hits += 1
                verdict = "PASS"
            elif expected in [t[0] for t in top]:
                verdict = "top5"
            else:
                verdict = "MISS"
        pretty = ", ".join(f"{w} {c:.2f}" for w, c in top)
        print(f"{path.name:<22} {verdict:<5} exp={expected:<14} margin={margin:.2f}  "
              f"top5: {pretty}")

    if total:
        print(f"\ntop-1 on in-vocabulary glosses: {hits}/{total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
