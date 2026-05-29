---
name: git-commit
description: Detect whether the current repo is personal (GitHub) or work (BitBucket) and set the correct local git user identity. Use when starting work in a repo, before committing, when git identity looks wrong, or when the pre-commit hook blocks a commit due to wrong email.
---

# Git Identity

## Identity Map

| Remote | Email | Name |
|--------|-------|------|
| `github.com/drewgriffith15` | `wgriffith2@gmail.com` | Drew Griffith |
| `bitbucket.liberty.edu` | `wgriffith2@liberty.edu` | Drew Griffith |

## When Invoked

Run these steps:

1. Get the remote URL:
   ```powershell
   git config --get remote.origin.url
   # or if origin isn't set:
   git remote -v
   ```

2. Match against the identity map above.

3. Set local identity (never global):
   ```powershell
   git config user.email "wgriffith2@gmail.com"   # or liberty.edu for work
   git config user.name "Drew Griffith"
   ```

4. Confirm:
   ```powershell
   git config user.email
   git config user.name
   ```

5. Report: "Identity set to **[email]** for this repo."

## CRITICAL RULES (Non-Negotiable)

- **Work repositories ONLY use `wgriffith2@liberty.edu`**
  - Remote: `bitbucket.liberty.edu`
  - Email: `wgriffith2@liberty.edu`
  - Anything else is WRONG

- **Personal repositories ONLY use `wgriffith2@gmail.com`**
  - Remote: `github.com/drewgriffith15`
  - Email: `wgriffith2@gmail.com`
  - Anything else is WRONG

- **Never mix personal and work.** This is a hard boundary.
- If git email doesn't match the remote, BLOCK and ask Drew immediately.
- Always use `--local` scope (no `--global`)
- This skill MUST have a PreToolUse hook that validates remote:email before allowing any commit.

## Work Repo Topology (Liberty University / ADSADS) - DO NOT BREAK

The BitBucket **project** `https://bitbucket.liberty.edu/projects/ADSADS` maps to the local
**folder** `C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University`. A BitBucket
project is a *container of repos*, not a repo. So:

- The `Liberty University` folder is a **plain workspace folder. It must NEVER have its own
  top-level `.git`.** If one exists with remote `ads_etl`, that is the "umbrella" bug: it makes
  the workspace masquerade as a repo and recursively duplicates every project. Remove it.
- **Each project is its own repo, cloned into its own subfolder** (`ADS_ETL/`, `CanvasAPI/`,
  `Golem/`, `GraduationML/`, `PacingModel/`, `PersistenceML/`, `StrategicPlan/`, `gist-*/`, ...).
- The **`ads_etl` repo must contain ONLY ADS_ETL content**: ETL packages (`load_*_etl*.sql`,
  `ads_etl_functions.sql`), `sandbox/`, `PRDs/`, plsql config. It must **NEVER** track submodule
  gitlinks (mode `160000`) to sibling repos or to itself, and **never** an umbrella `README.md`/
  `setup.md` (those are workspace-level, kept at the workspace root only).
- **BitBucket slugs are case-insensitive:** `ads_etl.git` and `ADS_ETL.git` are the **same repo**.
  Never point a submodule/clone at a case-variant of its own parent. That self-reference is what
  caused the recursive "everything collapsed under ADS_ETL" incident.
- **Home dir is the personal repo:** `C:\Users\wgriffith2` is the personal GitHub `code` repo and
  physically encloses the work folder. Its `.gitignore` excludes `/Dropbox (Liberty University)/`
  so work files can never be staged to GitHub. Never `git add` work files from a home-dir shell.

### Guard before committing in the work repo
1. **Always run git from inside the project subfolder** (e.g. `ADS_ETL/`), never the `Liberty University`
   workspace root. From a subfolder, `git rev-parse --show-toplevel` must resolve to **that subfolder**.
   - Run at the workspace root it resolves to `C:/Users/wgriffith2` (the personal `code` repo enclosing
     everything). That is expected; the `.gitignore` line `/Dropbox (Liberty University)/` is the backstop
     that keeps work files out of the personal repo. Never `git add` work files from a workspace-root shell.
2. The `Liberty University` workspace folder must have **no** top-level `.git` of its own (remote `ads_etl`).
   If one reappears, that is the umbrella bug; remove it.
3. In `ADS_ETL/`, confirm **no** gitlinks: `git ls-tree HEAD | findstr 160000` returns nothing.
4. If checks 2 or 3 fail, STOP and surface to Drew before any commit/push.
