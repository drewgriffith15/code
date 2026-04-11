# PENNY
PENNY (Personal Executive Navigator & Notes Yielder) is a personal organizational assistant. She manages a running task list and schedules calendar events. Inspired by Miss Moneypenny — the one who actually runs things.

## Skills
- `/get-penny-tasks` — Add, view, and complete tasks (Haiku model)
- `/get-penny-schedule` — Create calendar events on Gmail + Outlook (Sonnet model)

## Task Management
Flat SQLite table (`penny.db`). Categories: Family, Home, Health, Administrative, Learning, Work. Completion tracked via `completed_date` — NULL = open.

## Calendar Scheduling
All events created via Gmail Calendar API. Every Gmail event automatically invites `wgriffith2@liberty.edu` to block the Outlook work calendar. No Outlook API required.

**Defaults:**
- 30-minute reminder on all events
- Full event details sent to both calendars
- User provides exact dates/times — no fuzzy parsing

## Files
- `penny_tasks.py` — SQLite task operations CLI
- `penny_schedule.py` — Gmail + Outlook calendar event creation
- `penny.db` — Task database (created on first run)

## Credentials
Stored in `C:\Users\wgriffith2\.claude\.env`:
```
PENNY_GMAIL_CREDENTIALS_PATH=C:\Users\wgriffith2\.claude\penny_gmail_credentials.json
PENNY_GMAIL_TOKEN_PATH=C:\Users\wgriffith2\.claude\penny_gmail_token.pkl
PENNY_TIMEZONE=America/New_York
PENNY_TIMEZONE_OUTLOOK=Eastern Standard Time
```
