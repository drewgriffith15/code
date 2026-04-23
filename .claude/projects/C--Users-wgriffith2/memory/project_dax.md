---
name: DAX Project State
description: DAX agent — 5-phase build state machine, file structure, session timing, skills
type: project
originSessionId: 3094c829-4461-4d37-b6c9-f8850ba1dbbc
---
DAX is Drew's Chief Data Architect & Scientist agent, invoked via `/dax`. Runs a strict 5-phase build state machine (Ideate → Document → Break Down → Build → OCD Check).

**Why:** Personal AI agent for all code/pipeline/data science work across Drew's projects.

**How to apply:** Use DAX for any build request. It's the only agent Drew calls directly for code work.

## File Structure
```
C:\Users\wgriffith2\Dropbox (Liberty University)\Code\DAX\
├── .claude/
│   ├── scripts/
│   │   └── session_timer.py   — phase timestamp logger, duration reporter
│   └── skills/
│       └── build/
│           └── SKILL.md       — 5-phase state machine instructions
├── CLAUDE.md                  — local only (gitignored)
├── .gitignore
├── README.md
└── PRDs/                      — local only (gitignored)
```

## Session Timing
Phase 1–5 start times + Phase 5 end time are logged to a temp JSON file (`dax_session_[ts].json` in system temp dir) via `session_timer.py`. Phase 5 runs `--report` to print total/active duration and delete the file. Idle gaps > 3 hours excluded from active session. All times rounded up to next 30-min ceiling (minimum 30 min).

## Shared .env
All projects under `C:\Users\wgriffith2\Dropbox (Liberty University)\Code\` load from a single `.env` at that root. No project-level `.env` files.

## Phase 5 OCD Check
- **Axis 1:** Modularity
- **Axis 2:** Security
- **Axis 3:** Doc-Sync & Git Hygiene (7-item checklist: PRD, CLAUDE.md, README, .gitignore, Memory, New project check, setup.md)
  - **3.7 setup.md:** Looks for `setup.md` in target project root. If missing, DAX creates it with patterns and shared knowledge. If present, skim and confirm it's current.
- **Axis 4:** Git Summary & Session Timing
- **Axis 5:** Backlog — always ask "Anything to add to the backlog?" Append items to `[target project]/BACKLOG.md` as `- <description> (YYYY-MM-DD)`. Create file if it doesn't exist.
- **Axis 6:** Commit & Push
