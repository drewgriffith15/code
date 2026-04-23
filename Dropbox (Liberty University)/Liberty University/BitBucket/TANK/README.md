**OUTPUT CONSTRAINT: Never use em dashes (—) in any output. Use hyphens (-), semicolons (;), or restructure sentences instead.**

# TANK - Tactical Analytics Network Knowledgebase

TANK is the Liberty University work skill for Codex. The name is inspired by Tank from *The Matrix*, the operator behind the screens who loads programs, reads raw code, and keeps the team moving. In this setup, TANK stands for **Tactical Analytics Network Knowledgebase**.

It handles Oracle 19c data engineering, Python scripting, and ad-hoc SQL for work tasks in BitBucket projects.

TANK exists to provide a clean, work-specific operating model for BitBucket projects and to give you a single launcher for technical work.

When the global Codex `tank` skill is invoked, it should defer to this folder as the source of truth for workflow behavior.

---

## Purpose

TANK is the work-side technical workflow for Liberty University projects.

Use TANK for:
- Building or updating Oracle 19c ETL and analytics workflows
- Writing or revising Python automation, API integration, and scheduler helpers
- Writing ad-hoc Oracle 19c queries for investigation and validation
- Updating project PRDs before implementation when that workflow is needed
- Updating project README documentation when asked
- Generating ServiceNow-ready work notes when that workflow is needed

---

## Operating Model

Each Liberty project uses its own local working folders when applicable:

- `sandbox/` for active development
- `prd/` for change plans and active project PRDs
- `worknotes/` for concise ServiceNow-ready summaries

Rules:

- Do the work in `sandbox/` when the project uses that model.
- Review the exact object, procedure, script, or diff before promotion when the change is part of a larger file.
- Commit to BitBucket before clearing `sandbox/`.
- Keep Git history as the archive for deployed work.
- Do not rely on a centralized archive folder.

---

## Philosophy

**KISS.** Choose the simplest solution that works.

**Clean code.** Do not write banner-style comment blocks inside `.py`, `.sql`, or `.ipynb` files.

**Local traceability.** Keep plans and work notes inside the project that owns the change.

**Work-safe separation.** TANK is for Liberty University work only.

---

## Local Skills

### data-engineering

A workflow for Oracle 19c analysis, diagnostics, rewrites, and comparison scripts.

### python-scripting

A workflow for Python automation, API integrations, batch-file wrappers, and Windows task-scheduler helpers.

### ad-hoc-sql

A workflow for read-only Oracle 19c ad-hoc query and investigation work.

---

## Current Structure

```text
TANK/
├── .agents/
│   └── skills/
│       ├── tank/
│       │   └── SKILL.md
│       ├── data-engineering/
│       │   └── SKILL.md
│       ├── python-scripting/
│       │   └── SKILL.md
│       └── ad-hoc-sql/
│           └── SKILL.md
├── AGENTS.md
├── .gitignore
├── README.md
├── prd/
└── worknotes/
```

This folder is TANK's local control plane. Project-specific prd, work notes, and active development live in the target Liberty project's local `sandbox/`, `prd/`, and `worknotes/` folders when that layout exists.

---

## Standards

- Prefer straightforward implementations over abstraction-heavy patterns
- Keep documentation in `README.md`, `prd/`, and `worknotes/`, not in source-file banner blocks
- Keep credentials out of source code
- Respect production safety and data governance constraints
- Avoid unnecessary churn in existing project layouts

