#!/usr/bin/env python3
"""
theo_redteam.py - THEO Draft Refinement Pipeline
Cuts first draft to target length, then runs scribe_redteam coaching analysis.

Usage:
    python theo_redteam.py <notion_url>
"""

import argparse
import os
import sys
import json
import re
import datetime
from pathlib import Path

import anthropic
import duckdb
from notion_client import Client
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent.parent / '.env', override=True)

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
NOTION_TOKEN = os.getenv("NOTION_TOKEN")
TANK_DB_PATH = os.getenv("TANK_DB_PATH", "C:/Users/wgriffith2/Code/TANK/tank.ddb")

TANK_ROOT = Path(__file__).parent.parent
TEMP_DIR = TANK_ROOT / "lessons" / "temp"
SCRIBE_REDTEAM_PATH = Path(r"C:\Users\wgriffith2\Dropbox (Liberty University)\Agents\scribe_redteam.md")

SONNET = "claude-sonnet-4-6"

TOO_SHORT_THRESHOLD = 13000   # chars — flag as incomplete draft
TARGET_CHAR_HIGH = 17000      # chars — above this, run cut phase

notion = Client(auth=NOTION_TOKEN)
ai = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)


def _tank_conn():
    return duckdb.connect(TANK_DB_PATH)


def _extract_page_id(url: str) -> str:
    clean = url.rstrip("/").split("?")[0].replace("-", "")
    match = re.search(r"[a-f0-9]{32}", clean)
    if match:
        return match.group(0)
    raise ValueError(f"Cannot extract page ID from URL: {url}")


def _lookup_lesson(notion_url: str) -> dict:
    page_id_raw = _extract_page_id(notion_url)
    con = _tank_conn()
    row = con.execute(
        """SELECT id, title, draft, final_edited, notion_page_id, notion_url
           FROM lessons
           WHERE replace(notion_page_id, '-', '') = ?""",
        [page_id_raw]
    ).fetchone()
    con.close()
    if not row:
        raise ValueError(f"No lesson found in TANK for: {notion_url}")
    return {
        "id": row[0], "title": row[1], "draft": row[2],
        "final_edited": row[3], "notion_page_id": row[4], "notion_url": row[5],
    }


def _word_count(text: str) -> int:
    return len(text.split())


def _checkpoint_path(lesson_id: str) -> Path:
    TEMP_DIR.mkdir(parents=True, exist_ok=True)
    return TEMP_DIR / f"redteam_{lesson_id}.json"


def _load_checkpoint(lesson_id: str) -> dict:
    path = _checkpoint_path(lesson_id)
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            print(f"  Checkpoint found: {path.name}")
            return data
        except Exception:
            pass
    return {}


def _save_checkpoint(lesson_id: str, data: dict):
    _checkpoint_path(lesson_id).write_text(json.dumps(data, indent=2), encoding="utf-8")


def _tank_update(lesson_id: str, **fields):
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    con = _tank_conn()
    set_clauses = ", ".join(f"{k} = ?" for k in fields)
    values = list(fields.values()) + [now, lesson_id]
    con.execute(f"UPDATE lessons SET {set_clauses}, updated_at = ? WHERE id = ?", values)
    con.close()


def _rich_text(text: str, bold: bool = False, italic: bool = False) -> dict:
    text = text.replace("—", "-")
    return {
        "type": "text",
        "text": {"content": text},
        "annotations": {"bold": bold, "italic": italic},
    }


def _parse_inline(text: str) -> list:
    segments = []
    pattern = re.compile(r"(\*\*(.+?)\*\*|\*(.+?)\*|([^*]+))")
    for m in pattern.finditer(text):
        if m.group(2):
            segments.append(_rich_text(m.group(2), bold=True))
        elif m.group(3):
            segments.append(_rich_text(m.group(3), italic=True))
        elif m.group(4):
            segments.append(_rich_text(m.group(4)))
    return segments if segments else [_rich_text(text)]


def _markdown_to_blocks(md: str) -> list:
    blocks = []
    skip_h1 = True
    for line in md.splitlines():
        raw = line.rstrip()
        if not raw:
            continue
        if raw.startswith("# ") and skip_h1:
            skip_h1 = False
            continue
        if raw.startswith("### "):
            blocks.append({"type": "heading_3", "heading_3": {"rich_text": _parse_inline(raw[4:])}})
        elif raw.startswith("## "):
            blocks.append({"type": "heading_2", "heading_2": {"rich_text": _parse_inline(raw[3:])}})
        elif raw.startswith("# "):
            blocks.append({"type": "heading_1", "heading_1": {"rich_text": _parse_inline(raw[2:])}})
        elif re.match(r"^\s*[-*]\s+", raw):
            content = re.sub(r"^\s*[-*]\s+", "", raw)
            blocks.append({"type": "bulleted_list_item", "bulleted_list_item": {"rich_text": _parse_inline(content)}})
        elif raw.strip():
            blocks.append({"type": "paragraph", "paragraph": {"rich_text": _parse_inline(raw)}})
    return blocks


def _overwrite_notion_page(page_id: str, content: str):
    block_ids = []
    cursor = None
    while True:
        kwargs = {"block_id": page_id, "page_size": 100}
        if cursor:
            kwargs["start_cursor"] = cursor
        resp = notion.blocks.children.list(**kwargs)
        for block in resp.get("results", []):
            block_ids.append(block["id"])
        if not resp.get("has_more"):
            break
        cursor = resp.get("next_cursor")

    for bid in block_ids:
        try:
            notion.blocks.update(bid, archived=True)
        except Exception:
            pass

    blocks = _markdown_to_blocks(content)
    for i in range(0, len(blocks), 100):
        notion.blocks.children.append(page_id, children=blocks[i:i + 100])


def run_step1_cut(lesson: dict) -> str:
    print("Step 1: Running cut pass (Claude Sonnet)...")
    draft = lesson["final_edited"] or lesson["draft"]

    cut_prompt = f"""You are editing a Bible study lesson manuscript. Cut it to approximately 2,500 words (15,000-17,000 characters).

CUTTING PRIORITIES (in order):
1. Content loops - remove any place where the same concept, illustration, or fact appears twice. Keep the stronger instance.
2. Stacked illustrations - if two illustrations make the same single point, cut the weaker one.
3. Over-explained transitions - trim verbose bridge sentences between sections.

DO NOT CUT:
- Scripture references or direct Bible quotes
- Section headers and structure
- The conclusion and call to action
- The Gypsy Smith / chalk circle story (high-impact)
- Discussion questions at the end

Return ONLY the revised lesson text. No preamble, no explanation, no commentary before or after.

LESSON:
{draft}"""

    response = ai.messages.create(
        model=SONNET,
        max_tokens=8192,
        messages=[{"role": "user", "content": cut_prompt}]
    )
    refined = response.content[0].text.strip()

    _tank_update(lesson["id"], final_edited=refined)
    print(f"  Saved to TANK final_edited ({len(refined):,} chars / {_word_count(refined):,} words)")

    print(f"  Overwriting Notion page...")
    _overwrite_notion_page(lesson["notion_page_id"], refined)
    print("  Notion page updated.")

    return refined


def run_step2_analysis(lesson: dict, draft_text: str):
    print("\nStep 2: Running redteam analysis (Claude Sonnet)...")

    scribe_prompt = SCRIBE_REDTEAM_PATH.read_text(encoding="utf-8")

    analysis_prompt = f"""{scribe_prompt}

ADDITIONAL INSTRUCTION: Output only Sections 1 through 4. Do NOT output Section 5 (One Thing to Fix).

LESSON TO ANALYZE:
{draft_text}"""

    response = ai.messages.create(
        model=SONNET,
        max_tokens=4096,
        messages=[{"role": "user", "content": analysis_prompt}]
    )
    feedback = response.content[0].text.strip()

    _tank_update(lesson["id"], redteam_feedback=feedback)
    print("  Saved to TANK redteam_feedback.")

    print("\n" + "=" * 60)
    print("REDTEAM ANALYSIS")
    print("=" * 60)
    print(feedback.encode("utf-8", errors="replace").decode("utf-8"))


def main():
    parser = argparse.ArgumentParser(description="THEO Redteam - Draft Refinement Pipeline")
    parser.add_argument("notion_url", help="Notion FULL page URL for the lesson")
    args = parser.parse_args()

    print(f"Looking up lesson...")
    lesson = _lookup_lesson(args.notion_url)
    print(f"Found: {lesson['title']} ({lesson['id']})")

    draft = lesson["final_edited"] or lesson["draft"]
    if not draft:
        print("ERROR: No draft or final_edited found in TANK for this lesson.")
        sys.exit(1)

    source_label = "final_edited" if lesson["final_edited"] else "draft"
    char_count = len(draft)
    word_count = _word_count(draft)
    print(f"\nStep 0: Word Count Gate")
    print(f"  Source: {source_label} ({char_count:,} chars / {word_count:,} words)")

    if char_count < TOO_SHORT_THRESHOLD:
        print(f"  STOP: Draft is too short ({char_count:,} < {TOO_SHORT_THRESHOLD:,} chars).")
        print("  Re-investigate the first draft before running redteam.")
        sys.exit(1)
    elif char_count <= TARGET_CHAR_HIGH:
        print(f"  Draft is within target range. Skipping cut phase.")
        skip_cuts = True
    else:
        print(f"  Draft exceeds target ({char_count:,} > {TARGET_CHAR_HIGH:,} chars). Running cut phase.")
        skip_cuts = False

    checkpoint = _load_checkpoint(lesson["id"])

    if not skip_cuts:
        if checkpoint.get("step1_complete"):
            print("Step 1: Already complete (checkpoint). Skipping.")
            refined = checkpoint.get("refined_draft") or lesson.get("final_edited") or draft
        else:
            refined = run_step1_cut(lesson)
            checkpoint["step1_complete"] = True
            checkpoint["refined_draft"] = refined
            _save_checkpoint(lesson["id"], checkpoint)
    else:
        refined = draft

    if checkpoint.get("step2_complete"):
        print("Step 2: Already complete (checkpoint). Skipping.")
    else:
        run_step2_analysis(lesson, refined)
        checkpoint["step2_complete"] = True
        _save_checkpoint(lesson["id"], checkpoint)

    _checkpoint_path(lesson["id"]).unlink(missing_ok=True)
    print("\nRedteam pipeline complete.")


if __name__ == "__main__":
    main()
