# KILO - workout program publisher.
# Reads a workout program folder from Construct wiki, pushes to Notion under KILO hub.

import os
import re
import sys
import time
import argparse
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path.home() / ".claude" / ".env.personal", override=True)

NOTION_TOKEN = os.getenv("NOTION_TOKEN")
KILO_HUB_PAGE_ID = "33bee045d5ec8030a6f5efe39ba4fadb"
PROGRAMS_DIR = Path(r"C:\Users\wgriffith2\Dropbox (Liberty University)\Construct\wiki\workouts\programs")

ACRONYMS = {"hiit", "emom", "amrap", "rdl", "diy"}


# ── Title formatting ──────────────────────────────────────────────────────────

def _title_case_tokens(tokens):
    out = []
    for t in tokens:
        if t.lower() in ACRONYMS:
            out.append(t.upper())
        else:
            out.append(t.capitalize())
    return " ".join(out)


def program_title(slug: str) -> str:
    return _title_case_tokens(slug.split("_"))


def day_title(filename: str) -> str:
    # day_01_intense_leg_day.md -> Day 01 - Intense Leg Day
    stem = Path(filename).stem
    parts = stem.split("_")
    if len(parts) < 2 or parts[0] != "day":
        return stem
    nn = parts[1].zfill(2)
    desc = _title_case_tokens(parts[2:]) if len(parts) > 2 else ""
    return f"Day {nn} - {desc}" if desc else f"Day {nn}"


def day_sort_key(path: Path) -> int:
    parts = path.stem.split("_")
    try:
        return int(parts[1])
    except (IndexError, ValueError):
        return 9999


# ── Markdown to Notion blocks ─────────────────────────────────────────────────

def _rt(text):
    return [{"type": "text", "text": {"content": text}}]


def _rt_link(text, url):
    return [{"type": "text", "text": {"content": text, "link": {"url": url}}}]


def _block(btype, text, rich=None):
    rich = rich if rich is not None else _rt(text)
    return {"object": "block", "type": btype, btype: {"rich_text": rich}}


def _strip_frontmatter(text: str) -> str:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "\n".join(lines[i + 1:])
    return text


_URL_RE = re.compile(r"https?://\S+")


def _paragraph_block(text: str):
    m = re.match(r"^(Video URL:\s*)(\S+)\s*$", text)
    if m:
        prefix, url = m.group(1), m.group(2)
        rich = [
            {"type": "text", "text": {"content": prefix}},
            {"type": "text", "text": {"content": url, "link": {"url": url}}},
        ]
        return {"object": "block", "type": "paragraph", "paragraph": {"rich_text": rich}}
    return _block("paragraph", text)


def markdown_to_blocks(md: str) -> list:
    md = _strip_frontmatter(md)
    lines = md.splitlines()
    blocks = []
    # track nesting for bullets: list of (indent, block)
    bullet_stack = []  # entries: (indent_level, block_dict)

    def flush_bullet_stack():
        bullet_stack.clear()

    for raw in lines:
        line = raw.rstrip()
        if not line.strip():
            flush_bullet_stack()
            continue

        # Headings
        m = re.match(r"^(#{1,3})\s+(.+)$", line)
        if m:
            flush_bullet_stack()
            level = len(m.group(1))
            text = m.group(2).strip()
            blocks.append(_block(f"heading_{level}", text))
            continue

        # Numbered list
        m = re.match(r"^(\s*)(\d+)\.\s+(.+)$", line)
        if m:
            flush_bullet_stack()
            text = m.group(3).strip()
            blocks.append(_block("numbered_list_item", text))
            continue

        # Bullet (handle nesting via leading whitespace)
        m = re.match(r"^(\s*)-\s+(.+)$", line)
        if m:
            indent = len(m.group(1))
            text = m.group(2).strip()
            new_block = _block("bulleted_list_item", text)
            # collapse stack down to entries with indent < current
            while bullet_stack and bullet_stack[-1][0] >= indent:
                bullet_stack.pop()
            if bullet_stack:
                parent = bullet_stack[-1][1]
                parent["bulleted_list_item"].setdefault("children", []).append(new_block)
            else:
                blocks.append(new_block)
            bullet_stack.append((indent, new_block))
            continue

        # Plain paragraph
        flush_bullet_stack()
        blocks.append(_paragraph_block(line.strip()))

    return blocks


# ── Notion client + helpers ───────────────────────────────────────────────────

def _notion():
    try:
        from notion_client import Client
    except ImportError:
        print("ERROR: notion-client not installed. Run: python -m pip install notion-client python-dotenv")
        sys.exit(1)
    if not NOTION_TOKEN:
        print("ERROR: NOTION_TOKEN not set in .env.personal")
        sys.exit(1)
    return Client(auth=NOTION_TOKEN)


def _retry(fn, *args, **kwargs):
    delay = 1.0
    for attempt in range(5):
        try:
            return fn(*args, **kwargs)
        except Exception as e:
            msg = str(e)
            transient = any(s in msg for s in ("429", "500", "502", "503", "504", "conflict_error"))
            if attempt == 4 or not transient:
                raise
            time.sleep(delay)
            delay = min(delay * 2, 16)


def _find_child_page(client, parent_id: str, title: str):
    cursor = None
    target = title.strip()
    while True:
        kwargs = {"block_id": parent_id, "page_size": 100}
        if cursor:
            kwargs["start_cursor"] = cursor
        resp = _retry(client.blocks.children.list, **kwargs)
        for b in resp.get("results", []):
            if b.get("type") == "child_page":
                t = b.get("child_page", {}).get("title", "").strip()
                if t == target:
                    return b["id"]
        if not resp.get("has_more"):
            return None
        cursor = resp.get("next_cursor")


def _append_blocks(client, page_id: str, blocks: list):
    for i in range(0, len(blocks), 100):
        _retry(client.blocks.children.append, block_id=page_id, children=blocks[i:i + 100])


def _create_child_page(client, parent_id: str, title: str, blocks: list) -> str:
    page = _retry(
        client.pages.create,
        parent={"type": "page_id", "page_id": parent_id},
        properties={"title": {"title": _rt(title)}},
    )
    page_id = page["id"]
    if blocks:
        _append_blocks(client, page_id, blocks)
    return page_id


def _page_url(page_id: str) -> str:
    return f"https://www.notion.so/{page_id.replace('-', '')}"


# ── Program + day discovery ───────────────────────────────────────────────────

def _resolve_program_dir(slug: str) -> Path:
    p = PROGRAMS_DIR / slug
    if not p.is_dir():
        available = sorted([d.name for d in PROGRAMS_DIR.iterdir() if d.is_dir() and not d.name.startswith("_")])
        print(f"ERROR: program slug '{slug}' not found under {PROGRAMS_DIR}")
        print("Available slugs:")
        for s in available:
            print(f"  {s}")
        sys.exit(1)
    return p


def _day_files(program_dir: Path) -> list:
    files = [f for f in program_dir.glob("day_*.md")]
    return sorted(files, key=day_sort_key)


# ── Commands ──────────────────────────────────────────────────────────────────

def cmd_check(slug: str) -> int:
    program_dir = _resolve_program_dir(slug)
    title = program_title(slug)
    client = _notion()
    existing = _find_child_page(client, KILO_HUB_PAGE_ID, title)
    day_count = len(_day_files(program_dir))
    print(f"Program: {title}  ({day_count} day files)")
    if existing:
        print(f"Notion: EXISTS at {_page_url(existing)}")
        return 1
    print("Notion: not found under KILO hub.")
    return 0


def cmd_push(slug: str, resume: bool = False) -> int:
    program_dir = _resolve_program_dir(slug)
    title = program_title(slug)
    day_files = _day_files(program_dir)
    if not day_files:
        print(f"ERROR: no day_*.md files in {program_dir}")
        return 1

    client = _notion()
    existing = _find_child_page(client, KILO_HUB_PAGE_ID, title)

    if existing and not resume:
        print(f"ERROR: program page '{title}' already exists in Notion.")
        print(f"  {_page_url(existing)}")
        print("Delete it manually in Notion before re-running, or pass 'resume' to skip-existing.")
        return 1

    if existing:
        program_page_id = existing
        print(f"Resuming under existing program page: {_page_url(program_page_id)}")
    else:
        program_page_id = _create_child_page(client, KILO_HUB_PAGE_ID, title, [])
        print(f"Created program page: {_page_url(program_page_id)}")

    created = 0
    skipped = 0
    for path in day_files:
        d_title = day_title(path.name)
        if resume and _find_child_page(client, program_page_id, d_title):
            print(f"  SKIP  {d_title}")
            skipped += 1
            continue
        md = path.read_text(encoding="utf-8")
        blocks = markdown_to_blocks(md)
        _create_child_page(client, program_page_id, d_title, blocks)
        print(f"  ADD   {d_title}")
        created += 1

    print()
    print(f"Done. Program: {title}")
    print(f"  URL:     {_page_url(program_page_id)}")
    print(f"  Created: {created}")
    if resume:
        print(f"  Skipped: {skipped}")
    return 0


def main():
    parser = argparse.ArgumentParser(prog="kilo", description="Push workout programs to Notion KILO hub.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_push = sub.add_parser("push", help="Push a program to Notion.")
    p_push.add_argument("slug")
    p_push.add_argument("--resume", action="store_true", help="Skip existing day pages.")

    p_check = sub.add_parser("check", help="Check whether program page exists on Notion.")
    p_check.add_argument("slug")

    args = parser.parse_args()

    if args.command == "push":
        sys.exit(cmd_push(args.slug, resume=args.resume))
    elif args.command == "check":
        sys.exit(cmd_check(args.slug))


if __name__ == "__main__":
    main()
