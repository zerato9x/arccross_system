extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loot_catalog := root.get_node_or_null("LootCatalog")
	var knowledge_catalog := root.get_node_or_null("KnowledgeCatalog")
	if loot_catalog == null or knowledge_catalog == null:
		_fail("Required data catalogs did not autoload.")
		return
	var validation: PackedStringArray = loot_catalog.validate_catalog()
	if not validation.is_empty():
		_fail("Catalog validation failed: " + "; ".join(validation))
		return

	var landmarks := Route1LandmarkCatalog.data()
	if landmarks == null or landmarks.landmarks.size() != 4:
		_fail("Route 1 does not define exactly four signature landmarks.")
		return
	var evidence_ids: PackedStringArray = []
	for landmark in landmarks.landmarks:
		if landmark == null or landmark.arm_id.is_empty() or landmark.poi_id.is_empty():
			_fail("A Route 1 landmark is incomplete.")
			return
		var profile: Dictionary = loot_catalog.get_profile_descriptor(landmark.loot_profile_id)
		if profile.is_empty():
			_fail("Missing landmark loot profile: " + landmark.loot_profile_id)
			return
		var guaranteed: Array = profile.get("guaranteed_entries", [])
		if guaranteed.size() != 1 or str(guaranteed[0].get("item_id", "")) != landmark.evidence_item_id:
			_fail("Landmark evidence is not its deterministic first-search result.")
			return
		if not knowledge_catalog.has_entry(landmark.evidence_item_id):
			_fail("Evidence has no matching knowledge entry: " + landmark.evidence_item_id)
			return
		evidence_ids.append(landmark.evidence_item_id)
		var search := MacroInteractionResolver.resolve_search(
			"ROUTE1_OVERHAUL_SMOKE",
			Vector2i(1, -1),
			0,
			{"loot": 8.0, "safety": 8.0, "sneak": 8.0},
			profile,
			landmark.poi_id
		)
		if not search.get("loot_ids", []).has(landmark.evidence_item_id):
			_fail("First search omitted signature evidence: " + landmark.evidence_item_id)
			return

	if not evidence_ids.has("north_relay_ledger"):
		_fail("North relay objective evidence is missing.")
		return
	var balance := load("res://BiologicalCore/survival_balance.tres") as SurvivalBalance
	if balance == null or not balance.validate():
		_fail("Survival balance is absent or invalid.")
		return
	print("[TEST PASS] Route 1 landmarks, evidence, loot, catalog roles, and survival data are valid.")
	quit(0)


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
