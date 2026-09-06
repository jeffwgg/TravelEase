"""Record supplementary travel-word clips via webcam (words missing from BIM-SIGN).

Saves MP4s to data_custom/{word}/{signer}/{nnn}.mp4 for later MediaPipe
extraction with the same (T, 258) format, then merges into training.

Usage:  python record_custom.py --word kiri --signer alice
Keys:   SPACE = start/stop clip, q = quit
"""

import argparse
import os
import time

import cv2

MISSING_WORDS = [
    ("kiri", "left"), ("kanan", "right"), ("ini", "this"),
    ("terus", "go straight"), ("pusing", "turn"),
    ("jauh", "far"), ("dekat", "near"),
    ("hotel", "hotel"), ("keluar", "exit"),
    ("tiket", "ticket"), ("tunggu", "wait"), ("telefon", "phone"),
]
TARGET_PER_WORD = 30


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--word", required=True, help="word id, e.g. kiri")
    ap.add_argument("--signer", required=True, help="signer name")
    ap.add_argument("--cam", type=int, default=0)
    args = ap.parse_args()

    out_dir = os.path.join(os.path.dirname(__file__), "..", "data_custom",
                           args.word, args.signer)
    os.makedirs(out_dir, exist_ok=True)
    existing = len([f for f in os.listdir(out_dir) if f.endswith(".mp4")])
    print(f"'{args.word}' signer={args.signer}: {existing}/{TARGET_PER_WORD} clips exist")

    cap = cv2.VideoCapture(args.cam)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    recording, frames, take = False, [], existing
    print("SPACE=start/stop  q=quit")

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        mirror = cv2.flip(frame, 1)
        if recording:
            frames.append(frame.copy())  # save unmirrored for consistency
            elapsed = time.time() - start
            cv2.putText(mirror, f"REC {elapsed:.1f}s take {take + 1}",
                        (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 255), 2)
        else:
            cv2.putText(mirror, f"{args.word} ({TARGET_PER_WORD - existing} left) SPACE=rec",
                        (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
        cv2.imshow("record", mirror)
        key = cv2.waitKey(1) & 0xFF
        if key == ord(" ") and not recording:
            recording, frames, start = True, [], time.time()
        elif key == ord(" ") and recording:
            recording = False
            if 0.8 <= time.time() - start <= 4.0 and frames:
                take += 1
                path = os.path.join(out_dir, f"{take:03d}.mp4")
                h, w = frames[0].shape[:2]
                vw = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"),
                                     30, (w, h))
                for f in frames:
                    vw.write(f)
                vw.release()
                existing += 1
                print(f"saved {path} ({len(frames)} frames)")
            else:
                print("discarded (length out of 0.8-4.0s range)")
            frames = []
            if existing >= TARGET_PER_WORD:
                print("target reached for this word")
        elif key == ord("q"):
            break
    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
