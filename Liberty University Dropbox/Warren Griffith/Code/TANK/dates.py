import re
import sys
from datetime import date, timedelta

_WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


def resolve_date(phrase: str) -> date | None:
    p = phrase.strip().lower()
    today = date.today()

    if p == "today":
        return today
    if p == "tomorrow":
        return today + timedelta(days=1)
    if p == "yesterday":
        return today - timedelta(days=1)

    m = re.fullmatch(r"in (\d+) days?", p)
    if m:
        return today + timedelta(days=int(m.group(1)))

    m = re.fullmatch(r"(\d+) days? ago", p)
    if m:
        return today - timedelta(days=int(m.group(1)))

    m = re.fullmatch(r"in (\d+) weeks?", p)
    if m:
        return today + timedelta(weeks=int(m.group(1)))

    m = re.fullmatch(r"(\d+) weeks? ago", p)
    if m:
        return today - timedelta(weeks=int(m.group(1)))

    m = re.fullmatch(r"next (\w+)", p)
    if m:
        day_name = m.group(1)
        if day_name not in _WEEKDAYS:
            return None
        target = _WEEKDAYS.index(day_name)
        current = today.weekday()
        if current == target:
            return None
        days_ahead = (target - current) % 7
        return today + timedelta(days=days_ahead)

    m = re.fullmatch(r"last (\w+)", p)
    if m:
        day_name = m.group(1)
        if day_name not in _WEEKDAYS:
            return None
        target = _WEEKDAYS.index(day_name)
        current = today.weekday()
        if current == target:
            return None
        days_behind = (current - target) % 7
        return today - timedelta(days=days_behind)

    m = re.fullmatch(r"this (\w+)", p)
    if m:
        day_name = m.group(1)
        if day_name not in _WEEKDAYS:
            return None
        target = _WEEKDAYS.index(day_name)
        current = today.weekday()
        delta = target - current
        return today + timedelta(days=delta)

    return None


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python dates.py \"<phrase>\"")
        sys.exit(1)

    phrase = sys.argv[1]
    result = resolve_date(phrase)

    if result is None:
        print(f"Ambiguous or unknown phrase: {phrase!r}", file=sys.stderr)
        sys.exit(1)

    print(result.isoformat())
