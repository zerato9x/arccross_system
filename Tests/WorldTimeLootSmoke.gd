extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	var loot_catalog := root.get_node("LootCatalog")

	world_state.begin_new_world("WORLD_TIME_LOOT_SMOKE")
	if world_state.world_time_minutes != GameTimeRules.STARTING_WORLD_MINUTES:
		_fail("A new world did not initialize the authoritative clock.")
		return

	var snapshot := world_state.advance_world_time(GameTimeRules.SEARCH_MINUTES)
	if (
		world_state.world_time_minutes
		!= GameTimeRules.STARTING_WORLD_MINUTES + GameTimeRules.SEARCH_MINUTES
	):
		_fail("RuntimeStateStore did not retain elapsed world minutes.")
		return
	if snapshot.get("hour", -1) != 9 or snapshot.get("minute", -1) != 0:
		_fail("World clock snapshot did not translate minutes correctly.")
		return

	var profile: Dictionary = loot_catalog.call(
		"get_profile_descriptor",
		"loot_relay_shelter"
	)
	if profile.is_empty() or profile.get("entries", []).is_empty():
		_fail("The relay shelter loot profile was not loaded.")
		return

	var metrics := {
		"loot": GameEnums.SCALE_MAX,
		"safety": GameEnums.SCALE_MAX,
		"sneak": GameEnums.SCALE_MAX,
	}
	var first := MacroInteractionResolver.resolve_search(
		"WORLD_TIME_LOOT_SMOKE",
		Vector2i(2, -1),
		0,
		metrics,
		profile
	)
	var second := MacroInteractionResolver.resolve_search(
		"WORLD_TIME_LOOT_SMOKE",
		Vector2i(2, -1),
		0,
		metrics,
		profile
	)
	if first.get("loot_ids", []) != second.get("loot_ids", []):
		_fail("Weighted loot resolution was not deterministic.")
		return
	if first.get("loot_ids", []).is_empty():
		_fail("A maximum-loot search produced no profile entries.")
		return

	for item_id in first.get("loot_ids", []):
		if not loot_catalog.call("has_item", item_id):
			_fail("A loot profile emitted an unknown item ID.")
			return
		var item_state: Dictionary = loot_catalog.call(
			"create_runtime_item_state",
			item_id
		)
		if (
			item_state.get("instance_id", "").is_empty()
			or item_state.get("definition", {}).get("id", "") != item_id
		):
			_fail("LootCatalog failed to fabricate a neutral runtime item state.")
			return

	var max_searches := int(profile.get("max_searches", 4))
	var exhausted_metrics := MacroInteractionResolver.calculate_search_metrics(
		metrics,
		[],
		max_searches,
		max_searches
	)
	var exhausted := MacroInteractionResolver.resolve_search(
		"WORLD_TIME_LOOT_SMOKE",
		Vector2i(2, -1),
		max_searches,
		exhausted_metrics,
		profile
	)
	if not exhausted.get("loot_ids", []).is_empty():
		_fail("An exhausted loot profile continued producing items.")
		return

	print(
		"[TEST PASS] Authoritative world time and weighted loot profiles are "
		+ "deterministic, bounded, and data-driven."
	)
	quit(0)

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
