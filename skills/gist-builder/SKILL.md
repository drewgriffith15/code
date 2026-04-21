---
name: gist-builder
description: Create or update one-off Liberty University work artifacts under the local gist folder. Use when Drew wants a version-controlled ad hoc deliverable such as a read-only Oracle SQL file, a Python utility script, or a markdown prompt artifact saved in `gist/sql`, `gist/python`, or `gist/prompt`.
---

# Gist Builder

Direct entry: use this skill when the request is a one-off artifact that should live in `gist/` instead of a project `sandbox/`.

## Purpose

Use this skill for version-controlled one-off work artifacts.
Default output types are:

- read-only Oracle SQL in `gist/sql`
- Python scripts in `gist/python`
- markdown prompts in `gist/prompt`

Keep the artifact thin, useful, and easy to find later.
Do not turn a gist request into a project workflow unless the user explicitly wants that escalation.

## Phase 1 - Ideation

Start by clarifying the artifact before writing it.

- Read the local `AGENTS.md` first.
- Identify the artifact type first: SQL, Python, or prompt markdown.
- Identify the exact deliverable, intended use, likely rerun value, and the smallest useful output.
- Record the session start timestamp so Phase 5 can report actual duration when that level of closeout is useful.
- Decide whether this really belongs in `gist/` or whether it has crossed into `data-engineering` or `python-scripting`.
- If the request is still a one-off, keep the scope narrow and avoid project-level ceremony.

## Workflow

- Write the artifact to the matching `gist/` subfolder.
- Name the file for the request, not the date.
- Prefer one request per file.
- Keep the output ready to use without extra wrappers or ceremony.
- Escalate to `data-engineering` or `python-scripting` only when the work stops being a one-off artifact and becomes a broader implementation workflow.

## Artifact Guidance

### SQL

- Default to read-only Oracle 19c SQL.
- Use clear aliases, explicit joins, and CTEs when they improve readability.
- Keep result sets targeted and minimize exposure of student data.
- Avoid SQL*Plus session commands unless the user explicitly asks for them.

### Python

- Prefer a single clear script over framework-heavy structure.
- Keep configuration and secrets out of source.
- Add light argument handling only when it materially improves rerun value.

### Prompt Markdown

- Save prompt artifacts as `.md`.
- Keep the prompt easy to paste into another AI tool.
- Use headings, bullets, and fenced blocks only when they improve reuse.
- Treat durable reusable behavior as a candidate for `skills/` or `templates/`, not `gist/`.

## Phase 5 - OCD Check (Tidy and Sync)

Run a lightweight final review before closing the one-off artifact.

### Axis 1 - Modularity

- Check whether the artifact is clean, minimal, and not carrying duplicated or unnecessary sections.
- Tighten only the touched artifact. Do not turn gist work into a refactor.

### Axis 2 - Security

- Check for hardcoded credentials, environment-specific paths, or content that exposes PII or student data unnecessarily.
- Fix issues found before finalizing the gist.

### Axis 3 - Doc Sync

- Usually no broader doc sync is needed for a one-off gist.
- If the gist introduced a reusable pattern that should move into a project doc, skill, or memory file, call that out explicitly.

### Axis 4 - Git Summary and Session Timing

- When the gist work is substantial enough to merit closeout, report the session start, end, and duration.
- Review the file diff before summarizing.
- Produce a short commit-ready summary when the user wants the gist committed.

### Axis 5 - Commit and Push

- This skill does not stage, commit, or push to BitBucket by default.
- If the user wants the gist committed, either get explicit approval for Git actions in the current repo or escalate the work into the appropriate project workflow.

## Safety Rules

- Do not recommend DML or destructive DDL unless the user explicitly asks.
- Do not expose PII or student records beyond what is needed for the artifact.
- Do not assume DBA-level visibility or privileges for SQL artifacts.
- Ask before destructive file or database actions.
- This skill does not stage, commit, or push to BitBucket.
