---
name: theo-full
description: THEO full draft pipeline. Use when Drew wants to generate a complete lesson draft from an existing outline file. Accepts a single outline path, runs theo.py draft mode, reports draft path and Notion full-page URL.
model: claude-sonnet-4-6
---

# THEO Full Draft Pipeline

Generate a complete lesson draft from an existing outline. Runs intro, points 1-3, conclusion, discussion, and ghost-writer pass — then pushes the full draft to Notion.

## Step 1 — Collect outline path

If the user provided an outline file path in the command args, use it. If not, ask:

> Which outline file do you want to draft from? Provide the full path.

Wait for the path before continuing.

## Step 2 — Confirm and run

Show the user what is about to run and confirm:

> Ready to run full draft pipeline on:
> `<outline_path>`
>
> This will generate: intro, 3 main points, conclusion, discussion questions, ghost-writer polish, then push to Notion.
> Proceed?

Wait for confirmation.

Then run:

```bash
python "C:/Users/wgriffith2/Code/TANK/scripts/theo.py" draft "<outline_path>"
```

Stream the output back to the user as it runs — each step prints progress (Generating intro..., Generating Point 1..., etc.).

## Step 3 — Report results

After the run completes, capture and report:
- Draft file path (printed as `Draft saved: ...`)
- TANK lesson ID (printed as `TANK lesson updated: LESS-XXXXXXXX`)
- Notion full-page URL (printed as `FULL page created: https://...`)

Final summary format:

```
/theo-full complete

Draft:  <path>
TANK:   LESS-XXXXXXXX
Notion: <full-page url>
```

If the run fails, report the full error output and stop.

## Notes

- Ghost-writer pass is always enabled. No toggle needed.
- The outline must already exist and have a matching sidecar `.json` file (created by a prior `/theo-outline` run) for TANK linking to work. If the sidecar is missing, theo.py will warn but still produce the draft.
- After Drew edits the lesson in Notion, use `theo_notion_sync.py` to pull edits back to TANK.
