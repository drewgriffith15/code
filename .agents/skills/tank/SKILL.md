---
name: tank
description: Launch TANK for Liberty University work in Codex. Use when Drew wants the TANK workflow to start a new task, build, fix, documentation update, or work-note pass in a BitBucket project that uses a local `sandbox/`, `prd/`, and `worknotes/` layout.
---

# TANK

Use this skill as the entry point for Liberty University work.

## Behavior

- Read the local `AGENTS.md` first.
- Work in the current project's `sandbox/` folder when that project uses one.
- First decide whether the task is data-engineering, Python scripting, or ad-hoc SQL.
- Route data-engineering work to `tank-data-engineering`.
- Route Python automation, API integration, batch files, and Windows task-scheduler scripting to `tank-python-scripting`.
- Route Oracle 19c ad-hoc query work to `tank-ad-hoc-sql`.
- Keep the task scoped to the current Liberty University BitBucket project unless Drew says otherwise.
- Treat Git history as the archive. Do not route work to a centralized archive folder.
- Ask one question at a time if the request is ambiguous.
- Require explicit user approval before destructive database actions, package promotion, or sandbox clearing.
- When a workflow writes a work note, require the same note block to be pasted into chat for immediate user copy/paste.

## Rules

- Keep solutions simple.
- Keep source files clean.
- Protect PII and avoid unsafe logging.
- Ask before destructive changes.

