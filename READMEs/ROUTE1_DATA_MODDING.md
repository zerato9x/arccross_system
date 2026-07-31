# Route 1 Data and Modding Contract

Act 1 is the four-node Route 1 circuit around Central: North, East, South, and West are all accessible, and their inner-ring connections form the core survival loop. Progression beyond the circuit remains locked. East, South, and West each hold one physical relay relic and regional evidence that points back to the North Fringe Relay; installing all three relics there unlocks North Route 2.

Gameplay definitions live in resources, not manager conditionals:

- `WorldCore/route1_landmarks.tres` maps an arm to its POI, landmark visual, loot profile, evidence item, and settlement properties.
- `WorldCore/search_sites.tres` defines every open, tool-locked, keyed, and quest-protected roadside cache. The zone generator assigns these IDs; it does not own their loot or access rules.
- `WorldCore/route_objectives.tres` defines required relic IDs, turn-in POI/fixture, item consumption, completion event, and graph triggers.
- `ItemCore/LootProfiles/loot_route1_*.tres` defines guaranteed first-search evidence and seeded weighted supplies.
- `ItemCore/Knowledge/*.tres` defines persistent Codex text, decode requirements, and run-local discovery triggers.
- `WorldCore/campaign_graph.tres` maps those triggers to revealed details, hidden context, and unlocked nodes.
- `BiologicalCore/survival_balance.tres` owns reserve drain, zero-resource grace periods, crisis damage, and fatal thresholds.
- `WorldCore/npc_roles.tres` owns NPC categories, weighted goals, perception, pursuit, stationary behavior, and visual policy.
- `WorldCore/route1_populations.tres` owns per-arm role groups, counts, factions, statuses, and placement policies deployed around the circuit.
- `ItemCore/npc_loadout_profiles.tres` owns weighted paper-doll slots and carried-item pools for each NPC role.
- `UI/Humanoid/equipment_visuals.tres` maps item IDs to layered equipment art without changing presenter code.
- `WorldCore/npc_plot_deployments.tres` owns conditional one-shot plot actors.
- `WorldCore/dialogue_profiles.tres` owns Ask text and response effects.

## Adding an item

Create an `ItemData` resource anywhere below `ItemCore/Items/`. IDs must be globally unique. Give it one or more `functional_roles`, or rely on the compatible fallback inferred from `item_type`. A physical lore object sets `knowledge_entry_id` to an existing knowledge resource ID.

The catalog loads item and loot-profile folders recursively. `LootCatalog.validate_catalog()` reports duplicate or missing references, absent sprite files, invalid knowledge links, and malformed loot entries. `Tools/Build-StaticItemCatalog.ps1` preserves the four authored Route‑1 evidence resources during a rebuild.

## Adding a landmark or loot profile

Add a `Route1LandmarkDefinition` to `route1_landmarks.tres`, then create its `LootProfile`. Put irreplaceable clues in `guaranteed_entries`; those appear only on the first search. Put supplies, tools, and salvage in weighted `entries`. Search results remain deterministic for world seed, node, hex, search count, and target.

For roadside rubble, add a `SearchSiteDefinition` to `search_sites.tres` and point `loot_profile_id` at the new profile. `requirements` accepts the same keys as other searches, including `any_item_ids`, `any_tags`, and `any_roles`. Set `quest_protected` when NPC salvagers must never claim items from that cache.

## Adding knowledge

The knowledge resource ID should normally match its physical evidence item ID. `decode_requirements` supports:

- `any_capabilities`
- `any_item_tags`
- `all_knowledge_ids`

Codex ownership persists across runs. Trigger application and exact node discovery remain run-local and are recorded in `RuntimeStateStore.run_flags`, so a new character knows the lore but must physically re-establish routes.

## Adding NPC behavior

Assign `npc_role_id` in an `EntityDefinition` or runtime actor request. Each role supplies goal weights; the simulator writes its selected goal and bounded player memory to `runtime.macro_ai`. Memory stores trust, threat, last known player position, and the eight most recent events.

Add or edit equipment variation in `npc_loadout_profiles.tres`. Each slot is a weighted array of `{item_id, weight}` entries; an empty `item_id` is a valid chance to leave a slot bare. Ranged weapon support is derived from the selected weapon's own item data.

Systemic NPCs use `token_visual_mode = "equipment_rig"`. Unique actors may use `token_visual_mode = "static_sprite"` with an 8-column by 11-direction sprite sheet in `token_sprite_path`. This changes presentation only; persistence and AI remain identical.

## Compatibility

This overhaul uses `RuntimeStateStore` version 10 and Meta schema version 2. Incompatible Meta JSON is copied to a versioned `.bak` file before a clean profile is written. Old run slots are rejected rather than partially migrated.
