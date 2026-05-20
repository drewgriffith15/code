#!/usr/bin/env python3
"""
holidays.py - Calculate upcoming holiday fertilizer windows for Bermuda lawn.
Usage: python holidays.py [window_days]
"""

import calendar
import sys
from datetime import datetime, timedelta


def easter(year):
    a = year % 19
    b = year // 100
    c = year % 100
    d = b // 4
    e = b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i = c // 4
    k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = ((h + l - 7 * m + 114) % 31) + 1
    return datetime(year, month, day)


def memorial_day(year):
    cal = calendar.monthcalendar(year, 5)
    mondays = [week[0] for week in cal if week[0] != 0]
    return datetime(year, 5, mondays[-1])


def july_fourth(year):
    return datetime(year, 7, 4)


def labor_day(year):
    cal = calendar.monthcalendar(year, 9)
    for week in cal:
        if week[0] != 0:
            return datetime(year, 9, week[0])


def get_upcoming_holidays(window_days=60):
    today = datetime.now().date()
    cutoff = today + timedelta(days=window_days)
    results = []
    for year in [today.year, today.year + 1]:
        entries = [
            ("Easter", easter(year), "12-12-12 Starter Fertilizer 3% Iron"),
            ("Memorial Day", memorial_day(year), "24-0-6 Flagship"),
            ("4th of July", july_fourth(year), "24-0-6 Flagship"),
            ("Labor Day", labor_day(year), "12-12-12 Starter Fertilizer 3% Iron"),
        ]
        for name, dt, product in entries:
            hdate = dt.date()
            window_start = hdate - timedelta(days=7)
            window_end = hdate + timedelta(days=7)
            if window_end >= today and window_start <= cutoff:
                results.append({
                    "holiday": name,
                    "date": hdate.isoformat(),
                    "window_start": window_start.isoformat(),
                    "window_end": window_end.isoformat(),
                    "product": product,
                })
    return results


if __name__ == "__main__":
    window = int(sys.argv[1]) if len(sys.argv) > 1 else 60
    holidays = get_upcoming_holidays(window)
    if not holidays:
        print(f"No holiday fert windows in the next {window} days.")
    else:
        print(f"Upcoming Holiday Fert Windows (next {window} days):")
        for h in holidays:
            print(
                f"  {h['holiday']} ({h['date']}) | "
                f"window: {h['window_start']} to {h['window_end']} | "
                f"{h['product']}"
            )
