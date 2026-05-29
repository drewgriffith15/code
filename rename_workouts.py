"""
Rename workout files in Construct/wiki/workouts/programs/<program>/ using Claude Haiku.

Strips noise tokens (workout, dumbbells, program name) and reorders into a concise
descriptive filename of the form: day_NN_<concise_description>.md

Usage:
    python rename_workouts.py            # dry-run, prints proposed renames
    python rename_workouts.py --apply    # actually rename on disk
    python rename_workouts.py --program beastmode --apply
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

from anthropic import Anthropic
from dotenv import load_dotenv

load_dotenv(Path.home() / ".claude" / ".env.personal", override=True)

ROOT = Path(r"C:\Users\wgriffith2\Dropbox (Liberty University)\Construct\wiki\workouts\programs")
MODEL = "claude-haiku-4-5-20251001"

SYSTEM = """You rename workout filenames to be concise and descriptive.

Rules:
- Output format: day_NN_<concise_description>.md (lowercase, underscores, .md extension)
- Preserve the day_NN prefix exactly.
- Remove these noise tokens entirely: workout, workouts, dumbbell, dumbbells, with_dumbbells, no_equipment, bodyweight (only if redundant), and the program name tokens provided.
- Keep meaningful descriptors: body part (leg, chest, back, glutes, full_body), modality (hiit, emom, tabata, superset, circuit, cardio, strength), and ONE evocative adjective if present (intense, epic, brawny, titan, etc.) - prefer the most distinctive one.
- Reorder for natural reading: adjective + modality/bodypart + "day" when it reads better.
- Target 3-6 tokens after day_NN. Be ruthless about cutting filler.
- Output ONLY the new filename. No prose, no quotes, no explanation.

Examples:
  program=beastmode, input=day_01_leg_day_intense_leg_workout_with_dumbbells.md
  output: day_01_intense_leg_day.md

  program=epic_endgame, input=day_49_superset_full_body_workout_with_dumbbells_epic.md
  output: day_49_superset_full_body.md

  program=epic_endgame, input=day_45_euphoric_emom_hiit_workout_advanced_epic_endgame.md
  output: day_45_euphoric_emom_hiit.md
"""

client = Anthropic()


def propose_rename(program: str, filename: str) -> str:
    msg = client.messages.create(
        model=MODEL,
        max_tokens=80,
        system=SYSTEM,
        messages=[{
            "role": "user",
            "content": f"program={program}\ninput={filename}",
        }],
    )
    out = msg.content[0].text.strip().splitlines()[0].strip().strip('"').strip("'")
    if not out.endswith(".md"):
        out += ".md"
    # safety: must keep day_NN prefix
    m = re.match(r"^(day_\d{2})_", filename)
    if m and not out.startswith(m.group(1) + "_"):
        out = f"{m.group(1)}_{out.lstrip('_')}"
    return out


def process_program(program_dir: Path, apply: bool) -> list[tuple[str, str]]:
    program = program_dir.name
    renames = []
    files = sorted(f for f in os.listdir(program_dir) if f.endswith(".md"))
    for fn in files:
        new_fn = propose_rename(program, fn)
        if new_fn == fn:
            print(f"  [skip] {fn}")
            continue
        print(f"  {fn}\n    -> {new_fn}")
        renames.append((fn, new_fn))
        if apply:
            src = program_dir / fn
            dst = program_dir / new_fn
            if dst.exists():
                print(f"    !! target exists, skipping")
                continue
            src.rename(dst)
    return renames


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="actually rename files")
    ap.add_argument("--program", help="only process this program subdir")
    args = ap.parse_args()

    if not ROOT.exists():
        print(f"Not found: {ROOT}", file=sys.stderr)
        sys.exit(1)

    programs = [ROOT / args.program] if args.program else sorted(p for p in ROOT.iterdir() if p.is_dir())
    log = {}
    for pdir in programs:
        if not pdir.is_dir():
            continue
        print(f"\n=== {pdir.name} ===")
        log[pdir.name] = process_program(pdir, apply=args.apply)

    mode = "APPLIED" if args.apply else "DRY-RUN (use --apply to rename)"
    total = sum(len(v) for v in log.values())
    print(f"\n{mode}: {total} files would be renamed")


if __name__ == "__main__":
    main()
