"""
ingest_youtube.py - YouTube transcript fetch for Construct

Pulls transcripts from YouTube and writes raw files to Construct/raw/.
No domain classification here - that happens in the ingest step (ingest_raw.py).

Usage:
    python ingest_youtube.py <url>        # single video
    python ingest_youtube.py --playlist   # drain watch-later playlist

Credentials:
    client_secrets.json and token.pickle must be in the same folder as this script.
    Copy from the Code folder on first setup. token.pickle regenerates via browser on first run.

Output:
    Construct/raw/YYYYMMDD_<slug>.md   (summary block + full transcript)
    Construct/raw/processed/           (files land here after ingest_raw.py runs)
"""

import os
import re
import sys
import tempfile
import pickle
import argparse
from typing import Dict, List, Optional
from datetime import datetime, timedelta
from pathlib import Path

import yt_dlp
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
import anthropic
from dotenv import load_dotenv

load_dotenv(os.path.expanduser(r"~\.claude\.env.personal"), override=True)

# --- Config ---

CONSTRUCT = Path(r"C:\Users\wgriffith2\Dropbox (Liberty University)\Construct")
RAW_DIR = CONSTRUCT / "raw"
PROCESSED_DIR = RAW_DIR / "processed"

PLAYLIST_ID = "PLnjO2KqvOatf7fg3Ts7doeUO3N65zig4q"

SCRIPT_DIR = Path(__file__).parent
CLIENT_SECRETS_FILE = SCRIPT_DIR / "client_secrets.json"
TOKEN_PICKLE_FILE = SCRIPT_DIR / "token.pickle"


# --- YouTube OAuth ---

def get_youtube_service():
    creds = None
    SCOPES = ["https://www.googleapis.com/auth/youtube"]

    if TOKEN_PICKLE_FILE.exists():
        with open(TOKEN_PICKLE_FILE, "rb") as f:
            creds = pickle.load(f)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not CLIENT_SECRETS_FILE.exists():
                raise FileNotFoundError(
                    f"OAuth client secrets not found: {CLIENT_SECRETS_FILE}\n"
                    "Copy client_secrets.json to this folder."
                )
            flow = InstalledAppFlow.from_client_secrets_file(str(CLIENT_SECRETS_FILE), SCOPES)
            creds = flow.run_local_server(port=0)
        with open(TOKEN_PICKLE_FILE, "wb") as f:
            pickle.dump(creds, f)

    return build("youtube", "v3", credentials=creds)


def get_playlist_videos(service, playlist_id: str) -> List[Dict]:
    print(f"Fetching playlist: {playlist_id}")
    videos = []
    next_page_token = None
    while True:
        resp = service.playlistItems().list(
            part="snippet",
            playlistId=playlist_id,
            maxResults=50,
            pageToken=next_page_token,
        ).execute()
        for item in resp.get("items", []):
            snippet = item.get("snippet", {})
            res = snippet.get("resourceId", {})
            if res.get("kind") == "youtube#video":
                vid = res["videoId"]
                videos.append({
                    "id": vid,
                    "url": f"https://www.youtube.com/watch?v={vid}",
                    "playlist_item_id": item["id"],
                })
        next_page_token = resp.get("nextPageToken")
        if not next_page_token:
            break
    print(f"Found {len(videos)} videos.")
    return videos


def remove_from_playlist(service, playlist_item_id: str) -> bool:
    try:
        service.playlistItems().delete(id=playlist_item_id).execute()
        return True
    except Exception as e:
        print(f"  WARNING: Could not remove from playlist: {e}")
        return False


# --- yt-dlp ---

class _DedupeLogger:
    """Pass to yt-dlp's logger= option; prints each unique error once."""
    def __init__(self):
        self._seen = set()
    def debug(self, msg): pass
    def warning(self, msg): pass
    def error(self, msg):
        if msg not in self._seen:
            self._seen.add(msg)
            print(f"  [yt-dlp] {msg}")

_YDL_LOGGER = _DedupeLogger()

def get_video_details(url: str) -> Optional[Dict]:
    opts = {"quiet": True, "no_warnings": True, "logger": _YDL_LOGGER}
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
            chapters = [
                {
                    "start_time": c.get("start_time"),
                    "end_time": c.get("end_time"),
                    "title": c.get("title", ""),
                }
                for c in (info.get("chapters") or [])
            ]
            return {
                "video_id": info.get("id", ""),
                "title": info.get("title", "Unknown Title"),
                "channel": info.get("uploader", "Unknown Channel"),
                "upload_date": info.get("upload_date", datetime.now().strftime("%Y%m%d")),
                "duration": info.get("duration", 0),
                "chapters": chapters,
            }
    except Exception as e:
        print(f"  ERROR getting video details: {e}")
        return None


def get_transcript(url: str, lang: str = "en") -> Optional[str]:
    with tempfile.TemporaryDirectory() as tmp:
        opts = {
            "writeautomaticsub": True,
            "subtitleslangs": [lang],
            "subtitlesformat": "vtt",
            "skip_download": True,
            "outtmpl": os.path.join(tmp, "sub"),
            "quiet": True,
            "no_warnings": True,
            "logger": _YDL_LOGGER,
        }
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                ydl.download([url])

            sub_file = next(
                (os.path.join(tmp, f) for f in os.listdir(tmp) if f.endswith(f".{lang}.vtt")),
                None,
            )
            if not sub_file:
                print("  No transcript found.")
                return None

            vtt = Path(sub_file).read_text(encoding="utf-8")
            lines, seen = [], ""
            for line in vtt.splitlines():
                if "-->" in line or not line.strip() or line.strip().startswith(("WEBVTT", "Kind:", "Language:")):
                    continue
                cleaned = re.sub(r"<[^>]+>", "", line).strip()
                if cleaned == seen:
                    continue
                lines.append(cleaned)
                seen = cleaned
            return " ".join(lines)

        except yt_dlp.utils.DownloadError as e:
            print(f"  ERROR: Transcript not available ({e})")
            return None
        except Exception as e:
            print(f"  ERROR getting transcript: {e}")
            return None


# --- Claude ---

def summarize_video(transcript: str, chapters: List[Dict], title: str, channel: str) -> str:
    client = anthropic.Anthropic()
    ai_chapters = not chapters

    if chapters:
        ch_text = "\n".join(
            f"{str(timedelta(seconds=int(c.get('start_time', 0))))} - {c.get('title', '')}"
            for c in chapters
        )
        prompt = (
            f"Video: {title} | {channel}\n\n"
            f"Chapters:\n{ch_text}\n\n"
            f"Transcript:\n{transcript}\n\n"
            f"For each chapter, write exactly one concise bullet point summarizing the key point.\n"
            f"Format:\n## Chapter Title\n- one sentence\n\nOne bullet per chapter, no more."
        )
    else:
        prompt = (
            f"Video: {title} | {channel}\n\n"
            f"Transcript:\n{transcript}\n\n"
            f"Break into 3-8 logical sections. Give each a short descriptive title.\n"
            f"Write exactly one bullet per section.\n"
            f"Format:\n## Section Title\n- one sentence\n\nOne bullet per section, no more."
        )

    msg = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=1024,
        temperature=0,
        messages=[{"role": "user", "content": prompt}],
    )
    summary = msg.content[0].text.strip()
    if ai_chapters:
        summary += "\n\n*AI-generated sections*"
    return summary


# --- Construct ---

def video_id_exists(video_id: str) -> Optional[Path]:
    """Returns path to existing file if video already fetched or ingested, else None."""
    needle = f"video_id: {video_id}"

    # Check raw/ (including processed/) and wiki summaries
    search_dirs = [RAW_DIR]
    wiki = CONSTRUCT / "wiki"
    if wiki.exists():
        for domain_dir in wiki.iterdir():
            for sub in ("summaries", "logs"):
                sd = domain_dir / sub
                if sd.exists():
                    search_dirs.append(sd)

    for d in search_dirs:
        for md in d.rglob("*.md"):
            try:
                if needle in md.read_text(encoding="utf-8", errors="ignore"):
                    return md
            except Exception:
                pass
    return None


def make_slug(text: str, max_len: int = 50) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
    if len(slug) <= max_len:
        return slug
    cut = slug[:max_len]
    last = cut.rfind("_")
    return cut[:last] if last > 10 else cut


def fmt_duration(seconds: int) -> str:
    m, s = divmod(seconds, 60)
    h, m = divmod(m, 60)
    return f"{h}h {m}m {s}s" if h else f"{m}m {s}s"


def write_raw_file(details: Dict, transcript: str, summary: str) -> Path:
    date_raw = details["upload_date"]  # YYYYMMDD from yt-dlp
    date_iso = f"{date_raw[:4]}-{date_raw[4:6]}-{date_raw[6:]}"
    slug = make_slug(details["title"])
    filename = f"{date_raw}_{slug}.md"

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    dest = RAW_DIR / filename

    content = (
        f"---\n"
        f"type: raw\n"
        f"date: {date_iso}\n"
        f"source_url: {details['url']}\n"
        f"channel: {details['channel']}\n"
        f"video_id: {details['video_id']}\n"
        f"---\n\n"
        f"# {details['title']}\n\n"
        f"**Channel:** {details['channel']}  \n"
        f"**Published:** {date_iso}  \n"
        f"**Duration:** {fmt_duration(details['duration'])}  \n"
        f"**URL:** {details['url']}\n\n"
        f"## Summary\n\n"
        f"{summary}\n\n"
        f"---\n\n"
        f"## Transcript\n\n"
        f"{transcript}\n"
    )

    dest.write_text(content, encoding="utf-8")
    return dest


# --- Core ---

def process_video(url: str, playlist_item_id: str = "", service=None) -> bool:
    """Fetch, summarize, and write one video to raw/. Returns True on success."""
    details = get_video_details(url)
    if not details:
        return False
    details["url"] = url

    print(f"  Title:   {details['title']}")
    print(f"  Channel: {details['channel']}")

    existing = video_id_exists(details["video_id"])
    if existing:
        print(f"  Already exists: {existing.relative_to(CONSTRUCT)}")
        if service and playlist_item_id:
            remove_from_playlist(service, playlist_item_id)
        return False

    transcript = get_transcript(url)
    if not transcript:
        return False
    print(f"  Transcript: {len(transcript.split())} words")

    summary = summarize_video(transcript, details["chapters"], details["title"], details["channel"])

    dest = write_raw_file(details, transcript, summary)
    print(f"  Written: raw/{dest.name}")

    if service and playlist_item_id:
        if remove_from_playlist(service, playlist_item_id):
            print("  Removed from playlist.")

    return True


def main():
    parser = argparse.ArgumentParser(
        description="YouTube transcript fetch for Construct (writes to raw/)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python ingest_youtube.py https://www.youtube.com/watch?v=abc123\n"
            "  python ingest_youtube.py --playlist"
        ),
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("url", nargs="?", help="Single YouTube URL")
    group.add_argument("--playlist", action="store_true", help="Drain watch-later playlist")
    args = parser.parse_args()

    if not os.getenv("ANTHROPIC_API_KEY"):
        print("FATAL: ANTHROPIC_API_KEY not set.")
        sys.exit(1)

    if args.playlist:
        try:
            service = get_youtube_service()
        except Exception as e:
            print(f"FATAL: YouTube auth failed: {e}")
            sys.exit(1)

        videos = get_playlist_videos(service, PLAYLIST_ID)
        if not videos:
            print("Playlist is empty.")
            return

        ok, skipped = 0, 0
        for i, v in enumerate(videos):
            print(f"\n[{i + 1}/{len(videos)}] {v['url']}")
            if process_video(v["url"], v["playlist_item_id"], service):
                ok += 1
            else:
                skipped += 1

        print(f"\nDone: {ok} written, {skipped} skipped.")

    else:
        print(f"Processing: {args.url}")
        process_video(args.url)
        print("\nDone.")


if __name__ == "__main__":
    main()
