# Memory Index

- [notion-client v3 data sources](feedback_notion_client_v3_data_sources.md) - schema updates require data_sources.update; databases.update silently drops properties
- [Notion allow_deleting_content danger](feedback_notion_allow_deleting_content.md) - replace_content with that flag archives child DBs/pages to trash; use update_content instead
- [Notion linked DB "Hide database title" is UI-only](feedback_notion_linked_db_title_ui_only.md) - the block-level toggle is not exposed via MCP; renaming the data source renames the SOURCE instead
- [No mid-chat model switches](feedback_no_mid_chat_model_switch.md) - never tell Drew to switch models mid-conversation; invalidates prompt cache and increases cost
- [Notion mobile cache on fresh writes](feedback_notion_mobile_cache.md) - mobile app shows stale empty page after API writes; force-quit fixes it, do not build workarounds
- [REMY Notion topology](project_remy_notion_topology.md) - remy_main_page is user-facing; remy_sources_page is hidden parent of the databases
- [REMY inventory 2026-05-27](project_remy_inventory_2026-05-27.md) - ground beef depleted; avoid until next Ellsworth order
- [REMY bell pepper dedup bug](feedback_remy_bell_pepper_dedup_bug.md) - grocery consolidation under-counts when multiple meals need the same produce item
- [KILO workout publisher](project_kilo.md) - kilo.py + /kilo skill; pushes one workout program from Construct to Notion KILO hub as nested child pages
- [REMY file paths](project_remy_paths.md) - canonical paths: remy.py, recipe DB at `C:\Users\wgriffith2\Dropbox (Liberty University)\Construct\wiki\food\recipes\`, meal history, Construct wiki root
- [Liberty work repo topology](project_liberty_work_repo_topology.md) - Liberty University folder is a workspace (BitBucket PROJECT), never a repo; each project its own clone; ads_etl = ETL code only, no submodule gitlinks; home dir gitignores work folder
