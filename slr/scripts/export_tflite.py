"""Export the BIM word classifier (best_model.pt) to a mobile TFLite file.

ai-edge-torch has no Windows converter wheels, so this uses the portable route:
transplant the torch SignLSTM weights into an equivalent tf-keras model
(Bidirectional LSTM x2 -> LayerNorm -> Dense) and convert with
tf.lite.TFLiteConverter. Keras LSTMs lower to the builtin
UnidirectionalSequenceLSTM, which tflite_flutter runs natively.

Then parity-checks the exported model against PyTorch on real clips from
keypoints_258.zip (same preprocessing as dataset.py: shoulder-normalize,
resample to 64 frames, standardize with norm_stats.npz) and fails loudly on
any top-1 mismatch.

Also emits the mobile mapping assets:
  export/bim_sign_to_prediction_index_map.json  {gloss_malay: gloss_id}
  export/bim_norm_stats.json                    {"mean": [...258], "std": [...258]}

Run from slr/ (needs the C:/venvs/slr312 venv: torch, tensorflow-cpu, tf-keras):
    C:/venvs/slr312/Scripts/python.exe scripts/export_tflite.py
"""

import csv
import io
import json
import os
import sys
import zipfile

os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

import numpy as np  # noqa: E402
import torch  # noqa: E402

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(SCRIPTS, "..")
DATA = os.path.join(ROOT, "data")
OUT = os.path.join(ROOT, "export")
sys.path.insert(0, SCRIPTS)

from dataset import FIXED_FRAMES, normalize_keypoints, resample  # noqa: E402
from train_lstm import SignLSTM  # noqa: E402

import tf_keras  # noqa: E402
import tensorflow as tf  # noqa: E402


def vocab_from_csv(path):
    with open(path, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    return {r["gloss_malay"]: int(r["gloss_id"]) for r in rows}


def build_torch_model():
    malay2id = vocab_from_csv(os.path.join(DATA, "metadata", "gloss_vocabulary.csv"))
    num_classes = len(malay2id)
    model = SignLSTM(258, num_classes)
    sd = torch.load(os.path.join(DATA, "best_model.pt"), map_location="cpu",
                    weights_only=True)
    model.load_state_dict(sd)  # strict: fails loudly on any config mismatch
    model.eval()
    print(f"torch model: {num_classes} classes, "
          f"hidden={sd['lstm.weight_hh_l0'].shape[1]}")
    return model, sd, malay2id


def _lstm_weights(sd, l):
    """Torch layer l -> (fwd, bwd) tuples of (kernel, recurrent, bias)."""
    out = []
    for suffix in ("", "_reverse"):
        w_ih = sd[f"lstm.weight_ih_l{l}{suffix}"].numpy()  # (4h, in)
        w_hh = sd[f"lstm.weight_hh_l{l}{suffix}"].numpy()  # (4h, h)
        b = sd[f"lstm.bias_ih_l{l}{suffix}"].numpy() + sd[f"lstm.bias_hh_l{l}{suffix}"].numpy()
        # torch gate order (i,f,g,o) matches Keras (i,f,c,o); kernels transposed
        out.append((w_ih.T, w_hh.T, b))
    return out


class _LayerNorm(tf_keras.layers.Layer):
    """torch.nn.LayerNorm (biased variance, eps=1e-5) in builtin ops only —
    tf-keras 2.19 has no LayerNorm layer."""

    def __init__(self, dim, eps=1e-5, **kw):
        super().__init__(**kw)
        self.dim, self.eps = dim, eps

    def build(self, _shape):
        self.gamma = self.add_weight("gamma", (self.dim,), initializer="ones")
        self.beta = self.add_weight("beta", (self.dim,), initializer="zeros")

    def call(self, x):
        mu = tf.reduce_mean(x, -1, keepdims=True)
        var = tf.math.reduce_variance(x, -1, keepdims=True)
        return (x - mu) / tf.sqrt(var + self.eps) * self.gamma + self.beta


def build_keras_model(sd, num_classes):
    # Static [1, 64, 258] so the RNN TensorList ops lower to builtin
    # UnidirectionalSequenceLSTM (dynamic batch breaks the converter, and
    # SELECT_TF_OPS is not runnable by tflite_flutter).
    inp = tf_keras.layers.Input(batch_shape=(1, FIXED_FRAMES, 258), name="keypoints")

    def lstm(units, return_sequences):
        # torch uses full sigmoid (Keras default is hard_sigmoid)
        return tf_keras.layers.LSTM(units, return_sequences=return_sequences,
                                    recurrent_activation="sigmoid")

    l0 = tf_keras.layers.Bidirectional(lstm(256, True), merge_mode="concat")
    # Layer 1 must return the full sequence: torch reads out[:, -1] which is
    # [forward_state@T-1, backward_state@T-1], but Keras
    # return_sequences=False yields [fwd@T-1, bwd@t=0]. Slice explicitly.
    l1 = tf_keras.layers.Bidirectional(lstm(256, True), merge_mode="concat")
    b0 = l0(inp)
    b1 = tf_keras.layers.Lambda(lambda t: t[:, -1, :], name="last_step")(l1(b0))
    x = _LayerNorm(512, name="ln")(b1)
    out = tf_keras.layers.Dense(num_classes)(x)
    model = tf_keras.Model(inp, out)

    for l, bidir in enumerate((l0, l1)):
        (fk, frk, fb), (bk, brk, bb) = _lstm_weights(sd, l)
        bidir.forward_layer.set_weights([fk, frk, fb])
        bidir.backward_layer.set_weights([bk, brk, bb])
        print(f"  transplanted BiLSTM layer {l}: "
              f"in={fk.shape[0]} -> {frk.shape[0]} units")

    model.get_layer("ln").set_weights([sd["head.0.weight"].numpy(),
                                       sd["head.0.bias"].numpy()])
    model.layers[-1].set_weights([sd["head.2.weight"].numpy().T,
                                  sd["head.2.bias"].numpy()])
    return model


def convert(keras_model, out_path):
    # Full fp32: LSTM recurrence accumulates quantization error over 64 steps
    # (fp16 weights caused 0.10 prob deltas / one top-1 flip in testing).
    conv = tf.lite.TFLiteConverter.from_keras_model(keras_model)
    tflite = conv.convert()
    with open(out_path, "wb") as f:
        f.write(tflite)
    print(f"exported {out_path} ({len(tflite) / 1e6:.1f} MB)")


_TF_IT = _TF_IT_PATH = None


def _tflite_interpreter(out_path):
    global _TF_IT, _TF_IT_PATH
    if _TF_IT is None or _TF_IT_PATH != out_path:
        from ai_edge_litert.interpreter import Interpreter
        _TF_IT = Interpreter(model_path=out_path)
        _TF_IT.allocate_tensors()
        _TF_IT_PATH = out_path
    return _TF_IT


def tflite_probs(out_path, x):
    """Run the exported model on (1, 64, 258) float input -> softmax probs.

    The converter emits the LSTM with persistent arena state (it leaks across
    invokes — verified empirically), so the state must be zeroed before every
    classification. Mobile mirrors this with Interpreter.resetAllVariables().
    """
    it = _tflite_interpreter(out_path)
    det_in, det_out = it.get_input_details()[0], it.get_output_details()[0]
    assert tuple(det_in["shape"]) == x.shape, \
        f"tflite input {det_in['shape']} != test input {x.shape}"
    it.reset_all_variables()
    it.set_tensor(det_in["index"], x.astype(np.float32))
    it.invoke()
    logits = it.get_tensor(det_out["index"])[0]
    e = np.exp(logits - logits.max())
    return e / e.sum()


def real_clips(n=20, seed=7):
    """Standardized test-split sequences straight from the dataset zip."""
    zip_path = os.path.join(DATA, "keypoints_258.zip")
    if not os.path.exists(zip_path):
        return None, None
    stats = np.load(os.path.join(DATA, "norm_stats.npz"))
    mean, std = stats["mean"][0, 0], stats["std"][0, 0]
    with zipfile.ZipFile(zip_path) as z:
        members = [name for name in z.namelist() if name.endswith(".npy")]
        rng = np.random.default_rng(seed)
        xs, ids = [], []
        for idx in rng.choice(len(members), size=n, replace=False):
            member = members[int(idx)]
            with z.open(member) as f:
                seq = np.load(io.BytesIO(f.read()))
            seq = resample(normalize_keypoints(seq), FIXED_FRAMES)
            xs.append((seq - mean) / std)
            ids.append(os.path.splitext(os.path.basename(member))[0])
    return np.stack(xs).astype(np.float32), ids


def parity(model, out_path, malay2id):
    ids = sorted(malay2id, key=malay2id.get)
    x, clip_ids = real_clips(n=40)
    if x is None:
        x = np.random.randn(8, FIXED_FRAMES, 258).astype(np.float32)
        clip_ids = [f"synthetic{i}" for i in range(8)]
        print("note: keypoints zip missing, parity on synthetic noise only")
    with torch.no_grad():
        t_probs = torch.softmax(model(torch.from_numpy(x)), 1).numpy()
    agreement, worst_conf, top2_order_diffs = 0, 0.0, 0
    for i in range(len(x)):
        p_tf = tflite_probs(out_path, x[i:i + 1])
        a, b = int(t_probs[i].argmax()), int(p_tf.argmax())
        agreement += a == b
        worst_conf = max(worst_conf, abs(float(t_probs[i].max()) - float(p_tf.max())))
        if list(t_probs[i].argsort()[::-1][:2]) != list(p_tf.argsort()[::-1][:2]):
            top2_order_diffs += 1
        status = "OK" if a == b else "MISMATCH"
        print(f"  {clip_ids[i][:38]:38s} torch={ids[a]:12s} "
              f"tflite={ids[b]:12s} {status}")
    n = len(x)
    print(f"parity: top-1 agreement {agreement}/{n}, "
          f"max top-1 conf delta {worst_conf:.5f}, "
          f"top-2 order differs on {top2_order_diffs} clips")
    if agreement < n or worst_conf > 0.1 or top2_order_diffs:
        raise SystemExit("PARITY CHECK FAILED — do not ship this tflite")


def write_assets(malay2id):
    with open(os.path.join(OUT, "bim_sign_to_prediction_index_map.json"),
              "w", encoding="utf-8") as f:
        json.dump(malay2id, f, ensure_ascii=False, indent=2)
    stats = np.load(os.path.join(DATA, "norm_stats.npz"))
    with open(os.path.join(OUT, "bim_norm_stats.json"), "w") as f:
        json.dump({"mean": stats["mean"][0, 0].tolist(),
                   "std": stats["std"][0, 0].tolist()}, f)
    print(f"wrote label map ({len(malay2id)} words) + norm stats -> {OUT}")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    model, sd, malay2id = build_torch_model()
    keras_model = build_keras_model(sd, len(malay2id))
    out = os.path.join(OUT, "bim_model.tflite")
    convert(keras_model, out)
    parity(model, out, malay2id)
    write_assets(malay2id)
    print("DONE — copy slr/export/* to mobile/assets/models/")
