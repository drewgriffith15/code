# TANK — Tactical Analytics Network Knowledgebase

tank is the Liberty University work repo for Codex. The launcher skill is `grill-me`, inspired by Tank from *The Matrix*, the operator behind the screens who loads programs, reads raw code, and keeps the team moving.

It handles Oracle 19c data engineering, Python scripting, and version-controlled one-off SQL, Python, and prompt artifacts for work tasks in BitBucket projects.

This repo exists to provide a clean, work-specific operating model for BitBucket projects and to give you a single launcher for technical work.

Primary entrypoints are the direct skills:

- `data-engineering`
- `python-scripting`
- `gist-builder`

Use `grill-me` only when you do not know which lane applies yet.

Create a new skill only when the work is repeated, distinct, and stable enough that the same instructions keep coming back.

When the global Codex `grill-me` skill is invoked, it should defer to this folder as the source of truth for workflow behavior.

---

## Purpose

This repo is the work-side technical workflow for Liberty University projects.

Use `grill-me` for:
- Building or updating Oracle 19c ETL and analytics workflows
- Writing or revising Python automation, API integration, and scheduler helpers
- Creating one-off SQL, Python, and prompt artifacts under `gist/`
- Updating project PRDs before implementation when that workflow is needed
- Updating project README documentation when asked
- Generating ServiceNow-ready work notes when that workflow is needed

Worknotes use the same concise template across the project-oriented skills when they are needed.

---

## Operating Model

Each Liberty project uses its own local working folders when applicable:

- `sandbox/` for active development
- `prd/` for change plans and active project PRDs
- `worknotes/` for concise ServiceNow-ready summaries

Rules:

- Do the work in `sandbox/` when the project uses that model.
- Start dev work in `sandbox/`.
- Keep `prd/` and `worknotes/` inside the active project folder, not at the repo root.
- Create `prd/` after the planning session when the work needs one.
- Save `worknotes/` during the OCD closeout step.
- Review the exact object, procedure, script, or diff before promotion when the change is part of a larger file.
- Commit to BitBucket before clearing `sandbox/`.
- Keep Git history as the archive for deployed work.
- Do not rely on a centralized archive folder.

---

## Philosophy

**KISS.** Choose the simplest solution that works.

**Clean code.** Do not write banner-style comment blocks inside `.py`, `.sql`, or `.ipynb` files.

**Local traceability.** Keep plans and work notes inside the project that owns the change.

**Work-safe separation.** This repo is for Liberty University work only.

---

## Local Skills

### data-engineering

A workflow for Oracle 19c analysis, diagnostics, rewrites, and comparison scripts.

### python-scripting

A workflow for Python automation, API integrations, batch-file wrappers, and Windows task-scheduler helpers.

### gist-builder

A workflow for one-off version-controlled SQL, Python, and prompt artifacts under `gist/`.

### Hidden system skills

`skills/.system/` holds internal helper skills that support Codex capabilities. They are part of the repo structure but are not the primary work entrypoints for TANK usage.

---

## Current Structure

```text
tank/
├── gist/
│   ├── sql/
│   ├── python/
│   └── prompt/
├── skills/
│   ├── .system/
│   │   └── <internal helper skills>/
│   ├── grill-me/
│   │   └── SKILL.md
│   ├── data-engineering/
│   │   └── SKILL.md
│   ├── python-scripting/
│   │   └── SKILL.md
│   └── gist-builder/
│       └── SKILL.md
├── templates/
├── AGENTS.md
├── .gitignore
├── README.md
└── setup.md
```

This folder is the local control plane plus the shared work asset root. Project-specific `sandbox/`, `prd/`, and `worknotes/` live in each target Liberty project folder when that layout exists.

---

## Standards

- Prefer straightforward implementations over abstraction-heavy patterns
- Keep documentation in `README.md`, `prd/`, and `worknotes/`, not in source-file banner blocks
- Keep credentials out of source code
- Respect production safety and data governance constraints
- Avoid unnecessary churn in existing project layouts

