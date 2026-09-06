"""Gradio demo: sign -> text/speech, and text -> sign animation.

Run:  python demo.py   (opens http://127.0.0.1:7860)

Tab 1: record a sign via webcam (1-3 s) -> top-3 prediction -> accumulated
       keyword set -> Malay sentence + TTS. Uses only the 117 dataset words.
Tab 2: type words (Malay or English gloss) -> stick-figure animation built
       from BIM-SIGN Pose keypoints (no video needed).
"""

import csv
import io
import os
import shutil
import subprocess
import sys
import tempfile
import wave
import zipfile

import cv2
import gradio as gr
import numpy as np
import torch

sys.path.insert(0, os.path.dirname(__file__))
from animate import animate  # noqa: E402
from dataset import (FIXED_FRAMES, flip_keypoints, normalize_keypoints,  # noqa: E402
                     trim_idle)
from infer import extract_keypoints_live  # noqa: E402
from templates import glosses_to_utterance  # noqa: E402
from train_lstm import SignLSTM  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")
DATA = os.path.join(ROOT, "data")
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"


def ensure_ffmpeg_on_path():
    """Gradio validates/converts media with system 'ffmpeg'/'ffprobe'.
    Prefer the project-bundled binaries in slr/bin, then imageio-ffmpeg's
    ffmpeg-only fallback (audio/video outputs returned as arrays/paths skip
    ffprobe checks, so the fallback stays workable)."""
    bin_dir = os.path.join(ROOT, "bin")
    if os.path.exists(os.path.join(bin_dir, "ffprobe.exe")) or \
       os.path.exists(os.path.join(bin_dir, "ffprobe")):
        os.environ["PATH"] = bin_dir + os.pathsep + os.environ["PATH"]
        return
    if shutil.which("ffmpeg") and shutil.which("ffprobe"):
        return
    try:
        import imageio_ffmpeg
    except ImportError:
        return
    shim_dir = os.path.join(tempfile.gettempdir(), "ffmpeg_shim")
    os.makedirs(shim_dir, exist_ok=True)
    dst = os.path.join(shim_dir, "ffmpeg.exe")
    if not os.path.exists(dst):
        shutil.copyfile(imageio_ffmpeg.get_ffmpeg_exe(), dst)
    os.environ["PATH"] = shim_dir + os.pathsep + os.environ["PATH"]


ensure_ffmpeg_on_path()

# ---------------------------------------------------------------- model
def load_vocab():
    with open(os.path.join(DATA, "metadata", "gloss_vocabulary.csv"),
              encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    malay2id = {r["gloss_malay"]: int(r["gloss_id"]) for r in rows}
    eng2malay = {}
    for r in rows:
        for e in r["english_gloss"].split("/"):
            eng2malay[e.strip().lower()] = r["gloss_malay"]
    return rows, malay2id, eng2malay


ROWS, MALAY2ID, ENG2MALAY = load_vocab()
ID2GLOSS = {v: k for k, v in MALAY2ID.items()}
NUM_CLASSES = len(ROWS)

# prefer a user-finetuned model when present (finetune_custom.py output)
_ft = os.path.join(DATA, "best_model_ft.pt")
_ft_vocab = os.path.join(DATA, "finetune_vocab.npz")
model = SignLSTM(258, NUM_CLASSES)
if os.path.exists(_ft) and os.path.exists(_ft_vocab):
    names = np.load(_ft_vocab, allow_pickle=True)["names"]
    ID2GLOSS = {i: n for i, n in enumerate(names.tolist())}
    NUM_CLASSES = len(ID2GLOSS)
    model = SignLSTM(258, NUM_CLASSES)
    model.load_state_dict(torch.load(_ft, map_location=DEVICE,
                                     weights_only=True))
    print(f"loaded finetuned model: {NUM_CLASSES} classes")
else:
    model.load_state_dict(torch.load(os.path.join(DATA, "best_model.pt"),
                                     map_location=DEVICE, weights_only=True))
model.eval()
_stats = np.load(os.path.join(DATA, "norm_stats.npz"))
MEAN, STD = _stats["mean"], _stats["std"]

_holistic = None


def get_holistic():
    global _holistic
    if _holistic is None:
        import mediapipe as mp
        _holistic = mp.solutions.holistic.Holistic(
            model_complexity=1, min_detection_confidence=0.5,
            min_tracking_confidence=0.5)
    return _holistic


# ------------------------------------------------------- sign -> text
def predict_sign(video_path: str):
    if not video_path:
        return "（沒有錄到影片）", None
    cap = cv2.VideoCapture(video_path)
    seq = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        seq.append(extract_keypoints_live(frame, get_holistic()))
    cap.release()
    if len(seq) < 5:
        return "（影片太短，請錄 1–3 秒）", None

    arr = np.stack(seq).astype(np.float32)
    # detection-quality guard: garbage input must not become a confident guess
    pose_vis = arr[:, 3::4][:, :33].mean()
    hand_motion = max(arr[:, 132:195:3].std(), arr[:, 195:258:3].std())
    if pose_vis < 0.15:
        return "⚠️ 看不清楚你——請靠近一點、光線充足、臉和手都在畫面內再試。", None
    if hand_motion < 0.01:
        return "⚠️ 沒看到手部動作——手要抬到鏡頭看得見的高度再比一次。", None

    trimmed = trim_idle(arr)
    views = {}  # orientation -> list of prob vectors
    for ori_name, base in (("orig", trimmed), ("flip", flip_keypoints(trimmed))):
        ps = []
        for candidate in (base, arr):  # trimmed + full clip of this orientation
            idx = np.linspace(0, len(candidate) - 1, FIXED_FRAMES)
            resampled = np.stack(
                [np.interp(idx, np.arange(len(candidate)), candidate[:, d])
                 for d in range(258)], axis=1)
            # MEAN/STD are saved with batch dims (1, 1, 258); squeeze for one clip
            resampled = (normalize_keypoints(resampled) - MEAN[0, 0]) / STD[0, 0]
            with torch.no_grad():
                ps.append(torch.softmax(
                    model(torch.from_numpy(resampled[None])), 1)[0].numpy())
        views[ori_name] = ps
    # pick the more confident orientation, then average its two views
    best_ori = max(views, key=lambda k: max(p.max() for p in views[k]))
    probs = np.mean(views[best_ori], axis=0)

    top3 = probs.argsort()[::-1][:3]
    md = " | ".join(f"**{ID2GLOSS[int(i)]}** {probs[i]:.0%}" for i in top3)
    best = ID2GLOSS[int(top3[0])]
    quality = f"\n\n（偵測品質：人物 {pose_vis:.0%}、手部動作 {hand_motion:.2f}——偏低會影響辨識）"
    return md + quality, best


def tts_audio(malay_text: str):
    """(sample_rate, int16 array) for gr.Audio. Returning an array (not a
    file path) skips gradio's ffprobe validation, which has no ffprobe on
    machines relying on the imageio-ffmpeg shim."""
    try:
        from gtts import gTTS
        mp3 = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
        gTTS(malay_text, lang="id").save(mp3.name)  # no Malay voice; id closest
        wav = mp3.name[:-4] + ".wav"
        subprocess.run([shutil.which("ffmpeg"), "-y", "-i", mp3.name, wav],
                       capture_output=True, check=True)
        with wave.open(wav, "rb") as w:
            sr = w.getframerate()
            n_channels = w.getnchannels()
            pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
        if n_channels > 1:
            pcm = pcm.reshape(-1, n_channels).mean(axis=1).astype(np.int16)
        return (sr, pcm)
    except Exception as e:  # offline, ffmpeg missing, etc. — speech is optional
        print(f"TTS skipped: {e}")
        return None


def on_sign_recorded(video, state):
    md, best = predict_sign(video)
    sentence_md = "（按上方錄影按鈕比一個詞）"
    audio = None
    if best:
        state = (state or []) + [best]
        u = glosses_to_utterance(state)
        sentence_md = (f"**辨識詞序：** {' + '.join(state)}  \n"
                       f"### 🗣 {u.malay}\n{u.chinese}"
                       + ("" if u.matched else "\n（未匹配句型，僅朗讀詞彙）"))
        audio = tts_audio(u.malay)
    return md, sentence_md, audio, state


# ------------------------------------------------------- text -> sign
_zip = zipfile.ZipFile(os.path.join(DATA, "keypoints_258.zip"))


def load_raw_clip(gloss: str, canonical_id: str) -> np.ndarray:
    with _zip.open(f"keypoints_258/{gloss}/{canonical_id}.npy") as f:
        return np.load(io.BytesIO(f.read())).astype(np.float32)


def pick_clip(gloss: str):
    """Median-length train clip for a gloss (stable, no randomness)."""
    path = os.path.join(DATA, "metadata", "splits", "train.txt")
    cands = [p[0] for p in (line.strip().split("\t") for line in open(path, encoding="utf-8"))
             if len(p) >= 2 and p[1] == gloss]
    if not cands:
        return None
    lens = [len(load_raw_clip(gloss, c)) for c in cands]
    return load_raw_clip(gloss, cands[int(np.argsort(lens)[len(lens) // 2])])


def text_to_sign(text: str):
    tokens = [t.strip(".,?!").lower() for t in text.split() if t.strip()]
    glosses, missing = [], []
    for t in tokens:
        g = t if t in MALAY2ID else ENG2MALAY.get(t)
        if g is None:
            missing.append(t)
        elif not g.endswith("_2"):
            glosses.append(g)
    if not glosses:
        return None, "找不到可用的詞彙。試試: " + ", ".join(
            sorted(set(ENG2MALAY.values()))[:12]) + " ..."
    combined = []
    for g in glosses:
        clip = pick_clip(g)
        if clip is None:
            missing.append(g)
            continue
        combined.append(clip)
    if not combined:
        return None, "詞彙數據缺失: " + ", ".join(missing)
    seq = np.concatenate(combined)
    out = os.path.join(tempfile.gettempdir(), "sign_anim.mp4")
    animate(seq, out)
    note = " | ".join(glosses) + (f"   ⚠️ 略過: {', '.join(missing)}" if missing else "")
    return out, note


# ---------------------------------------------------------------- UI
with gr.Blocks(title="BIM 旅遊手語翻譯") as demo:
    gr.Markdown("# 🤟 BIM 旅遊手語翻譯原型\n"
                "詞彙級辨識 + 模板組句。模型: BIM-SIGN Pose (117 詞) + 真實錄影增強訓練。")
    state = gr.State([])

    with gr.Tab("手語 → 文字/語音"):
        with gr.Row():
            with gr.Column():
                cam = gr.Video(sources=["webcam"], label="錄 1–3 秒，一次比一個詞")
                btn = gr.Button("辨識這段手語", variant="primary")
                clear = gr.Button("清空句子")
            with gr.Column():
                top3_md = gr.Markdown("辨識結果會顯示在這裡")
                sentence_md = gr.Markdown("（按上方錄影按鈕比一個詞）")
                audio_out = gr.Audio(label="語音朗讀", autoplay=True)
        btn.click(on_sign_recorded, [cam, state],
                  [top3_md, sentence_md, audio_out, state])
        clear.click(lambda: ([], "（已清空）", None, None),
                    outputs=[state, sentence_md, audio_out, state])

    with gr.Tab("文字 → 手語動畫"):
        with gr.Row():
            txt = gr.Textbox(label="輸入詞彙（馬來語或英文，空白分隔）",
                             placeholder="tandas mana / where toilet / berapa duit")
            btn2 = gr.Button("生成動畫", variant="primary")
        anim = gr.Video(label="火柴人動畫（BIM-SIGN Pose 關節點渲染）")
        note = gr.Markdown()
        btn2.click(text_to_sign, [txt], [anim, note])
        gr.Examples([["tandas mana"], ["berapa duit"], ["hospital mana"],
                     ["tolong"], ["terima kasih"]], [txt])

if __name__ == "__main__":
    demo.launch(server_name="127.0.0.1", server_port=7860)
