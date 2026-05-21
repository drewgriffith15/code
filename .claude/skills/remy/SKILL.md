---
name: remy
description: Weekly dinner planning conversation for REMY. Use this skill when the user types /remy or asks to plan meals for the week, plan dinners, figure out what to cook this week, or any similar request about weekly meal planning. This is Drew's personal system — recipes live in Construct wiki (food/recipes, tagged remy). Proposes 5 dinners respecting pacing, effort, and dietary constraints, then pushes the confirmed plan and grocery list to Notion.
model: claude-sonnet-4-6
---

# REMY Skill

Guide Drew through his weekly dinner planning conversation, then push the confirmed plan and grocery list to Notion.

REMY_SCRIPT: `C:\Users\wgriffith2\Dropbox (Liberty University)\Code\remy.py`
ENV_FILE: `C:\Users\wgriffith2\.claude\.env.personal`

## Step 0 — Pre-Flight Checks (Required — Do Not Skip)

**Do these before running any commands. This is not optional.**

### Model Check
Identify the current model. If it is NOT `claude-sonnet-4-6`:
- STOP immediately
- Tell Drew: "REMY requires Sonnet 4.6 for constraint reasoning. Switch with `/model claude-sonnet-4-6`, then re-invoke `/remy`."
- Do NOT proceed. Do NOT run remy.py. Wait for Drew to switch and re-invoke.

### Memory Load
Read `C:\Users\wgriffith2\.claude\projects\C--Users-wgriffith2\memory\project_remy.md` and confirm you have the following in context before proceeding:
- Current REMY project state and file structure
- Protein pacing algorithm details (26-week window, frequency targets)
- 3-week no-repeat window rule (last 15 meals)
- Dietary constraints (Keely: gluten-free, dairy-sensitive, almond-allergic)
- Starch clash rule (never pair Corn side with Potato starch)

If the memory file is missing or does not contain these details, STOP and tell Drew before proceeding.

## Step 1 — Collect Week Context (Required — Do This Before Running remy.py)

Ask Drew about the upcoming week before generating any plan. Say something like:
"Before I run the plan, what's the week looking like?"

Collect and note the following:
- **Busy nights** (practices, games, performances): which days? These get Low-effort meals only.
- **Eating-out nights**: which days to skip entirely? (no meal needed)
- **Cravings**: any specific proteins or meals Drew wants this week?
- **Avoid / inventory issues**: any proteins that are depleted or ones to skip this week?

After Drew describes the week, show a brief confirmation:

```
Week constraints:
  Busy nights (Low-effort only): MON, WED
  Eating out (skip): FRI
  Cravings: chicken
  Avoid: salmon
```

Ask: "Does that look right before I run the plan?"

Wait for confirmation before proceeding to Step 2.

**Notes:**
- Day abbreviations: MON, TUE, WED, THU, FRI
- "Busy" does NOT mean skip — it means only propose Low-effort meals (crock pot, one-pot, quick)
- Eating out means the night is excluded from the plan entirely
- Avoid is for depleted inventory or proteins Drew doesn't want this week

## Step 2 — Generate the Initial Plan

Run the plan command, passing the constraints collected in Step 1. Build the command from what Drew said:

```bash
python "C:/Users/wgriffith2/Dropbox (Liberty University)/Code/remy.py" plan \
  --busy-nights MON,WED \
  --eating-out FRI \
  --cravings chicken \
  --avoid salmon \
  --output /tmp/remy_plan.json
```

Only include args that apply. If Drew has no cravings, omit `--cravings`. If nothing to avoid, omit `--avoid`. Etc.

If Drew provided a start date (e.g., `/remy 2026-05-12`), add it as the positional date argument before any flags:

```bash
python "C:/Users/wgriffith2/Dropbox (Liberty University)/Code/remy.py" plan 2026-05-12 --busy-nights MON --output /tmp/remy_plan.json
```

The plan always targets next Monday automatically if no date is given.

Read `/tmp/remy_plan.json` into memory.

## Step 3 — Show the Pacing Context (Optional)

Before presenting, optionally run the pacing report to understand what proteins need attention:

```bash
python "C:/Users/wgriffith2/Dropbox (Liberty University)/Code/remy.py" pacing
```

Note any BEHIND proteins (use more) or AHEAD proteins (use less). This informs your negotiation reasoning.

## Step 4 — Present the Proposal

Show the 5-day plan in a clean format:

```
Monday    — Butter Chicken (Chicken Breast) | Side: Broccoli | Starch: Jasmine Rice | 30 min [Medium]
Tuesday   — Taco Soup (Ground Beef) | One-pot | 20 min [Low]
Wednesday — Honey Garlic Shrimp (Shrimp) | Side: Green Peas | Starch: Jasmine Rice | 20 min [Low]
Thursday  — Baked Pork Chops (Pork Chops) | Side: Green Beans | Starch: Yellow Potatoes | 35 min [Low]
Friday    — Teriyaki Chicken (Chicken Thighs) | Side: Broccoli | Starch: Brown Rice | 25 min [Low]
```

Note anything that goes on the grocery list. Briefly explain why anything unusual was picked (pacing reason, effort constraint, etc.).

## Step 5 — Negotiate

Let Drew react. He can:
- Swap a meal entirely ("swap Tuesday for something with pork")
- Change a side or starch
- Move a meal to a different night
- Ask why you picked something

**When Drew requests a swap:**

1. Read the current plan from `/tmp/remy_plan.json`
2. Search Construct for alternatives: glob `C:\Users\wgriffith2\Dropbox (Liberty University)\Construct\wiki\food\recipes\*.md`
   - Filter by frontmatter: `tags` contains `remy`, `meal_type: dinner`, `protein` matches request
   - Skip meals already in the current plan
   - Skip proteins with Qty=0 in Ellsworth inventory
3. Pick the best match respecting protein pacing and effort preference
4. Update the affected day in the JSON: replace meal, protein, starch, side, thaw, cook_time, ingredients, instructions_raw
   - Get full recipe data from the embedded JSON block in the .md file
5. Rewrite `/tmp/remy_plan.json` with the update
6. Confirm the swap to Drew

Repeat until Drew says some form of "yes," "looks good," "confirmed," or "let's go."

## Step 6 — Push

Once Drew confirms, run:

```bash
python "C:/Users/wgriffith2/Dropbox (Liberty University)/Code/remy.py" push /tmp/remy_plan.json
```

This does everything in one command:
- Pushes meal plan to Notion (5 day pages with ingredients, instructions, thaw callouts, starch + side)
- Generates and pushes grocery list to Notion (categorized by aisle, staples tagged, wife's substitutions noted)
- Saves the confirmed plan to meal history

## Step 7 — Confirm

Tell Drew:
- Meal plan is live in Notion
- Grocery list is live in Notion
- History logged

---

## Key Rules (never violate)

- **3-week no-repeat window**: remy.py enforces this automatically — trust the proposal
- **Protein variety**: no consecutive days with the same protein group (chicken/beef/pork/turkey/seafood)
- **Starch clash**: never pair Corn side with a Potato starch
- **Dietary (wife)**: gluten-free, dairy-sensitive (butter is fine), almond-allergic
- **Sides for needs_side=true meals only**: one-pot meals get no side veggie
- **Salmon is currently depleted** (Qty=0) — do not propose salmon

## Ellsworth Item Codes Reference

Proteins start with 1, 2, or 3. Veggies start with 4.
Available veggies (Qty > 0): Green Beans, Brussel Sprouts, Squash, Broccoli, Okra, Black Eyed Peas, Green Peas, Corn.
