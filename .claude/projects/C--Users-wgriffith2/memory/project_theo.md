---
name: THEO Project State
description: Lesson pipeline - plan/draft/full CLI, Notion push/sync, voice patterns, sidecar pattern
type: project
originSessionId: 206ecdca-65d8-4c7e-b47d-ea6c7cb6a781
---
## Current State (2026-05-16)

**Location:** `C:\Users\wgriffith2\Dropbox (Liberty University)\Code\`

**Pipeline:** transcript -> outline (Opus + extended thinking) -> draft (Sonnet, voice guide injected) -> ghost-writer polish -> auto FULL page push to Notion -> redteam refinement -> voice edit pass

**Scripts (all in Dropbox Code folder):**
- `theo.py` - main CLI; prep/plan/draft/full subcommands
- `theo_outline.py` - outline generation
- `theo_ghost_writer.py` - ghost-writer draft pass
- `theo_redteam.py` - draft refinement; word count gate; cuts + Theological Heavyweights coaching (self-contained prompt, loads influence profiles from wiki)
- `theo_editor.py` - voice-to-lesson finalization; `--load <notion_url>` / `--push <lesson_id>`
- `theo_notion_push.py` - push draft to private Notion FULL page (manual re-push)
- `theo_notion_sync.py` - pull Notion edits back to final_edited; Y/N prompt before overwrite
- `update_voice.py` - refresh voice_patterns.json from last 3 hand-edited lessons
- `voice_patterns.json` - Drew's voice patterns; injected into section prompts during draft generation

**Lesson data fields:** `id, lesson_date, title, book, chapter, series, url, verses, source_transcript, outline, draft, final_edited, redteam_feedback, notion_page_id, notion_url, created_at, updated_at`

**Sidecar pattern:** `plan` creates `outline_name.json` alongside outline file with `lesson_id` and `outline_notion_page_id`. `draft` reads both; uses `outline_notion_page_id` to append FULL page link to the Notion outline entry.

**FULL page:** auto-created under `THEO_FULL_PAGE_ID` (env var). Stores `notion_page_id` and `notion_url` in lesson record. Outline page gets a "FULL Page: [link]" block appended.

**Models:** Opus 4.7 for outline generation (extended thinking), Sonnet 4.6 for draft sections + ghost-writer + redteam, Haiku 4.5 for title/slug extraction

**Skills:**
- `/theo-outline` - runs prep + plan for each transcript; auto-assigns sequential Sundays; pushes to Notion
- `/theo-ghostwriter` - existing outline -> full draft pipeline; pushes FULL page to Notion
- `/theo-redteam` - draft refinement; cuts to length + coaching analysis
- `/theo-editor` - voice-edit pass; checkpoint approved sections; pushes final to Notion
- `/theo-vtt` - voice-to-text refinement; Drew pastes raw phone dictation + identifies section header; skill reads full file for context, applies Scribe Editor rules, replaces target section only; no output confirmation (file opens in editor)
