---
name: theo-outline
description: THEO outline pipeline. Use when Drew wants to generate one or more lesson outlines from sermon transcript files. Accepts one or more file paths, asks for lesson dates, runs theo_outline.py for each, saves outlines to Construct, pushes to Notion.
model: claude-sonnet-4-6
---

# THEO Outline Pipeline

Generate lesson outlines from sermon transcripts. One file or many — skill loops through all of them.

Transcripts can be any path on the machine. Most will come from `Construct/raw/processed/theology/` but this is not enforced.
Outlines are saved to: `Construct/wiki/theology/outlines/`

## Step 0 — Collect series metadata

Before collecting file paths, ask:

> What is the **series name** for these lessons? (required — use "none" for standalone transcripts not part of a series)

Wait for the series name. Then ask:

> What is the **speaker/author** name? (optional — leave blank if mixed sources or unknown)

Wait for the response. A blank or "n/a" answer is the normal path — most transcripts already have a speaker in their header and auto-detection will pick it up. Only enter a name here if you want to force-override all files in the batch.

Store both values. They will be passed to `prep` for every file.

## Step 1 — Collect file paths

If the user provided file paths in the command args, use them. If not, ask:

> Which transcript file(s) do you want to outline? Provide full paths, one per line.

Wait for the paths before continuing.

## Step 2 — Collect lesson dates

Ask:

> What is the lesson date for each file? (YYYY-MM-DD)
> - filename1
> - filename2
> ...

Wait for the dates before continuing.

## Step 3 — Prep then outline each file

For each file in order, run two commands sequentially:

**3a. Normalize the transcript header:**
```bash
python "C:/Users/wgriffith2/Dropbox (Liberty University)/Code/theo_outline.py" prep "<transcript_path>" --series "<series_name>" [--speaker "<speaker_name>"]
```
Omit `--speaker` if no speaker was provided in Step 0. Capture and report the status line (e.g., `OK Nehemiah 1 | Speaker: ... | Series: ...`).

If prep fails, stop and report the error. Do not run plan for that file.

**3b. Check for existing outline:**

From the `prep` output (e.g. `OK Nehemiah 1`), derive the expected filename:
- Scripture slug: book abbreviation + chapter, lowercased with underscore (e.g. `Nehemiah 1` -> `neh_1`)
- Full filename: `{date_nodash}_{slug}.md` (e.g. `20260518_neh_1.md`)
- Full path: `C:/Users/wgriffith2/Dropbox (Liberty University)/Construct/wiki/theology/outlines/{filename}`

If that file already exists, warn the user:

> ⚠ Outline already exists: `{filename}`
> Running `plan` will overwrite it locally and create a duplicate row in Notion.
> Proceed anyway? (yes / no)

If the user says no, skip `plan` for this file and move to the next. If yes, continue.

**3c. Generate the outline:**
```bash
python "C:/Users/wgriffith2/Dropbox (Liberty University)/Code/theo_outline.py" plan "<transcript_path>" --date <YYYY-MM-DD>
```

Run them one at a time sequentially — do not parallelize. After each plan run, capture and report:
- Outline file path (printed as `Outline saved: ...`)
- Notion page ID (printed as `Notion outline page created: ...`) — format as a clickable URL: `https://notion.so/{page_id_no_hyphens}`

If outline generation fails (transcript read error, Claude API error), stop and report. Do not continue to the next file until the user clears it.

If only the Notion push fails, warn the user and continue to the next file. The local outline is saved. The user can repush later via `repush-outline`.

## Repush an outline to Notion

Use this when a previous Notion push failed or needs to be re-run for an existing outline file.

If the user says something like "repush this outline" or references a specific `.md` file, ask for the outline path if not already known:

> Which outline file do you want to repush? Provide the full path.

Then run:
```bash
python "C:/Users/wgriffith2/Dropbox (Liberty University)/Code/theo_outline.py" repush-outline "<outline_path>"
```

This requires a matching `.json` sidecar file next to the `.md` (created automatically during the original run). If the sidecar is missing, report the error — the outline will need to be fully regenerated.

Report success (`Notion outline page updated: <page_id>`) or the error message.

---

## Step 4 — Final summary

After all files are processed, report a clean summary table:

```
/theo-outline complete — N outline(s) generated

Week 1 (YYYY-MM-DD): <title>
  Outline: <path in Construct/wiki/theology/outlines/>
  Notion:  https://notion.so/<page_id_no_hyphens>

Week 2 (YYYY-MM-DD): <title>
  ...
```
