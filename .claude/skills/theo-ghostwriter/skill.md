---
name: theo-ghostwriter
description: THEO ghost-writer pipeline. Use when Drew wants to generate a complete lesson draft from an existing outline file. Accepts a single outline path from Construct/wiki/theology/outlines/, runs theo_ghost_writer.py draft mode, reports the draft path in Construct/wiki/theology/lessons/.
---

# THEO Ghost-Writer Pipeline

Generate a complete lesson draft from an existing outline. Runs intro, points 1-3, conclusion, discussion, and ghost-writer pass — then pushes the full draft to Notion.

Outlines live in: `Construct/wiki/theology/outlines/`

## Step 1 — Collect outline path

If the user provided an outline file path in the command args, use it. If not, ask:

> Which outline file do you want to draft from? Provide the full path.

The outline should be a file from `Construct/wiki/theology/outlines/` (e.g., `20260518_neh_2.md`). Wait for the path before continuing.

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
python "C:/Users/wgriffith2/Dropbox (Liberty University)/Code/theo_ghost_writer.py" draft "<outline_path>"
```

Stream the output back to the user as it runs — each step prints progress (Generating intro..., Generating Point 1..., etc.).

## Step 3 — Report results

After the run completes, capture and report:
- Draft file path (printed as `Draft saved: ...`)

Final summary format:

```
/theo-ghostwriter complete

Draft: <path>
```

If the run fails, report the full error output and stop.

## Notes

- Ghost-writer pass is always enabled. No toggle needed.
- Draft is saved to `Construct/wiki/theology/lessons/` as `{outline_stem}_draft.md`.
- To push the finished lesson to Notion after editing, use `/theo-push`.
