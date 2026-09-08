"""HTTP bridge for the TravelEase BIM word-recognition model.

The Flutter app sends one 0.8-4 second video clip at a time. This module keeps
all MediaPipe and PyTorch work on the Python side and leaves ASL/CSL flows in
the app untouched.

Run from ``slr/``:
    python -m uvicorn scripts.bim_api:app --host 0.0.0.0 --port 8000
"""

import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool

SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from templates import glosses_to_utterance

# ``demo`` owns the existing webcam preprocessing and model-loading path.
# Reusing it keeps mobile output aligned with the desktop demo and training.
from demo import ID2GLOSS, NUM_CLASSES, predict_sign  # noqa: E402


app = FastAPI(title="TravelEase BIM recognition API", version="1.0.0")

TOP3_PATTERN = re.compile(r"\*\*(?P<word>[^*]+)\*\*\s+(?P<percent>\d+)%")

MALAY_TO_ENGLISH = {
    "Di mana tandas?": "Where is the toilet?",
    "Di mana hospital?": "Where is the hospital?",
    "Di mana balai polis?": "Where is the police station?",
    "Di mana kedai?": "Where is the shop?",
    "Di mana kafetaria?": "Where is the restaurant?",
    "Di mana stesen bas?": "Where is the bus station?",
    "Di mana stesen keretapi?": "Where is the train station?",
    "Di mana boleh naik teksi?": "Where can I take a taxi?",
    "Sila pergi ke kiri.": "Please go left.",
    "Sila pergi ke kanan.": "Please go right.",
    "Terus jalan sahaja.": "Please go straight.",
    "Pusing ke kiri di hadapan.": "Turn left ahead.",
    "Pusing ke kanan di hadapan.": "Turn right ahead.",
    "Jalan ikut arah ini.": "Go in this direction.",
    "Berapa harganya?": "How much does it cost?",
    "Berapa harga yang ini?": "How much is this one?",
    "Saya nak beli yang ini.": "I want to buy this one.",
    "Terlalu mahal.": "Too expensive.",
    "Saya nak beli tiket.": "I want to buy a ticket.",
    "Tolong! Saya perlukan bantuan.": "Help! I need assistance.",
    "Boleh saya dapatkan air?": "May I have some water?",
    "Saya lapar, nak makan.": "I am hungry and want to eat.",
    "Di mana boleh makan?": "Where can I eat?",
    "Tidak, terima kasih.": "No, thank you.",
    "Boleh tak?": "Is that possible?",
    "Saya sakit.": "I am in pain.",
    "Barang saya hilang.": "My belongings are missing.",
    "Boleh pinjam telefon?": "May I borrow a phone?",
    "Terima kasih!": "Thank you!",
    "Apa khabar?": "How are you?",
    "Selamat pagi!": "Good morning!",
    "Nama saya...": "My name is...",
    "Bila?": "When?",
    "Apa ini?": "What is this?",
}


def _parse_previous_glosses(raw: str) -> list[str]:
    try:
        glosses = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="glosses must be a JSON array") from exc
    if not isinstance(glosses, list) or not all(isinstance(g, str) for g in glosses):
        raise HTTPException(status_code=400, detail="glosses must be a JSON array of strings")
    # A short phrase is enough for the prototype and avoids an accidental
    # client loop growing an unbounded request.
    return [g.strip() for g in glosses if g.strip()][-8:]


def _top3(markdown: str) -> list[dict[str, object]]:
    return [
        {"word": m.group("word"), "confidence": int(m.group("percent")) / 100}
        for m in TOP3_PATTERN.finditer(markdown)
    ]


@app.get("/health")
def health():
    """Small readiness endpoint for a mobile deployment check."""
    return {"status": "ok", "classes": NUM_CLASSES, "model_words": len(ID2GLOSS)}


@app.post("/v1/bim/recognize")
async def recognize(
    video: UploadFile = File(...),
    glosses: str = Form("[]"),
):
    """Recognise one BIM word and return the accumulated travel phrase."""
    previous = _parse_previous_glosses(glosses)
    suffix = Path(video.filename or "clip.mp4").suffix.lower() or ".mp4"
    if suffix not in {".mp4", ".mov", ".avi", ".mkv", ".webm"}:
        raise HTTPException(status_code=415, detail="Please upload a video clip.")

    fd, temp_path = tempfile.mkstemp(prefix="travelease_bim_", suffix=suffix)
    os.close(fd)
    try:
        with open(temp_path, "wb") as dst:
            shutil.copyfileobj(video.file, dst)
        markdown, word = await run_in_threadpool(predict_sign, temp_path)
    except Exception as exc:
        raise HTTPException(status_code=500, detail="BIM recognition failed") from exc
    finally:
        await video.close()
        try:
            os.unlink(temp_path)
        except FileNotFoundError:
            pass

    if not word:
        # Surface the existing detection diagnostic instead of inventing a word.
        raise HTTPException(status_code=422, detail={"message": markdown})

    all_glosses = previous + [word]
    utterance = glosses_to_utterance(all_glosses)
    candidates = _top3(markdown)
    confidence = candidates[0]["confidence"] if candidates else 0.0
    return {
        "word": word,
        "confidence": confidence,
        "top3": candidates,
        "glosses": all_glosses,
        "malay": utterance.malay,
        "chinese": utterance.chinese,
        "english": MALAY_TO_ENGLISH.get(utterance.malay, " ".join(all_glosses)),
        "matched": utterance.matched,
    }
