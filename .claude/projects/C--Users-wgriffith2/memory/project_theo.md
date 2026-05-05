---
name: THEO Project State
description: Lesson pipeline - plan/draft/full CLI, Notion push/sync, voice patterns, sidecar pattern
type: project
originSessionId: 206ecdca-65d8-4c7e-b47d-ea6c7cb6a781
---
## Current State (2026-05-02)

**Location:** `C:/Users/wgriffith2/Code/TANK/` (integrated into TANK as of 2026-04-30)

**Pipeline:** `theo.py plan/draft/full` - transcript -> outline (Opus + extended thinking) -> draft (Sonnet, voice guide injected) -> ghost-writer polish -> auto FULL page push to Notion -> sync edits back to TANK

**Scripts:**
- `scripts/theo.py` - main CLI; plan/draft/full subcommands
- `scripts/theo_notion_push.py` - push draft to private Notion FULL page; exports `create_full_page(lesson_id, content, title, parent_page_id)`
- `scripts/theo_notion_sync.py` - pull Notion edits back to `lessons.final_edited`
- `scripts/update_voice.py` - refresh voice_patterns.json from last 3 final_edited lessons
- `references/voice_patterns.json` - Drew's voice patterns; injected into section prompts

**TANK lessons table fields:** `id, lesson_date, title, book, chapter, series, url, verses, source_transcript, outline, draft, final_edited, notion_page_id (FULL page), notion_url (FULL page), created_at, updated_at`

**Sidecar pattern:** `plan` creates `outline_name.json` alongside outline file with `lesson_id` and `outline_notion_page_id`. `draft` reads both; uses `outline_notion_page_id` to append FULL page link to the Notion outline entry.

**FULL page workflow (as of 2026-05-02):**
- `run_draft()` auto-creates private FULL page under `THEO_HUB_PAGE_ID` (env var, fallback to hardcoded)
- Stores `notion_page_id` and `notion_url` in TANK (NOT the outline page ID - that's separate)
- Appends a "FULL Page: [link]" block to the outline page in Notion via `_link_full_page_to_outline()`
- `theo_notion_push.py` CLI is now for manual re-push only

**Models:** Opus 4.7 for outline generation (extended thinking), Sonnet 4.6 for draft sections + ghost-writer, Haiku 4.5 for title/slug extraction

**Skills:**
- `/theo-outline` - one or more transcripts -> outlines; auto-assigns sequential Sundays for batch; pushes to Notion
- `/theo-full` - existing outline -> full draft pipeline; pushes FULL page to Notion
- `/tank-theology` - query lessons, prayer requests, prior life notes (read-only)

**PRDs Done:** PRD_THEO_PRIVATE_LESSONS_PAGE_DONE_20260502_135849.md, PRD_THEO_NotionBidirectionalSync_20260502_094047_DONE_20260502_140634.md, PRD_THEO_Skills_20260505_085949_DONE_20260505_091133.md
**PRDs Pending:** none
