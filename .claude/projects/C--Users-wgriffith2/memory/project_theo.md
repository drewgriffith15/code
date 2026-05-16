---
name: THEO Project State
description: Lesson pipeline - plan/draft/full CLI, Notion push/sync, voice patterns, sidecar pattern
type: project
originSessionId: 206ecdca-65d8-4c7e-b47d-ea6c7cb6a781
---
## Current State (2026-05-09)

**Updates (2026-05-09) - theo-editor:**
- Added `theo_editor.py` - voice-to-lesson finalization script. `--load <notion_url>`: looks up lesson in TANK by Notion page ID, parses `final_edited` into ordered sections (including `__OPENING__` for pre-header content), outputs JSON with section names and text. `--push <lesson_id>`: reads checkpoint JSON, assembles full draft (approved sections override originals, untouched sections keep original), saves to TANK `final_edited`, overwrites Notion page, deletes checkpoint.
- Added `/theo-editor` skill - Drew pastes voiced section transcripts one at a time with section name as first line; skill applies scribe_editor formatting rules, extracts Bible Nerd blockquotes (`> **Does anyone know...`) from original section and merges them back at proportional positions; checkpoints approved sections to `lessons/temp/editor_{lesson_id}.json` after each approval; runs `--push` on "done".
- `_markdown_to_blocks` in `theo_editor.py` includes `> ` -> Notion `quote` block support (missing from theo_redteam.py and theo_notion_push.py).

**Why:** Drew voices lesson sections after the redteam pass rather than typing rewrites. This eliminates the manual copy/paste/format loop and handles Bible Nerd blockquote preservation automatically.

**Updates (2026-05-09) - redteam fixes:**
- Added `theo_redteam.py` - draft refinement pipeline. Accepts Notion FULL page URL. Step 0: word count gate (< 13k chars: stop; 13k-17k: skip cuts; > 17k: cut pass). Step 1 (if needed): Sonnet cuts to ~2,500 words, saves to `lessons.final_edited`, overwrites Notion FULL page. Step 2: scribe_redteam coaching analysis (sections 1-4 only, section 5 dropped), saves to `lessons.redteam_feedback`. Checkpoint sidecar in lessons/temp/ for resume on failure. Original `draft` field never modified.
- Added `/theo-redteam` skill (accepts Notion URL, shells out to theo_redteam.py)
- FULL page parent changed: theo.py `_create_full_page_notion` now uses `THEO_FULL_PAGE_ID` instead of `THEO_HUB_PAGE_ID`. New dedicated Notion page "THEO" at `35bee045d5ec80da97b8d003434ffb43`.
- `THEO_FULL_PAGE_ID` added to `.env`
- `redteam_feedback` VARCHAR column added to TANK lessons table
- TANK lessons table now: `id, lesson_date, title, book, chapter, series, url, verses, source_transcript, outline, draft, final_edited, redteam_feedback, notion_page_id, notion_url, created_at, updated_at`

**Why:** scribe_redteam.md coaching analysis framework integrated into THEO pipeline as a second-draft refinement step before Drew makes personal edits. Shortens lesson to target length (2,500 words / 15,000-17,000 chars) and saves coaching feedback to TANK for retrieval.

## Previous State (2026-05-07)

**Updates (2026-05-07 session 2):**
- Title generation: `TITLE_PROMPT` updated - no longer ALL CAPS; now title case, max 50 chars. `extract_title()` has post-processing guard: forces `.title()` if model returns all caps, truncates on word boundary if > 50 chars.
- Added `repush-outline` subcommand to theo.py CLI: clears existing Notion outline page blocks and re-pushes from local `.md`. Reads Notion page ID from sidecar `.json`. Use after manually editing a local outline file. Command: `python scripts/theo.py repush-outline <outline.md>`

**Latest Fix (2026-05-07):** Fixed Notion outline push schema - was using "Name" property (doesn't exist); now uses "Lesson" (title). Also now populates all outline properties: Lesson, Date, Link, Resource Type, Speaker/Author, Study Series, Summary. Added `extract_lesson_thesis()`, `_extract_series_from_transcript()`, `_extract_speaker_from_header()` helper functions.

## Previous State (2026-05-02)

**Location:** `C:/Users/wgriffith2/Code/TANK/` (integrated into TANK as of 2026-04-30)

**Pipeline:** `theo.py plan/draft/full` - transcript -> outline (Opus + extended thinking) -> draft (Sonnet, voice guide injected) -> ghost-writer polish -> auto FULL page push to Notion -> sync edits back to TANK

**Scripts:**
- `scripts/theo.py` - main CLI; prep/plan/draft/full subcommands. `prep` normalizes transcript headers (book/chapter via regex->Haiku escalation, URL+speaker extraction, in-place write); run before `plan` for YouTube or Logos source material
- `scripts/theo_notion_push.py` - push draft to private Notion FULL page; exports `create_full_page(lesson_id, content, title, parent_page_id)`
- `scripts/theo_notion_sync.py` - pull Notion edits back to `lessons.final_edited`; shows char count + 500-char before/after preview, Y/N prompt before overwrite; `--force` skips prompt
- `scripts/update_voice.py` - refresh voice_patterns.json from last 3 final_edited lessons (hand-edited versions only, never AI drafts)
- `references/voice_patterns.json` - Drew's voice patterns; stored outside TANK DB as portable reference file; learns from hand-edited lessons via update_voice.py; injected into section prompts during draft generation

**TANK lessons table fields:** `id, lesson_date, title, book, chapter, series, url, verses, source_transcript, outline, draft, final_edited, notion_page_id (FULL page), notion_url (FULL page), created_at, updated_at`

**Sidecar pattern:** `plan` creates `outline_name.json` alongside outline file with `lesson_id` and `outline_notion_page_id`. `draft` reads both; uses `outline_notion_page_id` to append FULL page link to the Notion outline entry.

**FULL page workflow (as of 2026-05-02):**
- `run_draft()` auto-creates private FULL page under `THEO_HUB_PAGE_ID` (env var, fallback to hardcoded)
- Stores `notion_page_id` and `notion_url` in TANK (NOT the outline page ID - that's separate)
- Appends a "FULL Page: [link]" block to the outline page in Notion via `_link_full_page_to_outline()`
- `theo_notion_push.py` CLI is now for manual re-push only

**Models:** Opus 4.7 for outline generation (extended thinking), Sonnet 4.6 for draft sections + ghost-writer, Haiku 4.5 for title/slug extraction

**Skills:**
- `/theo` - direct invocation; `/theo <subcommand> [args]`; no pipeline scaffolding; routes to prep/plan/draft/full
- `/theo-outline` - Step 0 collects series name + optional speaker; runs `prep` on each file then `plan`; auto-assigns sequential Sundays; pushes to Notion
- `/theo-full` - existing outline -> full draft pipeline; pushes FULL page to Notion

**PRDs Done:** PRD_THEONotionSchema_20260506_194802.md, PRD_THEO_PRIVATE_LESSONS_PAGE_DONE_20260502_135849.md, PRD_THEO_NotionBidirectionalSync_20260502_094047_DONE_20260502_140634.md, PRD_THEO_Skills_20260505_085949_DONE_20260505_091133.md, PRD_theoprep_20260506_070237.md, PRD_THEO_Safeguards_20260504_054810.md
**PRDs Pending:** none
