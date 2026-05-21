---
name: query-wiki
description: Query Drew's Construct personal wiki (Obsidian markdown vault). Reads index.md, navigates to relevant pages, synthesizes an answer with wikilink citations and file paths. Offers to file the synthesis back as a new wiki page. Use when Drew asks a question about any Construct domain: lawn, garden, food, theology, workouts, health, technology, general. Triggered by /query-wiki <question>.
model: claude-haiku-4-5-20251001
---

# Query Wiki

Query Drew's Construct personal wiki and synthesize an answer.

## Vault root

`C:\Users\wgriffith2\Dropbox (Liberty University)\Construct`

## Workflow

1. Read `Construct/index.md` — scan all 8 domain sections for relevant page entries
2. Read the 2-3 most relevant wiki pages (shallow; user can ask to go deeper)
3. Read `Construct/log.md` when the question is temporal or operational ("what did I do last week", "when did I last apply X") - log.md is the recency record; it serves as the hot cache for recent activity
4. Synthesize a focused answer with inline citations
5. **Always** append an entry to `Construct/log.md` (see Query Log below)
6. Ask: "Want me to save this as a new wiki page?"

## Citation format

Every cited page gets both formats:

`[[page-stem]]` `(wiki/domain/subfolder/filename.md)`

Example: `[[20260510_neh_1]]` `(wiki/theology/logs/20260510_neh_1.md)`

## When nothing is found

> Nothing in Construct covers this yet. Consider adding a source: drop a file in `raw/` and run `ingest_raw.py --run`.

## Query Log

After every query, append one entry to `Construct/log.md`:

```
## [YYYY-MM-DD] query | <query text, trimmed to ~60 chars> (<domain(s) searched>)
```

Keep entries terse — date, what was asked, which domain(s) were read.

## Filing back (if Drew says yes)

- Determine domain from the question topic
- Type: `concept` or `summary`
- Path: `wiki/<domain>/<descriptive-name-with-hyphens>.md`
- Required frontmatter (all 6 fields):
  ```yaml
  domain: <domain>
  type: concept
  date: YYYYMMDD
  updated: YYYYMMDD
  tags: [tag1, tag2]
  sources: []
  ```
- Append to `Construct/index.md` under the correct domain heading
- Append to `Construct/log.md`: `## [YYYY-MM-DD] query | <title>`
