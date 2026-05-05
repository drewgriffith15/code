---
name: TANK Project State
description: Unified DuckDB second brain architecture, domain-specific skills, benchmarking tools
type: project
originSessionId: 1415b19e-2760-4ae7-8126-f800cad1f59e
---
## Current State (2026-05-04)

**Architecture:** Single DuckDB database (`tank.ddb`) with unified API (`scripts/tank.py`). All personal AI skills read/write to TANK. Domains: lawn, garden, tasks, food, theology, knowledge, workouts.

**Recent Changes (2026-05-05):**
- PRD workflow updated: PRDs now carry metadata block (Status/Created/Completed). Completed PRDs move to `PRDs/completed/` instead of renaming. Build skill Phase 2 + Phase 5 updated accordingly.
- `scripts/backfill_prd_metadata.py` run once to migrate all existing `*_DONE_*` PRDs (24 files); script can now be deleted.

**Prior Changes (2026-05-04):**
- Renamed domain `meals` → `food` across DB, all skills, remy.py, migrate_remy_data.py
- Renamed skill `tank-meals` → `tank-food`
- Idempotency layer shipped: add_atom() dedup for knowledge/task atoms (2026-05-05)
- YouTube ingest pipeline shipped: youtube_ingest.py fetches playlist, transcribes via yt-dlp, classifies+summarizes via Haiku, writes to TANK as knowledge atoms (2026-05-05)

**Key Functions:**
- `query_by_context(context_domain, tag, status)` - filter tasks by context domain
- `query(domain, type, tags, limit)` - general filtered query
- `add_atom()` - idempotent for knowledge/task types: re-insert same (domain, type, title) returns existing id silently; log atoms always insert
- `add_task()`, `complete_task()` - write operations
- `hybrid_search()`, `find_similar_atoms()` - semantic search

**Skills:** `/tank-lawn`, `/tank-garden`, `/tank-food`, `/tank-tasks`, `/tank-theology`, `/tank-knowledge`, `/tank-workouts` (domain-specific), `/remy`, `/theo`, `/kilo` (pipeline agents)

**Utilities:** `weather.py`, `holidays.py`, `dates.py` (standalone, no DB dependency)

**Remaining Optimization Opportunities:** Connection pooling for DuckDB, query result caching for repeated queries.
