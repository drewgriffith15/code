# REMY
# REMY (Recipe Engine for Meal Yielding) is a personal meal planning system inspired by
# the rat chef in Ratatouille: bringing taste and culinary intuition to weekly family meal
# planning. It stores family dinner recipes as structured JSON, manages a frozen food
# inventory from Ellsworth (a 6-month food delivery service), and drives a weekly meal
# planning conversation that outputs to Notion.

import os
import sys
import json
import argparse
import random
import re
from pathlib import Path
from datetime import datetime, timedelta, date
from collections import Counter
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent.parent / '.env', override=True)
sys.path.insert(0, str(Path(__file__).parent))
import tank

NOTION_TOKEN = os.getenv("NOTION_TOKEN")

PROTEIN_GROUPS = {
    "Chicken Breast": "chicken", "Chicken Thighs": "chicken", "Whole Chicken": "chicken",
    "Ground Beef": "beef", "Flank Steak": "beef", "Flat Iron Steak": "beef",
    "Sirloin Filet": "beef", "Sirloin Tip Roast": "beef", "Stew Beef": "beef",
    "Pork Chops": "pork", "Pork Tenderloin": "pork", "Ground Pork": "pork",
    "Link Sausage": "pork",
    "Ground Turkey": "turkey",
    "Shrimp": "seafood", "Salmon": "seafood",
}

FREQUENCY_26W = {
    "Once a week": 19.5,
    "Twice a month": 9.75,
    "Once a month": 6.5,
    "Twice every 6 months": 3.25,
}

POTATO_STARCHES = {"Yellow Potatoes", "Red Potatoes", "Sweet Potatoes", "Russet Potatoes"}
RICE_STARCHES = {"Jasmine Rice", "Brown Rice"}

CONSUMPTION_RATES = {
    "Ground Beef": 1,
    "Ground Pork": 1,
    "Ground Turkey": 1,
    "Chicken Breast": 6,
    "Chicken Thighs": 0.5,
    "Pork Chops": 6,
    "Pork Tenderloin": 2,
    "Flank Steak": 1,
    "Stew Beef": 2,
    "Whole Chicken": 1,
    "Link Sausage": 1,
    "Shrimp": 0.5,
    "Green Beans": 2,
    "Brussel Sprouts": 2,
    "Squash": 2,
    "Broccoli": 2,
    "Okra": 2,
    "Black Eyed Peas": 2,
    "Green Peas": 2,
    "Corn": 2,
}

_ELLSWORTH_NAMES: set = set()
_data_load_summary: dict = {}


# ── Notion block builders ──────────────────────────────────────────────────────

def _rt(text):
    return [{"type": "text", "text": {"content": text}}]

def _h2(text):
    return {"object": "block", "type": "heading_2", "heading_2": {"rich_text": _rt(text)}}

def _h3(text):
    return {"object": "block", "type": "heading_3", "heading_3": {"rich_text": _rt(text)}}

def _para(text):
    return {"object": "block", "type": "paragraph", "paragraph": {"rich_text": _rt(text)}}

def _bullet(text):
    return {"object": "block", "type": "bulleted_list_item", "bulleted_list_item": {"rich_text": _rt(text)}}

def _numbered(text):
    return {"object": "block", "type": "numbered_list_item", "numbered_list_item": {"rich_text": _rt(text)}}

def _divider():
    return {"object": "block", "type": "divider", "divider": {}}

def _callout(text, emoji="❄️"):
    return {
        "object": "block", "type": "callout",
        "callout": {"rich_text": _rt(text), "icon": {"type": "emoji", "emoji": emoji}},
    }


def _enrich_instructions(ingredients, instructions):
    lookup = {}
    for ing in ingredients:
        item = ing.get("item", "").lower().strip()
        if not item:
            continue
        display = " ".join(filter(None, [ing.get("amount", ""), ing.get("unit", ""), ing.get("item", "")])).strip()
        lookup[item] = display
        for w in item.split():
            if len(w) > 3 and w not in lookup:
                lookup[w] = display

    enriched = []
    for step in instructions:
        text = step.get("text", "") if isinstance(step, dict) else str(step)
        matches = [(len(k), k, v) for k, v in lookup.items() if k in text.lower()]
        seen, notes = set(), []
        for _, _, disp in sorted(matches, reverse=True):
            if disp not in seen:
                seen.add(disp)
                notes.append(disp)
        enriched.append(f"{text}  [{', '.join(notes)}]" if notes else text)
    return enriched


# ── Notion API helpers ─────────────────────────────────────────────────────────

def _notion():
    try:
        from notion_client import Client
    except ImportError:
        print("ERROR: notion-client not installed. Run: python -m pip install notion-client")
        sys.exit(1)
    if not NOTION_TOKEN:
        print("ERROR: NOTION_TOKEN not set in .env")
        sys.exit(1)
    return Client(auth=NOTION_TOKEN)


def _clear_page(client, page_id):
    resp = client.blocks.children.list(block_id=page_id)
    for block in resp.get("results", []):
        client.blocks.delete(block_id=block["id"])
    while resp.get("has_more"):
        resp = client.blocks.children.list(block_id=page_id, start_cursor=resp["next_cursor"])
        for block in resp.get("results", []):
            client.blocks.delete(block_id=block["id"])


def _append_blocks(client, page_id, blocks):
    for i in range(0, len(blocks), 100):
        client.blocks.children.append(block_id=page_id, children=blocks[i:i + 100])


# ── Data loading ───────────────────────────────────────────────────────────────

def _parse_history_atom(atom):
    content = atom.get("content", "")
    try:
        data = json.loads(content)
        if isinstance(data, dict) and "week_of" in data:
            return data
    except (json.JSONDecodeError, TypeError):
        pass

    title = atom.get("title", "")
    m = re.search(r"(\d{4}-\d{2}-\d{2})", title)
    week_of = m.group(1) if m else ""
    meals = []
    for line in content.strip().splitlines():
        line = line.strip()
        if not line.startswith("- "):
            continue
        line = line[2:]
        pm = re.match(r"^(.+?)\s*\(([^)]+)\)", line)
        if pm:
            meal_name = pm.group(1).strip()
            protein = pm.group(2).strip()
            after = line[pm.end():].strip()
            side = after.split("| side:")[1].strip() if "| side:" in after else None
            meals.append({"meal": meal_name, "protein": protein, "side": side})
    return {"week_of": week_of, "meals": meals}


def load_data():
    global _ELLSWORTH_NAMES

    recipes_raw = tank.query(domain="food", type="recipe", limit=200)
    recipes = []
    for r in recipes_raw:
        try:
            content = json.loads(r["content"]) if r.get("content") else {}
        except (json.JSONDecodeError, TypeError):
            content = {}
        content["_atom_id"] = r["id"]
        content["_title"] = r["title"]
        recipes.append(content)

    data_atoms = tank.query(domain="food", type="data", limit=20)
    by_title = {a["title"]: a for a in data_atoms}

    ell_atom = by_title.get("ellsworth_active_inventory")
    ellsworth = json.loads(ell_atom["content"]) if ell_atom else []
    _ELLSWORTH_NAMES = {row["Name"].lower() for row in ellsworth}

    pantry_atom = by_title.get("pantry_staples")
    pantry = json.loads(pantry_atom["content"]) if pantry_atom else {}

    cfg_atom = by_title.get("notion_config")
    notion_cfg = json.loads(cfg_atom["content"]) if cfg_atom else {}

    log_atoms = tank.query(domain="food", type="log", limit=100)
    history = []
    for r in log_atoms:
        if "Meal plan week of" in (r.get("title") or ""):
            parsed = _parse_history_atom(r)
            if parsed.get("week_of"):
                history.append(parsed)
    history.sort(key=lambda w: w["week_of"])

    global _data_load_summary
    _data_load_summary = {
        "recipes_loaded": len(recipes),
        "history_weeks_loaded": len(history),
        "ellsworth_rows_loaded": len(ellsworth),
        "data_atoms_loaded": len(data_atoms),
        "constraints": ["protein_pacing_26wk", "3wk_no_repeat", "starch_clash", "dietary_gf_dairy_almond"],
    }

    return {
        "recipes": recipes,
        "ellsworth": ellsworth,
        "pantry": pantry,
        "notion_config": notion_cfg,
        "history": history,
    }


# ── Protein pacing ─────────────────────────────────────────────────────────────

def pacing_scores(history, ellsworth):
    recent_26 = sorted(history, key=lambda w: w.get("week_of", ""), reverse=True)[:26]
    usage = Counter()
    for week in recent_26:
        for meal in week.get("meals", []):
            protein = meal.get("protein", "")
            if protein:
                usage[protein] += 1

    scores = {}
    for row in ellsworth:
        name = row.get("Name", "")
        schedule = row.get("Schedule", "Once a month")
        expected = FREQUENCY_26W.get(schedule, 6.5)
        actual = usage.get(name, 0)
        if expected == 0:
            status = "ON_TRACK"
        elif actual > expected * 1.2:
            status = "AHEAD"
        elif actual < expected * 0.8:
            status = "BEHIND"
        else:
            status = "ON_TRACK"
        scores[name] = {
            "schedule": schedule,
            "expected_26w": round(expected, 1),
            "actual_26w": actual,
            "status": status,
        }
    return scores


# ── Recipe filtering ───────────────────────────────────────────────────────────

def filter_recipes(recipes, ellsworth, history):
    available_proteins = {
        row["Name"] for row in ellsworth
        if int(float(row.get("Qty", 0))) > 0
    }

    recent_meals = set()
    for week in sorted(history, key=lambda w: w.get("week_of", ""), reverse=True)[:3]:
        for m in week.get("meals", []):
            recent_meals.add(m.get("meal", "").lower())

    eligible = [
        r for r in recipes
        if r.get("meal_type") == "dinner"
        and r.get("protein", "") in available_proteins
        and r.get("meal", "").lower() not in recent_meals
    ]
    return eligible, available_proteins


# ── Side veggie assignment ─────────────────────────────────────────────────────

def _assign_veggie(recipe, ellsworth, starch):
    starch_is_potato = starch and any(p in starch for p in POTATO_STARCHES)

    veggie_addins = recipe.get("veggie_addins")
    if veggie_addins:
        candidates = [
            v for v in veggie_addins
            if not (starch_is_potato and "corn" in v.lower())
        ]
        return random.choice(candidates) if candidates else None

    if not recipe.get("needs_side"):
        return None

    available_veggies = [
        row["Name"] for row in ellsworth
        if row.get("Item", "").startswith("4")
        and int(float(row.get("Qty", 0))) > 0
        and not (starch_is_potato and "corn" in row["Name"].lower())
    ]
    return random.choice(available_veggies) if available_veggies else None


# ── Meal proposal ──────────────────────────────────────────────────────────────

_DAY_ABBREV = {
    "MON": "Monday", "TUE": "Tuesday", "WED": "Wednesday", "THU": "Thursday", "FRI": "Friday",
    "MONDAY": "Monday", "TUESDAY": "Tuesday", "WEDNESDAY": "Wednesday",
    "THURSDAY": "Thursday", "FRIDAY": "Friday",
}


def _normalize_days(day_list):
    result = set()
    for d in (day_list or []):
        key = d.strip().upper()
        if key in _DAY_ABBREV:
            result.add(_DAY_ABBREV[key])
    return result


def propose_plan(start_date=None, busy_nights=None, eating_out=None, cravings=None, avoid=None):
    data = load_data()
    recipes = data["recipes"]
    ellsworth = data["ellsworth"]
    history = data["history"]

    if not start_date:
        today = date.today()
        days_ahead = (7 - today.weekday()) % 7 or 7
        start_date = (today + timedelta(days=days_ahead)).strftime("%Y-%m-%d")

    eating_out_days = _normalize_days(eating_out)
    busy_days = _normalize_days(busy_nights)
    craving_set = {c.lower().strip() for c in (cravings or [])}
    avoid_set = {a.lower().strip() for a in (avoid or [])}

    all_days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    active_days = [d for d in all_days if d not in eating_out_days]

    eligible, _ = filter_recipes(recipes, ellsworth, history)
    scores = pacing_scores(history, ellsworth)

    # Hard-filter avoided proteins and meal names
    if avoid_set:
        eligible = [
            r for r in eligible
            if r.get("protein", "").lower() not in avoid_set
            and r.get("meal", "").lower() not in avoid_set
        ]

    def priority(r, is_busy=False):
        status = scores.get(r.get("protein", ""), {}).get("status", "ON_TRACK")
        effort = r.get("effort", "Medium")
        base = {"BEHIND": 0, "ON_TRACK": 1, "AHEAD": 2}.get(status, 1)
        eff = {"Low": 0, "Medium": 1, "High": 2}.get(effort, 1)
        craving_boost = -5 if (
            any(c in r.get("protein", "").lower() for c in craving_set) or
            any(c in r.get("meal", "").lower() for c in craving_set)
        ) else 0
        return base * 10 + eff + craving_boost + random.random()

    plan = {"week_of": start_date, "days": []}
    used_groups = []
    used_titles = set()

    for day in active_days:
        is_busy = day in busy_days

        # For busy nights, only Low-effort meals qualify
        day_pool = [r for r in eligible if r.get("effort", "Medium") == "Low"] if is_busy else eligible[:]
        day_pool.sort(key=lambda r: priority(r, is_busy))

        selected = None
        for recipe in day_pool:
            protein = recipe.get("protein", "")
            group = PROTEIN_GROUPS.get(protein, protein)
            status = scores.get(protein, {}).get("status", "ON_TRACK")
            meal_title = recipe.get("meal", "")

            if meal_title in used_titles:
                continue
            has_non_ahead = sum(
                1 for r in eligible
                if scores.get(r.get("protein", ""), {}).get("status", "ON_TRACK") != "AHEAD"
            )
            if status == "AHEAD" and has_non_ahead > len(active_days):
                continue
            if used_groups and used_groups[-1] == group:
                continue
            if protein == "Chicken Breast" and sum(1 for d in plan["days"] if d.get("protein") == "Chicken Breast") >= 2:
                continue

            selected = recipe
            break

        # Fallback: relax protein-group and AHEAD constraints
        if not selected:
            for recipe in day_pool:
                if recipe.get("meal") not in used_titles:
                    selected = recipe
                    break

        # Last resort: pull from full eligible pool
        if not selected:
            for recipe in eligible:
                if recipe.get("meal") not in used_titles:
                    selected = recipe
                    break

        if not selected:
            continue

        protein = selected.get("protein", "")
        used_groups.append(PROTEIN_GROUPS.get(protein, protein))
        used_titles.add(selected.get("meal", ""))

        starch = selected.get("recommended_starch")
        veggie = _assign_veggie(selected, ellsworth, starch)

        thaw = []
        if protein:
            thaw.append(protein)
        if veggie and veggie.lower() in _ELLSWORTH_NAMES:
            thaw.append(veggie)

        rice_starch = starch if starch in RICE_STARCHES else None

        plan["days"].append({
            "day": day,
            "meal": selected.get("meal", ""),
            "protein": protein,
            "starch": starch,
            "side": veggie,
            "effort": selected.get("effort", ""),
            "cook_time": selected.get("total_time") or selected.get("cook_time", ""),
            "thaw": thaw,
            "rice_starch": rice_starch,
            "ingredients": selected.get("ingredients", []),
            "instructions_raw": selected.get("instructions", []),
        })

    return plan


# ── Grocery list ───────────────────────────────────────────────────────────────

def build_grocery_list(plan, pantry):
    aoh_keys = set()
    for group in pantry.get("always_on_hand", {}).values():
        if isinstance(group, list):
            for item in group:
                # Strip parentheticals like "(canned)", then split on "/" to get
                # normalized variants. Avoids word-level extraction which causes
                # false positives (e.g. "salt" from "Kosher Salt" blocking "unsalted butter").
                base = re.sub(r'\(.*?\)', '', item).strip()
                for variant in re.split(r'\s*/\s*', base):
                    v = variant.lower().strip()
                    if v:
                        aoh_keys.add(v)

    sections = {
        "Produce": [],
        "Meat & Seafood": [],
        "Dairy & Refrigerated": [],
        "Frozen": [],
        "Bakery & Deli": [],
        "Pantry & Dry Goods": [],
        "Oils & Spices (Check Pantry)": [],
    }
    meal_names, sub_notes, starch_adds = [], [], []
    seen_items = set()
    gf_pasta_needed = False

    produce_kw = ["tomato", "lemon", "lime", "onion", "shallot", "garlic", "carrot", "celery",
                  "pepper", "avocado", "potato", "basil", "ginger", "jalapen", "cilantro",
                  "scallion", "green onion", "mushroom", "zucchini", "squash", "snap pea",
                  "chile", "chili", "leek"]
    dairy_kw = ["cream", "cheese", "yogurt", "milk", "egg", "sour cream"]
    spice_kw = ["salt", "pepper", "paprika", "cumin", "oregano", "thyme", "rosemary",
                "chili powder", "cayenne", "turmeric", "curry", "cinnamon", "coriander",
                "bay leaf", "seasoning", "spice blend"]
    pantry_kw = ["sauce", "broth", "stock", "vinegar", "oil", "sugar", "honey", "syrup",
                 "bean", "rice", "pasta", "flour", "coconut", "tomato paste", "sesame",
                 "mirin", "fish sauce", "oyster sauce", "soy sauce", "tamari", "cornstarch",
                 "sriracha", "hoisin", "tamarind", "breadcrumb", "panko"]

    for day in plan.get("days", []):
        meal_names.append(day.get("meal", ""))
        starch = day.get("starch")
        if starch and starch not in RICE_STARCHES and starch != "Gluten-Free Pasta":
            if starch in POTATO_STARCHES:
                key = starch.lower()
                if key not in seen_items:
                    starch_adds.append(starch + " (2 lbs)")
                    seen_items.add(key)
        if starch == "Gluten-Free Pasta":
            gf_pasta_needed = True

        for ing in day.get("ingredients", []):
            item_str = ing.get("item", "").lower().strip()
            if not item_str:
                continue

            if any(e in item_str for e in _ELLSWORTH_NAMES):
                continue
            skip = any(a in item_str for a in aoh_keys)
            if skip:
                continue

            dedup_key = item_str[:25]
            if dedup_key in seen_items:
                continue
            seen_items.add(dedup_key)

            display = " ".join(filter(None, [
                ing.get("amount", ""), ing.get("unit", ""), ing.get("item", "")
            ])).strip()

            gluten_flag = any(k in item_str for k in ["flour", "breadcrumb", "panko"])
            dairy_flag = (
                any(k in item_str for k in ["heavy cream", "whipping cream", "milk", "cream cheese"])
                and "butter" not in item_str
                and "coconut" not in item_str
                and "oat" not in item_str
            )

            if gluten_flag:
                display += " [GF substitute for wife]"
                sub_notes.append(f"{day.get('meal')}: {ing.get('item')} - use King Arthur GF 1:1")
            if dairy_flag:
                display += " [dairy note for wife]"
                sub_notes.append(f"{day.get('meal')}: {ing.get('item')} - use dairy-free alternative")

            is_dried_herb = "dried" in item_str and any(k in item_str for k in produce_kw)
            if any(k in item_str for k in spice_kw) or is_dried_herb:
                sections["Oils & Spices (Check Pantry)"].append(display)
            elif any(k in item_str for k in produce_kw):
                sections["Produce"].append(display)
            elif any(k in item_str for k in dairy_kw) and "butter" not in item_str:
                sections["Dairy & Refrigerated"].append(display)
            elif any(k in item_str for k in pantry_kw):
                sections["Pantry & Dry Goods"].append(display)
            else:
                sections["Pantry & Dry Goods"].append(display)

    for item in starch_adds:
        sections["Produce"].append(item)
    if gf_pasta_needed:
        sections["Pantry & Dry Goods"].append("Gluten-Free Pasta [GF for wife]")

    cat_map = {
        "produce": "Produce",
        "dairy_refrigerated": "Dairy & Refrigerated",
        "bakery_deli": "Bakery & Deli",
        "frozen": "Frozen",
        "pantry_dry_goods": "Pantry & Dry Goods",
    }
    for cat_key, items in pantry.get("weekly_staples", {}).items():
        section = cat_map.get(cat_key, "Pantry & Dry Goods")
        for item in items:
            sections[section].append(f"{item} [Staple]")

    return {
        "week_of": plan.get("week_of", ""),
        "meals_this_week": meal_names,
        "sections": sections,
        "substitution_notes": list(dict.fromkeys(sub_notes)),
    }


# ── History save ───────────────────────────────────────────────────────────────

def save_history(plan):
    week_of = plan.get("week_of", "")
    meals = [
        {
            "meal": d.get("meal", ""),
            "protein": d.get("protein", ""),
            "side": d.get("side"),
            "starch": d.get("starch"),
        }
        for d in plan.get("days", [])
    ]
    content_data = {
        "week_of": week_of,
        "confirmed_at": datetime.now().isoformat(),
        "meals": meals,
    }
    atom_id = tank.add_atom(
        domain="food",
        type="log",
        title=f"Meal plan week of {week_of}",
        content=json.dumps(content_data),
        tags=["meal_plan"],
    )
    print(f"History saved: {atom_id} - week of {week_of}")
    return atom_id


# ── Inventory update ──────────────────────────────────────────────────────────

def update_inventory(plan):
    data_atoms = tank.query(domain="food", type="data", limit=20)
    by_title = {a["title"]: a for a in data_atoms}
    ell_atom = by_title.get("ellsworth_active_inventory")
    if not ell_atom:
        print("WARNING: ellsworth_active_inventory not found — skipping inventory update")
        return

    inventory = json.loads(ell_atom["content"])
    inv_by_name = {row["Name"]: row for row in inventory}

    decrements = {}
    for day in plan.get("days", []):
        protein = day.get("protein")
        side = day.get("side")
        if protein and protein in CONSUMPTION_RATES:
            decrements[protein] = decrements.get(protein, 0) + CONSUMPTION_RATES[protein]
        if side and side in CONSUMPTION_RATES:
            decrements[side] = decrements.get(side, 0) + CONSUMPTION_RATES[side]

    warnings = []
    for name, amount in decrements.items():
        if name not in inv_by_name:
            continue
        current = float(inv_by_name[name]["Qty"])
        new_qty = current - amount
        if new_qty < 0:
            new_qty = 0
            warnings.append(f"WARNING: {name} inventory insufficient — set to 0 (needed {amount}, had {current})")
        inv_by_name[name]["Qty"] = new_qty
        if new_qty == 0:
            warnings.append(f"DEPLETED: {name} is now at 0")

    updated = list(inv_by_name.values())
    tank.update_content(ell_atom["id"], json.dumps(updated))

    for w in warnings:
        print(w)

    if not warnings:
        print("Inventory updated.")
    return warnings


# ── Notion push: meal plan ─────────────────────────────────────────────────────

def push_plan(plan, notion_cfg):
    client = _notion()
    meal_pages = notion_cfg.get("meal_pages", {})

    for day_data in plan.get("days", []):
        day = day_data.get("day", "")
        meal = day_data.get("meal", "")
        cook_time = day_data.get("cook_time", "")
        thaw = day_data.get("thaw", [])
        starch = day_data.get("starch")
        side = day_data.get("side")
        ingredients = day_data.get("ingredients", [])
        instructions_raw = day_data.get("instructions_raw", [])

        rice_starch = day_data.get("rice_starch")
        page_id = meal_pages.get(day)
        if not page_id:
            print(f"  WARNING: no page_id for {day}, skipping")
            continue

        instructions = _enrich_instructions(ingredients, instructions_raw)
        _clear_page(client, page_id)
        client.pages.update(
            page_id=page_id,
            properties={"title": {"title": _rt(meal)}}
        )

        blocks = [_h2(meal)]

        sides_parts = [s for s in [starch, side] if s]
        if sides_parts:
            blocks.append(_para("Sides: " + " + ".join(sides_parts)))

        if thaw:
            blocks.append(_callout("Thaw from freezer:  " + "  •  ".join(thaw), "❄️"))

        if rice_starch:
            blocks.append(_callout(f"Pre-make rice: {rice_starch}", "🍚"))

        if cook_time:
            blocks.append(_para(f"Total time: {cook_time}"))

        blocks.append(_divider())
        blocks.append(_h3("Ingredients"))
        for ing in ingredients:
            line = " ".join(filter(None, [
                ing.get("amount", ""), ing.get("unit", ""), ing.get("item", "")
            ])).strip()
            if line:
                blocks.append(_bullet(line))

        blocks.append(_h3("Instructions"))
        for step_text in instructions:
            if step_text:
                blocks.append(_numbered(step_text))

        _append_blocks(client, page_id, blocks)
        print(f"  Pushed: {day} - {meal}")

    print("Meal plan pushed to Notion.")


# ── Notion push: grocery list ──────────────────────────────────────────────────

def push_grocery(grocery_data, notion_cfg):
    client = _notion()
    page_id = notion_cfg.get("grocery_list_page")
    if not page_id:
        print("ERROR: no grocery_list_page in notion_config")
        sys.exit(1)

    week_of = grocery_data.get("week_of", "")
    meals = grocery_data.get("meals_this_week", [])
    sections = grocery_data.get("sections", {})
    sub_notes = grocery_data.get("substitution_notes", [])

    _clear_page(client, page_id)
    client.pages.update(
        page_id=page_id,
        properties={"title": {"title": _rt(f"Week of {week_of}")}}
    )

    blocks = [
        _h2(f"Grocery List - Week of {week_of}"),
        _para(f"Generated {datetime.now().strftime('%B %d, %Y')}"),
        _divider(),
        _h3("This Week's Meals"),
    ]
    for meal in meals:
        blocks.append(_bullet(meal))
    blocks.append(_divider())

    emojis = {
        "Produce": "🥦", "Meat & Seafood": "🥩", "Dairy & Refrigerated": "🥛",
        "Frozen": "❄️", "Bakery & Deli": "🍞", "Pantry & Dry Goods": "🫙",
        "Oils & Spices (Check Pantry)": "🧂",
    }
    for section_name, items in sections.items():
        if not items:
            continue
        emoji = emojis.get(section_name, "")
        label = f"{emoji}  {section_name}" if emoji else section_name
        blocks.append(_h3(label))
        for item in items:
            blocks.append(_bullet(item))

    if sub_notes:
        blocks.append(_divider())
        blocks.append(_h3("Allergy Substitutions (Wife)"))
        for note in sub_notes:
            blocks.append(_bullet(note))

    _append_blocks(client, page_id, blocks)
    print(f"Grocery list pushed to Notion: week of {week_of}")


# ── patch_starch ───────────────────────────────────────────────────────────────

def patch_starch(meal_name, new_starch):
    """Update recommended_starch on a recipe in Construct wiki."""
    recipes = tank.query(domain="food", type="recipe", limit=200)
    match = next((r for r in recipes if r["title"].lower() == meal_name.lower()), None)
    if not match:
        print(f"Recipe not found: {meal_name}")
        return

    try:
        content = json.loads(match["content"]) if match.get("content") else {}
    except (json.JSONDecodeError, TypeError):
        content = {}

    old_starch = content.get("recommended_starch")
    content["recommended_starch"] = new_starch
    tank.update_content(match["id"], json.dumps(content))
    print(f"Updated {meal_name}: '{old_starch}' -> '{new_starch}'")


# ── CLI ────────────────────────────────────────────────────────────────────────

def _print_plan(plan):
    print(f"\nWeek of {plan['week_of']}:")
    for day in plan.get("days", []):
        starch = day.get("starch") or ""
        side = day.get("side") or ""
        sides = " + ".join(filter(None, [starch, side]))
        sides_str = f" | {sides}" if sides else ""
        effort = day.get("effort", "")
        effort_str = f" [{effort}]" if effort else ""
        print(f"  {day['day']:10} {day['meal']} ({day['protein']}){sides_str} - {day.get('cook_time', '')}{effort_str}")


def _split_csv(val):
    return [v.strip() for v in val.split(",")] if val else []


def cmd_plan(args):
    plan = propose_plan(
        start_date=getattr(args, "date", None),
        busy_nights=_split_csv(getattr(args, "busy_nights", None)),
        eating_out=_split_csv(getattr(args, "eating_out", None)),
        cravings=_split_csv(getattr(args, "cravings", None)),
        avoid=_split_csv(getattr(args, "avoid", None)),
    )
    _print_plan(plan)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(plan, f, indent=2)
        print(f"\nPlan written to {args.output}")


def cmd_push(args):
    with open(args.file, encoding="utf-8") as f:
        plan = json.load(f)

    data = load_data()
    notion_cfg = data["notion_config"]
    pantry = data["pantry"]

    push_plan(plan, notion_cfg)
    grocery = build_grocery_list(plan, pantry)
    push_grocery(grocery, notion_cfg)
    save_history(plan)
    update_inventory(plan)


def cmd_full(args):
    plan = propose_plan(start_date=getattr(args, "date", None))
    _print_plan(plan)

    data = load_data()
    push_plan(plan, data["notion_config"])
    grocery = build_grocery_list(plan, data["pantry"])
    push_grocery(grocery, data["notion_config"])
    save_history(plan)


def cmd_pacing(args):
    data = load_data()
    scores = pacing_scores(data["history"], data["ellsworth"])
    print(f"\nProtein pacing ({len(data['history'])} weeks of history):\n")
    for protein, info in sorted(scores.items(), key=lambda x: x[1]["status"]):
        qty = next((int(float(r.get("Qty", 0))) for r in data["ellsworth"] if r["Name"] == protein), 0)
        status_flag = {"BEHIND": "<<", "AHEAD": ">>", "ON_TRACK": "  "}.get(info["status"], "  ")
        print(f"  {status_flag} {protein:28} {info['status']:10} "
              f"used={info['actual_26w']:2}  expected={info['expected_26w']:4}  in_stock={qty}")


def cmd_patch_starch(args):
    patch_starch(args.meal, args.starch)


def main():
    parser = argparse.ArgumentParser(description="REMY - Meal planning for the week")
    sub = parser.add_subparsers(dest="command", required=True)

    p_plan = sub.add_parser("plan", help="Generate meal plan JSON (no push)")
    p_plan.add_argument("date", nargs="?", help="Start date YYYY-MM-DD (default: next Monday)")
    p_plan.add_argument("--output", "-o", help="Write plan JSON to file")
    p_plan.add_argument("--busy-nights", help="Comma-separated days (MON,TUE,etc) - only Low-effort meals proposed")
    p_plan.add_argument("--eating-out", help="Comma-separated days to skip (no meal planned)")
    p_plan.add_argument("--cravings", help="Comma-separated proteins or keywords to weight higher")
    p_plan.add_argument("--avoid", help="Comma-separated proteins or meal names to never propose")

    p_push = sub.add_parser("push", help="Push a plan JSON file to Notion")
    p_push.add_argument("file", help="Path to plan JSON file")

    p_full = sub.add_parser("full", help="Generate plan + push to Notion (end-to-end)")
    p_full.add_argument("date", nargs="?", help="Start date YYYY-MM-DD (default: next Monday)")

    p_pacing = sub.add_parser("pacing", help="Show protein pacing report")

    p_patch = sub.add_parser("patch-starch", help="Update recommended_starch on a recipe")
    p_patch.add_argument("meal", help="Exact recipe name")
    p_patch.add_argument("starch", help="New starch value")

    args = parser.parse_args()
    dispatch = {
        "plan": cmd_plan,
        "push": cmd_push,
        "full": cmd_full,
        "pacing": cmd_pacing,
        "patch-starch": cmd_patch_starch,
    }
    dispatch[args.command](args)


if __name__ == "__main__":
    main()
