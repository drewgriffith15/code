"""
ingest_workout_playlist.py - Caroline Girvan workout playlist ingest.

Pulls video descriptions from a public YouTube playlist, runs each through
Haiku to format as standardized workout markdown, writes one file per video
to Construct/wiki/workouts/programs/<slug>/.

Phases:
    --sample    Fetch 3 random descriptions, format with Haiku, print + save
                to programs/<slug>/_samples/ for review. No real ingest.
    --ingest    Process all videos. Skips URLs already present in target folder.

Usage:
    python ingest_workout_playlist.py <playlist_url> --sample
    python ingest_workout_playlist.py <playlist_url> --program xmas --ingest
    python ingest_workout_playlist.py <playlist_url> --program xmas --ingest --force
"""

import argparse
import os
import random
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional

import yt_dlp
import anthropic
from dotenv import load_dotenv

load_dotenv(Path.home() / ".claude" / ".env.personal", override=True)

PROGRAMS_ROOT = Path(
    r"C:\Users\wgriffith2\Dropbox (Liberty University)\Construct\wiki\workouts\programs"
)
MODEL = "claude-haiku-4-5-20251001"

FORMAT_SYSTEM = """ROLE
Senior Fitness Documentation Specialist. Convert a raw YouTube workout description
into a clean, standardized Markdown document.

OUTPUT STRUCTURE (in this exact order)
1. # <Title>
2. Blank line, then: Video URL: <url>
3. ## Workout Overview  (one short paragraph)
4. ## Notes  (bulleted list with -)
5. # Equipment Needed  (bulleted list with -)
6. ### Workout Format  (bulleted list with -)
7. ## Workout Plan  (numbered list 1., 2., ...)
8. ### Finisher  (only if present)

STYLING RULES
- No asterisks anywhere. No bold, no italics.
- Lists: numbers (1.) for exercises, dashes (-) for sub-items and notes.
- Unilateral movements: indent Left/Right as dashed sub-items under the parent number.
- Staple exercises: integrate into the numbered list where they occur.
- Sets in parentheses next to exercise name when applicable. Example: 1. Squat (2 sets).
- Do NOT repeat per-exercise duration when it matches the Workout Format timer.
  The reader already knows the work/rest interval from the Format section.
  Only include a duration on an exercise if it deviates from the standard timer
  (example: a finisher exercise held to failure, or a single move at a different interval).
- Preserve chronological order. Never reorder exercises.

CONSTRAINTS
- Output ONLY the markdown. No preamble, no commentary, no code fences.
- If the description lacks workout content (intro video, announcement, etc.),
  output exactly: SKIP: <one-line reason>
"""


class _Quiet:
    def debug(self, m): pass
    def warning(self, m): pass
    def error(self, m): print(f"  [yt-dlp] {m}")


YDL_QUIET = {"quiet": True, "no_warnings": True, "logger": _Quiet()}


def fetch_playlist(url: str) -> Dict:
    """Returns {title, entries: [{id, url, title, description, position}]}."""
    opts = {**YDL_QUIET, "extract_flat": False, "skip_download": True}
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=False)
    entries = []
    for i, e in enumerate(info.get("entries") or [], start=1):
        if not e:
            continue
        vid = e.get("id", "")
        entries.append({
            "position": i,
            "id": vid,
            "url": f"https://www.youtube.com/watch?v={vid}",
            "title": e.get("title", "Unknown"),
            "description": e.get("description", "") or "",
        })
    return {"title": info.get("title", "Unknown Playlist"), "entries": entries}


def day_number(position: int, title: str) -> str:
    m = re.search(r"\bday\s*(\d{1,2})\b", title, re.IGNORECASE)
    if m:
        return f"{int(m.group(1)):02d}"
    return f"{position:02d}"


def slugify(text: str, max_len: int = 60) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
    if len(s) <= max_len:
        return s
    cut = s[:max_len]
    last = cut.rfind("_")
    return cut[:last] if last > 10 else cut


def existing_source_urls(program_dir: Path) -> set:
    urls = set()
    if not program_dir.exists():
        return urls
    for md in program_dir.glob("*.md"):
        try:
            txt = md.read_text(encoding="utf-8", errors="ignore")
            m = re.search(r"^source_url:\s*(\S+)", txt, re.MULTILINE)
            if m:
                urls.add(m.group(1).strip())
        except Exception:
            pass
    return urls


def format_description(title: str, url: str, description: str) -> str:
    client = anthropic.Anthropic()
    user_msg = (
        f"VIDEO TITLE: {title}\n"
        f"VIDEO URL: {url}\n\n"
        f"RAW DESCRIPTION:\n{description}"
    )
    msg = client.messages.create(
        model=MODEL,
        max_tokens=2048,
        temperature=0,
        system=FORMAT_SYSTEM,
        messages=[{"role": "user", "content": user_msg}],
    )
    return msg.content[0].text.strip()


def write_workout_file(
    program_dir: Path,
    slug: str,
    day: str,
    entry: Dict,
    markdown_body: str,
) -> Path:
    program_dir.mkdir(parents=True, exist_ok=True)
    title_slug = slugify(entry["title"])
    filename = f"day_{day}_{title_slug}.md"
    dest = program_dir / filename

    frontmatter = (
        f"---\n"
        f"domain: workouts\n"
        f"type: knowledge\n"
        f"tags: [program, {slug}]\n"
        f"source_url: {entry['url']}\n"
        f"---\n\n"
    )
    dest.write_text(frontmatter + markdown_body + "\n", encoding="utf-8")
    return dest


def cmd_sample(playlist_url: str, slug_hint: Optional[str]) -> int:
    print(f"Fetching playlist: {playlist_url}")
    pl = fetch_playlist(playlist_url)
    print(f"Playlist title: {pl['title']}")
    print(f"Videos found:   {len(pl['entries'])}")

    if not pl["entries"]:
        print("No entries. Aborting.")
        return 1

    slug = slug_hint or input("\nFolder slug (e.g. 'xmas'): ").strip()
    if not slug:
        print("No slug given. Aborting.")
        return 1

    program_dir = PROGRAMS_ROOT / slug
    sample_dir = program_dir / "_samples"
    sample_dir.mkdir(parents=True, exist_ok=True)

    pool = [e for e in pl["entries"] if e["description"].strip()]
    if len(pool) < 3:
        print(f"WARN: only {len(pool)} entries with descriptions. Using all.")
        sample = pool
    else:
        sample = random.sample(pool, 3)

    for i, entry in enumerate(sample, start=1):
        print(f"\n{'=' * 70}")
        print(f"SAMPLE {i}/{len(sample)}: {entry['title']}")
        print(f"URL: {entry['url']}")
        print(f"{'=' * 70}")
        formatted = format_description(entry["title"], entry["url"], entry["description"])
        print(formatted)
        out = sample_dir / f"sample_{i:02d}_{slugify(entry['title'])}.md"
        out.write_text(formatted + "\n", encoding="utf-8")
        print(f"\n  saved: {out}")

    print(f"\n{'=' * 70}")
    print(f"Samples written to: {sample_dir}")
    print("Review them. If happy, run with --ingest --program", slug)
    return 0


def cmd_ingest(playlist_url: str, slug: str, force: bool) -> int:
    print(f"Fetching playlist: {playlist_url}")
    pl = fetch_playlist(playlist_url)
    print(f"Playlist title: {pl['title']}")
    print(f"Videos found:   {len(pl['entries'])}")

    program_dir = PROGRAMS_ROOT / slug
    existing = set() if force else existing_source_urls(program_dir)
    if existing:
        print(f"Existing files match {len(existing)} source URLs. Will skip those.")

    written, skipped_dup, skipped_empty, skipped_llm = 0, 0, 0, 0
    skip_log: List[str] = []

    for entry in pl["entries"]:
        print(f"\n[{entry['position']}/{len(pl['entries'])}] {entry['title']}")
        if entry["url"] in existing:
            print("  skip: already ingested")
            skipped_dup += 1
            continue
        if not entry["description"].strip():
            print("  skip: empty description")
            skipped_empty += 1
            skip_log.append(f"empty: {entry['url']}  {entry['title']}")
            continue

        formatted = format_description(entry["title"], entry["url"], entry["description"])
        if formatted.startswith("SKIP:"):
            print(f"  skip: {formatted}")
            skipped_llm += 1
            skip_log.append(f"llm-skip: {entry['url']}  {formatted}")
            continue

        day = day_number(entry["position"], entry["title"])
        dest = write_workout_file(program_dir, slug, day, entry, formatted)
        print(f"  written: {dest.name}")
        written += 1

    if skip_log:
        log_path = program_dir / "_skipped.md"
        log_path.write_text("\n".join(skip_log) + "\n", encoding="utf-8")
        print(f"\nSkip log: {log_path}")

    print(f"\nDone. written={written} dup={skipped_dup} empty={skipped_empty} llm_skip={skipped_llm}")
    print(f"\nNext: python rename_workouts.py --program {slug} --apply")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("playlist_url", help="Public YouTube playlist URL")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--sample", action="store_true", help="Fetch 3 random descriptions, format, review")
    mode.add_argument("--ingest", action="store_true", help="Process all videos and write files")
    ap.add_argument("--program", help="Folder slug under programs/ (required for --ingest)")
    ap.add_argument("--force", action="store_true", help="Overwrite even if source_url already present")
    args = ap.parse_args()

    if not os.getenv("ANTHROPIC_API_KEY"):
        print("FATAL: ANTHROPIC_API_KEY not set.")
        return 1

    if args.sample:
        return cmd_sample(args.playlist_url, args.program)

    if args.ingest:
        if not args.program:
            print("FATAL: --ingest requires --program <slug>")
            return 1
        return cmd_ingest(args.playlist_url, args.program, args.force)

    return 1


if __name__ == "__main__":
    sys.exit(main())
