---
name: REMY Project State
description: Meal planning system complete; remy.py consolidates recipes + grocery generation + Notion push; /remy skill for conversational planning
type: project
originSessionId: 6a1cec8c-008f-40eb-a0e4-d7924cfccf10
---
REMY (Recipe Engine for Meal Yielding) is Drew's personal weekly meal planning system.

**Scripts:** `C:\Users\wgriffith2\Dropbox (Liberty University)\Code\remy.py`
**Skill:** `/remy`
**Recipe data:** Construct wiki at `Construct\wiki\food\recipes\` (markdown files tagged `remy`)
**Operational data:** Ellsworth inventory, pantry staples, meal history in Construct or JSON files in Code folder

**Key Algorithm Details:**
- Protein pacing: tracks 26-week cumulative usage vs. expected frequency (Once a week=19.5x, Twice a month=9.75x, etc.)
- 3-week no-repeat window: no meal from last 15 confirmed meals
- Starch clash rule: never pair Corn side with Potato starch
- Dietary constraints: wife is gluten-free (use King Arthur GF 1:1), dairy-sensitive (avoid liquid dairy except butter), almond-allergic

**CLI modes:** plan, push, full, pacing, patch-starch

**Constraint args (plan):**
- `--busy-nights MON,WED`: only Low-effort meals proposed for those days
- `--eating-out FRI`: those days skipped entirely
- `--cravings chicken`: boosts matching proteins in proposal priority
- `--avoid salmon`: hard-filters protein/meal from proposal

**Notion output:** Meal plan pages (ingredients, instructions, thaw callouts, starch + side) + grocery list categorized by aisle with wife's substitution notes.

**No Known Issues:** System working as designed.
