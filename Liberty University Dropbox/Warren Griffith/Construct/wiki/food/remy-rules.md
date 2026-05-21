---
domain: food
type: knowledge
date: 2026-05-20
updated: 2026-05-20
tags: [remy-rules]
---

# REMY Rules

## Planning Window

Weekly meal planning covers 5 dinners: Monday through Friday.

3-week no-repeat window: never suggest a meal that appeared in the last 3 confirmed weeks (15 meals).

Protein pacing: track 26-week cumulative meal count per protein vs. expected frequency. Deprioritize proteins pacing ahead of schedule; prioritize proteins pacing behind.

## Ellsworth Frequency Targets

Ellsworth is a 6-month food delivery service providing frozen proteins and vegetables. Each item has a target frequency that drives protein pacing:

- Once a week = 19.5x per 26 weeks
- Twice a month = 9.75x per 26 weeks
- Once a month = 6.5x per 26 weeks
- Twice every 6 months = 3.25x per 26 weeks

## Starch Clash Rule

NEVER violate: Do not pair Corn with Potatoes (Yellow, Red, Russet, or Sweet) in the same meal.

- If the main dish contains potatoes, the side must not be corn.
- If the side is corn, the main dish must not contain potatoes.

## Starch Sourcing

Starch is always driven by `recommended_starch` on the recipe - never assign ad hoc.

- Jasmine Rice / Brown Rice: weekly staple, always purchased. No grocery list action needed.
- Yellow / Red / Sweet Potatoes: NOT Ellsworth, NOT pantry. Add to Produce on grocery list.
- Russet Potatoes: NOT Ellsworth, NOT pantry. Add to Produce. Only appears on meatloaf-style dishes.
- Gluten-Free Pasta: NOT a staple. Add to Pantry & Dry Goods with GF substitution note for Keely.
- null: no action - starch is already in the dish or it is self-contained.

## Veggie Add-ins

Some recipes have a `veggie_addins` list (e.g., Egg Roll in a Bowl, Mongolian Beef). When planning one of these meals:

- Randomly pick one veggie from the list.
- Mention it as a cook-in addition on the meal plan.
- All veggie add-ins are Ellsworth freezer items - add to "Thaw from freezer" note, NOT the grocery list.

## Dietary Constraints (Keely)

Keely's dietary restrictions apply to all shared family meals:

- Gluten-free: substitute flour with King Arthur GF 1:1 Flour Replacement.
- Dairy-sensitive: no liquid dairy in shared meals (milk, cream, cheese). Butter in cooking is fine.
- Almond-allergic: no almond products at all.

Drew and kids eat standard. Flag gluten-containing ingredients and liquid dairy on the grocery list with substitution notes for Keely.

## Grocery List Generation

1. Collect all ingredients from all 5 recipes.
2. Remove anything that is an Ellsworth freezer item (proteins and vegetables) - note as "Thaw from freezer".
3. Remove anything in pantry `always_on_hand` (assumed stocked).
4. Always add the full `weekly_staples` list - non-negotiable. Tag each with [Staple].
5. Add starch per sourcing rules above.
6. Flag gluten-containing ingredients and liquid dairy with Keely substitution notes.
7. Categorize by store aisle: Produce, Meat & Seafood, Dairy & Refrigerated, Frozen, Bakery & Deli, Pantry & Dry Goods, Oils & Spices.
