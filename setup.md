# Setup

Personal tools and scripts for Drew Griffith.

## Prerequisites

- Python 3.11+
- `python -m pip install -r requirements.txt` (if present) or install per script below
- `.env.personal` at `~/.claude/.env.personal` with:
  - `NOTION_TOKEN`
  - `ANTHROPIC_API_KEY`
  - `WIKI_FOOD` (path to Construct/wiki/food)

## Scripts

### remy.py - Meal Planning

```
python remy.py plan [date] [--busy-nights MON,WED] [--eating-out FRI] [--cravings chicken] [--avoid salmon] [--output plan.json]
python remy.py push plan.json
python remy.py full [date]
python remy.py pacing
python remy.py patch-starch "Meal Name" "New Starch"
```

Reads recipes from `Construct/wiki/food/recipes/` (tagged `remy`). Writes history to `Construct/wiki/food/meal-plans/meal-history.json`. Pushes meal plan + grocery list to Notion.

### ingest_youtube.py - YouTube Transcript Fetch

```
python ingest_youtube.py <url>
python ingest_youtube.py --playlist
```

Requires `client_secrets.json` and `token.pickle` in the same folder (OAuth - browser auth on first run). Outputs to `Construct/raw/`.

### theo_outline.py - THEO Lesson Pipeline

```
python theo_outline.py prep <transcript_path> --series "Series Name" [--speaker "Name"]
python theo_outline.py plan <transcript_path> [--date YYYY-MM-DD]
python theo_outline.py repush-outline <outline_path>
```

Saves outlines to `Construct/wiki/theology/outlines/`. Pushes to Notion THEO database.

## Hotkeys

`hotkeys.ahk` runs on startup. Shortcut goes in:
`~\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup`

Key bindings: see `commands.html` (Ctrl+Alt+H to open).
