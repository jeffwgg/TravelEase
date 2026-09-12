#!/usr/bin/env python3
"""Scrape BIM (Bahasa Isyarat Malaysia) sign videos from bimsignbank.org.

The BIM SignBank front-end (https://bimsignbank.org/home) is a React SPA
backed by a public Strapi API at https://api.bimsignbank.org. Each entry
("bim") carries a Malay word (`Perkataan`), an English gloss (`Word`) and a
YouTube link to the signing video (`Video`).

This script:
  1. Derives the needed glosses from the app's sign dictionary by parsing the
     `glossBim: '...'` entries in lib/models/repositories/sign_reference_repository.dart.
  2. Resolves each gloss to a SignBank entry (exact match -> token match ->
     alias), mirroring the multi-word greedy matching that
     sign_word_video_library.dart performs (e.g. TERIMA KASIH -> terima_kasih.mp4).
  3. Downloads the YouTube clip, REMOVES THE AUDIO TRACK, and saves it as
     assets/signs/bim/<slug>.mp4  (e.g. "pintu.mp4").

Requirements:  pip install -U yt-dlp   (ffmpeg must be on PATH)

Usage:
    python scripts/scrape_bim_signs.py                 # fetch only what is missing
    python scripts/scrape_bim_signs.py --force         # re-download everything
    python scripts/scrape_bim_signs.py --list          # show resolution, download nothing
    python scripts/scrape_bim_signs.py pintu doktor    # only these slugs
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API_BASE = "https://api.bimsignbank.org/api/bims"
# Cloudflare blocks the default urllib user-agent on this host.
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/127.0 Safari/537.36"
    ),
    "Accept": "application/json",
}

MOBILE_DIR = Path(__file__).resolve().parents[1]
DICT_FILE = MOBILE_DIR / "lib" / "models" / "repositories" / "sign_reference_repository.dart"
OUT_DIR = MOBILE_DIR / "assets" / "signs" / "bim"

# Glosses that have no standalone entry in the SignBank; map slug -> search terms
# (tried in order) for the closest published sign. Only applied to single words,
# never to phrase compounds (so 'DAFTAR MASUK' falls back to daftar.mp4 + masuk.mp4,
# exactly like the Dart resolveClipSources greedy matcher does).
ALIASES: dict[str, list[str]] = {
    "penerbangan": ["kapal terbang", "terbang"],   # "Kapal terbang" = Aeroplane/Flight
    "bantuan": ["bantu", "tolong"],                # "Tolong (Bantu)" = Help, Assist
    "halo": ["hello", "hai"],                      # "Hai, Hello" = Hi, Hello
}

# Force the exact published variant for glosses whose context disambiguates them.
# 'HALO GEMBIRA JUMPA AWAK' = nice to MEET you -> use "Jumpa (II)" (Meet), not (I) (Find).
OVERRIDES: dict[str, str] = {
    "jumpa": "jumpa (ii)",
}


# ---------------------------------------------------------------------------
# Gloss derivation from the Flutter sign dictionary
# ---------------------------------------------------------------------------

def slugify(token: str) -> str:
    """Same normalization as SignWordVideoLibrary.slugify (Dart)."""
    out: list[str] = []
    last_sep = False
    for ch in token.lower():
        if ch.isascii() and ch.isalnum():
            out.append(ch)
            last_sep = False
        elif out and not last_sep:
            out.append("_")
            last_sep = True
    slug = "".join(out).rstrip("_")
    return slug


def parse_gloss_words(gloss: str) -> list[str]:
    words = [w.strip() for w in gloss.split()]
    return [w for w in words if slugify(w)]


def load_dict_glosses() -> list[str]:
    """All unique glossBim phrases from the sign dictionary."""
    text = DICT_FILE.read_text(encoding="utf-8")
    phrases = re.findall(r"glossBim:\s*'([^']*)'", text)
    if not phrases:
        sys.exit(f"No glossBim entries found in {DICT_FILE}")
    seen: dict[str, None] = {}
    for p in phrases:
        seen.setdefault(p.strip(), None)
    return list(seen)


def build_worklist() -> list[dict]:
    """Resolve which slugs to fetch, mirroring resolveClipSources(): greedy
    3/2-token compound matching first (e.g. TERIMA KASIH -> terima_kasih.mp4),
    then the single words a compound didn't consume."""
    tasks: list[dict] = []
    queued_slugs: set[str] = set()
    entry_cache: dict[str, dict | None] = {}

    def cached(term: str, use_aliases: bool) -> dict | None:
        key = term if use_aliases else f"={term}"
        if key not in entry_cache:
            if use_aliases:
                entry_cache[key] = resolve_entry(term)
            else:  # compounds must match the full phrase, no alias substitution
                entry_cache[key] = _direct_resolve(term)
        return entry_cache[key]

    for phrase in load_dict_glosses():
        group = parse_gloss_words(phrase)
        i = 0
        while i < len(group):
            consumed = False
            for n in (3, 2):
                if i + n > len(group):
                    continue
                tokens = group[i : i + n]
                entry = cached(" ".join(tokens).lower(), use_aliases=False)
                if entry:
                    slug = slugify("-".join(tokens))
                    if slug not in queued_slugs:
                        queued_slugs.add(slug)
                        tasks.append({"slug": slug, "term": " ".join(tokens).lower(), "entry": entry})
                    i += n
                    consumed = True
                    break
            if not consumed:
                term = group[i].lower()
                slug = slugify(term)
                if slug and slug not in queued_slugs:
                    queued_slugs.add(slug)
                    tasks.append({"slug": slug, "term": term, "entry": None})  # resolved later (also for --slugs)
                i += 1
    return tasks


# ---------------------------------------------------------------------------
# SignBank API lookup
# ---------------------------------------------------------------------------

def api_search(op: str, term: str) -> list[dict]:
    params = urllib.parse.urlencode(
        {
            "populate": "category_group",
            "pagination[pageSize]": "100",
            f"filters[Perkataan][{op}]": term,
        }
    )
    req = urllib.request.Request(f"{API_BASE}?{params}", headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["data"]
    except (urllib.error.URLError, KeyError) as exc:
        print(f"  ! API lookup failed for '{term}' ({op}): {exc}", file=sys.stderr)
        return []


def normalize_phrase(s: str) -> list[str]:
    """'Tolong (Bantu)' -> ['tolong bantu'];  'Kapal terbang' -> ['kapal terbang'];
    'Lihat, Tengok' -> ['lihat', 'tengok']. Parentheses become plain words so
    aliases like '(Bantu)' stay matchable; spaces inside a token are kept
    (multi-word signs stay one token)."""
    s = s.lower().replace("(", " ").replace(")", " ")
    s = re.sub(r"\s+", " ", s)
    return [t.strip() for t in re.split(r"[,;]", s) if t.strip()]


def _entry_score(entry: dict, term: str) -> tuple:
    """Rank key: lower is better. None when the term is not a real match."""
    text = re.sub(r"\s+", " ", (entry.get("Perkataan") or "").strip().lower())
    if not text:
        return None
    if text == term:
        return (0, len(normalize_phrase(text)), entry.get("id", 0))
    toks = normalize_phrase(text)
    if term in toks:
        return (1, len(toks), entry.get("id", 0))
    if re.search(rf"(^|\s){re.escape(term)}(\s|$)", " ".join(toks)):
        return (2, len(toks), entry.get("id", 0))
    # a multi-word term spanning tokens, e.g. 'kapal terbang' in 'Kapal terbang'.
    # Never allow this for single words: substring matching would map
    # 'halo' -> 'Chalok' (c-HALO-k).
    if " " in term and term in " ".join(toks):
        return (3, len(toks), entry.get("id", 0))
    return None


def _direct_resolve(term: str) -> dict | None:
    """Best entry whose Perkataan actually contains the full term as words."""
    best = None
    for op in ("$eqi", "$containsi"):
        scored = [(s, e) for e in api_search(op, term) if (s := _entry_score(e, term)) is not None]
        if scored:
            scored.sort(key=lambda se: se[0])
            best = scored[0][1]
            break
    return best


def resolve_entry(term: str) -> dict | None:
    """Find the best SignBank entry for a (lowercased) single word,
    honoring the exact-variant override first, then aliases."""
    candidates = ([OVERRIDES[term]] if term in OVERRIDES else []) + [term] + ALIASES.get(term, [])
    for t in candidates:
        entry = _direct_resolve(t)
        if entry:
            return entry
    return None


# ---------------------------------------------------------------------------
# Download + mute
# ---------------------------------------------------------------------------

def yt_video_id(url: str) -> str | None:
    if not url:
        return None
    m = re.search(r"(?:youtu\.be/|v=|embed/|shorts/)([A-Za-z0-9_-]{6,})", url)
    return m.group(1) if m else None


def ffprobe_video_codec(path: Path) -> str:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=codec_name", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True)
    return out.stdout.strip()


def download_and_mute(video_url: str, dest: Path, height: int) -> bool:
    try:
        import yt_dlp
    except ImportError:
        sys.exit("yt-dlp not installed. Run:  python -m pip install -U yt-dlp")

    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg not found on PATH.")

    with tempfile.TemporaryDirectory() as td:
        opts = {
            # YouTube now requires a JS runtime + the EJS challenge solver to
            # sign format URLs (see yt-dlp wiki /EJS); node ships with many
            # dev setups and is auto-detected when the path is None.
            "js_runtimes": {"node": {"path": None}, "deno": {"path": None}},
            "remote_components": "ejs:github",
            "format": f"bv*[height<={height}]+ba/b[height<={height}]/bv*+ba/b",
            "merge_output_format": "mp4",
            "outtmpl": str(Path(td) / "raw.%(ext)s"),
            "noplaylist": True,
            "quiet": True,
            "no_warnings": True,
            "noprogress": True,
            "retries": 3,
        }
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(video_url, download=True)
                src = Path(ydl.prepare_filename(info))
                if not src.exists():  # container may differ from requested ext
                    cand = list(Path(td).glob("raw.*"))
                    if not cand:
                        raise RuntimeError("download produced no file")
                    src = cand[0]
        except Exception as exc:
            print(f"  ! yt-dlp failed: {exc}", file=sys.stderr)
            return False

        # Strip the audio track (-an). Keep the video stream untouched when it
        # is already H.264 (what Flutter's video_player expects on mobile);
        # otherwise re-encode to H.264 yuv420p.
        codec = ffprobe_video_codec(src)
        cmds = []
        if codec == "h264":
            cmds.append(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-an",
                         "-c:v", "copy", "-movflags", "+faststart", str(dest)])
        cmds.append(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-an",
                     "-c:v", "libx264", "-crf", "26", "-preset", "fast",
                     "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(dest)])
        for cmd in cmds:
            if subprocess.run(cmd).returncode == 0 and dest.exists() and dest.stat().st_size > 0:
                return True
        dest.unlink(missing_ok=True)
        print("  ! ffmpeg failed to produce a silent mp4", file=sys.stderr)
        return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("slugs", nargs="*", help="only these gloss slugs (default: all dictionary glosses)")
    ap.add_argument("--force", action="store_true", help="re-download files that already exist")
    ap.add_argument("--list", action="store_true", dest="list_only", help="resolve glosses, download nothing")
    ap.add_argument("--height", type=int, default=480, help="max video height (default 480)")
    args = ap.parse_args()

    print(f"Sign dictionary: {DICT_FILE}")
    print(f"Output folder:   {OUT_DIR}\n")

    tasks = build_worklist()
    if args.slugs:
        wanted = {s.lower() for s in args.slugs}
        tasks = [t for t in tasks if t["slug"] in wanted]

    out_dir: Path = OUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    ok = skipped = missing = failed = 0
    for t in tasks:
        slug, term = t["slug"], t["term"]
        entry = t["entry"] if t["entry"] is not None else resolve_entry(term)
        if not entry:
            print(f"[MISSING] {slug:16s} no SignBank entry for '{term}'")
            missing += 1
            continue
        vid = yt_video_id(entry.get("Video") or "")
        dest = out_dir / f"{slug}.mp4"
        line = f"{slug:16s} <- {entry['Perkataan']:24s} {entry.get('Word') or '':26s} {vid or ''}"
        if args.list_only:
            print(f"[PLAN]      {line}")
            continue
        if dest.exists() and not args.force:
            print(f"[EXISTS]    {line}")
            skipped += 1
            continue
        print(f"[DOWNLOAD]  {line}")
        if not vid:
            print(f"[FAILED]    {slug}: entry has no video url")
            failed += 1
            continue
        if download_and_mute(f"https://youtu.be/{vid}", dest, args.height):
            ok += 1
        else:
            failed += 1

    if not args.list_only:
        print(f"\nDone: {ok} downloaded, {skipped} existing, {missing} missing, {failed} failed.")
        print(f"Files in {out_dir}:")
        for f in sorted(out_dir.glob("*.mp4")):
            print(f"  {f.name:20s} {f.stat().st_size/1024:8.0f} KB")


if __name__ == "__main__":
    main()
