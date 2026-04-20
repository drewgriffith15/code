# TANK Setup

## Purpose

TANK is the Liberty University work agent for technical tasks that fall into three lanes. The name is inspired by Tank from *The Matrix* and expands as **Tactical Analytics Network Knowledgebase**.

- Oracle 19c data engineering
- Python scripting and automation
- Oracle 19c ad-hoc SQL

It is meant to be a clean, work-only control plane for local project work. It is not a personal assistant, and it is not a generic catch-all workflow.

## Source Of Truth

The local TANK folder is the authoritative control plane.

- Local control plane: `C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\BitBucket\TANK`
- Global launcher: `C:\Users\wgriffith2\.codex\skills\tank`

The launcher should do nothing except point back to the TANK folder and its skill set.

## Folder Layout

The expected top-level layout is:

```text
TANK/
├── AGENTS.md
├── README.md
├── setup.md
├── .agents/
│   └── skills/
│       ├── tank/
│       ├── data-engineering/
│       ├── python-scripting/
│       └── ad-hoc-sql/
├── prd/
└── worknotes/
```

If a project uses `sandbox/`, treat it as the active build area for that project. If a project does not use `sandbox/`, do not invent one.

## Global Launcher

The global `tank` skill is only a router. It should not contain workflow logic.

Expected behavior:

- resolve to the local TANK control plane
- read the local `AGENTS.md` and `README.md`
- expose the plain skill names
- avoid embedding legacy references or names from prior setups

Validation after install:

- `tank` exists in the global Codex skills directory
- the global launcher points to the TANK folder
- the launcher references the current local skill names

## Skill Map

### data-engineering

Use for Oracle 19c SQL and PL/SQL diagnostics, rewrites, comparisons, and deployment prep.

Avoid:

- DML unless explicitly approved
- destructive DDL unless explicitly approved
- assuming DBA-level visibility

### python-scripting

Use for Python utilities, API integrations, batch-file wrappers, and Windows Task Scheduler helpers.

Avoid:

- hardcoding secrets
- logging sensitive records
- overengineering simple automation

### ad-hoc-sql

Use for read-only Oracle 19c investigation, validation, joins, aggregations, and quick analysis queries.

Avoid:

- DML unless explicitly approved
- destructive DDL unless explicitly approved
- exposing unnecessary PII

## Setup Steps

1. Create the TANK project folder in BitBucket.
2. Add `AGENTS.md`, `README.md`, and `setup.md`.
3. Create `.agents/skills/` with the three plain skill names.
4. Install the global `tank` launcher in `C:\Users\wgriffith2\.codex\skills\tank`.
5. Confirm the global launcher points to the TANK folder.
6. Confirm the three local skills are discoverable by name.
7. Remove any legacy folders, installs, or references that are not part of the current TANK layout.

## Routing Rules

- Use `data-engineering` for Oracle 19c PL/SQL analysis, refactoring, and deployment workflows.
- Use `python-scripting` for Python automation, API calls, and task automation.
- Use `ad-hoc-sql` for read-only Oracle 19c query work.
- If the request could fit more than one lane, choose the narrowest lane that solves the problem.
- If the request is still ambiguous, ask one short question before building.

## Safety Rules

- Ask before any DML.
- Ask before any destructive DDL.
- Do not expose PII or student data unnecessarily.
- Do not add noisy logging or cache sensitive records.
- Keep production changes gated and explicit.

## Maintenance Rules

- Keep the global launcher thin.
- Keep the local skill docs focused on behavior, not history.
- Use plain skill names only.
- Do not reintroduce old naming from prior setups.
- When a skill changes, update the local docs first, then verify the launcher still points to the right place.

## Troubleshooting

- If the launcher is missing, reinstall the global `tank` skill.
- If a skill is not discovered, check the folder name under `.agents/skills/`.
- If a path is wrong, confirm the BitBucket TANK folder is the source of truth.
- If a legacy label appears anywhere, remove the leftover file, folder, or text reference.

## First Verification

Before using TANK on a new machine or profile, verify:

- global `tank` exists
- the local TANK folder exists
- `data-engineering` exists
- `python-scripting` exists
- `ad-hoc-sql` exists
- no legacy references remain
