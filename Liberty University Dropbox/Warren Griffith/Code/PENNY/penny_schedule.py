#!/usr/bin/env python3
"""
penny_schedule.py - PENNY calendar scheduling utility.
Handles Gmail and Outlook calendar event creation. No AI calls.
"""

import json
import os
import pickle
import sys
from pathlib import Path

from dotenv import load_dotenv

# Load credentials from global .claude/.env
ENV_PATH = Path.home() / ".claude" / ".env"
load_dotenv(ENV_PATH)

TIMEZONE_IANA   = os.getenv("PENNY_TIMEZONE", "America/New_York")
TIMEZONE_OUTLOOK = os.getenv("PENNY_TIMEZONE_OUTLOOK", "Eastern Standard Time")


# ---------------------------------------------------------------------------
# Gmail
# ---------------------------------------------------------------------------

def create_gmail_event(title, date, time_start, time_end, notes=None):
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from googleapiclient.discovery import build

    SCOPES = ["https://www.googleapis.com/auth/calendar"]

    credentials_path = os.getenv("PENNY_GMAIL_CREDENTIALS_PATH")
    token_path       = os.getenv("PENNY_GMAIL_TOKEN_PATH")

    if not credentials_path or not token_path:
        print("ERROR: PENNY_GMAIL_CREDENTIALS_PATH and PENNY_GMAIL_TOKEN_PATH must be set in .env")
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

    service = build("calendar", "v3", credentials=creds)

    start_dt = f"{date}T{time_start}:00"
    end_dt   = f"{date}T{time_end}:00"

    event = {
        "summary":     title,
        "description": notes or "",
        "start": {"dateTime": start_dt, "timeZone": TIMEZONE_IANA},
        "end":   {"dateTime": end_dt,   "timeZone": TIMEZONE_IANA},
    }

    created = service.events().insert(calendarId="primary", body=event).execute()
    print(f"Gmail event created: {title} | {date} {time_start}–{time_end}")
    print(f"  Link: {created.get('htmlLink')}")


# ---------------------------------------------------------------------------
# Outlook (Microsoft Graph)
# ---------------------------------------------------------------------------

def create_outlook_event(title, date, time_start, time_end, notes=None):
    import msal
    import requests

    client_id       = os.getenv("PENNY_OUTLOOK_CLIENT_ID")
    tenant_id       = os.getenv("PENNY_OUTLOOK_TENANT_ID")
    token_cache_path = os.getenv("PENNY_OUTLOOK_TOKEN_CACHE_PATH")

    if not client_id or not tenant_id:
        print("ERROR: PENNY_OUTLOOK_CLIENT_ID and PENNY_OUTLOOK_TENANT_ID must be set in .env")
        sys.exit(1)

    # Set up token cache
    cache = msal.SerializableTokenCache()
    if token_cache_path and Path(token_cache_path).exists():
        with open(token_cache_path) as f:
            cache.deserialize(f.read())

    authority = f"https://login.microsoftonline.com/{tenant_id}"
    app = msal.PublicClientApplication(client_id, authority=authority, token_cache=cache)

    SCOPES = ["https://graph.microsoft.com/Calendars.ReadWrite"]

    # Try silent token from cache first
    accounts = app.get_accounts()
    result = None
    if accounts:
        result = app.acquire_token_silent(SCOPES, account=accounts[0])

    # Fall back to device code flow (user authenticates once, then token is cached)
    if not result:
        flow = app.initiate_device_flow(scopes=SCOPES)
        if "user_code" not in flow:
            print("ERROR: Could not initiate device code flow.")
            sys.exit(1)
        print(flow["message"])
        result = app.acquire_token_by_device_flow(flow)

    # Persist cache
    if token_cache_path and cache.has_state_changed:
        with open(token_cache_path, "w") as f:
            f.write(cache.serialize())

    if "access_token" not in result:
        print(f"ERROR: Could not get Outlook token: {result.get('error_description')}")
        sys.exit(1)

    token = result["access_token"]

    start_dt = f"{date}T{time_start}:00"
    end_dt   = f"{date}T{time_end}:00"

    event = {
        "subject": title,
        "body": {
            "contentType": "Text",
            "content": notes or "",
        },
        "start": {"dateTime": start_dt, "timeZone": TIMEZONE_OUTLOOK},
        "end":   {"dateTime": end_dt,   "timeZone": TIMEZONE_OUTLOOK},
        "showAs":                    "busy",
        "sensitivity":               "private",
        "isReminderOn":              True,
        "reminderMinutesBeforeStart": 30,
    }

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type":  "application/json",
    }

    response = requests.post(
        "https://graph.microsoft.com/v1.0/me/events",
        json=event,
        headers=headers,
        timeout=15,
    )

    if response.status_code == 201:
        print(f"Outlook event created: {title} | {date} {time_start}–{time_end}")
        print("  Private, Busy, 30-min reminder applied.")
    else:
        print(f"ERROR: Failed to create Outlook event ({response.status_code})")
        print(response.text)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Command: create-file
# ---------------------------------------------------------------------------

def cmd_create_file(filepath):
    with open(filepath, encoding="utf-8") as f:
        data = json.load(f)

    title      = data.get("title", "").strip()
    date       = data.get("date", "").strip()
    time_start = data.get("time_start", "").strip()
    time_end   = data.get("time_end", "").strip()
    calendar   = data.get("calendar", "").strip().lower()
    notes      = data.get("notes")

    missing = [k for k, v in {"title": title, "date": date, "time_start": time_start,
                               "time_end": time_end, "calendar": calendar}.items() if not v]
    if missing:
        print(f"ERROR: Missing required fields: {', '.join(missing)}")
        sys.exit(1)

    if calendar not in ("gmail", "outlook"):
        print("ERROR: calendar must be 'gmail' or 'outlook'")
        sys.exit(1)

    if calendar == "gmail":
        create_gmail_event(title, date, time_start, time_end, notes)
    else:
        create_outlook_event(title, date, time_start, time_end, notes)


# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        print("Commands: create-file <path>")
        sys.exit(1)

    cmd = args[0]

    if cmd == "create-file":
        if len(args) < 2:
            print("ERROR: create-file requires a file path.")
            sys.exit(1)
        cmd_create_file(args[1])
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
