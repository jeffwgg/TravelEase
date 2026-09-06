"""Train an LSTM word classifier on BIM-SIGN Pose (T, 258) keypoint sequences.

Augmentation simulates real webcam clips (leading/trailing stillness, random
signing speed, landmark jitter, shoulder wobble). Checkpoint resume supported.

Usage:  python train_lstm.py [--epochs 40] [--hidden 256] [--layers 2]
"""

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from dataset import BIMSignDataset  # noqa: E402

import torch  # noqa: E402
import torch.nn as nn  # noqa: E402
from torch.utils.data import DataLoader, TensorDataset  # noqa: E402


class SignLSTM(nn.Module):
    def __init__(self, in_dim: int, num_classes: int, hidden: int = 256,
                 layers: int = 2, dropout: float = 0.4):
        super().__init__()
        self.lstm = nn.LSTM(in_dim, hidden, num_layers=layers,
                            batch_first=True, dropout=dropout,
                            bidirectional=True)
        self.head = nn.Sequential(
            nn.LayerNorm(hidden * 2),
            nn.Dropout(dropout),
            nn.Linear(hidden * 2, num_classes),
        )

    def forward(self, x):
        out, _ = self.lstm(x)
        return self.head(out[:, -1])


def _stretch(x: torch.Tensor, target_t: int) -> torch.Tensor:
    """(B, T, D) -> (B, target_t, D) linear time-resample."""
    y = x.permute(0, 2, 1)
    y = torch.nn.functional.interpolate(y, size=target_t, mode="linear",
                                        align_corners=True)
    return y.permute(0, 2, 1)


def augment(x: torch.Tensor) -> torch.Tensor:
    """Simulate real webcam clips: random stillness at both ends, random
    signing speed, realistic landmark jitter (MediaPipe hand/pose landmarks
    wobble ~0.01 in standardized units once shoulder-center normalization
    amplifies it), affine wobble from shoulder jitter, amplitude change."""
    B, T, D = x.shape
    outs = []
    for b in range(B):
        s = x[b:b + 1]
        if torch.rand(1).item() < 0.8:
            k0 = int(torch.randint(0, 22, (1,)))
            k1 = int(torch.randint(0, 22, (1,)))
            rate = float(torch.empty(1).uniform_(0.75, 1.35))
            sign = _stretch(s, max(8, int(T * rate)))
            seq = torch.cat([s[:, :1].expand(-1, k0, -1), sign,
                             s[:, -1:].expand(-1, k1, -1)], dim=1)
            s = _stretch(seq, T)
        sigma = float(torch.empty(1).uniform_(0.002, 0.02))
        s = s + torch.randn_like(s) * sigma
        # shoulder-detection jitter: smooth random-walk scale & offset wobble
        w = torch.randn(1, T, 4).cumsum(dim=1)
        w = (w - w.mean(dim=1, keepdim=True)) / (w.std() + 1e-6)
        scale = 1 + 0.008 * w[..., 0:1]
        off = 0.01 * w[..., 1:2]
        s = s * scale + off
        s = s * float(torch.empty(1).uniform_(0.9, 1.1))
        outs.append(s)
    return torch.cat(outs, 0)


def evaluate(model, loader, device):
    model.eval()
    correct = total = 0
    with torch.no_grad():
        for xb, yb in loader:
            xb, yb = xb.to(device), yb.to(device)
            pred = model(xb).argmax(1)
            correct += (pred == yb).sum().item()
            total += len(yb)
    return correct / max(total, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--epochs", type=int, default=40)
    ap.add_argument("--hidden", type=int, default=256)
    ap.add_argument("--layers", type=int, default=2)
    ap.add_argument("--batch", type=int, default=64)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--frames", type=int, default=64)
    args = ap.parse_args()

    data_dir = os.path.join(os.path.dirname(__file__), "..", "data")
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"device: {device}")

    dss = {s: BIMSignDataset(data_dir, split=s, frame_count=args.frames)
           for s in ("train", "val", "test")}
    xtr, ytr = dss["train"].load_all()
    xva, yva = dss["val"].load_all()
    xte, yte = dss["test"].load_all()
    print(f"train {xtr.shape}, val {xva.shape}, test {xte.shape}, "
          f"classes {dss['train'].num_classes}")

    mean, std = xtr.mean(axis=(0, 1), keepdims=True), xtr.std(axis=(0, 1), keepdims=True) + 1e-6
    xtr, xva, xte = [(a - mean) / std for a in (xtr, xva, xte)]
    np.savez(os.path.join(data_dir, "norm_stats.npz"),
             mean=mean.astype(np.float32), std=std.astype(np.float32))

    torch.manual_seed(42)
    train_loader = DataLoader(
        TensorDataset(torch.from_numpy(xtr), torch.from_numpy(ytr)),
        batch_size=args.batch, shuffle=True)
    val_loader = DataLoader(
        TensorDataset(torch.from_numpy(xva), torch.from_numpy(yva)),
        batch_size=args.batch)

    model = SignLSTM(xtr.shape[2], dss["train"].num_classes,
                     args.hidden, args.layers).to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=args.epochs)
    lossf = nn.CrossEntropyLoss(label_smoothing=0.05)

    best_val, best_path = 0.0, os.path.join(data_dir, "best_model.pt")
    ckpt_path = os.path.join(data_dir, "checkpoint.pt")
    start_epoch = 0
    if os.path.exists(ckpt_path):
        ck = torch.load(ckpt_path, map_location=device, weights_only=False)
        model.load_state_dict(ck["model"])
        opt.load_state_dict(ck["opt"])
        sched.load_state_dict(ck["sched"])
        start_epoch, best_val = ck["epoch"], ck["best_val"]
        print(f"resumed from checkpoint at epoch {start_epoch}")

    for epoch in range(start_epoch, args.epochs):
        model.train()
        total_loss = 0.0
        for xb, yb in train_loader:
            xb, yb = xb.to(device), yb.to(device)
            xb = augment(xb)
            loss = lossf(model(xb), yb)
            opt.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            total_loss += loss.item() * len(yb)
        sched.step()
        val_acc = evaluate(model, val_loader, device)
        marker = ""
        if val_acc > best_val:
            best_val = val_acc
            torch.save(model.state_dict(), best_path)
            marker = " *"
        torch.save({"model": model.state_dict(), "opt": opt.state_dict(),
                    "sched": sched.state_dict(), "epoch": epoch + 1,
                    "best_val": best_val}, ckpt_path)
        print(f"epoch {epoch + 1:3d}  loss {total_loss / len(ytr):.4f}  "
              f"val_acc {val_acc:.4f}{marker}")

    model.load_state_dict(torch.load(best_path, weights_only=True))
    test_loader = DataLoader(
        TensorDataset(torch.from_numpy(xte), torch.from_numpy(yte)),
        batch_size=args.batch)
    print(f"best val_acc {best_val:.4f}  test_acc {evaluate(model, test_loader, device):.4f}")
    print(f"model saved to {best_path}")


if __name__ == "__main__":
    main()
