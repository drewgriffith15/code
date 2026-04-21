# tank Setup

## Purpose

tank is the Liberty University work repo for technical tasks that fall into three lanes. The launcher skill is `grill-me`, inspired by Tank from *The Matrix*.

- Oracle 19c data engineering
- Python scripting and automation
- Version-controlled one-off SQL, Python, and prompt artifacts

It is meant to be a clean, work-only control plane for local project work. It is not a personal assistant, and it is not a generic catch-all workflow.

## Source Of Truth

The local TANK folder is the authoritative control plane.

- Local control plane: `C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\BitBucket\TANK`
- Global Codex skill path: `C:\Users\wgriffith2\.codex\skills`
- Global launcher: `C:\Users\wgriffith2\.codex\skills\grill-me`

The launcher should do nothing except point back to the tank folder and its skill set.
Codex should resolve only through the tank-controlled skill set.

## Folder Layout

The expected top-level layout is:

```text
TANK/
├── AGENTS.md
├── README.md
├── setup.md
├── gist/
│   ├── sql/
│   ├── python/
│   └── prompt/
├── skills/
│   ├── .system/
│   │   └── <internal helper skills>/
│   ├── grill-me/
│   ├── data-engineering/
│   ├── python-scripting/
│   └── gist-builder/
├── templates/
└── (no root prd/ or worknotes/)
```

If a project uses this workflow, treat `sandbox/` as the active build area, create `prd/` after planning, and save `worknotes/` during closeout. If a project does not use `sandbox/`, do not invent one.

## Global Launcher

The global `grill-me` skill is only a router. It should not contain workflow logic.

Expected behavior:

- resolve to the local TANK control plane
- read the local `AGENTS.md` and `README.md`
- expose the plain skill names
- avoid embedding legacy references or names from prior setups
- prefer direct skills when the lane is already known
- use `grill-me` only when the lane is ambiguous or when you want a prompt/workflow builder
- leave `skills/.system/` available for helper capabilities without treating it as the normal work entry surface

## Recommended Install Pattern

The cleanest setup is to keep the real skill content in the TANK repo and expose it to Codex with a directory symlink.

Target layout:

- real skills live here: `C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\BitBucket\TANK\skills`
- Codex points here: `C:\Users\wgriffith2\.codex\skills`

This keeps the work-side skill set versioned in BitBucket while letting Codex discover it through its normal local skill path.

### Create Or Reset The Link

Run these steps from an elevated Command Prompt.

1. Close Codex first.
2. If `C:\Users\wgriffith2\.codex\skills` already exists as a normal folder, delete or rename it.
3. Create the symlink:

```bat
mklink /D "C:\Users\wgriffith2\.codex\skills" "C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\BitBucket\TANK\skills"
```

4. Reopen Codex.
5. Confirm Codex now sees the tank-managed skills from the linked folder.
6. Confirm the direct skills are the normal entrypoints and `grill-me` is only a fallback.

### Reset Troubleshooting

If Codex starts showing the wrong skills again:

1. Verify `C:\Users\wgriffith2\.codex\skills` is still a directory link and not a copied folder.
2. Verify the link target still points to `TANK\skills`.
3. Verify the TANK repo still contains only the skills you want Codex to see.
4. Remove any stray non-TANK skill folders from the Codex path if they were copied in manually.

Validation after install:

- `grill-me` exists in the global Codex skills directory
- the global launcher points to the tank folder
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

### gist-builder

Use for one-off version-controlled SQL, Python, and prompt artifacts stored under `gist/`.

Avoid:

- letting one-off artifacts sprawl into project workflows
- destructive database or file actions unless explicitly approved
- exposing unnecessary PII

## Setup Steps

1. Create the tank project folder in BitBucket.
2. Add `AGENTS.md`, `README.md`, and `setup.md`.
3. Create `skills/` with the plain skill names.
4. Install or update the global `grill-me` launcher in `C:\Users\wgriffith2\.codex\skills\grill-me`.
5. Point `C:\Users\wgriffith2\.codex\skills` to `C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University\BitBucket\TANK\skills` with an elevated `mklink /D`.
6. Confirm the global launcher points to the tank folder.
7. Confirm the three direct local skills are discoverable by name.
8. Remove any legacy folders, installs, or references that are not part of the current TANK layout.

## Routing Rules

- Use `data-engineering` for Oracle 19c PL/SQL analysis, refactoring, and deployment workflows.
- Use `python-scripting` for Python automation, API calls, and task automation.
- Use `gist-builder` for one-off SQL, Python, and prompt artifact work.
- If the request could fit more than one lane, choose the narrowest lane that solves the problem.
- If the request is still ambiguous, ask one short question before building.
- The shared folder convention is `sandbox/` first, `prd/` after planning, and `worknotes/` during OCD closeout.

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
- Prefer the symlinked Codex skills path over copying skills into `.codex\skills`.
- When a skill changes, update the local docs first, then verify the launcher still points to the right place.

## Troubleshooting

- If the launcher is missing, reinstall the global `grill-me` skill.
- If Codex shows the wrong skills, verify the `.codex\skills` link and recreate it if needed.
- If a skill is not discovered, check the folder name under `skills/`.
- If a path is wrong, confirm the BitBucket TANK folder is the source of truth.
- If a legacy label appears anywhere, remove the leftover file, folder, or text reference.

## First Verification

Before using TANK on a new machine or profile, verify:

- global `grill-me` exists
- the local TANK folder exists
- `data-engineering` exists
- `python-scripting` exists
- `gist-builder` exists
- no legacy references remain
