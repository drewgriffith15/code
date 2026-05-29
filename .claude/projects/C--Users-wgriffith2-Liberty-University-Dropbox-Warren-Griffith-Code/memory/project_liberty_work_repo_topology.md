---
name: project-liberty-work-repo-topology
description: "Liberty work folder is a workspace (BitBucket PROJECT), NOT a repo; each project is its own clone; ads_etl holds ETL code only, never submodule gitlinks"
metadata: 
  node_type: memory
  type: project
  originSessionId: 677a40a2-e358-40c2-a7b0-adebf750b52b
---

The BitBucket **project** `https://bitbucket.liberty.edu/projects/ADSADS` maps to the local **folder** `C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University`. A BitBucket project is a container of repos, not a clonable repo.

Canonical structure:
- `Liberty University` is a **plain workspace folder with NO top-level `.git`.**
- Each project is its own repo cloned into its own subfolder: `ADS_ETL/`, `CanvasAPI/`, `CourseSuccessML/`, `Golem/`, `GraduationML/`, `PacingModel/`, `PersistenceML/`, `StrategicPlan/`, `gist-prompt/`, `gist-python/`, `gist-sql/`.
- The `ads_etl` repo (subfolder `ADS_ETL/`) contains **only** ADS_ETL content: `load_*_etl*.sql`, `ads_etl_functions.sql`, `sandbox/`, `PRDs/`, plsql config. It must **never** track submodule gitlinks (mode `160000`) to sibling repos or itself, and never an umbrella `README.md`/`setup.md` (workspace docs live at the workspace root only, untracked).

**Incident 2026-05-29:** a top-level `.git` (remote `ads_etl`) had turned the workspace into a fake "umbrella" repo tracking 11 submodule gitlinks (10 siblings + a self-reference). Because BitBucket slugs are case-insensitive, `ADS_ETL.git` == `ads_etl.git`, so the ADS_ETL submodule pointed at its own parent and recursively cloned every project into `ADS_ETL/` ("everything collapsed under ADSETL"). Separately, commit `1864034` ("Remove stray SQL files from repo root") had deleted 20 production ETL files; they were recovered from `1864034^` onto branch `fix/restore-etl-and-clean-umbrella`.

**Guardrails (never let this recur):**
- Never create/keep a top-level `.git` on the `Liberty University` folder.
- Never add submodule gitlinks to `ads_etl`; never point any clone at a case-variant of its own parent slug.
- Home dir `C:\Users\wgriffith2` is the personal GitHub `code` repo and encloses the work folder. Its `.gitignore` now excludes `/Dropbox (Liberty University)/` so work files can't leak to GitHub. Never `git add` work files from a home-dir shell. See [[feedback_no_mid_chat_model_switch]] style walled-garden discipline in global CLAUDE.md.
- The `/git-commit` skill SKILL.md now carries this topology + a pre-commit guard.
