#!/usr/bin/env python3
"""
theo_outline.py - THEO Lesson Outline Pipeline
Transforms sermon transcripts into structured lesson outlines saved to Construct.

Usage:
    python theo_outline.py prep <transcript_path> --series <series> [--speaker <speaker>]
    python theo_outline.py plan <transcript_path> [--date YYYY-MM-DD]
    python theo_outline.py repush-outline <outline_path>
"""

import argparse
import os
import sys
import re
import datetime
import json
from pathlib import Path

import anthropic
from notion_client import Client
from dotenv import load_dotenv

load_dotenv(r"C:\Users\wgriffith2\.claude\.env.personal", override=True)

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
NOTION_TOKEN = os.getenv("NOTION_TOKEN")

CONSTRUCT_ROOT = Path("C:/Users/wgriffith2/Dropbox (Liberty University)/Construct")
OUTLINES_DIR = CONSTRUCT_ROOT / "wiki" / "theology" / "outlines"

THEO_NOTION_DB = "292ee045-d5ec-8024-bd94-e7fc3768bf0c"
THEO_HUB_PAGE_ID = os.getenv("THEO_HUB_PAGE_ID", "292ee045d5ec8011b6cbf876d6b301e1")

OPUS = "claude-opus-4-7"
HAIKU = "claude-haiku-4-5-20251001"

notion = Client(auth=NOTION_TOKEN)


def ensure_dirs():
    OUTLINES_DIR.mkdir(parents=True, exist_ok=True)


# ============================================================
# PROMPTS
# ============================================================

OUTLINE_SYSTEM = """
PURPOSE: Generate Contemporary Bible Study Lesson Outline (Deep Extraction Mode)

Your Role: You are the Guardian of the Source Material. You are a Senior Homiletics Architect specializing in the forensic analysis of sermons.

The Stake: The writer who comes after you will NOT see the original transcript. They will only see your outline. If you summarize a specific quote, a Greek definition, or a historical fact into a generic bullet point, it is lost forever. Your goal is not just structure; it is Data Preservation.

Input: A sermon transcript with a header containing metadata (Title, URL, Duration, etc.).

Goal: Produce a structured 3-Point Outline that acts as a Data-Heavy repository of the sermon's best content. Capture specific phrasing, historical details, and theological logic.

CHAIN OF THOUGHT (Deep Data Audit):
1. Identify the Gold: Locate exact sentences where the speaker delivers punchlines, definitions, or critical insights.
2. Isolate Contextual Assets: Scan for specific historical details (dates, geography, customs), linguistic details (Greek/Hebrew word definitions), narrative details (unique story mechanics). These are Critical Assets - extract, do not summarize.
3. Trace the Logic: How does the speaker move from Problem -> Solution -> Response? Ensure your 3 Main Points mirror this arc.
4. Select Sticky Phrasing: If the speaker uses a unique metaphor or catchy phrase, preserve it exactly. Do not flatten it.

CORE INSTRUCTIONS:

1. Header Data Extraction:
   - URL: Look for the URL in the input header. If blank or missing, write "n/a".
   - Title: Extract the sermon title (usually the first line starting with #).

2. High-Fidelity Extraction (No Fluff Rule):
   - Direct Quotes > Summaries: Use the speaker's exact wording whenever possible.
   - Specifics > Generalities: Never write "The speaker gives an illustration about work." Describe the specific mechanics.
   - The N/A Rule: If a specific section has no corresponding element in the text, write "N/A". Do not fabricate content.

3. Structural Adaptation (Rule of Three):
   - Organize content into exactly Three Main Points.
   - Consolidation: Group multiple points logically.
   - Expansion: If the transcript is a continuous narrative, divide logically (Problem, Solution, Response).

4. Handling Illustrations & Anecdotes:
   - Identify personal stories or specific anecdotes.
   - Sanitize: Remove names of speaker's children or hyper-specific personal details a small group leader could not retell.
   - Preserve the Core: Keep the mechanics of the illustration intact.

5. The Equipping Pivot (Conclusion Strategy):
   - Re-frame the Altar Call: Do not simply ask "Do you want to get saved?" (The audience is believers).
   - From Conversion to Commission: Transform the closing appeal into an apologetic tool. Equip the student to take this theological lesson and use it to explain the Gospel to others.

OUTPUT FORMAT:
Use exactly this template:

**Title:** [Extract Title from input header]
**URL:** [Extract URL from input. If missing or blank, write "n/a"]
**Resource Type:** Sermon
**Study Series:** [Series Name or "n/a"]
**Speaker/Author:** [Speaker Name from the input header or pulled from transcript or "n/a"]

**Core Scripture Passage(s):** [CRITICAL: List the PRIMARY Reading Text FIRST. Follow with supplementary verses separated by semicolons. Use Christian Standard Bible (CSB) version.]
**Lesson Thesis/Main Idea:** [1-2 sentence summary of the sermon's core argument]

**  Introduction & Prayer: [Clear Topic Sentence - 3 words or less]**
    A. **Opening Prayer Guide:** [DO NOT write a verbatim prayer. Instead, provide 1-2 sentences instructing the leader on specific spiritual outcomes to seek. Start sentences with "Pray for..." or "Ask God to..."]
    B. **Contextual Overview:** [Extract specific historical/cultural context here. If the speaker mentions specific geography, customs, or laws, it MUST go here. Do not write a generic summary.]  

**  Main Point 1: [Clear Topic Sentence - 3 words or less]**
    A. **Scriptural Basis:** [Key verse(s) + concise explanation of the speaker's interpretation]
    B. **Theological Insight/Deeper Implication:** [Summarize the core theological exploration. Capture the depth.]
    C. **Generalized Illustration/Modern Relevance:**
        * Illustration 1a: [DATA PRESERVATION: Extract the specific illustration. Describe the mechanics of the story/analogy.]
    D. **Supporting Idea(s):**
        * Idea 1a: [Name of Author: "Exact Quote mentioned in transcript"]
    E. **Supporting Verse(s):**
        * Verse 1a: [Citation: Text of verse]
    F. **Sub-points:** [THE GOLD MINE: This section must be dense with direct quotes.]
        * Sub-point 1a: [Direct Quote/Paraphrase: Capture the specific logic/phrasing.]
        * Sub-point 1b: [Direct Quote/Paraphrase: Capture the specific logic/phrasing.]
        * (Include as many as needed to fully capture the argument)
    G. **Transition to Next Point:** [Logical bridge to the next section]

**  Main Point 2: [Clear Topic Sentence - 3 words or less]**
    A. **Scriptural Basis:** [Key verse(s) + concise explanation]
    B. **Theological Insight/Deeper Implication:** [Summarize the core exploration]
    C. **Generalized Illustration/Modern Relevance:**
        * Illustration 2a: [DATA PRESERVATION: Extract the specific illustration. Use exact wording.]
    D. **Supporting Idea(s):**
        * Idea 2a: [Name of Author: "Exact Quote"]
    E. **Supporting Verse(s):**
        * Verse 2a: [Citation: Text of verse]
    F. **Sub-points:** [THE GOLD MINE]
        * Sub-point 2a: [Direct Quote/Paraphrase: Capture the specific logic/phrasing.]
        * Sub-point 2b: [Direct Quote/Paraphrase: Capture the specific logic/phrasing.]
        * (Include as many as needed)
    G. **Transition to Next Point:** [Logical bridge]

**  Main Point 3: [Clear Topic Sentence - 3 words or less]**
    A. **Scriptural Basis:** [Key verse(s) + concise explanation]
    B. **Theological Insight/Deeper Implication:** [Summarize the core exploration]
    C. **Generalized Illustration/Modern Relevance:**
        * Illustration 3a: [DATA PRESERVATION: Extract the specific illustration. Use exact wording.]
    D. **Supporting Idea(s):**
        * Idea 3a: [Name of Author: "Exact Quote"]
    E. **Supporting Verse(s):**
        * Verse 3a: [Citation: Text of verse]
    F. **Sub-points:** [THE GOLD MINE]
        * Sub-point 3a: [Direct Quote/Paraphrase: Capture the specific logic/phrasing.]
        * Sub-point 3b: [Direct Quote/Paraphrase: Capture the specific logic/phrasing.]
        * (Include as many as needed)
    G. **Transition to Conclusion:** [Logical bridge]

**  Conclusion: [Clear Conclusion Sentence - 3 words or less]**
    A. **Conclusion:** [Super brief statement that leads to the closing prayer that does not rehash anything we talked about already]
    B. **Closing Prayer Guide:** [DO NOT write a verbatim prayer. Instead, provide 1-2 sentences that guides the leader on application and repentance. Start sentences with "Pray for..." or "Ask God for..."]
"""

TITLE_PROMPT = """ROLE: Theological Copywriter (Tim Keller Style).
TASK: Write a Main Title for this lesson.
STYLE: High-Impact, Relatable
CONSTRAINTS:
1. Fewer than 50 characters (count carefully).
2. Title Case (capitalize major words, not articles/prepositions unless first word).
3. Output ONLY the title text. No markdown formatting. No ALL CAPS.

INPUT CONTEXT:
{outline}
"""

SLUG_PROMPT = """TASK: Convert the scripture reference "{reference}" into a short filename slug.

RULES:
1. Format: [3-4 LETTER UPPERCASE BOOK]-[CHAPTER]
2. Remove spaces, add hyphen.
3. Examples:
   - "1 Kings 18" -> "1KNG-18"
   - "Matthew 2" -> "MAT-2"
   - "Ephesians 1" -> "EPH-1"
   - "Psalms 139" -> "PSA-139"
   - "Revelation 2" -> "REV-2"
   - "Jeremiah 21" -> "JER-21"
4. Output ONLY the slug text. No other words.
"""


# ============================================================
# CLAUDE API CALLS
# ============================================================

def get_client():
    return anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)


def generate_outline(transcript_text: str) -> str:
    client = get_client()
    response = client.messages.create(
        model=OPUS,
        max_tokens=16000,
        thinking={"type": "adaptive"},
        output_config={"effort": "high"},
        system=OUTLINE_SYSTEM,
        messages=[{"role": "user", "content": transcript_text}],
    )
    return next((b.text for b in response.content if b.type == "text"), "")


def extract_title(outline: str) -> str:
    client = get_client()
    response = client.messages.create(
        model=HAIKU,
        max_tokens=50,
        messages=[{"role": "user", "content": TITLE_PROMPT.format(outline=outline)}],
    )
    title = response.content[0].text.strip()
    if title == title.upper():
        title = title.title()
    if len(title) > 50:
        title = title[:50].rsplit(" ", 1)[0]
    return title


def extract_primary_scripture(outline: str) -> str:
    match = re.search(r"\*\*Core Scripture Passage\(s\):\*\*\s*(.+)", outline)
    if match:
        raw = match.group(1).strip()
        return raw.split(";")[0].strip()
    return ""


def extract_full_scripture(outline: str) -> str:
    match = re.search(r"\*\*Core Scripture Passage\(s\):\*\*\s*(.+)", outline)
    if match:
        return match.group(1).strip()
    return ""


def extract_lesson_thesis(outline: str) -> str:
    match = re.search(r"\*\*Lesson Thesis/Main Idea:\*\*\s*(.+?)(?=\n\n|\*\*|$)", outline, re.DOTALL)
    if match:
        return match.group(1).strip()
    return ""


def scripture_to_slug(reference: str) -> str:
    client = get_client()
    response = client.messages.create(
        model=HAIKU,
        max_tokens=20,
        messages=[{"role": "user", "content": SLUG_PROMPT.format(reference=reference)}],
    )
    return response.content[0].text.strip()


# ============================================================
# CONSTRUCT HELPERS
# ============================================================

def _outline_filename(slug: str, date_str: str) -> str:
    """Convert 'NEH-1' + '2026-05-18' to '20260518_neh_1.md'."""
    dt = date_str.replace("-", "") if date_str else datetime.date.today().isoformat().replace("-", "")
    slug_lower = slug.lower().replace("-", "_")
    return f"{dt}_{slug_lower}.md"


def _build_frontmatter(date_str: str, slug: str, transcript_path: str, series: str = "") -> str:
    dt = date_str.replace("-", "") if date_str else datetime.date.today().isoformat().replace("-", "")
    book = slug.split("-")[0].lower()
    tags = ["outline", book]
    if series:
        tags.append(re.sub(r"[^a-z0-9]+", "-", series.lower()).strip("-"))
    tags_str = json.dumps(tags)
    return f"---\ndomain: theology\ntype: outline\ndate: {dt}\nupdated: {dt}\ntags: {tags_str}\nsources: [\"{transcript_path}\"]\n---\n\n"


def _strip_frontmatter(md: str) -> str:
    if not md.startswith("---"):
        return md
    # Find closing --- on its own line (not inside YAML string values)
    m = re.search(r"(?m)^---\s*$", md[3:])
    if m:
        return md[3 + m.end():].lstrip("\n")
    return md


def _strip_for_notion(md: str) -> str:
    """Strip YAML frontmatter, metadata header block, and markdown syntax for Notion plain text."""
    text = _strip_frontmatter(md)

    # Skip metadata header lines (Title, URL, Resource Type, Study Series, Speaker/Author + blanks/hr)
    metadata_keys = ("**Title:**", "**URL:**", "**Resource Type:**", "**Study Series:**", "**Speaker/Author:**")
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        if not stripped or stripped == "---" or any(stripped.startswith(k) for k in metadata_keys):
            i += 1
        else:
            break
    text = "\n".join(lines[i:])

    # Strip markdown syntax
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)               # bold
    text = re.sub(r"\*(.+?)\*", r"\1", text)                   # italic
    text = re.sub(r"^#{1,6}\s+", "", text, flags=re.MULTILINE) # headings
    text = re.sub(r"^---+\s*$", "", text, flags=re.MULTILINE)  # horizontal rules

    return text.strip()


# ============================================================
# SIDECAR
# ============================================================

def _save_sidecar(outline_path: Path, outline_notion_page_id: str = None):
    data = {}
    if outline_notion_page_id:
        data["outline_notion_page_id"] = outline_notion_page_id
    sidecar = outline_path.with_suffix(".json")
    sidecar.write_text(json.dumps(data), encoding="utf-8")


# ============================================================
# NOTION PUSH
# ============================================================

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


def markdown_to_notion_blocks(md: str) -> list:
    blocks = []
    lines = _strip_frontmatter(md).splitlines()
    skip_h1 = True

    for line in lines:
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


def _append_blocks(page_id: str, blocks: list):
    notion.blocks.children.append(page_id, children=blocks)


def _chunk_rich_text(text: str, chunk_size: int = 1990) -> list:
    """Split large text into Notion rich_text array (2000 char limit per object)."""
    chunks = []
    while text:
        chunks.append({"type": "text", "text": {"content": text[:chunk_size]}})
        text = text[chunk_size:]
    return chunks


def _extract_url_from_outline(outline: str) -> str | None:
    match = re.search(r"\*\*URL:\*\*\s*(.+)", outline)
    if match:
        url = match.group(1).strip()
        return None if url.lower() in ("n/a", "") else url
    return None


def push_outline_to_notion(outline_path: Path, title: str, scripture: str, full_scripture: str = "", date_str: str = None, speaker: str = "", series: str = "", thesis: str = "") -> str:
    md = outline_path.read_text(encoding="utf-8")
    outline_raw = _strip_frontmatter(md)   # for URL extraction (still has **URL:** line)
    outline_clean = _strip_for_notion(md)  # plain text for Notion property display
    page_date = date_str or datetime.date.today().isoformat()

    properties = {
        "Lesson Name": {"title": [{"text": {"content": title}}]},
        "Lesson Date": {"date": {"start": page_date}},
        "Lesson Type": {"select": {"name": "Sermon"}},
        "Outline": {"rich_text": _chunk_rich_text(outline_clean)},
    }
    if speaker:
        properties["Source Name"] = {"select": {"name": speaker}}
    if series:
        properties["Series Name"] = {"select": {"name": series}}

    url = _extract_url_from_outline(outline_raw)
    if url:
        properties["Link"] = {"url": url}

    page = notion.pages.create(
        parent={"database_id": THEO_NOTION_DB},
        properties=properties,
    )

    # Append "OUTLINE ONLY" placeholder at bottom (will be replaced by theo-push with final draft)
    _append_blocks(page["id"], [{"type": "paragraph", "paragraph": {"rich_text": [_rich_text("OUTLINE ONLY")]}}])

    return page["id"]


# ============================================================
# TRANSCRIPT PREPROCESSING
# ============================================================

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


def _regex_scan(text: str) -> tuple:
    sample = text[:2000].lower()
    all_names = []
    for full_name, (slug, abbrevs) in _BIBLE_BOOKS.items():
        all_names.append((full_name, slug, full_name))
        for abbr in abbrevs:
            all_names.append((abbr, slug, full_name))
    all_names.sort(key=lambda x: len(x[0]), reverse=True)

    for name, slug, full_name in all_names:
        pattern = re.compile(r'\b' + re.escape(name) + r'\.?\s+(\d+)\b', re.IGNORECASE)
        m = pattern.search(sample)
        if m:
            chapter = int(m.group(1))
            display = full_name.title() + " " + str(chapter)
            return display, f"{slug}-{chapter}"
    return None, None


def _ai_scan(text: str, full: bool = False) -> tuple:
    sample = text if full else text[:500]
    client = get_client()
    prompt = (
        "What Bible book and chapter is this sermon/study about? "
        "Return ONLY: BookName Chapter (e.g. 'Nehemiah 1' or 'Romans 7'). "
        "If you cannot determine it, return exactly: UNKNOWN\n\n"
        f"{sample}"
    )
    response = client.messages.create(
        model=HAIKU,
        max_tokens=20,
        messages=[{"role": "user", "content": prompt}],
    )
    result = response.content[0].text.strip()
    if result.upper() == "UNKNOWN":
        return None, None
    m = re.match(r'^(.+?)\s+(\d+)$', result)
    if m:
        book_raw = m.group(1).strip()
        chapter = int(m.group(2))
        book_lower = book_raw.lower()
        for full_name, (slug, _) in _BIBLE_BOOKS.items():
            if full_name == book_lower or book_lower in full_name:
                display = full_name.title() + " " + str(chapter)
                return display, f"{slug}-{chapter}"
        display = book_raw.title() + " " + str(chapter)
        return display, f"{book_raw.upper()[:3]}-{chapter}"
    return None, None


def _resolve_book_chapter(text: str) -> tuple:
    title, slug = _regex_scan(text)
    if title:
        return title, slug
    title, slug = _ai_scan(text, full=False)
    if title:
        return title, slug
    title, slug = _ai_scan(text, full=True)
    if title:
        return title, slug
    return "Unknown", "UNKNOWN-0"


def _extract_series_from_transcript(text: str) -> str:
    match = re.search(r"\*\*Series:\*\*\s*(.+)", text)
    return match.group(1).strip() if match else ""


def _extract_speaker_from_header(text: str) -> str:
    match = re.search(r"\*\*Speaker:\*\*\s*(.+)", text)
    return match.group(1).strip() if match else ""


def _extract_url_from_transcript(text: str) -> str:
    patterns = [
        r'(?:link|url)\s*:\s*(https?://\S+)',
        r'(https?://(?:www\.)?youtube\.com/\S+)',
        r'(https?://youtu\.be/\S+)',
        r'(https?://\S+)',
    ]
    sample = text[:1000]
    for pattern in patterns:
        m = re.search(pattern, sample, re.IGNORECASE)
        if m:
            return m.group(1).strip().rstrip(')')
    return ""


def _extract_speaker_from_transcript(text: str) -> str:
    patterns = [
        r'Pastor\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)',
        r'(?:by|speaker|author|pastor)\s*[:\-]?\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)',
        r'//\s*([A-Z][a-z]+\s+[A-Z][a-z]+)\s*$',
    ]
    sample = text[:500]
    for pattern in patterns:
        m = re.search(pattern, sample, re.MULTILINE)
        if m:
            return m.group(1).strip()
    return ""


def _strip_prep_header(text: str) -> str:
    if not text.startswith("#"):
        return text
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        stripped = line.strip()
        if i > 0 and stripped and not stripped.startswith("#") and not stripped.startswith("**"):
            return "".join(lines[i:])
    return text


def _write_prep_header(path: Path, title: str, url: str, series: str, speaker: str):
    original = _strip_prep_header(path.read_text(encoding="utf-8"))
    url_line = f"**URL:** {url}" if url else "**URL:**"
    speaker_line = f"**Speaker:** {speaker}" if speaker else "**Speaker:**"
    header = f"# {title}\n\n{url_line}\n**Series:** {series}\n{speaker_line}\n\n"
    path.write_text(header + original, encoding="utf-8")


# ============================================================
# PIPELINE
# ============================================================

def run_prep(transcript_path: str, series: str, speaker: str = ""):
    src = Path(transcript_path)
    if not src.exists():
        print(f"Error: file not found: {transcript_path}")
        sys.exit(1)

    text = src.read_text(encoding="utf-8")
    url = _extract_url_from_transcript(text)
    resolved_speaker = speaker or _extract_speaker_from_transcript(text)
    title, slug = _resolve_book_chapter(text)
    _write_prep_header(src, title, url, series, resolved_speaker)

    speaker_out = resolved_speaker if resolved_speaker else "(none)"
    url_out = url if url else "(none)"
    print(f"OK {title} | Speaker: {speaker_out} | URL: {url_out} | Series: {series}")
    print(f"Header written to: {src.name}")


def run_plan(transcript_path: str, date_str: str = None):
    ensure_dirs()
    src = Path(transcript_path)
    if not src.exists():
        print(f"Error: transcript not found: {transcript_path}")
        sys.exit(1)

    print(f"Reading transcript: {src.name}")
    transcript = src.read_text(encoding="utf-8")

    print("Generating outline (Opus, extended thinking)...")
    outline = generate_outline(transcript)

    print("Extracting title and scripture...")
    title = extract_title(outline)
    scripture = extract_primary_scripture(outline)
    full_scripture = extract_full_scripture(outline)
    slug = scripture_to_slug(scripture) if scripture else "unknown"

    lesson_date = date_str or datetime.date.today().isoformat()
    series = _extract_series_from_transcript(transcript)
    speaker = _extract_speaker_from_header(transcript)
    thesis = extract_lesson_thesis(outline)

    outline_filename = _outline_filename(slug, lesson_date)
    outline_path = OUTLINES_DIR / outline_filename
    frontmatter = _build_frontmatter(lesson_date, slug, str(src), series)
    outline_path.write_text(frontmatter + outline, encoding="utf-8")
    print(f"Outline saved: {outline_path}")

    outline_notion_page_id = None
    print("Pushing outline to Notion...")
    try:
        outline_notion_page_id = push_outline_to_notion(outline_path, title, scripture, full_scripture, date_str, speaker, series, thesis)
        print(f"Notion outline page created: {outline_notion_page_id}")
    except Exception as e:
        print(f"Notion push failed: {e}")

    _save_sidecar(outline_path, outline_notion_page_id)

    print(f"\nTitle: {title}")
    print(f"Scripture: {scripture}")
    print(f"Outline: {outline_path}")
    return outline_path


def run_repush_outline(outline_path: str):
    md_path = Path(outline_path)
    json_path = md_path.with_suffix(".json")
    if not json_path.exists():
        print(f"ERROR: Sidecar not found: {json_path}")
        return

    sidecar = json.loads(json_path.read_text(encoding="utf-8"))
    page_id = sidecar.get("outline_notion_page_id")
    if not page_id:
        print("ERROR: outline_notion_page_id not found in sidecar JSON.")
        return

    md = md_path.read_text(encoding="utf-8")
    outline_clean = _strip_for_notion(md)

    print(f"Updating Outline property on Notion page {page_id}...")
    notion.pages.update(
        page_id=page_id,
        properties={
            "Outline": {"rich_text": _chunk_rich_text(outline_clean)},
        }
    )

    print(f"Done. Notion outline page updated: {page_id}")


# ============================================================
# CLI
# ============================================================

def main():
    parser = argparse.ArgumentParser(description="THEO Outline Pipeline")
    sub = parser.add_subparsers(dest="command")

    p_prep = sub.add_parser("prep", help="Normalize transcript header before pipeline")
    p_prep.add_argument("transcript", help="Path to transcript file")
    p_prep.add_argument("--series", required=True, help="Study series name")
    p_prep.add_argument("--speaker", default="", help="Speaker/author name (optional)")

    p_plan = sub.add_parser("plan", help="Transcript -> outline -> Construct + Notion")
    p_plan.add_argument("transcript", help="Path to transcript file")
    p_plan.add_argument("--date", help="Lesson date (YYYY-MM-DD)", default=None)

    p_repush = sub.add_parser("repush-outline", help="Re-push edited outline .md to existing Notion page")
    p_repush.add_argument("outline", help="Path to outline .md file")

    args = parser.parse_args()

    if args.command == "prep":
        run_prep(args.transcript, args.series, args.speaker)
    elif args.command == "plan":
        run_plan(args.transcript, args.date)
    elif args.command == "repush-outline":
        run_repush_outline(args.outline)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
