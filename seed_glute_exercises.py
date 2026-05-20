import os
import duckdb
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent.parent / '.env', override=True)

CONSTRUCT_ROOT = Path(r"C:/Users/wgriffith2/Dropbox (Liberty University)/Construct")
DB_PATH = os.getenv("TANK_DB_PATH", str(CONSTRUCT_ROOT))  # TODO: migrate to Construct wiki

EXERCISES = [
    # --- Squeeze (peak contraction, shortened position) ---
    ("Dumbbell Hip Thrust",        "Squeeze", "glute maximus",       "hamstrings",             "DB"),
    ("KAS Glute Bridge",           "Squeeze", "glute maximus",       "hamstrings",             "DB or KB"),
    ("Frog Pumps",                 "Squeeze", "glute maximus upper", "glute medius",           "DB or Band"),
    ("Banded Glute Kickbacks",     "Squeeze", "glute maximus upper", None,                     "Band"),
    ("Banded Donkey Kicks",        "Squeeze", "glute maximus",       None,                     "Band"),

    # --- Press (deep stretch, torque at bottom) ---
    ("Glute-Dominant Step-Ups",    "Press",   "glute maximus",       "quads",                  "DB or KB or Bodyweight"),
    ("Bulgarian Split Squats",     "Press",   "glute maximus",       "quads, hamstrings",      "DB or KB"),
    ("Goblet Box Squat",           "Press",   "glute maximus",       "quads",                  "DB or KB"),
    ("Curtsy Lunges",              "Press",   "glute medius",        "glute maximus",          "DB or KB"),
    ("Cossack Squats",             "Press",   "glute maximus",       "adductors",              "DB or KB or Bodyweight"),

    # --- Hinge (maximum stretch position) ---
    ("Single-Leg Dumbbell Deadlift", "Hinge", "glute maximus",      "hamstrings",             "DB or KB"),
    ("B-Stance RDL",               "Hinge",   "glute maximus",       "hamstrings",             "DB or KB"),
    ("Kettlebell Swings",          "Hinge",   "glute maximus",       "hamstrings, core",       "KB"),
    ("Suitcase Deadlift",          "Hinge",   "glute medius",        "glute maximus, core",    "DB or KB"),
    ("Banded Good Mornings",       "Hinge",   "glute maximus",       "hamstrings",             "Band"),

    # --- Abduction (shelf builders, glute medius/minimus) ---
    ("Clamshells",                 "Abduction", "glute medius",      "glute minimus",          "Band or Bodyweight"),
    ("Standing Banded Hip Abduction", "Abduction", "glute medius",   "glute minimus",          "Band"),
    ("Monster Walks",              "Abduction", "glute medius",      "glute minimus",          "Band"),
    ("Fire Hydrants",              "Abduction", "glute medius upper","glute minimus",          "Band or Bodyweight"),
    ("Side-Lying Hip Abduction",   "Abduction", "glute medius",      "glute minimus",          "Bodyweight or Band"),
    ("Banded Seated Hip Abduction","Abduction", "glute medius upper","glute medius lower",     "Band"),
]


def main():
    con = duckdb.connect(DB_PATH)

    # Issue 1: create table
    con.execute("""
        CREATE TABLE IF NOT EXISTS exercises (
            name              VARCHAR NOT NULL UNIQUE,
            category          VARCHAR NOT NULL,
            primary_muscles   VARCHAR NOT NULL,
            secondary_muscles VARCHAR,
            equipment         VARCHAR NOT NULL
        )
    """)

    # Issue 2: seed exercises (idempotent)
    before = con.execute("SELECT count(*) FROM exercises").fetchone()[0]
    for name, category, primary, secondary, equipment in EXERCISES:
        con.execute("""
            INSERT INTO exercises (name, category, primary_muscles, secondary_muscles, equipment)
            SELECT ?, ?, ?, ?, ?
            WHERE NOT EXISTS (SELECT 1 FROM exercises WHERE name = ?)
        """, [name, category, primary, secondary, equipment, name])

    # Issue 3: verification report
    total = con.execute("SELECT count(*) FROM exercises").fetchone()[0]
    inserted = total - before
    print(f"\nGlute Exercise Database — {total} exercises total ({inserted} newly inserted)\n")
    print(f"{'CATEGORY':<12}  {'EXERCISE'}")
    print("-" * 60)

    rows = con.execute("""
        SELECT category, name
        FROM exercises
        ORDER BY category, name
    """).fetchall()

    current_cat = None
    for category, name in rows:
        if category != current_cat:
            if current_cat is not None:
                print()
            print(f"  [{category.upper()}]")
            current_cat = category
        print(f"    {name}")

    print()
    con.close()


if __name__ == "__main__":
    main()
