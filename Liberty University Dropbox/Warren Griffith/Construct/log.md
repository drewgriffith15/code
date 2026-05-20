# Construct Log

Append-only record of all ingest, log, query, and lint operations.

Format: `## [YYYY-MM-DD] <operation> | <description>`

Parse last 5 entries: `grep "^## \[" log.md | tail -5`

---

## [2026-05-12] init | Construct initialized

Architecture scaffolded from Karpathy LLM Wiki pattern. Domains: lawn, garden, food, workouts, theology, health, technology, general. Migration from TANK (DuckDB) pending.

## [2026-05-12] update | Architecture finalized

Added raw/<domain>/processed/ subfolders. Added wiki/<domain>/logs/, entities/, summaries/ subdirs for all 8 domains. Added per-domain log index files with domain-appropriate columns. Removed journal layer. CLAUDE.md tightened to Karpathy pattern.

## [2026-05-12] ingest | LLM Wiki (Karpathy)

Processed. Generated: summary, compounding-knowledge-base (concept), rag-vs-llm-wiki (concept), andrej-karpathy (entity), obsidian (entity), obsidian-web-clipper (entity), qmd (entity), technology/overview. Source moved to processed/.

## [2026-05-12] ingest | Build A Second Brain (Matt Wolfe)

Processed. Updated: summary, obsidian entity, obsidian-web-clipper entity, technology/overview. Source moved to processed/.

## [2026-05-12] migration | Phase 1 TANK -> Construct

- lawn: 169 atoms
- garden: 102 atoms
- food: 118 atoms
- health: 57 atoms
- general: 45 atoms
- technology: 74 atoms

Total: 565 files written. 138 name collisions renamed with _tank suffix.

## [2026-05-12] lint | Phase 1 post-migration cleanup

Removed all _tank duplicate files from garden/logs (3 files: transplanted, fertilized, sprayed from April 29 bulk import dupe).

Removed technology domain root dupe of Matt Wolfe video (already in summaries/).

Moved 21 misrouted YouTube/knowledge files from domain roots to summaries/:
- lawn: 1 file
- garden: 7 files (1 was a same-name dupe, deleted)
- general: 1 file
- technology: 12 files (1 was a same-name dupe, deleted)

Built per-domain log indexes: garden (16 entries), food (7 entries), health (1 entry).

Updated global index.md to reflect all migrated content. Workouts and theology still pending.

## [2026-05-12] maintenance | Lint operation expanded

Replaced vague 4-bullet Lint operation in CLAUDE.md with comprehensive 6-part maintenance protocol:
- 1. Naming Convention Validation (date format, source-derived prefixes, timeless reference rules)
- 2. Required Files Per Domain (overview.md, logs/index.md for each domain)
- 3. Frontmatter Completeness (all six fields required: domain, type, date, updated, tags, sources)
- 4. Index Consistency (all wiki/ pages linked from index.md, all wikilinks point to existing files)
- 5. Domain-Specific Audit Rules (lawn, garden, food, theology, workouts, technology)
- 6. Recovery Procedures (table mapping common issues to exact fixes)

Future Claude sessions can execute maintenance audits without clarification.

## [2026-05-12] migration | Phase 2 Theology -> Construct

- lessons: 137 files -> wiki/theology/logs/
- knowledge: 200 files -> wiki/theology/ (summaries/ or root)
- log atoms: 3 files (prayer sessions)
Total: 340 files written. 1 collisions renamed.
Log index built: 140 entries.

## [2026-05-12] lint | Theology cleanup

Moved misrouted file to summaries: 20260511_tactics_all_sessions_gregory_koukl.md -> wiki/theology/summaries/.

Deleted 3 outline-only duplicate May 10th lesson files (all same YouTube source, different TANK lesson IDs).

Renamed May 10th keeper (Final Edited) and 5 future outline-only files to verse-based naming convention:
- 20260510_neh_1.md (Final Edited; was _tank collision file)
- 20260517_neh_2.md through 20260614_neh_6.md (future outlines, Nehemiah series)

Rebuilt theology log index: 135 entries.

## [2026-05-12] migration | Phase 3 CGX -> Construct

- beastmode: 10 files -> wiki/workouts/summaries/beastmode/
- epic_endgame: 50 files -> wiki/workouts/summaries/epic_endgame/
- epic_heat: 50 files -> wiki/workouts/summaries/epic_heat/
- epic_iii: 50 files -> wiki/workouts/summaries/epic_iii/
- fuel: 30 files -> wiki/workouts/summaries/fuel/
- iron: 30 files -> wiki/workouts/summaries/iron/
Total: 220 files written.

## [2026-05-12] lint | Schema compliance fixes

1. CLAUDE.md: Fixed ingest operation paths (`raw/<domain>/` -> `raw/`; `raw/<domain>/processed/` -> `raw/processed/`). Fixed frontmatter date format spec (`YYYY-MM-DD` -> `YYYYMMDD`).
2. wiki/food/: Renamed 10 REMY config files from dated to timeless naming convention. Updated index.md links.
3. Created overview.md for 7 domains: lawn, garden, food, workouts, theology, health, general. Updated index.md with Overview sections for all 7.

## [2026-05-13] ingest | Hooks in Claude Code

Domain: technology. Source moved to raw/processed/.

## [2026-05-13] ingest | How AI Just Changed Stock Picking - Claude's New Finance Plugins

Domain: technology. Source moved to raw/processed/.

## [2026-05-13] ingest | New Skills! /handoff, /prototype, /review and /writing-* | Skills Changelog

Domain: technology. Source moved to raw/processed/.

## [2026-05-13] ingest | 3 Megachurch Pastors Reveal Why They've Decided to Get "Political" | Live Free with Josh Howerton

Domain: theology. Source moved to raw/processed/.

## [2026-05-13] ingest | Pinecone Just Demoted Vector Search. Here's the Knowledge Layer.

Domain: technology. Source moved to raw/processed/.

## [2026-05-13] ingest | How I Train Calves Like An Athlete Not A Bodybuilder

Domain: workouts. Source moved to raw/processed/.

## [2026-05-13] ingest | How to actually force Claude Code to use the right CLI (don't use CLAUDE.md)

Domain: technology. Source moved to raw/processed/.

## [2026-05-13] ingest | Anthropic Just Dethroned OpenAI. Here's What Happens Next.

Domain: technology. Source moved to raw/processed/.

## [2026-05-13] ingest | “The Biggest Android Update Ever”

Domain: technology. Source moved to raw/processed/.

## [2026-05-18] ingest | How To Best Train The Glutes (Rule Of Thirds)

Domain: workouts. Source moved to raw/processed/.

## [2026-05-18] ingest | This is How God Sparks Revivals // Getting It Back // Pastor Josh Howerton

Domain: theology. Source moved to raw/processed/.

## [2026-05-18] ingest | Neuroscience Proves This Biblical Habit Rewires Your Brain

Domain: theology. Source moved to raw/processed/.

## [2026-05-18] ingest | Does Training More Often Actually Make You Fitter? (11-Week Study)

Domain: workouts. Source moved to raw/processed/.

## [2026-05-18] ingest | The OpenSource Tool That Connects Claude to ANY App You Use (NEW System)

Domain: technology. Source moved to raw/processed/.

## [2026-05-18] ingest | I stopped using /grill-me for coding. Here’s what I use instead:

Domain: technology. Source moved to raw/processed/.

## [2026-05-18] ingest | Skill Chaining in Claude OS is INSANE (Don’t Fall Behind!)

Domain: technology. Source moved to raw/processed/.

## [2026-05-18] ingest | Why Bear Grylls' Morning Routine Hasn't Changed in DECADES

Domain: workouts. Source moved to raw/processed/.

## [2026-05-18] ingest | How to Deploy Your Claude Automations (3 Methods)

Domain: technology. Source moved to raw/processed/.

## [2026-05-18] ingest | Microsoft 365 Copilot May 2026 Updates: EVERYTHING You Need to Know

Domain: technology. Source moved to raw/processed/.

## [2026-05-18] ingest | Your SaaS Bill Just Got a Second Meter. You're About to Pay It.

Domain: technology. Source moved to raw/processed/.

## [2026-05-18] ingest | Every Claude Code User NEEDS To Watch This

Domain: technology. Source moved to raw/processed/.

## [2026-05-18] ingest | This Claude Code + Obsidian Command Center is INSANE

Domain: technology. Source moved to raw/processed/.

## [2026-05-19] maintenance | Index and overview sync

Updated index.md and all 8 domain overview.md files to reflect current state:
- Fixed food domain recipe path: `entities/` → `recipes/`
- Corrected summaries counts: general (45→24), health (54→51), technology (89+→85), theology (200+→204)
- Fixed theology path: `lessons/index` → `logs/index`
- Removed broken theology prayer-requests reference
- Updated technology overview current state timestamp (2026-05-12 → 2026-05-19)
- Added workouts research and session log sections
- Verified all domain paths and file references consistent with current directory structure

## [2026-05-18] ingest | Are Generational CURSES Real?! What the Bible REALLY Says... | Live Free with Josh Howerton

Domain: theology. Source moved to raw/processed/.

## [2026-05-18] ingest | Eating Just 1 Cup of THIS Fruit Every Day Makes You Smarter

Domain: health. Source moved to raw/processed/.

## [2026-05-18] ingest | How to Use Your Claude Code Projects in Codex in 5 Mins

Domain: technology. Source moved to raw/processed/.
