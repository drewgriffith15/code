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
**Operational data:** Ellsworth inventory, pantry staples, meal history at `Construct\wiki\food\meal-plans\meal-history.json`

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

**LLM consolidation:** Opus `_llm_consolidate_grocery()` deduplicates ingredients across meals, converts recipe quantities to purchase-sized items, categorizes, and flags dietary subs (GF, dairy-free). Falls back to heuristic if API fails or key missing.

**Recent fixes (2026-05-28):**
- `build_grocery_list()` now takes explicit `ellsworth_names` param (was reading module global `_ELLSWORTH_NAMES` set as side effect of `load_data()`). Callers pass `data["ellsworth_names"]`. `load_data()` now returns `ellsworth_names` in its dict.
- Grocery dedup key changed from `item_str[:25]` (prefix hash) to `(meal_name, item_str)`. Fixes bell pepper and other same-produce-across-meals under-count bug. LLM now receives full cross-meal ingredient list for correct consolidation.
