"""
ingest_raw.py - Process raw YouTube files into Construct wiki

Reads from Construct/raw/, classifies domain, writes wiki summary pages,
updates index.md + log.md, moves raw files to raw/processed/.

Usage:
    python ingest_raw.py                               # dry run - show what would happen
    python ingest_raw.py --run                         # process all files in raw/
    python ingest_raw.py --run 20260510_some_video.md  # process one specific file

Dry run is always safe. Use --run when you've reviewed raw/ and are ready to commit.
"""

import os
import re
import sys
import shutil
import argparse
from typing import Dict, List, Optional
from datetime import datetime
from pathlib import Path

import anthropic
from dotenv import load_dotenv

load_dotenv(os.path.expanduser(r"~\.claude\.env.personal"), override=True)

# --- Config ---

CONSTRUCT = Path(r"C:\Users\wgriffith2\Dropbox (Liberty University)\Construct")
RAW_DIR = CONSTRUCT / "raw"
PROCESSED_DIR = RAW_DIR / "processed"
WIKI_DIR = CONSTRUCT / "wiki"
INDEX_FILE = CONSTRUCT / "index.md"
LOG_FILE = CONSTRUCT / "log.md"

VALID_DOMAINS = {"lawn", "garden", "food", "theology", "workouts", "health", "technology", "general"}

DOMAIN_HEADINGS = {
    "lawn": "Lawn",
    "garden": "Garden",
    "food": "Food",
    "theology": "Theology",
    "workouts": "Workouts",
    "health": "Health",
    "technology": "Technology",
    "general": "General",
}


# --- Parse raw file ---

def parse_raw_file(path: Path) -> Optional[Dict]:
    """Extract frontmatter fields + content sections from a raw file."""
    text = path.read_text(encoding="utf-8", errors="replace")

    # Frontmatter block
    fm_match = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not fm_match:
        print(f"  WARNING: No frontmatter in {path.name} - skipping.")
        return None

    fm = {}
    for line in fm_match.group(1).splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            fm[k.strip()] = v.strip()

    body = text[fm_match.end():]

    # Title from first H1
    title_match = re.search(r"^# (.+)$", body, re.MULTILINE)
    title = title_match.group(1).strip() if title_match else path.stem

    # Split at transcript separator: --- followed by ## Transcript
    transcript_sep = re.search(r"\n---\n+## Transcript", body)
    if transcript_sep:
        body_content = body[:transcript_sep.start()].rstrip()
        transcript_match = re.search(r"## Transcript\n\n(.*?)$", body[transcript_sep.start():], re.DOTALL)
        transcript = transcript_match.group(1).strip() if transcript_match else ""
    else:
        body_content = body.rstrip()
        transcript = ""

    # Summary paragraph (single block under ## Summary, for backwards compat)
    summary_match = re.search(r"## Summary\n\n(.*?)(?=\n---|\n## |\Z)", body, re.DOTALL)
    summary = summary_match.group(1).strip() if summary_match else ""

    return {
        "filename": path.name,
        "stem": path.stem,
        "title": title,
        "date": fm.get("date", datetime.now().strftime("%Y-%m-%d")),
        "source_url": fm.get("source_url", ""),
        "channel": fm.get("channel", ""),
        "video_id": fm.get("video_id", ""),
        "body_content": body_content,
        "summary": summary,
        "transcript": transcript,
        "raw_path": path,
    }


# --- Claude classification ---

def classify_domain(title: str, channel: str, summary: str, transcript: str = "") -> str:
    """Classify domain. Uses summary; falls back to transcript first 2000 words if summary is thin."""
    client = anthropic.Anthropic()

    content = summary if len(summary.split()) >= 20 else " ".join(transcript.split()[:2000])

    prompt = (
        f"Video title: {title}\n"
        f"Channel: {channel}\n\n"
        f"Content:\n{content}\n\n"
        f"Classify into exactly one domain: lawn, garden, food, theology, workouts, health, technology, general\n"
        f"- technology: AI, software, programming, tech industry\n"
        f"- general: news, current events, or anything that doesn't fit the others\n"
        f"Reply with only the single domain word, nothing else."
    )
    msg = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=10,
        temperature=0,
        messages=[{"role": "user", "content": prompt}],
    )
    result = msg.content[0].text.strip().lower()
    return result if result in VALID_DOMAINS else "general"


# --- Write wiki summary page ---

def channel_tag(channel: str) -> str:
    return re.sub(r"[\W_]+", "-", channel).strip("-").lower()


def write_wiki_page(parsed: Dict, domain: str) -> Path:
    today = datetime.now().strftime("%Y%m%d")
    date_clean = parsed["date"].replace("-", "")
    tag = channel_tag(parsed["channel"])
    source_url = parsed["source_url"]

    dest_dir = WIKI_DIR / domain / "summaries"
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / parsed["filename"]

    content = (
        f"---\n"
        f"domain: {domain}\n"
        f"type: summary\n"
        f"date: {date_clean}\n"
        f"tags: [{tag}]\n"
        f"sources: [{source_url}]\n"
        f"updated: {today}\n"
        f"---\n\n"
        f"{parsed['body_content']}\n"
    )

    dest.write_text(content, encoding="utf-8")
    return dest


# --- index.md update ---

def update_index(domain: str, filename: str, title: str, channel: str):
    """
    Update index.md with the new summary.

    Logic (in order):
    1. If '*+N additional summaries in wiki/<domain>/summaries/*' exists -> increment N
    2. Else if '### Summaries' section exists under domain -> append a link line
    3. Else -> add a '### Summaries' section with a link line under the domain heading
    4. If domain heading missing entirely -> append a new domain block at end
    """
    text = INDEX_FILE.read_text(encoding="utf-8")
    stem = Path(filename).stem
    wiki_path = f"wiki/{domain}/summaries/{stem}"
    link_line = f"- [[{wiki_path}|{title}]] — {channel}\n"
    heading = DOMAIN_HEADINGS[domain]

    # Case 1: increment existing count placeholder
    count_re = re.compile(
        rf"(\*\+)(\d+)( additional summaries in wiki/{re.escape(domain)}/summaries/\*)"
    )
    m = count_re.search(text)
    if m:
        new_count = int(m.group(2)) + 1
        text = text[: m.start()] + f"*+{new_count} additional summaries in wiki/{domain}/summaries/*" + text[m.end():]
        INDEX_FILE.write_text(text, encoding="utf-8")
        return

    # Find domain section boundaries
    domain_re = re.compile(rf"^## {re.escape(heading)}$", re.MULTILINE)
    dm = domain_re.search(text)

    if not dm:
        # Case 4: no domain heading at all - append new block
        block = (
            f"\n## {heading}\n\n"
            f"### Summaries\n"
            f"{link_line}"
        )
        INDEX_FILE.write_text(text.rstrip() + block + "\n", encoding="utf-8")
        return

    # Find the end of this domain's block (next ## heading or EOF)
    next_domain_m = re.search(r"^\n## ", text[dm.end():], re.MULTILINE)
    block_end = dm.end() + next_domain_m.start() if next_domain_m else len(text)
    domain_block = text[dm.start(): block_end]

    # Case 2: ### Summaries exists in this domain block
    summaries_re = re.compile(r"^### Summaries$", re.MULTILINE)
    sm = summaries_re.search(domain_block)
    if sm:
        # Find end of Summaries subsection (next ### or next ## or end of block)
        after_header = domain_block[sm.end():]
        next_section_m = re.search(r"\n###|\n##", after_header)
        if next_section_m:
            insert_rel = sm.end() + next_section_m.start()
        else:
            insert_rel = len(domain_block)
        insert_abs = dm.start() + insert_rel
        text = text[:insert_abs] + link_line + text[insert_abs:]
        INDEX_FILE.write_text(text, encoding="utf-8")
        return

    # Case 3: no ### Summaries section - insert one before the end of this domain block
    summaries_block = f"\n### Summaries\n{link_line}"
    text = text[:block_end] + summaries_block + text[block_end:]
    INDEX_FILE.write_text(text, encoding="utf-8")


# --- log.md ---

def append_log(title: str, domain: str):
    today = datetime.now().strftime("%Y-%m-%d")
    entry = (
        f"\n## [{today}] ingest | {title}\n\n"
        f"Domain: {domain}. Source moved to raw/processed/.\n"
    )
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(entry)


# --- Core ---

def process_file(parsed: Dict, dry_run: bool = True, force: bool = False) -> bool:
    title = parsed["title"]
    channel = parsed["channel"]

    if not parsed["body_content"] and not parsed["transcript"]:
        print(f"  WARNING: No content or transcript found - skipping.")
        return False

    domain = classify_domain(title, channel, parsed["body_content"], parsed["transcript"])
    print(f"  Domain:  {domain}")

    wiki_dest = WIKI_DIR / domain / "summaries" / parsed["filename"]
    already_indexed = wiki_dest.exists()
    if already_indexed and not force:
        print(f"  SKIP: Wiki page already exists at {wiki_dest.relative_to(CONSTRUCT)}")
        return False

    processed_dest = PROCESSED_DIR / domain / parsed["filename"]
    if processed_dest.exists() and not parsed["raw_path"].exists():
        print(f"  SKIP: Already in raw/processed/{domain}/")
        return False

    if dry_run:
        action = "OVERWRITE" if already_indexed else "->"
        print(f"  {action} wiki/{domain}/summaries/{parsed['filename']}")
        print(f"  -> raw/processed/{domain}/{parsed['filename']}")
        return True

    write_wiki_page(parsed, domain)
    print(f"  Written: wiki/{domain}/summaries/{parsed['filename']}")

    (PROCESSED_DIR / domain).mkdir(parents=True, exist_ok=True)
    shutil.move(str(parsed["raw_path"]), str(processed_dest))
    print(f"  Moved:   raw/processed/{domain}/{parsed['filename']}")

    if not already_indexed:
        update_index(domain, parsed["filename"], title, channel)
        append_log(title, domain)
        print(f"  Updated: index.md + log.md")
    else:
        print(f"  Skipped: index.md + log.md (already indexed)")

    return True


def get_raw_files(target: Optional[str] = None) -> List[Path]:
    """Return .md files from raw/ root only (excludes processed/ subfolder)."""
    if target:
        p = RAW_DIR / target
        if not p.exists():
            print(f"ERROR: {p} not found.")
            return []
        return [p]
    return sorted(f for f in RAW_DIR.glob("*.md") if f.is_file())


def main():
    parser = argparse.ArgumentParser(
        description="Ingest raw YouTube files into Construct wiki",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python ingest_raw.py                               # dry run all\n"
            "  python ingest_raw.py --run                         # process all\n"
            "  python ingest_raw.py --run 20260510_some_video.md  # process one"
        ),
    )
    parser.add_argument("--run", action="store_true", help="Write files (default is dry run)")
    parser.add_argument("--force", action="store_true", help="Overwrite existing wiki pages (skips index/log update)")
    parser.add_argument("file", nargs="?", help="Specific filename in raw/ to process")
    args = parser.parse_args()

    dry_run = not args.run

    if not os.getenv("ANTHROPIC_API_KEY"):
        print("FATAL: ANTHROPIC_API_KEY not set.")
        sys.exit(1)

    if dry_run:
        print("DRY RUN - no files will be written. Pass --run to execute.\n")

    files = get_raw_files(args.file)
    if not files:
        print("Nothing to process in raw/.")
        return

    print(f"Found {len(files)} file(s) in raw/.\n")
    ok, skipped = 0, 0

    for path in files:
        print(f"[{path.name}]")
        parsed = parse_raw_file(path)
        if not parsed:
            skipped += 1
            print()
            continue

        print(f"  Title:   {parsed['title']}")
        print(f"  Channel: {parsed['channel']}")

        if process_file(parsed, dry_run=dry_run, force=args.force):
            ok += 1
        else:
            skipped += 1
        print()

    action = "Would process" if dry_run else "Processed"
    print(f"{action}: {ok}  |  Skipped: {skipped}")
    if dry_run and ok > 0:
        suffix = " --force" if args.force else ""
        print(f"\nRun with --run{suffix} to execute.")


if __name__ == "__main__":
    main()
