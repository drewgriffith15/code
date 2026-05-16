#!/usr/bin/env python3
"""
theo_ghost_writer.py - THEO Ghost-Writer Pipeline
Generates a full lesson draft from an existing outline file.

Usage:
    python theo_ghost_writer.py draft <outline_path> [--no-ghost-writer]
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

load_dotenv(Path(__file__).parent.parent.parent / '.env', override=True)

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
NOTION_TOKEN = os.getenv("NOTION_TOKEN")

DRAFTS_DIR = Path(__file__).parent / "lessons" / "drafts"
TEMP_DIR = Path(__file__).parent / "lessons" / "temp"
VOICE_PATTERNS_PATH = Path(__file__).parent / "references" / "voice_patterns.json"

THEO_FULL_PAGE_ID = os.getenv("THEO_FULL_PAGE_ID", "35bee045d5ec80da97b8d003434ffb43")

SONNET = "claude-sonnet-4-6"
HAIKU = "claude-haiku-4-5-20251001"

notion = Client(auth=NOTION_TOKEN)


def ensure_dirs():
    for d in [DRAFTS_DIR, TEMP_DIR]:
        d.mkdir(parents=True, exist_ok=True)


# ============================================================
# PROMPTS
# ============================================================

INTRO_PROMPT = """TASK:
{outline}

SPECIAL INSTRUCTION: "The Prayer, The Header, & The Launch."
The Scripture has just been read. You are writing the Opening Prayer followed by the Introduction.

Follow this EXACT 3-step format:

1. THE OPENING PRAYER:
   - Start with exactly: "Let's open in prayer..."
   - Insert a blank line.
   - Write a specific prayer (approx. 50 words) based on the "Lesson Thesis". Be reverent but direct.
   - End with "Amen."
   - Insert a blank line after "Amen."

2. THE INTRO HEADER:
   - Create a short, punchy, creative title for the Introduction section (e.g., "## OUT OF NOWHERE").
   - Format it as an H2 (## TITLE).
   - It should NOT just be "## INTRODUCTION". Make it specific to the story/hook.

3. THE LAUNCH (The Hook, The Context, The Promise):
   - THE HOOK: Immediately following the Header, grab attention using one of these two methods:
        1. The Story Drop-In: Bypass long background explanations and drop the audience straight into the action or conflict of the biblical scene. Make it feel like a movie.
        2. The Surprising Statement/Question: Open with a bold claim or a thought-provoking question that forces the listener's brain to instantly search for an answer.
   - NEVER use phrases like "In the passage we just read."
   - THE CONTEXT: Once the audience is hooked, briefly weave in the necessary Historical setting or Theological background from the outline.
   - THE BIG PROMISE: Tell the audience exactly what they are going to gain from this lesson. Answer the question, "What's in it for me?"
   - End this section by building tension that leads seamlessly into the first main point.
   - DO NOT EXCEED 4000 characters for THE LAUNCH section.

OUTPUT STRUCTURE EXAMPLE:
Let's open in prayer...

[Prayer text...] Amen.

## THE UNEXPECTED GUEST
[Hook the audience... Provide context... Make the Big Promise... Build tension...]
"""

POINT_PROMPT = """CONTEXT SO FAR:
{running_context}
(Note: {context_note})

TASK:
{outline_section}

Now, write at about 500 words related to this section.
"""

CONCLUSION_PROMPT = """CONTEXT SO FAR:
{running_context}
(Note: The lesson is over. Do not summarize what you just taught.)

TASK:
{outline_section}

CRITICAL CONSTRAINT: "The Hard Stop."
1. The Outline contains a detailed "Equipping Pivot" with lists. Do NOT read this as a list.
2. Instead, synthesize that data into ONE final application/challenge.
3. Use a narrative flow (paragraph form).
4. End the final few sentences with "..." to indicate a slow, deliberate cadence.
5. Total length: < 150 words
6. Tone: Urgent, final, prayerful.

FORMATTING REQUIREMENT (The Prayer Transition):
- Do NOT output the "## CONCLUSION & PRAYER" header. That is added automatically.
- After the application/challenge text is finished, insert a blank line.
- Write exactly: "Let's close in prayer..."
- Insert another blank line.
- Write the Closing Prayer that is about 50 words.

OUTPUT STRUCTURE:
[Application/challenge paragraph...]

Let's close in prayer...

[Closing prayer text...] Amen.
"""

DISCUSSION_PROMPT = """ROLE: Expert Small Group Architect.
INPUT: Full Lesson Outline.
GOAL: Create exactly 2 discussion questions.

FORMATTING RULES (STRICT):
1. Output MUST be a simple numbered list (1., 2.).
2. Format pattern: "Number. Title: Question Text"
3. NO Markdown bolding (**text**) or italics (*text*). Keep it plain text.
4. NO headers and NO horizontal rules (---).
5. NO word count notes (e.g., "*(40 words)*").
6. NO intro or outro text or additional notes. Output ONLY the discussion questions.

STYLE:
- Short, punchy, "Real Talk" (Joby Martin vibe).
- Length: Under 45 words per question.

EXAMPLE FORMAT OUTPUT (Follow this EXACTLY):
1. The Herod in the Mirror: We judge Herod, but what specific "throne" (money, reputation) are you terrified to hand over to Jesus?
2. The Bible Nerd Trap: You can have right theology and a dead heart. Are you actively seeking Jesus, or just checking the "church" box?

DATA SOURCE:
{outline}
"""

GHOST_WRITER_SYSTEM = """
ROLE & PURPOSE:
You are "The Scribe," a final polish editor for Drew's Bible study lessons. The draft you receive was already written in Drew's voice. Your job is light refinement - NOT wholesale rewriting.

WHAT YOU DO:
1. Smooth any sentences that feel stiff or written rather than spoken.
2. Catch and replace any banned phrases that slipped through: "changes everything," "this isn't just," "here's the thing," "this is where it gets personal," "in conclusion," "firstly," "secondly," "by the way," "as a side note," "dive deep," "unpack," "journey," "transformative," "game-changer."
3. Verify every scripture reference from the input is still present in the output. If one is missing, restore it.
4. Ensure slash notation is used for grouped concepts (right/wrong/good/evil, not "right, wrong, good, and evil").
5. Check reading level - simplify any word over 3 syllables unless it is a theological term being explicitly defined.

WHAT YOU DO NOT DO:
- Do not restructure sections or reorder content.
- Do not add new content, illustrations, or personal stories not already in the draft.
- Do not remove teacher check-ins or rhetorical questions already present.
- Do not change the voice - it is already Drew's. Only smooth rough edges.

OUTPUT: Return the full polished lesson. Same structure, same sections, lighter touch.
"""

SLUG_PROMPT = """TASK: Convert the scripture reference "{reference}" into a short filename slug.

RULES:
1. Format: [3-4 LETTER UPPERCASE BOOK]-[CHAPTER]
2. Remove spaces, add hyphen.
3. Examples:
   - "1 Kings 18" -> "1KNG-18"
   - "Matthew 2" -> "MAT-2"
   - "Ephesians 1" -> "EPH-1"
4. Output ONLY the slug text. No other words.
"""


# ============================================================
# CLAUDE API CALLS
# ============================================================

def get_client():
    return anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)


def generate_intro(outline: str, voice_guide: str = "") -> str:
    client = get_client()
    kwargs = dict(
        model=SONNET,
        max_tokens=2000,
        messages=[{"role": "user", "content": INTRO_PROMPT.format(outline=outline)}],
    )
    if voice_guide:
        kwargs["system"] = voice_guide
    response = client.messages.create(**kwargs)
    return response.content[0].text


def generate_point(running_context: str, context_note: str, outline_section: str, voice_guide: str = "") -> str:
    client = get_client()
    prompt = POINT_PROMPT.format(
        running_context=running_context,
        context_note=context_note,
        outline_section=outline_section,
    )
    kwargs = dict(
        model=SONNET,
        max_tokens=1500,
        messages=[{"role": "user", "content": prompt}],
    )
    if voice_guide:
        kwargs["system"] = voice_guide
    response = client.messages.create(**kwargs)
    return response.content[0].text


def generate_conclusion(running_context: str, outline_section: str, voice_guide: str = "") -> str:
    client = get_client()
    prompt = CONCLUSION_PROMPT.format(
        running_context=running_context,
        outline_section=outline_section,
    )
    kwargs = dict(
        model=SONNET,
        max_tokens=800,
        messages=[{"role": "user", "content": prompt}],
    )
    if voice_guide:
        kwargs["system"] = voice_guide
    response = client.messages.create(**kwargs)
    return response.content[0].text


def generate_discussion(outline: str) -> str:
    client = get_client()
    response = client.messages.create(
        model=SONNET,
        max_tokens=400,
        messages=[{"role": "user", "content": DISCUSSION_PROMPT.format(outline=outline)}],
    )
    return response.content[0].text


def generate_ghost_writer(draft: str) -> str:
    client = get_client()
    response = client.messages.create(
        model=SONNET,
        max_tokens=8000,
        system=GHOST_WRITER_SYSTEM,
        messages=[{"role": "user", "content": draft}],
    )
    return response.content[0].text


def extract_primary_scripture(outline: str) -> str:
    match = re.search(r"\*\*Core Scripture Passage\(s\):\*\*\s*(.+)", outline)
    if match:
        raw = match.group(1).strip()
        return raw.split(";")[0].strip()
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
# VOICE PATTERNS
# ============================================================

def load_voice_patterns() -> dict | None:
    if not VOICE_PATTERNS_PATH.exists():
        return None
    try:
        with open(VOICE_PATTERNS_PATH, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _build_voice_guide(p: dict) -> str:
    banned = ", ".join(f'"{b}"' for b in p.get("banned_phrases", []))

    def fmt_examples(examples: list) -> str:
        return "\n".join(f'  - "{ex}"' for ex in examples)

    def fmt_list(items: list) -> str:
        return "\n".join(f'  - "{item}"' for item in items)

    cadence_exs = fmt_examples(p["cadence"]["examples"])
    checkin_exs = fmt_examples(p["teacher_checkin"]["examples"])
    slash_exs = fmt_examples(p["slash_notation"]["examples"])
    depth_exs = fmt_examples(p["theological_depth"]["examples"])
    vuln_exs = fmt_examples(p["vulnerability"]["examples"])
    transition_approved = fmt_list(p["transition_phrases"]["approved"])

    return f"""VOICE GUIDE - write in Drew's voice throughout:
{p["voice_summary"]}

PATTERN: CADENCE
{p["cadence"]["description"]}
Examples:
{cadence_exs}

PATTERN: TEACHER CHECK-INS
{p["teacher_checkin"]["description"]}
Examples:
{checkin_exs}

PATTERN: SLASH NOTATION
{p["slash_notation"]["description"]}
Examples:
{slash_exs}

PATTERN: THEOLOGICAL DEPTH
{p["theological_depth"]["description"]}
Examples:
{depth_exs}

PATTERN: VULNERABILITY
{p["vulnerability"]["description"]}
Examples:
{vuln_exs}

APPROVED TRANSITION PHRASES (use these, not invented ones):
{transition_approved}

Reading level: {p["reading_level"]}
Banned phrases (never use): {banned}
No stolen valor: {p["no_stolen_valor"]}
Preserve high-value assets: {p["preserve_high_value_assets"]}"""


# ============================================================
# NOTION
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
    lines = md.splitlines()
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


def _create_full_page_notion(content: str, title: str, parent_page_id: str) -> tuple:
    blocks = markdown_to_notion_blocks(content)
    page = notion.pages.create(
        parent={"page_id": parent_page_id},
        properties={"title": [{"type": "text", "text": {"content": title}}]},
        children=blocks[:100] if blocks else []
    )
    page_id = page["id"]
    notion_url = page.get("url", f"https://notion.so/{page_id.replace('-', '')}")
    for i in range(100, len(blocks), 100):
        _append_blocks(page_id, blocks[i:i + 100])
    return page_id, notion_url


def _link_full_page_to_outline(outline_notion_page_id: str, full_page_url: str, title: str):
    block = {
        "type": "paragraph",
        "paragraph": {
            "rich_text": [
                _rich_text("FULL Page: "),
                {"type": "text", "text": {"content": title, "link": {"url": full_page_url}}},
            ]
        },
    }
    _append_blocks(outline_notion_page_id, [block])


# ============================================================
# SIDECAR
# ============================================================

def _load_sidecar(outline_path: Path) -> str | None:
    sidecar = outline_path.with_suffix(".json")
    if sidecar.exists():
        try:
            data = json.loads(sidecar.read_text(encoding="utf-8"))
            return data.get("outline_notion_page_id")
        except Exception:
            pass
    return None


# ============================================================
# PIPELINE
# ============================================================

def _make_draft_filename(slug: str) -> str:
    dt = datetime.date.today().isoformat().replace("-", "")
    ts = datetime.datetime.now().strftime("%H%M%S")
    return f"{dt}_{ts}_{slug}_draft.md"


def extract_point_sections(outline: str) -> list:
    pattern = re.compile(
        r"(\*\*\s*Main Point [123]:.*?)(?=\*\*\s*Main Point [123]:|\*\*\s*Conclusion:|\Z)",
        re.DOTALL,
    )
    return [m.group(0).strip() for m in pattern.finditer(outline)]


def extract_conclusion_section(outline: str) -> str:
    match = re.search(r"\*\*\s*Conclusion:.*", outline, re.DOTALL)
    return match.group(0).strip() if match else ""


def run_draft(outline_path: str, ghost_writer: bool = True):
    ensure_dirs()
    op = Path(outline_path)
    if not op.exists():
        print(f"Error: outline not found: {outline_path}")
        sys.exit(1)

    outline = op.read_text(encoding="utf-8")
    scripture = extract_primary_scripture(outline)
    slug = scripture_to_slug(scripture) if scripture else "unknown"

    outline_notion_page_id = _load_sidecar(op)

    voice_patterns = load_voice_patterns()
    voice_guide = _build_voice_guide(voice_patterns) if voice_patterns else ""
    if voice_guide:
        print("Voice patterns loaded.")
    else:
        print("No voice_patterns.json found - running without voice guide.")

    print("Generating intro...")
    intro = generate_intro(outline, voice_guide)
    (TEMP_DIR / "theo_intro.md").write_text(intro, encoding="utf-8")

    point_sections = extract_point_sections(outline)
    points = []
    running = intro

    notes = [
        "Point 1 of 3 - establish the first main argument",
        "Point 2 of 3 - build on Point 1",
        "Point 3 of 3 - bring it home, set up the conclusion",
    ]

    for i, (section, note) in enumerate(zip(point_sections, notes), 1):
        print(f"Generating Point {i}...")
        pt = generate_point(running, note, section, voice_guide)
        points.append(pt)
        running = running + "\n\n" + pt
        (TEMP_DIR / f"theo_point{i}.md").write_text(pt, encoding="utf-8")

    conclusion_section = extract_conclusion_section(outline)
    print("Generating conclusion...")
    conclusion = generate_conclusion(running, conclusion_section, voice_guide)
    (TEMP_DIR / "theo_conclusion.md").write_text(conclusion, encoding="utf-8")

    print("Generating discussion questions...")
    discussion = generate_discussion(outline)
    (TEMP_DIR / "theo_discussion.md").write_text(discussion, encoding="utf-8")

    sections = [intro] + points + ["\n## CONCLUSION & PRAYER\n", conclusion, "\n## REAL TALK\n", discussion]
    draft = "\n\n".join(sections)

    if ghost_writer:
        print("Running ghost-writer...")
        draft = generate_ghost_writer(draft)

    draft_filename = _make_draft_filename(slug)
    draft_path = DRAFTS_DIR / draft_filename
    draft_path.write_text(draft, encoding="utf-8")
    print(f"Draft saved: {draft_path}")

    if outline_notion_page_id:
        lesson_title = op.stem
        print("Pushing FULL page to Notion...")
        try:
            page_id, notion_url = _create_full_page_notion(draft, lesson_title, THEO_FULL_PAGE_ID)
            print(f"FULL page created: {notion_url}")
            _link_full_page_to_outline(outline_notion_page_id, notion_url, lesson_title)
            print("Linked FULL page to outline page.")
        except Exception as e:
            print(f"Notion FULL page push failed: {e}")

    return draft_path


# ============================================================
# CLI
# ============================================================

def main():
    parser = argparse.ArgumentParser(description="THEO Ghost-Writer Pipeline")
    sub = parser.add_subparsers(dest="command")

    p_draft = sub.add_parser("draft", help="Outline -> full lesson draft")
    p_draft.add_argument("outline", help="Path to outline file")
    p_draft.add_argument("--no-ghost-writer", action="store_true")

    args = parser.parse_args()

    if args.command == "draft":
        run_draft(args.outline, ghost_writer=not args.no_ghost_writer)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
