#!/usr/bin/env python3
"""
update_voice.py - Refresh voice_patterns.json from last 3 final_edited lessons in Construct.

Usage:
    python update_voice.py
"""

import json
import os
import datetime
from pathlib import Path

import anthropic
import duckdb
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent.parent / '.env', override=True)

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
CONSTRUCT_ROOT = Path(r"C:/Users/wgriffith2/Dropbox (Liberty University)/Construct")
Construct_DB_PATH = os.getenv("Construct_DB_PATH", str(CONSTRUCT_ROOT))  # TODO: migrate to Construct wiki
VOICE_PATTERNS_PATH = Path(__file__).parent / 'voice_patterns.json'

HAIKU = "claude-haiku-4-5-20251001"

DRIFT_FIELDS = ["voice_summary", "cadence", "teacher_checkin", "sentence_fragments",
                "transition_phrases", "theological_depth", "vulnerability"]

ANALYSIS_PROMPT = """You are analyzing lesson transcripts from a Bible study teacher named Drew to extract his voice patterns.

Here are his last {n} edited lessons:

{lessons}

Based only on these transcripts, extract Drew's voice patterns and return a JSON object with exactly these fields:

{{
  "voice_summary": "One paragraph (under 100 words) describing Drew's overall teaching voice and style",
  "cadence": {{
    "description": "Describe his natural sentence-starting patterns and spoken momentum style",
    "examples": ["3-5 actual short examples pulled directly from these transcripts"]
  }},
  "teacher_checkin": {{
    "description": "Describe how he breaks the fourth wall and checks in with the audience",
    "examples": ["3-5 actual examples pulled from these transcripts"]
  }},
  "sentence_fragments": {{
    "description": "Describe when and how he uses fragments for emphasis",
    "examples": ["3-5 actual fragment examples from these transcripts"]
  }},
  "transition_phrases": {{
    "approved": ["8-12 actual transition phrases he used in these transcripts"]
  }},
  "theological_depth": {{
    "description": "Describe how he handles Greek/Hebrew terms, historical context, and scholarly quotes",
    "examples": ["2-3 actual examples from these transcripts"]
  }},
  "vulnerability": {{
    "description": "Describe how he expresses humility and personal struggle in teaching",
    "examples": ["2-3 actual examples from these transcripts"]
  }}
}}

Return ONLY valid JSON. No markdown fences, no explanation."""


def fetch_last_lessons(n: int = 3) -> list[dict]:
    con = duckdb.connect(Construct_DB_PATH)
    rows = con.execute("""
        SELECT id, title, lesson_date, final_edited
        FROM lessons
        WHERE final_edited IS NOT NULL AND final_edited != ''
        ORDER BY lesson_date DESC
        LIMIT ?
    """, [n]).fetchall()
    con.close()
    return [{"id": r[0], "title": r[1], "date": str(r[2]), "text": r[3]} for r in rows]


def analyze_lessons(lessons: list[dict]) -> dict:
    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

    lessons_text = ""
    for i, lesson in enumerate(lessons, 1):
        lessons_text += f"\n\n--- LESSON {i}: {lesson['title']} ({lesson['date']}) ---\n\n"
        lessons_text += lesson["text"]

    prompt = ANALYSIS_PROMPT.format(n=len(lessons), lessons=lessons_text)

    response = client.messages.create(
        model=HAIKU,
        max_tokens=3000,
        messages=[{"role": "user", "content": prompt}],
    )
    raw = response.content[0].text.strip()
    return json.loads(raw)


def _diff_field(field: str, old_val, new_val) -> str | None:
    if old_val == new_val:
        return None
    if isinstance(old_val, str) and isinstance(new_val, str):
        old_words = len(old_val.split())
        new_words = len(new_val.split())
        return f"  {field}: updated ({old_words} words -> {new_words} words)"
    if isinstance(old_val, dict) and isinstance(new_val, dict):
        changes = []
        for k in new_val:
            if k not in old_val:
                changes.append(f"    {k}: added")
            elif old_val[k] != new_val[k]:
                if isinstance(new_val[k], list):
                    added = [x for x in new_val[k] if x not in old_val.get(k, [])]
                    removed = [x for x in old_val.get(k, []) if x not in new_val[k]]
                    if added:
                        changes.append(f"    {k}: {len(added)} new item(s) added")
                    if removed:
                        changes.append(f"    {k}: {len(removed)} item(s) removed")
                else:
                    changes.append(f"    {k}: updated")
        return (f"  {field}:\n" + "\n".join(changes)) if changes else None
    return f"  {field}: updated"


def merge_and_diff(existing: dict, new_drift: dict) -> tuple[dict, list[str], list[str]]:
    stable = existing.get("meta", {}).get("stable_fields", [])
    updated = existing.copy()
    changed_lines = []
    unchanged = []

    for field in DRIFT_FIELDS:
        if field not in new_drift:
            unchanged.append(field)
            continue
        diff = _diff_field(field, existing.get(field), new_drift[field])
        if diff:
            updated[field] = new_drift[field]
            changed_lines.append(diff)
        else:
            unchanged.append(field)

    return updated, changed_lines, unchanged


def main():
    print("Fetching last 3 final_edited lessons from Construct...")
    lessons = fetch_last_lessons(3)

    if not lessons:
        print("No final_edited lessons found in Construct. Nothing to update.")
        return

    print(f"Found {len(lessons)} lesson(s): {', '.join(l['id'] for l in lessons)}")

    if not VOICE_PATTERNS_PATH.exists():
        print("Error: voice_patterns.json not found. Seed it first.")
        return

    with open(VOICE_PATTERNS_PATH, encoding="utf-8") as f:
        existing = json.load(f)

    print("Analyzing lessons with Claude Haiku...")
    new_drift = analyze_lessons(lessons)

    updated, changed_lines, unchanged = merge_and_diff(existing, new_drift)

    today = datetime.date.today().isoformat()
    lesson_ids = [l["id"] for l in lessons]

    print(f"\nVoice pattern update - {today}")
    print(f"Lessons analyzed: {', '.join(lesson_ids)}")
    print()

    if changed_lines:
        print("Changed:")
        for line in changed_lines:
            print(line)
    else:
        print("No changes detected.")

    if unchanged:
        print(f"\nUnchanged: {', '.join(unchanged)}")

    stable = existing.get("meta", {}).get("stable_fields", [])
    print(f"Stable fields (not touched): {', '.join(stable)}")

    if not changed_lines:
        print("\nNothing to write.")
        return

    answer = input("\nWrite changes? (y/n): ").strip().lower()
    if answer != "y":
        print("Aborted. No changes written.")
        return

    updated["meta"]["last_updated"] = today
    updated["meta"]["lessons_used"] = lesson_ids

    with open(VOICE_PATTERNS_PATH, "w", encoding="utf-8") as f:
        json.dump(updated, f, indent=2, ensure_ascii=False)

    print(f"voice_patterns.json updated.")


if __name__ == "__main__":
    main()
