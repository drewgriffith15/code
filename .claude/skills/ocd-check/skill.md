---
name: ocd-check
description: Standalone code quality and architecture review. Run after a build session, before a major refactor, or any time the codebase feels drifty. Scopes to recently changed files via git diff. Blends architectural depth analysis (seams, modules, leverage) with modularity, security, doc-sync, and a commit-ready git summary. Use when Drew types /ocd-check or asks for an OCD check, architecture review, or code cleanup outside of a build session.
model: claude-haiku-4-5
---

# OCD Check

A standalone code quality and architecture review. Scoped to recently changed files — not the whole codebase. Token-efficient, targeted, and structured.

Vocabulary for architecture analysis is defined in [LANGUAGE.md](LANGUAGE.md). Use those terms exactly. Don't drift into "service," "component," "boundary," or "API."

---

## WALLED GARDEN VALIDATION (Pre-Phase)

**CRITICAL: Run this first, before all phases.**

Ask Drew to confirm repo type. Options:
- Work (BitBucket) — Liberty University ADS_ETL projects
- Personal (GitHub) — drewgriffith15 personal repos

Once confirmed, validate the git remote matches:

```bash
git config --get remote.origin.url
```

**Validation rules:**
- Work repos MUST have `bitbucket.liberty.edu` in remote
- Personal repos MUST have `github.com/drewgriffith15` in remote

If mismatch:
> WALLED GARDEN VIOLATION. You said this is [work/personal], but the remote is [GitHub/BitBucket]. This repo is configured for the wrong environment. Fix the git remote or switch to the correct working directory.

Stop and do not proceed. This catches configuration errors before any commits.

If valid, proceed to Phase 0.

---

## Phase 0 — SCOPE DETECTION

Run this first, every time:

```bash
git diff --name-only HEAD~10
```

If that returns nothing (clean history or new repo), fall back to:

```bash
git diff --name-only origin/master...HEAD
```

List the changed files to Drew. Say:

> Scoping OCD Check to [N] changed files: [list]. Proceeding.

Do not ask for approval — just proceed immediately to Phase 1.

---

## Phase 1 — ARCHITECTURAL ANALYSIS

Read each changed file. Apply the deletion test and the seam discipline from [LANGUAGE.md](LANGUAGE.md) and [DEEPENING.md](DEEPENING.md).

For each file or cluster of files, look for:

- **Shallow modules** — interface nearly as complex as the implementation. Apply the deletion test: would deleting this module concentrate complexity, or just move it?
- **Missing seams** — tightly coupled modules where behaviour cannot be altered without editing in place.
- **Phantom seams** — single-adapter seams that add indirection without enabling variation.
- **Locality failures** — pure functions extracted just for testability, but the real bugs hide in how they're called.
- **Untestable interfaces** — callers must test *past* the interface because the module is the wrong shape.

Produce a numbered candidate list. For each:

```
[N]. Files: [which files/modules]
     Problem: [why this causes friction — use LANGUAGE.md vocab]
     Solution: [what would change in plain English]
     Benefits: [leverage for callers, locality for maintainers, how tests improve]
```

If no architectural issues are found in the changed files, say so directly and skip to Phase 2.

If issues are found, present the list and ask:

> Which of these would you like to explore, or shall I proceed to Phase 2?

If Drew picks a candidate, drop into a grilling loop (see GRILLING section below). Otherwise proceed to Phase 2.

---

## GRILLING LOOP (optional, triggered from Phase 1)

When Drew picks a candidate, walk the design tree with him. One question at a time.

Cover: constraints, dependencies (use [DEEPENING.md](DEEPENING.md) categories), shape of the deepened module, what sits behind the seam, what tests survive.

Side effects during the loop:
- **New concept not in CONTEXT.md?** Add it now.
- **Fuzzy term sharpened during conversation?** Update CONTEXT.md now.
- **Drew rejects candidate with a load-bearing reason?** Offer to record it as an ADR (see [ADR-FORMAT.md](../grill-with-docs/ADR-FORMAT.md)).
- **Drew wants to compare interface designs?** Use [INTERFACE-DESIGN.md](INTERFACE-DESIGN.md).

When the grilling is done, say:

> Grilling complete. Moving to Phase 2 — Modularity & Security.

---

## Phase 2 — MODULARITY & SECURITY

Review the changed files only. Do not refactor files that weren't touched.

### Modularity
- Functions longer than ~30 lines that should be split?
- Duplicated logic that should be extracted?
- Variable names unclear or not self-documenting?
- Fix any issues found inline.

### Security
- Hardcoded credentials, API keys, or paths that should be `.env` variables?
- PII exposed in logs or print statements?
- Fix any issues found inline.

Report what was fixed or confirm each axis is clean.

---

## Phase 3 — DOC-SYNC

Work through each item in order. Report status for each before moving to the next. No batching.

**Status format:**
```
✓ [Item] — [what was done or confirmed]
↩ [Item] — skipped: [reason]
✏ [Item] — updated: [what changed]
```

**3.1 CLAUDE.md**
Read the project's `CLAUDE.md`. Were any new conventions, file structure changes, or constraints visible in the changed files? If yes, update it.

**3.2 README.md**
Read the project's `README.md`. Do the changed files affect how the project works, its commands, credentials, or skills? If yes, update it.

**3.3 .gitignore**
Read `.gitignore`. Verify it excludes: `.env`, credentials, databases, `PRDs/`. Add anything missing.

**3.4 Memory**
Read the relevant memory file under `C:\Users\wgriffith2\.claude\projects\C--Users-wgriffith2\memory\`. Does it reflect current project state? If not, update it.

**3.5 setup.md**
Check for `setup.md` in the project root. If missing, create one from patterns in the changed files. If present, confirm it still reflects the current workflow.

**3.6 Skills sync (conditional)**
If any `.claude/skills/` path appears in the git diff scope, run:
```powershell
& "C:\Users\wgriffith2\Dropbox (Liberty University)\Code\skills\scripts\sync-commands.ps1"
```
Fix any MISSING or STALE entries in `commands.html` at `C:\Users\wgriffith2\Dropbox (Liberty University)\Code\commands.html`. If no skills changed, skip and say so.

---

## Phase 4 — GIT SUMMARY

Run:

```bash
git diff --stat
```

Then read the diff for each changed file.

Produce a commit-ready summary in this exact format — nothing before it, nothing after it:

```
<one-line title: imperative verb, max 72 chars>

- <what changed and why — 3 to 5 bullets>
- <specific: function names, field names, behavior changes>
- <include the "why" not just the "what">
```

After producing the summary, say:

> OCD Check complete. Commit with the above message?

If Drew says yes, run:

1. **Set git identity** — check the remote and set `--local` identity before committing:
   ```bash
   git config --get remote.origin.url
   ```
   Match against this identity map:
   | Remote | Email |
   |--------|-------|
   | `github.com/drewgriffith15` | `wgriffith2@gmail.com` |
   | `bitbucket.liberty.edu` | `wgriffith2@liberty.edu` |

   Set with:
   ```bash
   git config --local user.email "<matched_email>"
   git config --local user.name "Drew Griffith"
   ```
   If the remote doesn't match either entry, STOP and ask Drew before proceeding.

2. `git add` on only the files modified during this check (no `git add -A`)
3. `git commit -m "[summary]"` — no Co-Authored-By attribution on work commits (BitBucket remotes)
4. `git push`
5. Report the result.

---

## Rules

- Scope to changed files only. Never scan the full codebase unprompted.
- Use [LANGUAGE.md](LANGUAGE.md) vocab for all architecture observations. No substitutions.
- Fix inline during Phase 2. Don't produce a report and leave it for Drew to action.
- One status line per doc-sync item. No batching.
- Never use `git add -A` or `git add .`.
