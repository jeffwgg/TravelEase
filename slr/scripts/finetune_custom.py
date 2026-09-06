"""Fine-tune the BIM sign model with a small set of user-recorded clips.

Real-webcam generalization is the model's weak spot; 10-30 labeled clips per
word from the actual user beats any amount of synthetic augmentation.

Prereq (run once after recording):
    python record_custom.py --word tandas --signer alice   (repeat per word)
    python extract_custom.py                               (keypoints + manifest)

Usage:
    python finetune_custom.py --base ../data/best_model.pt \
        --out ../data/best_model_ft.pt --epochs 30 --lr 3e-4

Custom glosses not in the 117-word vocab are added as new classes.
"""

import argparse
import csv
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from dataset import BIMSignDataset, FIXED_FRAMES, normalize_keypoints, resample  # noqa: E402

import torch  # noqa: E402
import torch.nn as nn  # noqa: E402
from torch.utils.data import DataLoader, TensorDataset  # noqa: E402

from train_lstm import SignLSTM, augment, evaluate  # noqa: E402

CUSTOM_ROOT = os.path.join(os.path.dirname(__file__), "..", "data_custom")


def load_custom(min_per_word: int):
    """Return (X, y, gloss_names) for custom clips; classes = dataset vocab
    (for shared words) + new words appended."""
    base = BIMSignDataset(os.path.join(os.path.dirname(__file__), "..", "data"),
                          split="train")
    gloss2id = dict(base.vocab)  # gloss_id -> malay is vocab; need name->id
    name2id = {v: k for k, v in gloss2id.items()}
    names = [gloss2id[i] for i in sorted(gloss2id)]

    manifest = os.path.join(CUSTOM_ROOT, "custom_manifest.csv")
    if not os.path.exists(manifest):
        raise SystemExit("custom_manifest.csv not found — run extract_custom.py first")

    rows = list(csv.DictReader(open(manifest, encoding="utf-8")))
    counts = {}
    for r in rows:
        counts[r["gloss"]] = counts.get(r["gloss"], 0) + 1
    too_few = {w: c for w, c in counts.items() if c < min_per_word}
    if too_few:
        raise SystemExit(f"need >= {min_per_word} clips per word; add more: {too_few}")

    xs, ys = [], []
    for r in rows:
        arr = np.load(os.path.join(CUSTOM_ROOT, r["path"])).astype(np.float32)
        if arr.shape[1] != 258:
            continue
        # raw MediaPipe coords -> same shoulder-center/scale space as the dataset
        arr = resample(normalize_keypoints(arr), FIXED_FRAMES)
        xs.append(arr)
        if r["gloss"] in name2id:
            ys.append(name2id[r["gloss"]])
        else:
            nid = len(names)
            name2id[r["gloss"]] = nid
            names.append(r["gloss"])
            ys.append(nid)
    print(f"custom clips: {len(xs)} across {counts}")
    return np.stack(xs).astype(np.float32), np.array(ys, dtype=np.int64), names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=os.path.join(
        os.path.dirname(__file__), "..", "data", "best_model.pt"))
    ap.add_argument("--out", default=os.path.join(
        os.path.dirname(__file__), "..", "data", "best_model_ft.pt"))
    ap.add_argument("--epochs", type=int, default=30)
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--min-per-word", type=int, default=8)
    ap.add_argument("--holdout", type=float, default=0.25,
                    help="fraction of custom clips held out for validation")
    args = ap.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    x, y, names = load_custom(args.min_per_word)
    num_classes = len(names)
    print(f"classes total: {num_classes}")

    # stratified split by word
    rng = np.random.RandomState(0)
    tr, va = [], []
    for c in np.unique(y):
        idx = np.where(y == c)[0]
        rng.shuffle(idx)
        k = max(1, int(len(idx) * args.holdout))
        va.extend(idx[:k])
        tr.extend(idx[k:])
    tr, va = np.array(tr), np.array(va)
    print(f"train {len(tr)}, val {len(va)}")

    model = SignLSTM(258, num_classes)
    state = torch.load(args.base, map_location="cpu", weights_only=True)
    old_n = state["head.2.weight"].shape[0]
    if old_n != num_classes:
        # grow the head: keep all pretrained class rows, init only the new ones
        n_new = num_classes - old_n
        state["head.2.weight"] = torch.cat(
            [state["head.2.weight"],
             torch.randn(n_new, state["head.2.weight"].shape[1]) * 0.02])
        state["head.2.bias"] = torch.cat(
            [state["head.2.bias"], torch.zeros(n_new)])
        model.load_state_dict(state)
        print(f"grew head {old_n} -> {num_classes} classes (pretrained rows kept)")
    else:
        model.load_state_dict(state)
    model.to(device).train()

    # standardize custom clips with the dataset stats used in training
    stats = np.load(os.path.join(os.path.dirname(__file__), "..", "data",
                                 "norm_stats.npz"))
    mu, sd = stats["mean"], stats["std"]
    xtr = torch.from_numpy((x[tr] - mu) / sd)
    ytr = torch.from_numpy(y[tr])
    xva = torch.from_numpy((x[va] - mu) / sd)
    yva = torch.from_numpy(y[va])

    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    lossf = nn.CrossEntropyLoss(label_smoothing=0.05)
    loader = DataLoader(TensorDataset(xtr, ytr), batch_size=16, shuffle=True)

    best_acc, best_state = 0.0, None
    for epoch in range(args.epochs):
        model.train()
        for xb, yb in loader:
            xb, yb = xb.to(device), yb.to(device)
            loss = lossf(model(augment(xb)), yb)
            opt.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
        model.eval()
        with torch.no_grad():
            va_pred = model(xva.to(device)).argmax(1).cpu().numpy()
        acc = float((va_pred == yva.numpy()).mean())
        marker = ""
        if acc >= best_acc:
            best_acc, best_state = acc, {k: v.clone() for k, v in
                                         model.state_dict().items()}
            marker = " *"
        print(f"epoch {epoch + 1:3d}  val_acc {acc:.3f}{marker}")

    if best_state:
        model.load_state_dict(best_state)
    torch.save(model.state_dict(), args.out)
    np.savez(os.path.join(os.path.dirname(__file__), "..", "data",
                          "finetune_vocab.npz"),
             names=np.array(names, dtype=object), allow_pickle=True)
    print(f"best val_acc {best_acc:.3f} -> {args.out}")
    print("point demo.py at this model to use it")


if __name__ == "__main__":
    main()
