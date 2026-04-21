---
name: python-scripting
description: Write and revise Python automation, API integrations, Windows batch wrappers, and scheduler-friendly utilities for Liberty University work. Use when Drew needs Python scripts, local automation helpers, command-line tools, or task-scheduler orchestration around work tasks.
---

# Python Scripting

Direct entry: use this skill when you already know the work is Python automation or scripting.

## Purpose

Use this skill for Python-centric work that supports Liberty University automation and utility scripting.
This includes API calls, file transforms, batch-file wrappers, Windows Task Scheduler triggers, and small command-line tools.
Keep the workflow practical and work-safe.

## Phase 1 - Ideation

Start by framing the script before editing files.

- Read the local `AGENTS.md` first.
- Identify the concrete script goal, the user-visible output, and the minimum viable implementation path.
- State the inputs, outputs, dependencies, secrets, scheduling needs, and any operational constraints that matter.
- Call out risks up front, especially destructive actions, PII exposure, brittle paths, scheduler assumptions, or API failure modes.
- Record the session start timestamp so Phase 5 can report actual duration.
- If the request needs a PRD or implementation note for the project, create or update it before coding.
- Prefer the simplest end-to-end design that solves the actual job, not the fanciest script structure.

## Workflow

- Use Python as the primary implementation language.
- Use batch files only when a Windows wrapper is needed to launch the Python job or scheduler task.
- Keep config, secrets, and environment-specific paths out of source when possible.
- Protect PII and avoid logging sensitive records unnecessarily.
- Ask before any destructive file or database action.
- Validate the script in a practical way before calling it done.

## Coding Guidance

- Favor readable procedural code over unnecessary abstraction.
- Add type hints when they improve clarity, but do not force them everywhere.
- Keep functions small and purpose-driven.
- Prefer standard library modules unless a third-party dependency materially improves the job.
- Use explicit error handling around API calls, file I/O, and scheduler entry points.
- Make command-line entry points easy to rerun manually.
- When batch files are used, keep them minimal and obvious.

## Phase 5 - OCD Check (Tidy and Sync)

Run a final review after the script works and before closing the session.

### Axis 1 - Modularity

- Check touched files for oversized functions, duplicated logic, weak naming, and unnecessary complexity.
- Split or tighten code only where it improves the touched implementation. Do not refactor unrelated areas.

### Axis 2 - Security

- Check for hardcoded credentials, API keys, tokens, local machine paths, or environment assumptions that should move to config or `.env`.
- Check logs, exceptions, and print statements for PII, student data, or secret leakage.
- Fix issues found in the touched files.

### Axis 3 - Doc Sync

- Update the active PRD if the implementation path changed from the original plan.
- Update project `CLAUDE.md` when the work introduced new conventions, constraints, commands, or file-structure expectations.
- Update project `README.md` when the script changes how the project is run, configured, or understood.
- Update the relevant project memory file under `C:\Users\wgriffith2\.claude\projects\C--Users-wgriffith2\memory\` when the project state materially changed.
- Write the final work note if the project expects one.

### Axis 4 - Git Summary and Session Timing

- Retrieve the session start timestamp recorded in Phase 1.
- Capture the session end timestamp.
- Report the actual elapsed time in a compact start, end, and duration block.
- Review `git diff --stat` and the actual file diffs before proposing a summary.
- Produce a commit-ready summary with an imperative one-line title and 3 to 5 bullets that explain both what changed and why.

### Axis 5 - Commit and Push

- Ask Drew whether to commit and push after the OCD check summary is complete.
- If approved, stage only the files touched in this build. Do not use blanket staging.
- Commit with the approved summary and treat push as a separate explicit approval gate unless Drew clearly approved both.

## Safety Rules

- Do not surface secrets, tokens, or student data in logs or console output.
- Do not build automation that bypasses approval gates for destructive actions.
- Keep scripts local to the current Liberty University project unless Drew says otherwise.
- This skill is allowed to stage, commit, and push validated BitBucket changes when the user approves the scope.

## Worknote Template

Use this exact structure for the project work note:

```md
<short summary under 150 characters>

- Session start: <timestamp>
- Session end: <timestamp>
- Duration: <elapsed time>
- What changed: <brief summary>
- Validation: <what was checked>
- OCD check: <pass/fail or short result>
- Follow-ups: <remaining items or "None">
```
