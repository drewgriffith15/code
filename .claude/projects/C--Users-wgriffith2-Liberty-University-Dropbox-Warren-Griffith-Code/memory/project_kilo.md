---
name: project-kilo
description: "KILO workout publisher - script paths, Notion hub, topology, idempotency rules"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5eb17d02-2223-4486-b016-b739d0de9947
---

KILO publishes workout programs from Construct wiki to Notion.

- Script: `C:\Users\wgriffith2\Dropbox (Liberty University)\Code\kilo.py`
- Skill: `C:\Users\wgriffith2\.claude\skills\kilo\SKILL.md`
- Programs source: `C:\Users\wgriffith2\Dropbox (Liberty University)\Construct\wiki\workouts\programs\<slug>\day_NN_*.md`
- Notion hub: https://www.notion.so/KILO-33bee045d5ec8030a6f5efe39ba4fadb (hub page id `33bee045d5ec8030a6f5efe39ba4fadb`, hardcoded in kilo.py)
- Env: `NOTION_TOKEN` from `C:\Users\wgriffith2\.claude\.env.personal`

Topology: KILO hub > Program child page > Day child page > workout markdown rendered as blocks. Plain child pages. No databases.

Title rules:
- Program: snake_case to Title Case. Acronyms uppercased: HIIT, EMOM, AMRAP, RDL, DIY.
- Day: `Day NN - Title Case Desc` from `day_NN_desc.md`.

CLI:
- `python kilo.py check <slug>` - reports whether program page exists on Notion.
- `python kilo.py push <slug>` - creates program + day pages. Refuses to overwrite if program exists.
- `python kilo.py push <slug> --resume` - finds-or-creates program page, skips day pages that already exist by title.

Idempotency rule: local is source of truth. Default push errors if program page already exists; user must delete in Notion manually. `--resume` is for recovering from partial failures.

Skill modes (single `/kilo` entrypoint with intent routing):
- push, push --resume, check are implemented.
- update mode is a placeholder; not yet built.

**Why:** Drew works out from Notion on mobile. He selects one program at a time to publish; only the active program lives in Notion. Local markdown stays the canonical source.

**How to apply:** When Drew says "push a workout program" or `/kilo <slug>`, route to push. When he says "fix day X of <slug>" or wants to edit a workout, route to update mode (and tell him update is not yet implemented; scope it with him before building).

First successful push: epic_3 (50 days) on 2026-05-28.
