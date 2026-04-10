#!/usr/bin/env python3
"""
penny_tasks.py - PENNY task management utility.
Handles all SQLite task operations. No AI calls.
"""

import json
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

BASE_DIR = Path(__file__).parent
DB_PATH = BASE_DIR / "penny.db"

VALID_CATEGORIES = {"Family", "Home", "Health", "Administrative", "Learning", "Work"}
VALID_PRIORITIES = {"low", "medium", "high"}


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


# ---------------------------------------------------------------------------
# Init
# ---------------------------------------------------------------------------

def cmd_init():
    conn = get_db()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS tasks (
            task_id       INTEGER PRIMARY KEY AUTOINCREMENT,
            task_name     TEXT NOT NULL,
            category      TEXT NOT NULL,
            created_date  TEXT NOT NULL,
            due_date      TEXT,
            priority      TEXT,
            notes         TEXT,
            completed_date TEXT
        );
    """)
    conn.commit()
    conn.close()
    print("DB ready.")


# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------

def cmd_list():
    conn = get_db()
    rows = conn.execute(
        "SELECT task_id, task_name, category, due_date, priority, notes "
        "FROM tasks WHERE completed_date IS NULL "
        "ORDER BY "
        "  CASE priority WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 ELSE 4 END, "
        "  due_date ASC, "
        "  task_id ASC"
    ).fetchall()
    conn.close()

    if not rows:
        print("No open tasks.")
        return

    print(f"\n{'ID':<5} {'TASK':<42} {'CATEGORY':<16} {'DUE':<12} {'PRI':<8} NOTES")
    print("-" * 105)
    for r in rows:
        due      = r["due_date"] or ""
        priority = r["priority"] or ""
        notes    = (r["notes"] or "")[:40]
        name     = r["task_name"][:41]
        print(f"{r['task_id']:<5} {name:<42} {r['category']:<16} {due:<12} {priority:<8} {notes}")
    print()


def cmd_history(limit=20):
    conn = get_db()
    rows = conn.execute(
        "SELECT task_id, task_name, category, completed_date "
        "FROM tasks WHERE completed_date IS NOT NULL "
        "ORDER BY completed_date DESC LIMIT ?",
        (int(limit),),
    ).fetchall()
    conn.close()

    if not rows:
        print("No completed tasks.")
        return

    print(f"\n{'ID':<5} {'TASK':<42} {'CATEGORY':<16} COMPLETED")
    print("-" * 80)
    for r in rows:
        print(f"{r['task_id']:<5} {r['task_name'][:41]:<42} {r['category']:<16} {r['completed_date'][:10]}")
    print()


# ---------------------------------------------------------------------------
# Writes
# ---------------------------------------------------------------------------

def cmd_add_file(filepath):
    with open(filepath, encoding="utf-8") as f:
        data = json.load(f)

    task_name = data.get("task_name", "").strip()
    category  = data.get("category", "").strip()
    due_date  = data.get("due_date")
    priority  = data.get("priority")
    notes     = data.get("notes")

    if not task_name:
        print("ERROR: task_name is required.")
        sys.exit(1)

    if category not in VALID_CATEGORIES:
        print(f"ERROR: category must be one of: {', '.join(sorted(VALID_CATEGORIES))}")
        sys.exit(1)

    if priority and priority not in VALID_PRIORITIES:
        print("ERROR: priority must be one of: low, medium, high")
        sys.exit(1)

    conn = get_db()
    conn.execute(
        "INSERT INTO tasks (task_name, category, created_date, due_date, priority, notes) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        (task_name, category, datetime.now().isoformat(), due_date, priority, notes),
    )
    conn.commit()
    conn.close()
    print(f"Task added: {task_name} [{category}]")


def cmd_complete(task_id):
    conn = get_db()
    row = conn.execute(
        "SELECT task_name FROM tasks WHERE task_id = ? AND completed_date IS NULL",
        (int(task_id),),
    ).fetchone()

    if not row:
        print(f"ERROR: No open task found with ID {task_id}.")
        conn.close()
        sys.exit(1)

    conn.execute(
        "UPDATE tasks SET completed_date = ? WHERE task_id = ?",
        (datetime.now().isoformat(), int(task_id)),
    )
    conn.commit()
    conn.close()
    print(f"Done: [{task_id}] {row['task_name']}")


# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        print("Commands: init, list, add-file <path>, complete <id>, history [limit]")
        sys.exit(1)

    cmd = args[0]

    if cmd == "init":
        cmd_init()
    elif cmd == "list":
        cmd_list()
    elif cmd == "add-file":
        if len(args) < 2:
            print("ERROR: add-file requires a file path.")
            sys.exit(1)
        cmd_add_file(args[1])
    elif cmd == "complete":
        if len(args) < 2:
            print("ERROR: complete requires a task ID.")
            sys.exit(1)
        cmd_complete(args[1])
    elif cmd == "history":
        limit = args[1] if len(args) > 1 else 20
        cmd_history(limit)
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
