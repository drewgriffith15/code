# REMY (Recipe Engine for Meal Yielding)
# Personal weekly meal planning system.
# Reads data from Construct wiki markdown files. Pushes plan + grocery list to Notion.

import os
import sys
import csv
import json
import argparse
import random
import re
from pathlib import Path
from datetime import datetime, timedelta, date
from collections import Counter
from dotenv import load_dotenv

load_dotenv(Path.home() / ".claude" / ".env.personal", override=True)

NOTION_TOKEN = os.getenv("NOTION_TOKEN")
WIKI_FOOD = Path(os.getenv("WIKI_FOOD", ""))

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

_ELLSWORTH_NAMES: set = set()
_data_load_summary: dict = {}


def _current_season() -> str:
    month = datetime.now().month
    return "spring-summer" if 3 <= month <= 8 else "fall-winter"


def _monday_of_week(d: date) -> date:
    return d - timedelta(days=d.weekday())


# ── Markdown parsing ───────────────────────────────────────────────────────────

def _parse_frontmatter(text: str) -> dict:
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}
    fm = {}
    for line in parts[1].splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ": " in line:
            key, _, val = line.partition(": ")
        elif line.endswith(":"):
            key, val = line[:-1], ""
        else:
            continue
        key = key.strip()
        val = val.strip()
        if val.startswith("[") and val.endswith("]"):
            fm[key] = [v.strip() for v in val[1:-1].split(",")]
        elif val.lower() == "true":
            fm[key] = True
        elif val.lower() == "false":
            fm[key] = False
        elif val.lower() in ("null", "~", ""):
            fm[key] = None
        else:
            fm[key] = val
    return fm


def _parse_json_block(text: str) -> dict:
    m = re.search(r"```json\s*\n([\s\S]+?)\n```", text)
    if not m:
        return {}
    try:
        return json.loads(m.group(1))
    except json.JSONDecodeError:
        return {}


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
        print("ERROR: NOTION_TOKEN not set in .env.personal")
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


def _update_notion_config(key: str, value: str):
    path = WIKI_FOOD / "notion-config.md"
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    data = _parse_json_block(text)
    data[key] = value
    new_json = json.dumps(data, indent=2, ensure_ascii=False)
    new_text = re.sub(r"```json\s*\n[\s\S]+?\n```", f"```json\n{new_json}\n```", text, count=1)
    path.write_text(new_text, encoding="utf-8")
    print(f"notion-config.md updated: {key} = {value}")


def _hub_page_id(notion_cfg) -> str:
    hub = notion_cfg.get("remy_main_page")
    if not hub:
        print("ERROR: no remy_main_page in notion-config.md")
        sys.exit(1)
    return hub


def _content_parent_id(notion_cfg) -> str:
    parent = notion_cfg.get("remy_sources_page") or notion_cfg.get("remy_main_page")
    if not parent:
        print("ERROR: no remy_sources_page or remy_main_page in notion-config.md")
        sys.exit(1)
    return parent


def _description_block_id(client, hub_page_id):
    resp = client.blocks.children.list(block_id=hub_page_id)
    for b in resp.get("results", []):
        if b.get("type") == "paragraph":
            return b["id"]
    return None


def _toggle_heading(text, children):
    return {
        "object": "block",
        "type": "heading_2",
        "heading_2": {
            "rich_text": _rt(text),
            "is_toggleable": True,
            "children": children,
        },
    }


def _toggle_block(text, children):
    return {
        "object": "block",
        "type": "toggle",
        "toggle": {"rich_text": _rt(text), "children": children},
    }


def _bullet_with_link(prefix, page_id, page_title):
    return {
        "object": "block",
        "type": "bulleted_list_item",
        "bulleted_list_item": {
            "rich_text": [
                {"type": "text", "text": {"content": prefix}},
                {"type": "mention", "mention": {"type": "page", "page": {"id": page_id}}},
            ],
        },
    }


def _create_child_page(client, parent_page_id, title, blocks):
    page = client.pages.create(
        parent={"type": "page_id", "page_id": parent_page_id},
        properties={"title": {"title": _rt(title)}},
    )
    page_id = page["id"]
    if blocks:
        _append_blocks(client, page_id, blocks)
    return page_id


# ── Data loading ───────────────────────────────────────────────────────────────

def _load_recipes() -> list:
    recipes_dir = WIKI_FOOD / "recipes"
    recipes = []
    for path in sorted(recipes_dir.glob("*.md")):
        text = path.read_text(encoding="utf-8")
        fm = _parse_frontmatter(text)
        tags = fm.get("tags") or []
        if isinstance(tags, str):
            tags = [tags]
        if "remy" not in tags:
            continue
        data = _parse_json_block(text)
        if not data:
            continue
        if fm.get("season"):
            data["season"] = fm["season"]
        data.setdefault("meal_type", fm.get("meal_type"))
        data.setdefault("protein", fm.get("protein"))
        data.setdefault("effort", fm.get("effort"))
        data.setdefault("needs_side", fm.get("needs_side", False))
        data.setdefault("recommended_starch", fm.get("recommended_starch"))
        data["_file"] = str(path)
        recipes.append(data)
    return recipes


def _load_ellsworth() -> tuple:
    path = WIKI_FOOD / "ellsworth_last_order.md"
    text = path.read_text(encoding="utf-8")
    parts = text.split("---", 2)
    body = parts[2] if len(parts) >= 3 else text
    lines = [l for l in body.strip().splitlines() if l.strip() and not l.startswith("#")]
    reader = csv.DictReader(lines)
    proteins, veggies, all_names = [], [], set()
    seen_names = set()
    for row in reader:
        item = row.get("Item", "").strip()
        name = row.get("Name", "").strip()
        schedule = row.get("Schedule", "Once a month").strip()
        if not name or name in seen_names:
            continue
        seen_names.add(name)
        all_names.add(name.lower())
        if name in PROTEIN_GROUPS:
            proteins.append({"Name": name, "Schedule": schedule})
        else:
            veggies.append({"Name": name})
    return proteins, veggies, all_names


def _load_depleted() -> set:
    path = WIKI_FOOD / "ellsworth_next_order_notes.md"
    if not path.exists():
        return set()
    text = path.read_text(encoding="utf-8")
    depleted = set()
    in_section = False
    for line in text.splitlines():
        if "Proteins That Ran Out Early" in line:
            in_section = True
            continue
        if in_section and line.startswith("##"):
            break
        if in_section and line.startswith("|") and "---" not in line and "Protein" not in line:
            cols = [c.strip() for c in line.strip("|").split("|")]
            if cols and cols[0]:
                depleted.add(cols[0].strip())
    return depleted


def _load_md_json(filename: str) -> dict:
    path = WIKI_FOOD / filename
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8")
    return _parse_json_block(text)


def _load_history() -> list:
    path = WIKI_FOOD / "meal-plans" / "meal-history.json"
    if not path.exists():
        return []
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except (json.JSONDecodeError, OSError):
        return []


def load_data() -> dict:
    global _ELLSWORTH_NAMES, _data_load_summary

    recipes = _load_recipes()
    proteins, veggies, all_names = _load_ellsworth()
    depleted = _load_depleted()
    _ELLSWORTH_NAMES = all_names

    available_proteins = {p["Name"] for p in proteins if p["Name"] not in depleted}

    pantry = _load_md_json("pantry-staples.md")
    notion_cfg = _load_md_json("notion-config.md")
    history = _load_history()

    _data_load_summary = {
        "recipes_loaded": len(recipes),
        "history_weeks_loaded": len(history),
        "ellsworth_proteins": len(proteins),
        "depleted": list(depleted),
        "constraints": ["protein_pacing_26wk", "3wk_no_repeat", "starch_clash", "seasonal_boost", "dietary_gf_dairy_almond"],
    }

    return {
        "recipes": recipes,
        "ellsworth_proteins": proteins,
        "ellsworth_veggies": veggies,
        "available_proteins": available_proteins,
        "depleted_proteins": depleted,
        "pantry": pantry,
        "notion_config": notion_cfg,
        "history": history,
    }


# ── Protein pacing ─────────────────────────────────────────────────────────────

def pacing_scores(history, ellsworth_proteins):
    recent_26 = sorted(history, key=lambda w: w.get("week_of", ""), reverse=True)[:26]
    usage = Counter()
    for week in recent_26:
        for meal in week.get("meals", []):
            protein = meal.get("protein", "")
            if protein:
                usage[protein] += 1

    scores = {}
    for row in ellsworth_proteins:
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

def filter_recipes(recipes, available_proteins, history):
    recent_meals = set()
    for week in sorted(history, key=lambda w: w.get("week_of", ""), reverse=True)[:3]:
        for m in week.get("meals", []):
            recent_meals.add(m.get("meal", "").lower())

    return [
        r for r in recipes
        if r.get("meal_type") == "dinner"
        and r.get("protein", "") in available_proteins
        and r.get("meal", "").lower() not in recent_meals
    ]


# ── Side veggie assignment ─────────────────────────────────────────────────────

def _assign_veggie(recipe, ellsworth_veggies, starch):
    starch_is_potato = starch and any(p in starch for p in POTATO_STARCHES)

    veggie_addins = recipe.get("veggie_addins")
    if veggie_addins:
        candidates = [v for v in veggie_addins if not (starch_is_potato and "corn" in v.lower())]
        return random.choice(candidates) if candidates else None

    if not recipe.get("needs_side"):
        return None

    available = [
        row["Name"] for row in ellsworth_veggies
        if not (starch_is_potato and "corn" in row["Name"].lower())
    ]
    return random.choice(available) if available else None


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
    ellsworth_veggies = data["ellsworth_veggies"]
    ellsworth_proteins = data["ellsworth_proteins"]
    available_proteins = data["available_proteins"]
    history = data["history"]
    season = _current_season()

    if not start_date:
        today = date.today()
        days_ahead = (7 - today.weekday()) % 7 or 7
        start_date = _monday_of_week(today + timedelta(days=days_ahead)).strftime("%Y-%m-%d")
    else:
        start_date = _monday_of_week(datetime.strptime(start_date, "%Y-%m-%d").date()).strftime("%Y-%m-%d")

    eating_out_days = _normalize_days(eating_out)
    busy_days = _normalize_days(busy_nights)
    craving_set = {c.lower().strip() for c in (cravings or [])}
    avoid_set = {a.lower().strip() for a in (avoid or [])}

    all_days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    active_days = [d for d in all_days if d not in eating_out_days]

    eligible = filter_recipes(recipes, available_proteins, history)
    scores = pacing_scores(history, ellsworth_proteins)

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
        recipe_season = r.get("season")
        season_boost = -2 if recipe_season == season else (2 if recipe_season and recipe_season != season else 0)
        return base * 10 + eff + craving_boost + season_boost + random.random()

    plan = {"week_of": start_date, "days": []}
    used_groups = []
    used_titles = set()

    for day in active_days:
        is_busy = day in busy_days
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

        if not selected:
            for recipe in day_pool:
                if recipe.get("meal") not in used_titles:
                    selected = recipe
                    break

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
        veggie = _assign_veggie(selected, ellsworth_veggies, starch)

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
            "cook_time": selected.get("cook_time", ""),
            "total_time": selected.get("total_time", "") or selected.get("cook_time", ""),
            "thaw": thaw,
            "rice_starch": rice_starch,
            "ingredients": selected.get("ingredients", []),
            "instructions_raw": selected.get("instructions", []),
        })

    return plan


# ── Grocery list ───────────────────────────────────────────────────────────────

_GROCERY_SECTIONS = [
    "Produce", "Meat & Seafood", "Dairy & Refrigerated", "Frozen",
    "Bakery & Deli", "Pantry & Dry Goods", "Oils & Spices (Check Pantry)",
]


def _llm_consolidate_grocery(raw_items, already_have=None):
    """Call Opus to consolidate ingredients into purchase-sized grocery items.
    `already_have` is a list of item names Drew already buys as staples or keeps on hand.
    Returns {'sections': {...}, 'substitution_notes': [...]} or None on failure."""
    if not raw_items:
        return {"sections": {s: [] for s in _GROCERY_SECTIONS}, "substitution_notes": []}
    already_have = already_have or []
    try:
        from anthropic import Anthropic
    except ImportError:
        print("WARN: anthropic SDK not installed. Run: python -m pip install anthropic")
        return None

    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        print("WARN: ANTHROPIC_API_KEY not set in .env.personal. Falling back to heuristic.")
        return None

    sections_str = ", ".join(f'"{s}"' for s in _GROCERY_SECTIONS)
    prompt = f"""You are compiling a weekly grocery shopping list for Drew's family.

Below is the raw list of dinner ingredients across this week. Your job:

1. CONSOLIDATE duplicates across meals. Sum quantities of the same ingredient. Example: "2 tbsp tomato paste" + "3 tbsp tomato paste" becomes one line.

2. CONVERT recipe quantities to purchasable quantities. Recipes call for specific amounts, but the grocery store sells fixed package sizes. Translate. Examples:
   - 5 tbsp tomato paste -> "1 can (6 oz) tomato paste"
   - 1/2 cup coconut milk -> "1 can (13.5 oz) coconut milk"
   - 1 lb ground beef -> "1 lb ground beef" (already purchase-sized)
   - 3 tbsp soy sauce -> "1 small bottle soy sauce (check pantry)"
   - 2 lemons -> "2 lemons"
   - 1 bunch cilantro -> "1 bunch cilantro"
   - 4 oz cream cheese -> "1 block (8 oz) cream cheese"

3. CATEGORIZE each consolidated item into one of these sections (use exact section names):
   {sections_str}

4. FLAG dietary substitutions for Drew's wife. Wife is gluten-free (use King Arthur GF 1:1 for wheat flour, GF pasta for pasta, GF panko/breadcrumbs), dairy-sensitive (avoid liquid dairy except butter; sub coconut or oat alternatives), and almond-allergic. When an item needs a sub, append " [GF substitute for wife]" or " [dairy-free substitute for wife]" to the item string AND add a corresponding line to substitution_notes shaped "MealName: original ingredient - swap instruction".

5. USE COMMON SENSE on quantities. If a recipe needs a small amount of an oil, vinegar, or pantry sauce, assume Drew probably has it; append "(check pantry)". Buy the smallest package of fresh herbs only used once.

6. DO NOT DUPLICATE STAPLES. Drew already buys these every week as weekly staples or keeps them always on hand. OMIT them entirely from your output. Do not add a separate line for any of these, even if a recipe calls for them. Drew has plenty.

Already-have list (do not duplicate any of these):
{json.dumps(already_have, indent=2)}

Raw ingredient list (may have cross-meal duplicates):
{json.dumps(raw_items, indent=2)}

Return ONLY a JSON object, no preamble, no markdown fences, matching this exact shape:
{{
  "sections": {{
    "Produce": ["item 1", "item 2"],
    "Meat & Seafood": [],
    "Dairy & Refrigerated": [],
    "Frozen": [],
    "Bakery & Deli": [],
    "Pantry & Dry Goods": [],
    "Oils & Spices (Check Pantry)": []
  }},
  "substitution_notes": ["Meal Name: ingredient - swap instruction"]
}}
"""
    try:
        client = Anthropic(api_key=api_key)
        resp = client.messages.create(
            model="claude-opus-4-7",
            max_tokens=4000,
            messages=[{"role": "user", "content": prompt}],
        )
        text = resp.content[0].text.strip()
        if text.startswith("```"):
            text = re.sub(r'^```(?:json)?\s*|\s*```$', '', text, flags=re.MULTILINE).strip()
        data = json.loads(text)
        secs = {s: list(data.get("sections", {}).get(s, [])) for s in _GROCERY_SECTIONS}
        notes = list(data.get("substitution_notes", []))
        return {"sections": secs, "substitution_notes": notes}
    except Exception as e:
        print(f"WARN: Opus grocery consolidation failed ({e}). Falling back to heuristic.")
        return None


def build_grocery_list(plan, pantry):
    aoh_keys = set()
    for group in pantry.get("always_on_hand", {}).values():
        if isinstance(group, list):
            for item in group:
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
    raw_items = []
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
            if any(a in item_str for a in aoh_keys):
                continue

            dedup_key = item_str[:25]
            if dedup_key in seen_items:
                continue
            seen_items.add(dedup_key)

            raw_items.append({
                "meal": day.get("meal", ""),
                "item": ing.get("item", ""),
                "amount": ing.get("amount", ""),
                "unit": ing.get("unit", ""),
            })

    already_have = []
    for items in pantry.get("weekly_staples", {}).values():
        if isinstance(items, list):
            already_have.extend(items)
    for group in pantry.get("always_on_hand", {}).values():
        if isinstance(group, list):
            already_have.extend(group)

    llm_result = _llm_consolidate_grocery(raw_items, already_have=already_have)
    if llm_result is not None:
        sections = llm_result["sections"]
        sub_notes = llm_result["substitution_notes"]
    else:
        for raw in raw_items:
            item_str = raw["item"].lower().strip()
            display = " ".join(filter(None, [raw["amount"], raw["unit"], raw["item"]])).strip()

            gluten_flag = any(k in item_str for k in ["flour", "breadcrumb", "panko"])
            dairy_flag = (
                any(k in item_str for k in ["heavy cream", "whipping cream", "milk", "cream cheese"])
                and "butter" not in item_str
                and "coconut" not in item_str
                and "oat" not in item_str
            )
            if gluten_flag:
                display += " [GF substitute for wife]"
                sub_notes.append(f"{raw['meal']}: {raw['item']} - use King Arthur GF 1:1")
            if dairy_flag:
                display += " [dairy note for wife]"
                sub_notes.append(f"{raw['meal']}: {raw['item']} - use dairy-free alternative")

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
    entry = {
        "week_of": week_of,
        "confirmed_at": datetime.now().isoformat(),
        "meals": meals,
    }
    history_path = WIKI_FOOD / "meal-plans" / "meal-history.json"
    history = _load_history()
    history.append(entry)
    history_path.parent.mkdir(parents=True, exist_ok=True)
    with open(history_path, "w", encoding="utf-8") as f:
        json.dump(history, f, indent=2, ensure_ascii=False)
    print(f"History saved: week of {week_of}")


# ── Notion push: meal plan ─────────────────────────────────────────────────────

def _build_meal_blocks(day_data):
    meal = day_data.get("meal", "")
    starch = day_data.get("starch") or ""
    side = day_data.get("side")
    total_time = day_data.get("total_time", "") or ""
    rice_starch = day_data.get("rice_starch")
    ingredients = day_data.get("ingredients", [])
    instructions_raw = day_data.get("instructions_raw", [])
    instructions = _enrich_instructions(ingredients, instructions_raw)

    blocks = [_h2(meal)]
    sides_parts = [s for s in [starch, side] if s]
    if sides_parts:
        blocks.append(_para("Sides: " + " + ".join(sides_parts)))
    if rice_starch:
        blocks.append(_callout(f"Pre-make rice: {rice_starch}", "🍚"))
    if total_time:
        blocks.append(_para(f"Total time: {total_time}"))

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
    return blocks


def push_plan(plan, notion_cfg):
    client = _notion()
    parent = _content_parent_id(notion_cfg)
    week_of = plan.get("week_of", "")
    meal_pages = []

    for day_data in plan.get("days", []):
        day = day_data.get("day", "")
        meal = day_data.get("meal", "")
        blocks = _build_meal_blocks(day_data)
        page_id = _create_child_page(client, parent, meal, blocks)
        meal_pages.append({"day": day, "meal": meal, "page_id": page_id})
        print(f"  Pushed: {day} - {meal}")

    print("Meal plan pushed to Notion.")
    return meal_pages


# ── Notion push: grocery list ──────────────────────────────────────────────────

_GROCERY_EMOJIS = {
    "Produce": "🥦", "Meat & Seafood": "🥩", "Dairy & Refrigerated": "🥛",
    "Frozen": "❄️", "Bakery & Deli": "🍞", "Pantry & Dry Goods": "🫙",
    "Oils & Spices (Check Pantry)": "🧂",
}


def _save_grocery_local(grocery_data):
    week_of = grocery_data.get("week_of", "")
    meals = grocery_data.get("meals_this_week", [])
    sections = grocery_data.get("sections", {})
    sub_notes = grocery_data.get("substitution_notes", [])

    grocery_dir = WIKI_FOOD / "grocery-lists"
    grocery_dir.mkdir(parents=True, exist_ok=True)
    path = grocery_dir / f"{week_of}.md"

    lines = [
        "---",
        f"week_of: {week_of}",
        f"generated: {datetime.now().strftime('%Y-%m-%d')}",
        "---",
        "",
        f"# Grocery List - Week of {week_of}",
        "",
        "## This Week's Meals",
        "",
    ]
    for meal in meals:
        lines.append(f"- {meal}")
    lines.append("")

    for section_name, items in sections.items():
        if not items:
            continue
        emoji = _GROCERY_EMOJIS.get(section_name, "")
        label = f"{emoji} {section_name}" if emoji else section_name
        lines.append(f"## {label}")
        lines.append("")
        for item in items:
            lines.append(f"- [ ] {item}")
        lines.append("")

    if sub_notes:
        lines.append("## Allergy Substitutions (Wife)")
        lines.append("")
        for note in sub_notes:
            lines.append(f"- {note}")

    path.write_text("\n".join(lines), encoding="utf-8")
    print(f"Grocery list saved locally: {path}")


def push_grocery(grocery_data, notion_cfg):
    client = _notion()
    parent = _content_parent_id(notion_cfg)

    week_of = grocery_data.get("week_of", "")
    meals = grocery_data.get("meals_this_week", [])
    sections = grocery_data.get("sections", {})
    sub_notes = grocery_data.get("substitution_notes", [])

    blocks = [
        _para(f"Generated {datetime.now().strftime('%B %d, %Y')}"),
        _divider(),
        _h3("This Week's Meals"),
    ]
    for meal in meals:
        blocks.append(_bullet(meal))
    blocks.append(_divider())

    for section_name, items in sections.items():
        if not items:
            continue
        emoji = _GROCERY_EMOJIS.get(section_name, "")
        label = f"{emoji}  {section_name}" if emoji else section_name
        blocks.append(_h3(label))
        for item in items:
            blocks.append({"object": "block", "type": "to_do", "to_do": {"rich_text": _rt(item), "checked": False}})

    if sub_notes:
        blocks.append(_divider())
        blocks.append(_h3("Allergy Substitutions (Wife)"))
        for note in sub_notes:
            blocks.append(_bullet(note))

    title = f"Grocery List - Week of {week_of}"
    page_id = _create_child_page(client, parent, title, blocks)
    _save_grocery_local(grocery_data)
    print(f"Grocery list pushed to Notion: week of {week_of}")
    return page_id


# ── Notion push: hub weekly toggle ─────────────────────────────────────────────

def push_hub_week(notion_cfg, week_of, meal_pages, grocery_page_id):
    client = _notion()
    hub = _hub_page_id(notion_cfg)

    grocery_bullet = {
        "object": "block",
        "type": "bulleted_list_item",
        "bulleted_list_item": {
            "rich_text": [
                {"type": "mention", "mention": {"type": "page", "page": {"id": grocery_page_id}}},
            ],
        },
    }

    day_bullets = []
    for mp in meal_pages:
        day_bullets.append({
            "object": "block",
            "type": "bulleted_list_item",
            "bulleted_list_item": {
                "rich_text": [
                    {"type": "mention", "mention": {"type": "page", "page": {"id": mp["page_id"]}}},
                ],
            },
        })

    toggle = _toggle_heading(f"Week of {week_of}", [grocery_bullet] + day_bullets)

    anchor = _description_block_id(client, hub)
    if anchor:
        client.blocks.children.append(block_id=hub, children=[toggle], after=anchor)
    else:
        client.blocks.children.append(block_id=hub, children=[toggle])
    print(f"Hub updated: week of {week_of} toggle inserted at top.")


# ── patch_starch ───────────────────────────────────────────────────────────────

def patch_starch(meal_name, new_starch):
    recipes_dir = WIKI_FOOD / "recipes"
    for path in recipes_dir.glob("*.md"):
        text = path.read_text(encoding="utf-8")
        data = _parse_json_block(text)
        if data.get("meal", "").lower() != meal_name.lower():
            continue
        old_starch = data.get("recommended_starch")
        data["recommended_starch"] = new_starch
        new_json = json.dumps(data, indent=2, ensure_ascii=False)
        new_text = re.sub(r"```json\s*\n[\s\S]+?\n```", f"```json\n{new_json}\n```", text, count=1)
        new_text = re.sub(
            r"^recommended_starch:.*$",
            f"recommended_starch: {new_starch if new_starch else 'null'}",
            new_text, flags=re.MULTILINE
        )
        path.write_text(new_text, encoding="utf-8")
        print(f"Updated {meal_name}: '{old_starch}' -> '{new_starch}'")
        return
    print(f"Recipe not found: {meal_name}")


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
    meal_pages = push_plan(plan, data["notion_config"])
    grocery = build_grocery_list(plan, data["pantry"])
    grocery_page_id = push_grocery(grocery, data["notion_config"])
    push_hub_week(data["notion_config"], plan.get("week_of", ""), meal_pages, grocery_page_id)
    save_history(plan)


def cmd_full(args):
    plan = propose_plan(start_date=getattr(args, "date", None))
    _print_plan(plan)
    data = load_data()
    meal_pages = push_plan(plan, data["notion_config"])
    grocery = build_grocery_list(plan, data["pantry"])
    grocery_page_id = push_grocery(grocery, data["notion_config"])
    push_hub_week(data["notion_config"], plan.get("week_of", ""), meal_pages, grocery_page_id)
    save_history(plan)


def cmd_pacing(args):
    data = load_data()
    scores = pacing_scores(data["history"], data["ellsworth_proteins"])
    depleted = data["depleted_proteins"]
    print(f"\nProtein pacing ({len(data['history'])} weeks of history):\n")
    for protein, info in sorted(scores.items(), key=lambda x: x[1]["status"]):
        dep_flag = " [DEPLETED]" if protein in depleted else ""
        status_flag = {"BEHIND": "<<", "AHEAD": ">>", "ON_TRACK": "  "}.get(info["status"], "  ")
        print(f"  {status_flag} {protein:28} {info['status']:10} "
              f"used={info['actual_26w']:2}  expected={info['expected_26w']:4}{dep_flag}")


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

    sub.add_parser("pacing", help="Show protein pacing report")

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
