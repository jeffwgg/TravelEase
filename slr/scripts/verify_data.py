"""Verify keypoints_258.zip contents after download: layout, dims, channels.

Run before training:  python verify_data.py
"""

import io
import os
import sys
import zipfile

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from dataset import BIMSignDataset  # noqa: E402

data_dir = os.path.join(os.path.dirname(__file__), "..", "data")
z = zipfile.ZipFile(os.path.join(data_dir, "keypoints_258.zip"))
names = [n for n in z.namelist() if n.endswith(".npy")]
print(f"members: {len(names)} npy files")
print("first 5:", names[:5])

sampled = 0
for n in names[:: max(1, len(names) // 10)]:
    arr = np.load(io.BytesIO(z.read(n)))
    print(f"{os.path.basename(n):24s} shape={arr.shape} dtype={arr.dtype} "
          f"finite={np.isfinite(arr).all()}")
    if sampled == 0:
        assert arr.ndim == 2, "expect (T, D)"
    sampled += 1

ds = BIMSignDataset(data_dir, split="val")
cid = ds.ids[0]
seq = ds.load_sequence(cid)
print(f"\nloader check: {cid} -> resampled {seq.shape}, "
      f"gloss '{ds.glosses[0]}' (id {ds.gloss_ids[0]})")
print(f"x range after normalize: [{seq[:, :2].min():.2f}, {seq[:, :2].max():.2f}]")

raw = np.load(io.BytesIO(z.read(ds._find_member(cid))))
vis = raw[:, 3::4][:, :33]
frac_binary = float(((vis < 0.05) | (vis > 0.95)).mean())
print(f"pose-visibility fraction ~binary: {frac_binary:.2f} "
      f"({'layout OK' if frac_binary > 0.5 else 'CHECK LAYOUT — channels may differ'})")
