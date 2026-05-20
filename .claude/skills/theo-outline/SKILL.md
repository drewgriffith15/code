---
name: theo-outline
description: THEO outline pipeline. Use when Drew wants to generate one or more lesson outlines from sermon transcript files. Accepts one or more file paths, asks for lesson dates, runs theo_outline.py for each, saves outlines to Construct, pushes to Notion.
model: claude-sonnet-4-6
---

# THEO Outline Pipeline

Generate lesson outlines from sermon transcripts. One file or many — skill loops through all of them.

Transcripts come from: `Construct/raw/processed/theology/`
Outlines are saved to: `Construct/wiki/theology/outlines/`

## Step 0 — Collect series metadata

Before collecting file paths, ask:

> What is the **series name** for these lessons? (required)

Wait for the series name. Then ask:

> What is the **speaker/author** name? (optional — leave blank if mixed sources or unknown)

Wait for the response. A blank or "n/a" answer is fine — speaker will be inferred per-file where possible.

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

**3b. Generate the outline:**
```bash
python "C:/Users/wgriffith2/Dropbox (Liberty University)/Code/theo_outline.py" plan "<transcript_path>" --date <YYYY-MM-DD>
```

Run them one at a time sequentially — do not parallelize. After each plan run, capture and report:
- Outline file path (printed as `Outline saved: ...`)
- Notion page ID (printed as `Notion outline page created: ...`)

If a run fails, stop and report the error. Do not continue to the next file until the user clears it.

## Step 4 — Final summary

After all files are processed, report a clean summary table:

```
/theo-outline complete — N outline(s) generated

Week 1 (YYYY-MM-DD): <title>
  Outline: <path in Construct/wiki/theology/outlines/>
  Notion:  <page id>

Week 2 (YYYY-MM-DD): <title>
  ...
```
