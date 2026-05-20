#!/usr/bin/env python3
import json
import os
import pickle
import sys
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from dotenv import load_dotenv

ENV_PATH = Path(__file__).parent.parent.parent / '.env'
load_dotenv(ENV_PATH, override=True)

TIMEZONE_IANA    = os.getenv("TIMEZONE", "America/New_York")
TIMEZONE_OUTLOOK = os.getenv("TIMEZONE_OUTLOOK", "Eastern Standard Time")
OUTLOOK_EMAIL    = os.getenv("OUTLOOK_EMAIL")


# ---------------------------------------------------------------------------
# Gmail Auth
# ---------------------------------------------------------------------------

def get_gmail_service():
    from google.auth.transport.requests import Request
    from google_auth_oauthlib.flow import InstalledAppFlow
    from googleapiclient.discovery import build

    SCOPES = ["https://www.googleapis.com/auth/calendar"]

    credentials_path = os.getenv("GMAIL_CREDENTIALS_PATH")
    token_path       = os.getenv("GMAIL_TOKEN_PATH")

    if not credentials_path or not token_path:
        print("ERROR: GMAIL_CREDENTIALS_PATH and GMAIL_TOKEN_PATH must be set in .env")
        sys.exit(1)

    creds = None
    if Path(token_path).exists():
        with open(token_path, "rb") as f:
            creds = pickle.load(f)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(credentials_path, SCOPES)
            creds = flow.run_local_server(port=0)
        with open(token_path, "wb") as f:
            pickle.dump(creds, f)

    return build("calendar", "v3", credentials=creds)


# ---------------------------------------------------------------------------
# Command: check-conflicts
# Usage: penny.py check-conflicts <date> <time_start> <time_end>
# Example: penny.py check-conflicts 2026-05-10 14:00 15:00
# Prints JSON list of conflicting events to stdout.
# ---------------------------------------------------------------------------

def cmd_check_conflicts(date_str: str, time_start: str, time_end: str):
    tz    = ZoneInfo(TIMEZONE_IANA)
    start = datetime.fromisoformat(f"{date_str}T{time_start}").replace(tzinfo=tz)
    end   = datetime.fromisoformat(f"{date_str}T{time_end}").replace(tzinfo=tz)

    service = get_gmail_service()
    result  = service.events().list(
        calendarId="primary",
        timeMin=start.isoformat(),
        timeMax=end.isoformat(),
        singleEvents=True,
        maxResults=10,
    ).execute()

    conflicts = []
    for item in result.get("items", []):
        conflicts.append({
            "title": item.get("summary", "Untitled"),
            "start": item.get("start", {}).get("dateTime", "?")[:16].replace("T", " "),
            "end":   item.get("end",   {}).get("dateTime", "?")[:16].replace("T", " "),
            "link":  item.get("htmlLink"),
        })

    print(json.dumps(conflicts, indent=2))


# ---------------------------------------------------------------------------
# Command: create-file
# Usage: penny.py create-file <path_to_json>
# JSON fields: title, date, time_start, time_end, calendar, location (opt), notes (opt)
# ---------------------------------------------------------------------------

def resolve_date(value: str) -> str:
    v = value.strip().lower()
    if v == "today":
        return str(datetime.now().date())
    if v == "tomorrow":
        return str((datetime.now() + timedelta(days=1)).date())
    return value.strip()


def cmd_create_file(filepath: str):
    with open(filepath, encoding="utf-8") as f:
        data = json.load(f)

    title      = data.get("title", "").strip()
    date_str   = resolve_date(data.get("date", ""))
    time_start = data.get("time_start", "").strip()
    time_end   = data.get("time_end", "").strip()
    calendar   = data.get("calendar", "").strip().lower()
    location   = data.get("location") or data.get("where")
    notes      = data.get("notes")
    # Explicit override from skill; falls back to auto-detect if not present
    grandparent_invite = data.get("grandparent_invite", None)

    missing = [k for k, v in {"title": title, "date": date_str,
                               "time_start": time_start, "time_end": time_end,
                               "calendar": calendar}.items() if not v]
    if missing:
        print(f"ERROR: Missing required fields: {', '.join(missing)}")
        sys.exit(1)

    if calendar not in ("gmail", "outlook"):
        print("ERROR: calendar must be 'gmail' or 'outlook'")
        sys.exit(1)

    if calendar == "gmail":
        _create_gmail_event(title, date_str, time_start, time_end, location, notes, grandparent_invite)
    else:
        _create_outlook_event(title, date_str, time_start, time_end, location, notes)


GRANDPARENT_EMAIL = "rdculpepper@ourskylight.com"
KIDS_NAMES = ["Asher", "Lincoln", "Quinn"]


def _is_kids_event(title: str, notes: str | None) -> bool:
    check = f"{title} {notes or ''}".lower()
    return any(kid.lower() in check for kid in KIDS_NAMES)


def _create_gmail_event(title, date_str, time_start, time_end, location=None, notes=None, grandparent_invite=None):
    service = get_gmail_service()
    tz = ZoneInfo(TIMEZONE_IANA)

    start_dt = datetime.fromisoformat(f"{date_str}T{time_start}").replace(tzinfo=tz)
    end_dt   = datetime.fromisoformat(f"{date_str}T{time_end}").replace(tzinfo=tz)

    event = {
        "summary":     title,
        "description": notes or "",
        "start": {"dateTime": start_dt.isoformat()},
        "end":   {"dateTime": end_dt.isoformat()},
        "reminders": {"useDefault": False, "overrides": []},
    }
    if location:
        event["location"] = location

    # Use explicit flag if provided by skill; otherwise auto-detect from title/notes
    send_gp = grandparent_invite if grandparent_invite is not None else _is_kids_event(title, notes)

    attendees = []
    if OUTLOOK_EMAIL:
        attendees.append({"email": OUTLOOK_EMAIL})
    if send_gp:
        attendees.append({"email": GRANDPARENT_EMAIL})
    if attendees:
        event["attendees"] = attendees

    created = service.events().insert(calendarId="primary", body=event).execute()
    print(f"Gmail event created: {title} | {date_str} {time_start}-{time_end}")
    if OUTLOOK_EMAIL:
        print(f"  Invite sent to: {OUTLOOK_EMAIL}")
    if send_gp:
        print(f"  Grandparent invite sent to: {GRANDPARENT_EMAIL}")
    print(f"  Link: {created.get('htmlLink')}")


def _create_outlook_event(title, date_str, time_start, time_end, location=None, notes=None):
    import msal
    import requests as http_requests

    client_id        = os.getenv("OUTLOOK_CLIENT_ID")
    tenant_id        = os.getenv("OUTLOOK_TENANT_ID")
    token_cache_path = os.getenv("OUTLOOK_TOKEN_CACHE_PATH")

    if not client_id or not tenant_id:
        print("ERROR: OUTLOOK_CLIENT_ID and OUTLOOK_TENANT_ID must be set in .env")
        sys.exit(1)

    cache = msal.SerializableTokenCache()
    if token_cache_path and Path(token_cache_path).exists():
        with open(token_cache_path) as f:
            cache.deserialize(f.read())

    authority = f"https://login.microsoftonline.com/{tenant_id}"
    app       = msal.PublicClientApplication(client_id, authority=authority, token_cache=cache)
    SCOPES    = ["https://graph.microsoft.com/Calendars.ReadWrite"]

    accounts = app.get_accounts()
    result   = app.acquire_token_silent(SCOPES, account=accounts[0]) if accounts else None

    if not result:
        flow = app.initiate_device_flow(scopes=SCOPES)
        if "user_code" not in flow:
            print("ERROR: Could not initiate device code flow.")
            sys.exit(1)
        print(flow["message"])
        result = app.acquire_token_by_device_flow(flow)

    if token_cache_path and cache.has_state_changed:
        with open(token_cache_path, "w") as f:
            f.write(cache.serialize())

    if "access_token" not in result:
        print(f"ERROR: Could not get Outlook token: {result.get('error_description')}")
        sys.exit(1)

    event = {
        "subject": title,
        "body":    {"contentType": "Text", "content": notes or ""},
        "start":   {"dateTime": f"{date_str}T{time_start}:00", "timeZone": TIMEZONE_OUTLOOK},
        "end":     {"dateTime": f"{date_str}T{time_end}:00",   "timeZone": TIMEZONE_OUTLOOK},
        "showAs":       "busy",
        "sensitivity":  "private",
        "isReminderOn": False,
    }
    if location:
        event["location"] = {"displayName": location}

    headers  = {"Authorization": f"Bearer {result['access_token']}", "Content-Type": "application/json"}
    response = http_requests.post(
        "https://graph.microsoft.com/v1.0/me/events",
        json=event,
        headers=headers,
        timeout=15,
    )

    if response.status_code == 201:
        print(f"Outlook event created: {title} | {date_str} {time_start}-{time_end}")
    else:
        print(f"ERROR: Failed to create Outlook event ({response.status_code}): {response.text}")
        sys.exit(1)


# ---------------------------------------------------------------------------
# Command: delete-pattern
# Usage: penny.py delete-pattern <pattern> [--from YYYY-MM-DD] [--to YYYY-MM-DD] --list
#        penny.py delete-pattern <pattern> [--from YYYY-MM-DD] [--to YYYY-MM-DD] --confirm
# Finds Gmail events whose title contains <pattern> (case-insensitive) within the
# optional date range, then lists or deletes them. Deletion sends cancellation to attendees.
# ---------------------------------------------------------------------------

def _search_gmail_events(pattern: str, from_date: str | None, to_date: str | None) -> list[dict]:
    tz      = ZoneInfo(TIMEZONE_IANA)
    service = get_gmail_service()

    time_min = (
        datetime.fromisoformat(from_date).replace(hour=0, minute=0, tzinfo=tz).isoformat()
        if from_date
        else datetime.now(tz).isoformat()
    )
    time_max = (
        datetime.fromisoformat(to_date).replace(hour=23, minute=59, tzinfo=tz).isoformat()
        if to_date
        else None
    )

    kwargs = dict(
        calendarId="primary",
        timeMin=time_min,
        singleEvents=True,
        maxResults=250,
        orderBy="startTime",
    )
    if time_max:
        kwargs["timeMax"] = time_max

    matches = []
    page_token = None
    while True:
        if page_token:
            kwargs["pageToken"] = page_token
        result = service.events().list(**kwargs).execute()
        for item in result.get("items", []):
            title = item.get("summary", "")
            if pattern.lower() in title.lower():
                start_raw = item.get("start", {}).get("dateTime", "")
                end_raw   = item.get("end",   {}).get("dateTime", "")
                matches.append({
                    "event_id":   item["id"],
                    "title":      title,
                    "date":       start_raw[:10] if start_raw else "",
                    "time_start": start_raw[11:16] if len(start_raw) >= 16 else "",
                    "time_end":   end_raw[11:16]   if len(end_raw)   >= 16 else "",
                })
        page_token = result.get("nextPageToken")
        if not page_token:
            break

    return matches


def cmd_delete_pattern(pattern: str, from_date: str | None, to_date: str | None, mode: str):
    matches = _search_gmail_events(pattern, from_date, to_date)

    if mode == "list":
        print(json.dumps({"matches": matches, "count": len(matches)}, indent=2))
        return

    if mode == "confirm":
        if not matches:
            print(json.dumps({"deleted_count": 0, "status": "no matches found"}))
            return

        service = get_gmail_service()
        deleted = 0
        for event in matches:
            service.events().delete(calendarId="primary", eventId=event["event_id"]).execute()
            deleted += 1

        print(json.dumps({"deleted_count": deleted, "status": "success"}, indent=2))


# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        print("Commands:")
        print("  create-file <path>                        Create event from JSON file")
        print("  check-conflicts <date> <start> <end>      List Gmail conflicts in time window")
        print("  delete-pattern <pattern> [--from DATE] [--to DATE] --list|--confirm")
        print("")
        print("Examples:")
        print("  penny.py create-file event.json")
        print("  penny.py check-conflicts 2026-05-10 14:00 15:00")
        print('  penny.py delete-pattern "Pickup - Asher" --from 2026-08-18 --to 2026-11-04 --list')
        print('  penny.py delete-pattern "Pickup - Asher" --from 2026-08-18 --to 2026-11-04 --confirm')
        sys.exit(1)

    cmd = args[0]

    if cmd == "create-file":
        if len(args) < 2:
            print("ERROR: create-file requires a file path.")
            sys.exit(1)
        cmd_create_file(args[1])

    elif cmd == "check-conflicts":
        if len(args) < 4:
            print("ERROR: check-conflicts requires <date> <time_start> <time_end>")
            sys.exit(1)
        cmd_check_conflicts(args[1], args[2], args[3])

    elif cmd == "delete-pattern":
        remaining = args[1:]
        if not remaining:
            print("ERROR: delete-pattern requires a pattern string.")
            sys.exit(1)

        pattern   = remaining[0]
        from_date = None
        to_date   = None
        mode      = None

        i = 1
        while i < len(remaining):
            if remaining[i] == "--from" and i + 1 < len(remaining):
                from_date = remaining[i + 1]
                i += 2
            elif remaining[i] == "--to" and i + 1 < len(remaining):
                to_date = remaining[i + 1]
                i += 2
            elif remaining[i] == "--list":
                mode = "list"
                i += 1
            elif remaining[i] == "--confirm":
                mode = "confirm"
                i += 1
            else:
                i += 1

        if mode not in ("list", "confirm"):
            print("ERROR: delete-pattern requires --list or --confirm flag.")
            sys.exit(1)

        cmd_delete_pattern(pattern, from_date, to_date, mode)

    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
