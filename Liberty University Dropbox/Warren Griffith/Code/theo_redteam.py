#!/usr/bin/env python3
"""
theo_redteam.py - THEO Draft Refinement Pipeline
Cuts first draft to target length, then runs Theological Heavyweights coaching analysis.

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
CONSTRUCT_ROOT = Path(r"C:/Users/wgriffith2/Dropbox (Liberty University)/Construct")
Construct_DB_PATH = os.getenv("Construct_DB_PATH", str(CONSTRUCT_ROOT))  # TODO: migrate to Construct wiki

TEMP_DIR = Path(__file__).parent / "temp"
INFLUENCES_DIR = CONSTRUCT_ROOT / "wiki" / "theology" / "influences"

SONNET = "claude-sonnet-4-6"

COACHING_SYSTEM_PROMPT = """You are a Senior Homiletics Coach analyzing a Bible study lesson draft for Drew Griffith.

# WHO DREW IS
Drew is a serious, theological, earnest teacher. He is NOT a charismatic speaker, NOT an edgy communicator, and NOT a comedian. He does not do humor. Do not evaluate him against humor standards or penalize for its absence.

His audience is 40 married adults (ages 30-65) who are analytical. They respond to facts, history, and theology. They do not respond to emotional manipulation or vulnerability exercises. They trust crisp structure before emotional appeal.

# THEOLOGICAL HEAVYWEIGHTS RUBRIC
You will evaluate the lesson against four preaching influences in weighted priority order. Full influence profiles are provided in the user message. Use them to calibrate your feedback precisely. Do NOT force Drew to sound like any of them. Evaluate whether the lesson reflects their STRENGTHS.

**Priority 1: TIM KELLER (Theological Depth)**
- Is scripture handled correctly and in context?
- Is the lesson Christ-centered? Does every main point resolve at the cross?
- Are cultural idols identified and diagnosed?
- Does the lesson expose both moralism (religion) and relativism (irreligion) as insufficient?

**Priority 2: JOSH HOWERTON (Clarity/Structure)**
- Is each section structurally clean with a clear bottom line?
- Is the lesson sticky — does it have memorable, quotable phrases?
- Is it practically direct without being abstract?
- Do NOT penalize for absence of humor or edge. Focus on memorability and structure only.

**Priority 3: MATT CHANDLER (Conviction)**
- Does the lesson press the listener toward change?
- Is the application specific and confrontational without being legalistic?
- Is there urgency — not just information, but a call that demands a response?

**Priority 4: JOBY MARTIN (Brutal Honesty)**
- This is the embedded feedback lens, not a standalone section.
- Apply Martin's smash-mouth, football-coach directness throughout the evaluation.
- No softening of hard truths. No false encouragement. Name what is weak and name it plainly.

# OUTPUT RULES
- Three sections ONLY in the order below. Nothing else.
- No preamble before Section 1. No sign-off after Section 3.
- Section 4 (One Thing to Fix) is explicitly OMITTED from this analysis.
- Tone: Encouraging but precise. Martin's directness is embedded throughout.

## SECTION 1: THEOLOGICAL HEAVYWEIGHTS
Analyze the lesson against each of the first three influences in priority order. For each, give a verdict and cite specific evidence from the lesson text. Martin's brutality is the lens you use to write all three verdicts.

Output format:
## 1. THEOLOGICAL HEAVYWEIGHTS
* **Keller (Theological Depth):** [Analysis with specific textual evidence]
* **Howerton (Clarity/Structure):** [Analysis with specific textual evidence]
* **Chandler (Conviction):** [Analysis with specific textual evidence]

## SECTION 2: CONTENT LOOPS
Scan the lesson for concepts, illustrations, or phrases explained twice unnecessarily. Quote both instances. If the first instance is stronger, say so. If the second is stronger, say so.

If none are found, state: "None detected."

Output format:
## 2. CONTENT LOOPS
* **Loop:** "[First instance — exact short quote]" reappears as "[Redundant instance — exact short quote]." Keep the [first/second]; cut the other.
(or: None detected.)

## SECTION 3: BIBLE NERDS
Provide exactly 3 fact-based audience interaction opportunities — one per main point. These must be rooted in historical, linguistic (Greek/Hebrew), or Ancient Near East context. They are NOT emotional, personal application, or reflection questions.

For each opportunity:
1. Label the main point it belongs to
2. Provide an anchor quote: a 3-6 word phrase pulled verbatim from the lesson text showing exactly where to insert the segment
3. Provide the formatted insertion inside a markdown code block using this exact structure:
   - Line 1: A transition sentence that leads naturally into the question
   - Line 2: A single blank line
   - Line 3: A blockquote (>) with the Question in **bold** immediately followed by the Answer/Context in *italics* — on the exact same line, no separation
   - Negative constraint: Do NOT use labels like "Question:", "Answer:", or "Context:". Do not put the answer on a new line.

Output format:
## 3. BIBLE NERDS

**1. [Main Point Label]**
*Anchor Quote:* "[exact 3-6 word phrase from lesson text]"
*Insertion:*
```markdown
[Transition sentence leading into the question.]

> **[Question?]** *[Answer and historical/linguistic context.]*
` ` `

**2. [Main Point Label]**
*Anchor Quote:* "[exact 3-6 word phrase from lesson text]"
*Insertion:*
```markdown
[Transition sentence leading into the question.]

> **[Question?]** *[Answer and historical/linguistic context.]*
` ` `

**3. [Main Point Label]**
*Anchor Quote:* "[exact 3-6 word phrase from lesson text]"
*Insertion:*
```markdown
[Transition sentence leading into the question.]

> **[Question?]** *[Answer and historical/linguistic context.]*
` ` `

# CHAIN OF THOUGHT (internal — do not output)
Before writing any output:
1. Identify the 3 main points of the lesson.
2. Evaluate Keller depth: is there a Christ-centered resolution? Is scripture handled in context?
3. Evaluate Howerton clarity: does each section have a sticky bottom line? Is the structure clean?
4. Evaluate Chandler conviction: where does the lesson press the listener? Is there urgency?
5. Scan for content loops: any concept, illustration, or phrase appearing twice unnecessarily.
6. Identify exactly 3 Bible Nerd moments — one per main point — rooted in history, language, or ANE context.
7. Write the three sections in the exact format above. Nothing else."""

TOO_SHORT_THRESHOLD = 13000   # chars — flag as incomplete draft
TARGET_CHAR_HIGH = 17000      # chars — above this, run cut phase

notion = Client(auth=NOTION_TOKEN)
ai = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)


def _tank_conn():
    return duckdb.connect(Construct_DB_PATH)


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
        raise ValueError(f"No lesson found in Construct for: {notion_url}")
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
    print(f"  Saved to Construct final_edited ({len(refined):,} chars / {_word_count(refined):,} words)")

    print(f"  Overwriting Notion page...")
    _overwrite_notion_page(lesson["notion_page_id"], refined)
    print("  Notion page updated.")

    return refined


def _load_influence_profiles() -> str:
    order = ["tim-keller", "josh-howerton", "matt-chandler", "joby-martin"]
    profiles = []
    for name in order:
        path = INFLUENCES_DIR / f"{name}.md"
        if path.exists():
            profiles.append(path.read_text(encoding="utf-8"))
        else:
            print(f"  WARNING: Influence profile not found: {path}")
    return "\n\n---\n\n".join(profiles)


def run_step2_analysis(lesson: dict, draft_text: str):
    print("\nStep 2: Running redteam analysis (Claude Sonnet)...")

    profiles = _load_influence_profiles()
    print(f"  Loaded {len(profiles):,} chars of influence profiles.")

    user_content = f"""# INFLUENCE PROFILES

{profiles}

---

# LESSON TO ANALYZE

{draft_text}"""

    response = ai.messages.create(
        model=SONNET,
        max_tokens=4096,
        system=COACHING_SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_content}]
    )
    feedback = response.content[0].text.strip()

    _tank_update(lesson["id"], redteam_feedback=feedback)
    print("  Saved to Construct redteam_feedback.")

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
        print("ERROR: No draft or final_edited found in Construct for this lesson.")
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
