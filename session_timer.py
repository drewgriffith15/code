import argparse
import json
import math
import tempfile
from datetime import datetime
from pathlib import Path

IDLE_THRESHOLD_MINUTES = 180

PHASE_KEYS = ["1", "2", "3", "4", "5", "5_end"]
PHASE_LABELS = {
    "1":     "Phase 1 start",
    "2":     "Phase 2 start",
    "3":     "Phase 3 start",
    "4":     "Phase 4 start",
    "5":     "Phase 5 start",
    "5_end": "Phase 5 end  ",
}


def find_session_file():
    tmp = Path(tempfile.gettempdir())
    files = sorted(tmp.glob("dax_session_*.json"), key=lambda f: f.stat().st_mtime)
    return files[-1] if files else None


def ceil_15(minutes):
    return max(15, math.ceil(minutes / 15) * 15)


def fmt(minutes):
    h, m = divmod(minutes, 60)
    return f"{h}h {m:02d}m" if h else f"{m}m"


def init_session():
    tmp = Path(tempfile.gettempdir())
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    session_file = tmp / f"dax_session_{ts}.json"
    data = {"phases": {"1": datetime.now().isoformat(timespec="seconds")}}
    session_file.write_text(json.dumps(data, indent=2))
    print(f"Session started: {datetime.now().strftime('%a %b %d %H:%M')}")


def log_phase(phase):
    f = find_session_file()
    if not f:
        tmp = Path(tempfile.gettempdir())
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        f = tmp / f"dax_session_{ts}.json"
        f.write_text(json.dumps({"phases": {}}, indent=2))
    data = json.loads(f.read_text())
    data["phases"][phase] = datetime.now().isoformat(timespec="seconds")
    f.write_text(json.dumps(data, indent=2))


def report():
    f = find_session_file()
    if not f:
        print("No active DAX session file found.")
        return

    data = json.loads(f.read_text())
    phases = data.get("phases", {})
    present = [(k, datetime.fromisoformat(phases[k])) for k in PHASE_KEYS if k in phases]

    if not present:
        print("No phase timestamps recorded.")
        f.unlink()
        return

    print()
    for i, (key, ts) in enumerate(present):
        line = f"  {PHASE_LABELS[key]} : {ts.strftime('%a %b %d %H:%M')}"
        if i > 0:
            gap = (ts - present[i - 1][1]).total_seconds() / 60
            if gap > IDLE_THRESHOLD_MINUTES:
                h, m = divmod(int(gap), 60)
                line += f"   <- idle gap ({h}h {m:02d}m)"
        print(line)

    first_ts = present[0][1]
    last_ts = present[-1][1]
    total_raw = int((last_ts - first_ts).total_seconds() / 60)

    idle_total = sum(
        (present[i][1] - present[i - 1][1]).total_seconds() / 60
        for i in range(1, len(present))
        if (present[i][1] - present[i - 1][1]).total_seconds() / 60 > IDLE_THRESHOLD_MINUTES
    )
    active_raw = int(total_raw - idle_total)

    print()
    print(f"  Total session:  {fmt(total_raw)} -> {fmt(ceil_15(total_raw))}")
    print(f"  Active session: {fmt(active_raw)} -> {fmt(ceil_15(active_raw))}")
    print()

    f.unlink()


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--init", action="store_true")
    group.add_argument("--log-phase", metavar="PHASE")
    group.add_argument("--report", action="store_true")
    args = parser.parse_args()

    if args.init:
        init_session()
    elif args.log_phase:
        phase = "5_end" if args.log_phase == "5-end" else args.log_phase
        log_phase(phase)
    elif args.report:
        report()


if __name__ == "__main__":
    main()
