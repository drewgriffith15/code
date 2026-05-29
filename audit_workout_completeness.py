#!/usr/bin/env python3
"""Audit workout completeness across Construct wiki programs."""

import os
import re
from pathlib import Path
from datetime import datetime


PROGRAMS_ROOT = Path(
    r"C:\Users\wgriffith2\Dropbox (Liberty University)\Construct\wiki\workouts\programs"
)
OUTPUT_FILE = PROGRAMS_ROOT / "_incomplete.md"

# Placeholder patterns that indicate incomplete workouts
PLACEHOLDER_PATTERNS = [
    r"not provided",
    r"SKIP:",
    r"refer to the video",
    r"specific exercise breakdown",
    r"complete workout structure",
    r"exercise sequence",
]

PLACEHOLDER_REGEX = re.compile("|".join(PLACEHOLDER_PATTERNS), re.IGNORECASE)


def parse_markdown(file_path):
    """Parse markdown file and return (has_frontmatter, workout_plan_content)."""
    try:
        content = file_path.read_text(encoding="utf-8")
    except Exception as e:
        return None, f"read_error: {e}"

    if not content.strip():
        return False, "empty"

    # Check for frontmatter
    has_frontmatter = content.startswith("---")

    # Extract Workout Plan section
    match = re.search(r"^## Workout Plan\s*\n(.*?)(?=^##|\Z)", content, re.MULTILINE | re.DOTALL)

    if not match:
        return has_frontmatter, "missing_section"

    plan_content = match.group(1).strip()

    if not plan_content:
        return has_frontmatter, "empty_section"

    # Check for placeholder text
    if PLACEHOLDER_REGEX.search(plan_content):
        preview = plan_content.split("\n")[0][:100]
        return has_frontmatter, f"placeholder_text: {preview}"

    return has_frontmatter, "complete"


def get_preview(file_path, max_chars=100):
    """Get first 1-2 lines of Workout Plan section."""
    try:
        content = file_path.read_text(encoding="utf-8")
        match = re.search(r"^## Workout Plan\s*\n(.*?)(?=^##|\Z)", content, re.MULTILINE | re.DOTALL)
        if match:
            lines = match.group(1).strip().split("\n")
            preview = " ".join(lines[:2])
            return preview[:max_chars]
        return "section missing"
    except Exception:
        return "read_error"


def audit_programs():
    """Audit all programs and return incomplete files grouped by program."""
    incomplete_by_program = {}
    total_files = 0
    complete_files = 0

    if not PROGRAMS_ROOT.exists():
        print(f"ERROR: Programs root not found: {PROGRAMS_ROOT}")
        return None

    for program_folder in sorted(PROGRAMS_ROOT.iterdir()):
        if not program_folder.is_dir():
            continue

        program_name = program_folder.name

        # Skip utility files/folders
        if program_name.startswith("_"):
            continue

        incomplete_files = []
        program_files = 0
        program_complete = 0

        for md_file in sorted(program_folder.glob("*.md")):
            # Skip utility files
            if md_file.name.startswith("_"):
                continue

            total_files += 1
            program_files += 1

            has_frontmatter, status = parse_markdown(md_file)

            if status == "complete":
                complete_files += 1
                program_complete += 1
            else:
                preview = get_preview(md_file)
                incomplete_files.append({
                    "filename": md_file.name,
                    "reason": status,
                    "preview": preview,
                })

        if incomplete_files:
            incomplete_by_program[program_name] = incomplete_files

        print(f"[{program_name}] {program_complete}/{program_files} complete")

    return {
        "incomplete_by_program": incomplete_by_program,
        "total_files": total_files,
        "complete_files": complete_files,
        "incomplete_files": total_files - complete_files,
    }


def write_report(audit_results):
    """Write _incomplete.md report."""
    if not audit_results:
        print("No results to report.")
        return

    lines = []
    lines.append(f"# Incomplete Workout Files - {datetime.now().strftime('%Y-%m-%d')}\n")

    for program_name in sorted(audit_results["incomplete_by_program"].keys()):
        incomplete_files = audit_results["incomplete_by_program"][program_name]
        lines.append(f"## {program_name}\n")

        for item in incomplete_files:
            reason = item["reason"]
            preview = item["preview"]
            lines.append(f"- {item['filename']} - {reason}")
            lines.append(f"  Preview: {preview}\n")

    lines.append("## Summary\n")
    lines.append(
        f"{audit_results['incomplete_files']} files flagged across "
        f"{len(audit_results['incomplete_by_program'])} programs. "
        f"({audit_results['complete_files']}/{audit_results['total_files']} complete)\n"
    )

    report_content = "".join(lines)
    OUTPUT_FILE.write_text(report_content, encoding="utf-8")
    print(f"\nReport written to: {OUTPUT_FILE}")


if __name__ == "__main__":
    print(f"Scanning programs in: {PROGRAMS_ROOT}\n")
    audit_results = audit_programs()
    if audit_results:
        write_report(audit_results)
