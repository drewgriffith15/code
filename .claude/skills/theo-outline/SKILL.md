---
name: theo-outline
description: THEO outline pipeline. Use when Drew wants to generate one or more lesson outlines from sermon transcript files. Accepts one or more file paths, auto-assigns sequential Sunday dates, runs theo.py plan mode for each, pushes outlines to Notion.
model: claude-sonnet-4-6
---

# THEO Outline Pipeline

Generate lesson outlines from sermon transcripts. One file or many — skill loops through all of them.

## Step 1 — Collect file paths

If the user provided file paths in the command args, use them. If not, ask:

> Which transcript file(s) do you want to outline? Provide full paths, one per line.

Wait for the paths before continuing.

## Step 2 — Compute lesson dates

Run this Python to compute the sequential Sundays:

```python
from datetime import date, timedelta

today = date.today()
days_ahead = (6 - today.weekday()) % 7
if days_ahead == 0:
    days_ahead = 7
next_sunday = today + timedelta(days=days_ahead)

# Print one date per file — caller fills in N
files = [
    # populated from user input
]
for i, f in enumerate(files):
    lesson_date = (next_sunday + timedelta(weeks=i)).isoformat()
    print(f"{lesson_date}  {f}")
```

Show the user the file-to-date mapping and confirm before running:

> Ready to run outlines for N file(s):
> - YYYY-MM-DD: filename1.md
> - YYYY-MM-DD: filename2.md
> ...
> Proceed?

Wait for confirmation.

## Step 3 — Run theo.py plan for each file

For each file in order, run:

```bash
python "C:/Users/wgriffith2/Code/TANK/scripts/theo.py" plan "<transcript_path>" --date <YYYY-MM-DD>
```

Run them one at a time sequentially — do not parallelize. After each run, capture and report:
- TANK lesson ID (printed as `TANK lesson created: LESS-XXXXXXXX`)
- Outline file path (printed as `Outline saved: ...`)
- Notion page URL or ID (printed as `Notion outline page created: ...`)

If a run fails, stop and report the error. Do not continue to the next file until the user clears it.

## Step 4 — Final summary

After all files are processed, report a clean summary table:

```
/theo-outline complete — N outline(s) generated

Week 1 (YYYY-MM-DD): <title>
  Outline: <path>
  TANK:    LESS-XXXXXXXX
  Notion:  <page id or url>

Week 2 (YYYY-MM-DD): <title>
  ...
```
