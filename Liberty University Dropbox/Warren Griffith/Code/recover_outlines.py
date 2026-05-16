#!/usr/bin/env python3
"""
recover_outlines.py - Recover lesson outlines from Notion to Construct.
Pulls all outlines from THEO_NOTION_DB and saves as markdown files.

Usage:
    python recover_outlines.py
"""

import os
import sys
import re
import json
import datetime
from pathlib import Path
from dotenv import load_dotenv
from notion_client import Client

env_path = Path(__file__).parent / '.env'
if not env_path.exists():
    env_path = Path.home() / 'Code' / '.env'
load_dotenv(env_path, override=True)

NOTION_TOKEN = os.getenv("NOTION_TOKEN")
if not NOTION_TOKEN:
    raise ValueError("NOTION_TOKEN not found in .env file")
CONSTRUCT_ROOT = Path("C:/Users/wgriffith2/Dropbox (Liberty University)/Construct")
OUTLINES_DIR = CONSTRUCT_ROOT / "wiki" / "theology" / "outlines"

THEO_NOTION_DB = "292ee045-d5ec-8024-bd94-e7fc3768bf0c"

notion = Client(auth=NOTION_TOKEN)

_BIBLE_BOOKS = {
    "genesis": ("GEN", ["gen", "ge"]),
    "exodus": ("EXO", ["exo", "ex"]),
    "leviticus": ("LEV", ["lev", "le"]),
    "numbers": ("NUM", ["num", "nu"]),
    "deuteronomy": ("DEU", ["deu", "deut", "dt"]),
    "joshua": ("JOS", ["jos", "josh"]),
    "judges": ("JDG", ["jdg", "judg"]),
    "ruth": ("RUT", ["rut", "ru"]),
    "1 samuel": ("1SA", ["1sa", "1sam", "1 sam"]),
    "2 samuel": ("2SA", ["2sa", "2sam", "2 sam"]),
    "1 kings": ("1KI", ["1ki", "1kgs", "1 kgs"]),
    "2 kings": ("2KI", ["2ki", "2kgs", "2 kgs"]),
    "1 chronicles": ("1CH", ["1ch", "1chr", "1 chr"]),
    "2 chronicles": ("2CH", ["2ch", "2chr", "2 chr"]),
    "ezra": ("EZR", ["ezr"]),
    "nehemiah": ("NEH", ["neh"]),
    "esther": ("EST", ["est", "esth"]),
    "job": ("JOB", ["job"]),
    "psalms": ("PSA", ["psa", "ps", "psalm"]),
    "proverbs": ("PRO", ["pro", "prov"]),
    "ecclesiastes": ("ECC", ["ecc", "eccl"]),
    "song of solomon": ("SNG", ["sng", "song", "sos"]),
    "isaiah": ("ISA", ["isa"]),
    "jeremiah": ("JER", ["jer"]),
    "lamentations": ("LAM", ["lam"]),
    "ezekiel": ("EZK", ["ezk", "eze", "ezek"]),
    "daniel": ("DAN", ["dan"]),
    "hosea": ("HOS", ["hos"]),
    "joel": ("JOL", ["jol", "joe"]),
    "amos": ("AMO", ["amo"]),
    "obadiah": ("OBA", ["oba", "ob"]),
    "jonah": ("JON", ["jon"]),
    "micah": ("MIC", ["mic"]),
    "nahum": ("NAH", ["nah"]),
    "habakkuk": ("HAB", ["hab"]),
    "zephaniah": ("ZEP", ["zep", "zeph"]),
    "haggai": ("HAG", ["hag"]),
    "zechariah": ("ZEC", ["zec", "zech"]),
    "malachi": ("MAL", ["mal"]),
    "matthew": ("MAT", ["mat", "matt"]),
    "mark": ("MRK", ["mrk", "mk"]),
    "luke": ("LUK", ["luk", "lk"]),
    "john": ("JHN", ["jhn", "jn"]),
    "acts": ("ACT", ["act"]),
    "romans": ("ROM", ["rom"]),
    "1 corinthians": ("1CO", ["1co", "1cor", "1 cor"]),
    "2 corinthians": ("2CO", ["2co", "2cor", "2 cor"]),
    "galatians": ("GAL", ["gal"]),
    "ephesians": ("EPH", ["eph"]),
    "philippians": ("PHP", ["php", "phil"]),
    "colossians": ("COL", ["col"]),
    "1 thessalonians": ("1TH", ["1th", "1thes", "1 thes"]),
    "2 thessalonians": ("2TH", ["2th", "2thes", "2 thes"]),
    "1 timothy": ("1TI", ["1ti", "1tim", "1 tim"]),
    "2 timothy": ("2TI", ["2ti", "2tim", "2 tim"]),
    "titus": ("TIT", ["tit"]),
    "philemon": ("PHM", ["phm", "phlm"]),
    "hebrews": ("HEB", ["heb"]),
    "james": ("JAS", ["jas"]),
    "1 peter": ("1PE", ["1pe", "1pet", "1 pet"]),
    "2 peter": ("2PE", ["2pe", "2pet", "2 pet"]),
    "1 john": ("1JN", ["1jn", "1jo"]),
    "2 john": ("2JN", ["2jn", "2jo"]),
    "3 john": ("3JN", ["3jn", "3jo"]),
    "jude": ("JUD", ["jud"]),
    "revelation": ("REV", ["rev"]),
}


def extract_scripture_from_summary(summary: str) -> str:
    """Extract scripture reference from Summary field (e.g., 'Core Scripture: Nehemiah 1')."""
    match = re.search(r"Core Scripture[^:]*:\s*(.+?)(?:\n|$)", summary)
    if match:
        return match.group(1).strip()
    return ""


def scripture_to_slug(reference: str) -> str:
    """Convert 'Nehemiah 1' to 'neh_1'."""
    reference_lower = reference.lower().strip()

    for full_name, (slug, abbrevs) in _BIBLE_BOOKS.items():
        if reference_lower.startswith(full_name):
            match = re.search(r"\d+", reference_lower)
            if match:
                chapter = match.group(0)
                return f"{slug.lower()}-{chapter}"
            for abbr in abbrevs:
                if reference_lower.startswith(abbr):
                    match = re.search(r"\d+", reference_lower)
                    if match:
                        chapter = match.group(0)
                        return f"{slug.lower()}-{chapter}"

    return None


def notion_blocks_to_markdown(blocks: list) -> str:
    """Convert Notion blocks to markdown."""
    md_parts = []

    for block in blocks:
        block_type = block.get("type")

        if block_type == "heading_1":
            text = _extract_rich_text(block.get("heading_1", {}).get("rich_text", []))
            md_parts.append(f"# {text}")
        elif block_type == "heading_2":
            text = _extract_rich_text(block.get("heading_2", {}).get("rich_text", []))
            md_parts.append(f"## {text}")
        elif block_type == "heading_3":
            text = _extract_rich_text(block.get("heading_3", {}).get("rich_text", []))
            md_parts.append(f"### {text}")
        elif block_type == "paragraph":
            text = _extract_rich_text(block.get("paragraph", {}).get("rich_text", []))
            if text:
                md_parts.append(text)
        elif block_type == "bulleted_list_item":
            text = _extract_rich_text(block.get("bulleted_list_item", {}).get("rich_text", []))
            md_parts.append(f"- {text}")
        elif block_type == "numbered_list_item":
            text = _extract_rich_text(block.get("numbered_list_item", {}).get("rich_text", []))
            md_parts.append(f"1. {text}")
        elif block_type == "quote":
            text = _extract_rich_text(block.get("quote", {}).get("rich_text", []))
            md_parts.append(f"> {text}")
        elif block_type == "divider":
            md_parts.append("---")

    return "\n\n".join(md_parts)


def _extract_rich_text(rich_text_list: list) -> str:
    """Extract text from Notion rich_text array, preserving bold/italic."""
    parts = []
    for rt in rich_text_list:
        if rt.get("type") == "text":
            text = rt.get("text", {}).get("content", "")
            annotations = rt.get("annotations", {})

            if annotations.get("bold"):
                text = f"**{text}**"
            if annotations.get("italic"):
                text = f"*{text}*"
            if annotations.get("code"):
                text = f"`{text}`"

            parts.append(text)

    return "".join(parts)


def recover_outlines():
    """Fetch all outlines from Notion database and save as markdown."""
    OUTLINES_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Fetching outlines from Notion database: {THEO_NOTION_DB}")

    all_pages = []
    cursor = None

    while True:
        search_params = {
            "query": "",
            "filter": {
                "value": "page",
                "property": "object"
            },
            "page_size": 100,
        }
        if cursor:
            search_params["start_cursor"] = cursor

        response = notion.search(**search_params)

        # Filter results to only include pages from THEO_NOTION_DB
        for result in response.get("results", []):
            parent = result.get("parent", {})
            if parent.get("database_id") == THEO_NOTION_DB:
                all_pages.append(result)

        if not response.get("has_more"):
            break
        cursor = response.get("next_cursor")

    print(f"Found {len(all_pages)} outlines in Notion")

    recovered = 0
    skipped = 0

    for page in all_pages:
        page_id = page["id"]
        properties = page.get("properties", {})

        lesson_title = ""
        if "Lesson" in properties:
            title_prop = properties["Lesson"].get("title", [])
            lesson_title = _extract_rich_text(title_prop) if title_prop else ""

        date_str = None
        if "Date" in properties:
            date_obj = properties["Date"].get("date", {})
            if date_obj:
                date_str = date_obj.get("start", "")

        summary = ""
        if "Summary" in properties:
            summary_prop = properties["Summary"].get("rich_text", [])
            summary = _extract_rich_text(summary_prop) if summary_prop else ""

        scripture = extract_scripture_from_summary(summary)
        if not scripture:
            print(f"SKIP: {lesson_title} (no scripture reference in summary)")
            skipped += 1
            continue

        slug = scripture_to_slug(scripture)
        if not slug:
            print(f"SKIP: {lesson_title} - {scripture} (could not parse scripture)")
            skipped += 1
            continue

        if not date_str:
            print(f"SKIP: {lesson_title} (no date)")
            skipped += 1
            continue

        dt = date_str.replace("-", "")
        slug_lower = slug.lower().replace("-", "_")
        outline_filename = f"{dt}_{slug_lower}.md"
        outline_path = OUTLINES_DIR / outline_filename

        print(f"Recovering: {lesson_title} -> {outline_filename}")

        # Try to get outline from Summary property first (new format)
        markdown_content = ""
        if "Summary" in properties:
            summary_prop = properties["Summary"].get("rich_text", [])
            if summary_prop:
                markdown_content = _extract_rich_text(summary_prop)

        # Fallback to page blocks if Summary is empty (old format)
        if not markdown_content:
            blocks_resp = notion.blocks.children.list(page_id)
            blocks = blocks_resp.get("results", [])
            markdown_content = notion_blocks_to_markdown(blocks)

        book = slug.split("-")[0].lower()
        series = ""
        if "Study Series" in properties:
            series_prop = properties["Study Series"].get("select")
            if series_prop:
                series = series_prop.get("name", "").lower().replace(" ", "-")

        tags = ["outline", book]
        if series:
            tags.append(series)
        tags_str = json.dumps(tags)

        frontmatter = f"---\ndomain: theology\ntype: outline\ndate: {dt}\nupdated: {dt}\ntags: {tags_str}\nsources: []\n---\n\n"

        full_content = frontmatter + markdown_content
        outline_path.write_text(full_content, encoding="utf-8")

        sidecar = {
            "outline_notion_page_id": page_id.replace("-", "")
        }
        sidecar_path = outline_path.with_suffix(".json")
        sidecar_path.write_text(json.dumps(sidecar), encoding="utf-8")

        recovered += 1

    print(f"\nRecovery complete!")
    print(f"Recovered: {recovered}")
    print(f"Skipped: {skipped}")
    print(f"Outlines saved to: {OUTLINES_DIR}")


if __name__ == "__main__":
    recover_outlines()
