"""Render (T, 258) keypoint sequences as stick-figure animations (MP4/GIF).

Works on raw BIM-SIGN coordinates (normalized [0,1], x right, y down) —
i.e. npy files straight from keypoints_258.zip, NOT the neck-centered
version from dataset.normalize_keypoints.
"""

import cv2
import numpy as np

W, H = 640, 640
BG = (255, 255, 255)
POSE_COLOR = (180, 80, 0)     # blue-ish in BGR
LHAND_COLOR = (0, 150, 0)     # green
RHAND_COLOR = (0, 0, 220)     # red

POSE_PAIRS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),   # arms
    (11, 23), (12, 24), (23, 24),                        # torso
    (23, 25), (25, 27), (24, 26), (26, 28),              # legs
    (11, 0), (12, 0),                                     # neck -> nose
]
HAND_PAIRS = [
    (0, 1), (1, 2), (2, 3), (3, 4),
    (0, 5), (5, 6), (6, 7), (7, 8), (5, 9), (9, 10), (10, 11),
    (9, 13), (13, 14), (14, 15), (13, 17), (17, 18), (18, 19), (0, 17),
]
HAND_OFFSETS = {"left": 132, "right": 195}  # 21 pts * 3 starting at these


def _pt(seq_frame: np.ndarray, base: int, i: int, stride: int) -> np.ndarray:
    return seq_frame[base + i * stride: base + i * stride + 2]


def _draw_hand(img, frame, base, color):
    for a, b in HAND_PAIRS:
        pa = _pt(frame, base, a, 3) * (W, H)
        pb = _pt(frame, base, b, 3) * (W, H)
        cv2.line(img, pa.astype(int), pb.astype(int), color, 2, cv2.LINE_AA)
    for i in range(21):
        p = _pt(frame, base, i, 3) * (W, H)
        cv2.circle(img, p.astype(int), 3, color, -1, cv2.LINE_AA)


def render_frame(frame: np.ndarray) -> np.ndarray:
    img = np.full((H, W, 3), BG, dtype=np.uint8)
    for a, b in POSE_PAIRS:
        if frame[a * 4 + 3] < 0.5 or frame[b * 4 + 3] < 0.5:
            continue
        pa = _pt(frame, 0, a, 4) * (W, H)
        pb = _pt(frame, 0, b, 4) * (W, H)
        cv2.line(img, pa.astype(int), pb.astype(int), POSE_COLOR, 3, cv2.LINE_AA)
    for i in range(33):
        if frame[i * 4 + 3] < 0.5:
            continue
        p = _pt(frame, 0, i, 4) * (W, H)
        r = 6 if i == 0 else 4  # nose bigger = head marker
        cv2.circle(img, p.astype(int), r, POSE_COLOR, -1, cv2.LINE_AA)
    _draw_hand(img, frame, HAND_OFFSETS["left"], LHAND_COLOR)
    _draw_hand(img, frame, HAND_OFFSETS["right"], RHAND_COLOR)
    return img


def animate(seq: np.ndarray, out_path: str, fps: int = 12) -> str:
    """Write (T, 258) sequence to .mp4 (or .gif). Returns the path."""
    if out_path.endswith(".gif"):
        frames = [cv2.cvtColor(render_frame(f), cv2.COLOR_BGR2RGB)
                  for f in seq]
        _write_gif(frames, out_path, delay_ms=int(1000 / fps))
    else:
        vw = cv2.VideoWriter(out_path, cv2.VideoWriter_fourcc(*"mp4v"),
                             fps, (W, H))
        for f in seq:
            vw.write(render_frame(f))
        vw.release()
    return out_path


def _write_gif(frames, path, delay_ms):
    try:
        import imageio
        imageio.mimsave(path, frames, duration=delay_ms / 1000, loop=0)
    except ImportError:
        import PIL.Image
        imgs = [PIL.Image.fromarray(f) for f in frames]
        imgs[0].save(path, save_all=True, append_images=imgs[1:],
                     duration=delay_ms, loop=0)


if __name__ == "__main__":
    import sys
    seq = np.load(sys.argv[1])
    out = animate(seq.astype(np.float32), "sample.gif")
    print("wrote", out, f"({len(seq)} frames)")
