#!/usr/bin/env python3
# flatten_dirs.py — move all files from subfolders into the root, remove empty dirs.

import os
import shutil
from pathlib import Path

# === EDIT THESE ===
ROOTS = [
    "/home/drty-hry/Documents/transcript-editor/project/fixit-cy/transcripts/audio_chunks",
    "/home/drty-hry/Documents/transcript-editor/project/fixit-cy/transcripts/custom_transcript",
    # "/absolute/path/to/vtt_root",
]
DRY_RUN = False # set to False to actually move & delete
# ==================

def unique_name(dest_dir: Path, filename: str) -> Path:
    base, dot, ext = filename.partition(".")
    candidate = dest_dir / filename
    n = 2
    while candidate.exists():
        # preserve extension; append _2, _3, …
        fname = f"{base}_{n}.{ext}" if dot else f"{base}_{n}"
        candidate = dest_dir / fname
        n += 1
    return candidate

def flatten_one(root: Path):
    print(f"\n== Flattening: {root} ==")
    if not root.exists() or not root.is_dir():
        print(f"SKIP: {root} not found or not a directory.")
        return

    moved = 0
    # Move files up to the root
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if p.parent == root:
            continue  # already at top-level
        dest = unique_name(root, p.name)
        print(f"MOVE: {p} -> {dest}")
        if not DRY_RUN:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(p), str(dest))
        moved += 1

    # Remove empty subdirs (bottom-up)
    removed = 0
    for dirpath, dirnames, filenames in os.walk(root, topdown=False):
        d = Path(dirpath)
        if d == root:
            continue
        try:
            if not os.listdir(d):
                print(f"RMDIR: {d}")
                if not DRY_RUN:
                    d.rmdir()
                removed += 1
        except FileNotFoundError:
            pass

    print(f"Done: moved {moved} file(s), removed {removed} folder(s).{' (DRY RUN)' if DRY_RUN else ''}")

def main():
    for r in ROOTS:
        flatten_one(Path(r).expanduser().resolve())

if __name__ == "__main__":
    main()
