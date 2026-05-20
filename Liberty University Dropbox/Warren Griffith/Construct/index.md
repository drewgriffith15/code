# Construct Index

Catalog of all wiki pages. Updated by Claude Code on every ingest, log entry, or query that produces a new page.

Format: `- [[page-path|Title]] — one-line summary`

---

## Technology

### Overview
- [[wiki/technology/overview|Technology Overview]] — current state of the technology domain

### Concepts
- [[wiki/technology/compounding-knowledge-base|Compounding Knowledge Base]] — LLM wiki vs RAG: compile knowledge once, query the result rather than re-deriving on every request
- [[wiki/technology/rag-vs-llm-wiki|RAG vs LLM Wiki]] — side-by-side comparison of the two approaches to LLM-powered knowledge management

### Entities
- [[wiki/technology/entities/andrej-karpathy|Andrej Karpathy]] — AI researcher, author of the LLM Wiki pattern Construct is built on
- [[wiki/technology/entities/obsidian|Obsidian]] — markdown vault tool; visibility layer for Construct
- [[wiki/technology/entities/obsidian-web-clipper|Obsidian Web Clipper]] — Chrome extension; primary ingest tool for articles and YouTube transcripts
- [[wiki/technology/entities/qmd|qmd]] — optional local BM25/vector search engine for markdown files

### Summaries
- [[wiki/technology/summaries/20260512_llm_wiki_karpathy|LLM Wiki (Karpathy)]] — Karpathy's foundational pattern for a persistent, compounding LLM-maintained wiki
- [[wiki/technology/summaries/20260512_build_a_second_brain_that_remembers_everything|Build a Second Brain (Matt Wolfe)]] — Wolfe's implementation walkthrough using Obsidian + Claude Code; key setup and ingest details
- *+83 additional summaries in wiki/technology/summaries/*

---

## Lawn

### Overview
- [[wiki/lawn/overview|Lawn Overview]] — Bermuda lawn care program: products, applications, GreeNe Effect

### Log Index
- [[wiki/lawn/logs/index|Lawn Log Index]] — 56 application records from 2025-02-04 through present

### Product Entities (16)
- [[24_0_6_flagship|24-0-6 Flagship]] — primary summer fertilizer
- [[dimension_2ew|Dimension 2EW]] — pre-emergent herbicide (liquid)
- [[celsius_wg|Celsius WG]] — post-emergent herbicide
- [[atticus_gunner|Atticus Gunner]] — fungicide
- [[atticus_gravex|Atticus Gravex]] — fungicide
- [[atticus_sertay|Atticus Sertay]] — post-emergent herbicide
- [[atticus_talak|Atticus Talak]] — insecticide
- [[atticus_mineiro|Atticus Mineiro]] — insecticide
- [[7_0_0_greene_effect_n_ext|7-0-0 GreeNe Effect]] — N-Ext iron supplement, applied with liquid applications
- [[compaction_cure_0_0_5_n_ext|Compaction Cure 0-0-5]] — N-Ext soil amendment
- [[gallery_75_df|Gallery 75 DF]] — pre-emergent for ornamentals
- [[quinclorac_75_df|Quinclorac 75 DF]] — post-emergent crabgrass control
- *+4 more entities in wiki/lawn/entities/*

### Summaries
- [[wiki/lawn/summaries/20260511_weeds_in_flower_beds_try_liquid_weed_wacker|Weeds in Flower Beds (Liquid Weed Wacker)]] — YouTube summary

---

## Garden

### Overview
- [[wiki/garden/overview|Garden Overview]] — raised bed zone 8b garden: active plants, herbs, activity history

### Log Index
- [[wiki/garden/logs/index|Garden Log Index]] — 16 activity records from 2026-02-14 through present

### Plant Entities (23)
*Vegetables and peppers (current season):*
- [[amish_paste_tomato_amish_paste|Amish Paste Tomato]] — Tub 1 back row
- [[better_boy_tomato_better_boy|Better Boy Tomato]] — Tub 1 back row
- [[bell_pepper_california_wonder|Bell Pepper (California Wonder)]] — Tubs 1-2
- [[jalape_o_pepper_big_guy|Jalapeño Pepper (Big Guy)]] — Tub 3
- [[serrano_chili_pepper_serrano_chili|Serrano Chili Pepper]] — Tub 3
- [[zucchini_black_beauty|Zucchini (Black Beauty)]] — raised bed
- *+5 more pepper/tomato entities in wiki/garden/entities/*

*Herbs and flowers:*
- [[genovese_basil_genovese|Genovese Basil]] — herb
- [[boxwood_basil_boxwood|Boxwood Basil]] — herb
- [[calypso_cilantro_calypso|Calypso Cilantro]] — herb, raised bed
- *+9 more herb/flower entities in wiki/garden/entities/*

### Reference
- [[wiki/garden/20260429_zone_8b_garden_care_reference|Zone 8b Garden Care Reference]] — seasonal care guide for zone 8b
- [[wiki/garden/20260511_ibc_enclosure_build_plan_wood_horizontal_siding|IBC Enclosure Build Plan]] — planned for 2026-05-17

### Summaries
- *36 YouTube summaries in wiki/garden/summaries/*

---

## Food

### Overview
- [[wiki/food/overview|Food Overview]] — 82 recipes, REMY config, Keely dietary constraints

### Log Index
- [[wiki/food/logs/index|Food Log Index]] — 7 entries (meal plans + individual meals)

### Recipes (82)
Stored in wiki/food/recipes/ with date prefix 20260430_. Examples:
- [[wiki/food/recipes/20260430_butter_chicken|Butter Chicken]]
- [[wiki/food/recipes/20260430_creamy_tuscan_chicken|Creamy Tuscan Chicken]]
- [[wiki/food/recipes/20260430_slow_cooker_pot_roast|Slow Cooker Pot Roast]]
- [[wiki/food/recipes/20260430_white_chicken_chili|White Chicken Chili]]
- *+78 more recipes in wiki/food/recipes/*

### REMY Configuration
- [[wiki/food/ellsworth-active-inventory|Ellsworth Active Inventory]] — current protein/ingredient inventory
- [[wiki/food/pantry-staples|Pantry Staples]] — always-on-hand items excluded from grocery list
- [[wiki/food/remy-dietary-constraints-keely|Dietary Constraints (Keely)]] — Keely's restrictions for meal planning
- [[wiki/food/remy-grocery-list-generation-rules|Grocery List Generation Rules]] — REMY rules for generating weekly grocery lists
- [[wiki/food/remy-meal-planning-window-rules|Meal Planning Window Rules]] — planning window and rotation rules
- [[wiki/food/remy-starch-clash-rule|Starch Clash Rule]] — starch conflict avoidance rule
- [[wiki/food/remy-starch-sourcing-rules|Starch Sourcing Rules]] — starch selection priority rules
- [[wiki/food/remy-veggie-add-in-rules|Veggie Add-In Rules]] — vegetable selection rules
- [[wiki/food/remy-ellsworth-inventory-frequency-definitions|Ellsworth Frequency Definitions]] — inventory usage frequency definitions
- [[wiki/food/notion-config|Notion Config]] — REMY Notion integration config
- [[wiki/food/20260503_ellsworth_original_order|Ellsworth Original Order]] — initial Ellsworth order record (2026-05-03)

---

## Health

### Overview
- [[wiki/health/overview|Health Overview]] — illness protocols, supplement stack reference

### Log Index
- [[wiki/health/logs/index|Health Log Index]] — 1 entry

### Reference
- [[wiki/health/20260506_cold_flu_covid_protocol|Cold / Flu / COVID Protocol]] — treatment protocol
- [[wiki/health/20260511_comprehensive_daily_supplement_fitness_protocol|Daily Supplement & Fitness Protocol]] — supplement stack reference

### Summaries
- *51 YouTube summaries in wiki/health/summaries/*

## General

### Overview
- [[wiki/general/overview|General Overview]] — catch-all domain for uncategorized research

### Summaries
- *24 YouTube summaries in wiki/general/summaries/*

## Theology

### Overview
- [[wiki/theology/overview|Theology Overview]] — Bible study lessons, Nehemiah series, prayer requests, research

### Log Index
- [[wiki/theology/logs/index|Theology Log Index]] — 135 lesson entries (2023-present)

### Summaries
- *204 YouTube summaries in wiki/theology/summaries/*

## Workouts

### Overview
- [[wiki/workouts/overview|Workouts Overview]] — Caroline Girvan programs: FUEL, IRON, EPIC series, BEASTMODE

### Programs (reference files, no session logs yet)
- *beastmode: 10 day files in wiki/workouts/summaries/beastmode/*
- *epic_endgame: 50 day files in wiki/workouts/summaries/epic_endgame/*
- *epic_heat: 50 day files in wiki/workouts/summaries/epic_heat/*
- *epic_iii: 50 day files in wiki/workouts/summaries/epic_iii/*
- *fuel: 30 day files in wiki/workouts/summaries/fuel/*
- *iron: 30 day files in wiki/workouts/summaries/iron/*

### Summaries
- [[wiki/workouts/summaries/20250815_how_i_train_calves_like_an_athlete_not_a|How I Train Calves Like An Athlete Not A Bodybuilder]] — Jason and Lauren
- [[wiki/workouts/summaries/20210131_how_to_best_train_the_glutes_rule_of_thirds|How To Best Train The Glutes (Rule Of Thirds)]] — Bret Contreras Glute Guy
- [[wiki/workouts/summaries/20260506_does_training_more_often_actually_make_you_fitter|Does Training More Often Actually Make You Fitter? (11-Week Study)]] — wod-science
- [[wiki/workouts/summaries/20260514_why_bear_grylls_morning_routine_hasn_t_changed_in|Why Bear Grylls' Morning Routine Hasn't Changed in DECADES]] — High Performance
