---
name: theo-vtt
description: Voice-to-text refiner for THEO lesson drafts. Accepts raw phone dictation for a single section, applies Scribe Editor formatting rules, and replaces only that section in the lesson file. Use when Drew pastes raw VTT transcription and names a section to replace in a theology lesson file.
---

# THEO Voice-to-Text Editor

## Quick Start

Drew reads a section of his rough draft aloud, saves the phone dictation, pastes it here, and says which section to replace. This skill formats it and swaps only that section in the file.

## Workflow

### Step 1 - Gather inputs
Confirm all three before proceeding:
- [ ] Raw VTT text pasted in chat
- [ ] Section to replace (the `##` heading name, e.g., "POINT TWO", "CONCLUSION & PRAYER")
- [ ] Lesson file path - if not given, find the most recent file in:
  `C:\Users\wgriffith2\Dropbox (Liberty University)\Construct\wiki\theology\lessons\`

### Step 2 - Read the full file first
Read the entire lesson file before formatting. Understanding Drew's full argument and vocabulary is required to correct VTT garble accurately. Where VTT has misheard a word or phrase, infer the correct word from context - do not substitute a synonym. Preserve Drew's vocabulary and sentence-level intent exactly.

### Step 3 - Format the VTT
Apply all Scribe rules (see [REFERENCE.md](REFERENCE.md)):
- Repair sentence boundaries and transcription errors (homophones, dropped words, misheard phrases)
- Add And/But/So/Now cadence (~20% of sentences start with a conjunction + comma)
- Convert to natural contractions
- Slash notation for grouped concept lists
- Spaced hyphens only - no em-dashes
- Bold rhetorical check-in questions to the audience
- Strip all banned phrases
- Format Bible citations as `(Book Chapter:Verse NLT)`

### Step 4 - Replace section only
Locate the target `##` heading. Replace everything between that heading line and the next `##` heading (or end of file) with the formatted VTT content. Do not touch:
- YAML frontmatter
- The `##` section heading line itself
- Any other section

Section headings follow this pattern:
- `## POINT ONE: ...` / `## POINT TWO: ...` / `## POINT THREE: ...`
- `## CONCLUSION & PRAYER`
- `## REAL TALK`
- Intro = content between opening `---` and first `## POINT` heading

Use the Edit tool. One section per run. No output after the edit.
