"""BIM-SIGN Pose dataset loader.

Loads MediaPipe Holistic (T, 258) keypoint sequences from keypoints_258.zip,
resampled to a fixed frame count, using the official 80/10/10 split.
"""

import csv
import io
import os
import zipfile

import numpy as np

NUM_KEYPOINTS = 258
# 258 = 33 pose points * (x, y, z, visibility) + 21 left-hand * (x, y, z)
# + 21 right-hand * (x, y, z): pose 0..131, left hand 132..194, right 195..257.

FIXED_FRAMES = 64


def resample(seq: np.ndarray, target: int = FIXED_FRAMES) -> np.ndarray:
    """Linear resample (T, D) -> (target, D)."""
    t = len(seq)
    if t == target:
        return seq
    idx = np.linspace(0, t - 1, num=target)
    out = np.empty((target, seq.shape[1]), dtype=np.float32)
    for d in range(seq.shape[1]):
        out[:, d] = np.interp(idx, np.arange(t), seq[:, d])
    return out


def normalize_keypoints(seq: np.ndarray) -> np.ndarray:
    """Center at mid-shoulders, scale by shoulder width (pose landmarks 11/12)."""
    seq = seq.astype(np.float32)
    l_sh = seq[:, 11 * 4:11 * 4 + 2]
    r_sh = seq[:, 12 * 4:12 * 4 + 2]
    center = (l_sh + r_sh) / 2
    scale = np.linalg.norm(l_sh - r_sh, axis=1, keepdims=True)
    scale = np.maximum(scale, 1e-6)
    seq[:, :2] -= center  # normalize x/y only; z scale differs
    seq[:, :2] /= scale
    return seq


def trim_idle(seq: np.ndarray, low: float = 0.05, high: float = 0.95,
              pad: int = 5) -> np.ndarray:
    """Cut leading/trailing stillness using cumulative keypoint motion."""
    if len(seq) < 12:
        return seq
    motion = np.abs(np.diff(seq, axis=0)).sum(axis=1)
    total = motion.sum()
    if total < 1e-6:
        return seq
    c = np.cumsum(motion) / total
    i0 = max(0, int(np.searchsorted(c, low)) - pad)
    i1 = min(len(seq), int(np.searchsorted(c, high)) + 1 + pad)
    return seq[i0:i1] if i1 - i0 >= 10 else seq


def flip_keypoints(seq: np.ndarray) -> np.ndarray:
    """Mirror a keypoint sequence horizontally (x -> 1-x) and swap the
    left/right hand channel blocks — equivalent to flipping the video."""
    out = seq.copy()
    pose = out[:, 0:132].reshape(len(seq), 33, 4)
    pose[:, :, 0] = 1.0 - pose[:, :, 0]
    out[:, 0:132] = pose.reshape(len(seq), 132)
    for a, b in ((132, 195), (195, 258)):
        hand = out[:, a:b].reshape(len(seq), 21, 3)
        hand[:, :, 0] = 1.0 - hand[:, :, 0]
        out[:, a:b] = hand.reshape(len(seq), 63)
    out[:, 132:195], out[:, 195:258] = (out[:, 195:258].copy(),
                                        out[:, 132:195].copy())
    return out


class BIMSignDataset:
    def __init__(self, data_dir: str, split: str = "train",
                 frame_count: int = FIXED_FRAMES, normalize: bool = True):
        self.data_dir = data_dir
        self.frame_count = frame_count
        self.normalize = normalize
        self.zip_path = os.path.join(data_dir, "keypoints_258.zip")
        self._zip = None
        self._cache_name = os.path.join(data_dir, f"cache_{split}_{frame_count}.npz")

        split_file = os.path.join(data_dir, "metadata", "splits", f"{split}.txt")
        with open(split_file, encoding="utf-8") as f:
            rows = [line.strip().split("\t") for line in f if line.strip()]
        self.ids = [r[0] for r in rows]
        self.glosses = [r[1] for r in rows]
        self.gloss_ids = [int(r[2]) for r in rows]

        with open(os.path.join(data_dir, "metadata", "gloss_vocabulary.csv"),
                  encoding="utf-8") as f:
            self.vocab = {int(r["gloss_id"]): r["gloss_malay"]
                          for r in csv.DictReader(f)}
        self.num_classes = len(self.vocab)

        # The zip covers 15,266 of 15,277 manifest clips (99.9%); drop the rest.
        available = self._available_ids()
        present = [(i, cid) for i, cid in enumerate(self.ids) if cid in available]
        if len(present) < len(self.ids):
            print(f"note: {len(self.ids) - len(present)} clips listed in "
                  f"'{split}' are missing from the zip; skipping them")
            idx = [i for i, _ in present]
            self.ids = [self.ids[i] for i in idx]
            self.glosses = [self.glosses[i] for i in idx]
            self.gloss_ids = [self.gloss_ids[i] for i in idx]

    def __len__(self):
        return len(self.ids)

    def _available_ids(self) -> set:
        with zipfile.ZipFile(self.zip_path) as z:
            return {os.path.splitext(os.path.basename(n))[0]
                    for n in z.namelist() if n.endswith(".npy")}

    def _zipfile(self):
        if self._zip is None:
            self._zip = zipfile.ZipFile(self.zip_path)
        return self._zip

    def _find_member(self, canonical_id: str):
        z = self._zipfile()
        if not hasattr(self, "_member_map"):
            names = z.namelist()
            base = {os.path.splitext(os.path.basename(n))[0]: n
                    for n in names if n.endswith(".npy")}
            self._member_map = base
        return self._member_map.get(canonical_id)

    def load_sequence(self, canonical_id: str) -> np.ndarray:
        member = self._find_member(canonical_id)
        if member is None:
            raise KeyError(f"{canonical_id} not found in keypoints_258.zip")
        with self._zipfile().open(member) as f:
            seq = np.load(io.BytesIO(f.read()))
        if self.normalize:
            seq = normalize_keypoints(seq)
        return resample(seq, self.frame_count)

    def load_all(self):
        """Materialize the whole split into memory."""
        if os.path.exists(self._cache_name):
            data = np.load(self._cache_name)
            return data["x"], data["y"]
        xs, ys = [], []
        for i, cid in enumerate(self.ids):
            xs.append(self.load_sequence(cid))
            ys.append(self.gloss_ids[i])
            if (i + 1) % 500 == 0:
                print(f"loaded {i + 1}/{len(self.ids)}")
        x = np.stack(xs).astype(np.float32)
        y = np.array(ys, dtype=np.int64)
        np.savez_compressed(self._cache_name, x=x, y=y)
        return x, y


if __name__ == "__main__":
    ds = BIMSignDataset(os.path.join(os.path.dirname(__file__), "..", "data"),
                        split="train")
    print(f"train samples: {len(ds)}, classes: {ds.num_classes}")
    x, y = ds.load_all()
    print("x:", x.shape, "y:", y.shape)
