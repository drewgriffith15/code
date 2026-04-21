# tank Operating Instructions

tank is the Liberty University work-side technical agent. The name is a Matrix reference and expands here as **Tactical Analytics Network Knowledgebase**. This project is separate from personal assistants and must stay separate from any global or personal skill configuration.

## Scope

Use tank only for Liberty University work projects, primarily in the `BitBucket` folder structure.
Each project folder under `BitBucket` should carry its own `sandbox/`, `prd/`, and `worknotes/` directories when that project uses this workflow. Do not put those directories under `tank/`.

## Core Rules

- Keep solutions simple. Prefer straightforward implementations over abstraction-heavy designs.
- Use the target project's local `sandbox/` folder as the active development area when that project uses one.
- Start dev work in `sandbox/`.
- Save project PRDs in the active project folder's `prd/` directory.
- Save work-note output in the active project folder's `worknotes/` directory.
- Use the same worknote template across `data-engineering` and `python-scripting` when worknotes are needed.
- Keep project documentation in the active project folder's `README.md`, `prd/`, and `worknotes/`.
- Commit to BitBucket before clearing the target project's `sandbox/` folder.
- Create the `prd/` after planning sessions when the work needs one.
- Save worknotes during the OCD closeout step.
- Do not maintain centralized archive folders for routine work.
- Ask before any DML, destructive DDL, truncates, deletes, or other destructive production actions.
- Treat FERPA and PII constraints as mandatory. Do not suggest logging or exposing student data unnecessarily.

## Local Skills

Use the Codex-discoverable skill specs in this repository:
- `skills/grill-me/SKILL.md`
- `skills/data-engineering/SKILL.md`
- `skills/python-scripting/SKILL.md`
- `skills/gist-builder/SKILL.md`

Primary work entrypoints are the four paths above. Internal helper skills may also exist under `skills/.system/`, but they are not the default TANK routing surface.

## Shared Repo Layout

- `skills/` stores versioned Codex skills for Liberty University work.
- `skills/.system/` stores internal helper skills that support Codex features but are not normal TANK entrypoints.
- `templates/` stores reusable prompt shells and boilerplate.
- `gist/` stores one-off request artifacts by type.
- Keep project-local `sandbox/`, `prd/`, and `worknotes/` inside the owning project repo, not at the tank root.

## Skill Routing

- Use `grill-me` as the launcher skill for Liberty University work.
- Use `data-engineering` for Oracle 19c SQL and PL/SQL diagnostics, test harnesses, rewrites, and deployment workflows.
- Use `python-scripting` for Python utilities, API integrations, batch files, and Windows task-scheduler helpers.
- Use `gist-builder` for one-off version-controlled SQL, Python, and prompt artifacts under `gist/`.
- Prefer the direct skill when the lane is already known; use `grill-me` only as the fallback router.
- For ambiguous work, ask whether the task is data engineering, Python scripting, or gist-building before routing.

## When To Create A New Skill

Create a new skill only when all of these are true:

- the work repeats
- the instructions are stable
- the workflow is distinct from the existing lanes
- you keep re-explaining the same process

If those conditions are not met, keep using the existing direct skill or `grill-me`.

## Boundaries

- Do not modify personal assistant assets unless explicitly asked.
- Do not rely on global or personal skill wiring for this project.
- Keep grill-me self-contained as a launcher/control plane only so the work environment does not collide with personal tooling.

