---
name: python-scripting
description: Write and revise Python automation, API integrations, Windows batch wrappers, and scheduler-friendly utilities for Liberty University work. Use when Drew needs Python scripts, local automation helpers, command-line tools, or task-scheduler orchestration around work tasks.
---

# Python Scripting

## Purpose

Use this skill for Python-centric work that supports Liberty University automation and utility scripting.
This includes API calls, file transforms, batch-file wrappers, Windows Task Scheduler triggers, and small command-line tools.
Keep the workflow practical and work-safe.

## Workflow

- Read the local `AGENTS.md` first.
- Identify the concrete script goal before editing anything.
- Prefer the simplest script that works end to end.
- Use Python as the primary implementation language.
- Use batch files only when a Windows wrapper is needed to launch the Python job or scheduler task.
- Keep config, secrets, and environment-specific paths out of source when possible.
- Protect PII and avoid logging sensitive records unnecessarily.
- Ask before any destructive file or database action.

## Coding Guidance

- Favor readable procedural code over unnecessary abstraction.
- Add type hints when they improve clarity, but do not force them everywhere.
- Keep functions small and purpose-driven.
- Prefer standard library modules unless a third-party dependency materially improves the job.
- Use explicit error handling around API calls, file I/O, and scheduler entry points.
- Make command-line entry points easy to rerun manually.
- When batch files are used, keep them minimal and obvious.

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

