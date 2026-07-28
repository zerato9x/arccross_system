extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := IdentityCatalog.data()
	if catalog == null:
		return _fail("Identity catalog did not load.")
	var catalog_failures := catalog.validate()
	if not catalog_failures.is_empty():
		return _fail("Identity catalog invalid: %s" % str(catalog_failures))
	if catalog.occupations.size() != 4 or catalog.traits.size() != 4 or catalog.flaws.size() != 4:
		return _fail("Starter catalog must contain four entries per category.")
	if (
		catalog.occupation_selection_count != 1
		or catalog.trait_selection_count != 1
		or catalog.flaw_selection_count != 1
	):
		return _fail("Opening selection limits must remain 1/1/1.")
	if not await _verify_eviction_stage():
		return

	var expected_items := {
		"scavenger": ["res://ItemCore/Items/crowbar.tres"],
		"mechanic": ["res://ItemCore/Items/multitool.tres"],
		"electrician": ["res://ItemCore/Items/flashlight.tres"],
		"field_medic": ["res://ItemCore/Items/medkit.tres", "res://ItemCore/Items/bandage.tres"],
	}
	for occupation_id in expected_items.keys():
		var setup := _setup_for(str(occupation_id), "north_random_1")
		var failures := setup.validate(MacroGraphGenerator.allowed_start_node_ids())
		if not failures.is_empty():
			return _fail("Valid setup was rejected: %s" % str(failures))
		var state := setup.build_definition_state()
		if str(state.get("occupation_id", "")) != occupation_id:
			return _fail("Built definition lost occupation %s." % occupation_id)
		var starting_items: Array = state.get("loadout", {}).get("starting_items", [])
		for item_path in expected_items[occupation_id]:
			if not starting_items.has(item_path):
				return _fail("%s loadout is missing %s." % [occupation_id, item_path])

	var starts := MacroGraphGenerator.allowed_start_node_ids()
	if starts != PackedStringArray([
		"north_random_1", "east_random_1", "south_random_1", "west_random_1"
	]):
		return _fail("Unexpected departure node policy: %s" % str(starts))
	var expected_arrivals := {
		"north_random_1": GameEnums.MacroTravelDirection.SOUTH,
		"east_random_1": GameEnums.MacroTravelDirection.WEST,
		"south_random_1": GameEnums.MacroTravelDirection.NORTH,
		"west_random_1": GameEnums.MacroTravelDirection.EAST,
	}
	for start_id in starts:
		var setup := _setup_for("scavenger", start_id)
		if setup.arrival_direction != int(expected_arrivals[start_id]):
			return _fail("Incorrect inward arrival direction for %s." % start_id)
		if not setup.validate(starts).is_empty():
			return _fail("Valid departure was rejected: %s" % start_id)
	var invalid_arrival := _setup_for("scavenger", "north_random_1")
	invalid_arrival.arrival_direction = GameEnums.MacroTravelDirection.NORTH
	if invalid_arrival.validate(starts).is_empty():
		return _fail("Mismatched arrival direction was accepted.")
	var departure_snapshot := NewRunDepartureSnapshot.build("OPENING_FLOW_SMOKE")
	for node_entry in departure_snapshot.get("nodes", []):
		if (
			node_entry is Dictionary
			and str(node_entry.get("id", "")) == MacroGraphGenerator.CENTRAL_ID
			and bool(node_entry.get("unlocked", true))
		):
			return _fail("Departure map presents locked Central as unlocked.")
	var state_store := RuntimeStateStore.new()
	var setup_state := _setup_for("scavenger", "east_random_1").to_state()
	state_store.begin_new_world("OPENING_FLOW_SMOKE", setup_state)
	if not state_store.has_pending_new_run_setup():
		return _fail("New-run setup was not staged.")
	if str(state_store.run_flags.get("chosen_start_node_id", "")) != "east_random_1":
		return _fail("Run flags lost the chosen start node.")
	if not bool(state_store.run_flags.get("eviction_completed", false)):
		return _fail("Eviction completion was not recorded as run-local state.")
	var consumed := state_store.consume_pending_new_run_setup()
	if state_store.has_pending_new_run_setup():
		return _fail("Pending setup was not consumed atomically.")
	if (
		str(consumed.get("occupation_id", "")) != "scavenger"
		or Array(consumed.get("trait_ids", [])) != ["field_sense"]
		or Array(consumed.get("flaw_ids", [])) != ["light_sleeper"]
	):
		return _fail("Identity IDs did not survive setup staging.")
	print("OpeningFlowDataSmoke PASSED")
	quit(0)


func _verify_eviction_stage() -> bool:
	var flow := load("res://UI/Intro/opening_flow.tres") as OpeningFlowDefinition
	if flow == null:
		_fail("Opening flow resource did not load.")
		return false
	if (
		flow.eviction_background_path.is_empty()
		or not ResourceLoader.exists(flow.eviction_background_path)
		or flow.eviction_npc_portrait_path.is_empty()
		or not ResourceLoader.exists(flow.eviction_npc_portrait_path)
	):
		_fail("Eviction stage is missing its resource-backed art.")
		return false
	if flow.eviction_speaker_name.is_empty() or flow.eviction_dialogue.is_empty():
		_fail("Eviction stage is missing its resource-backed speaker or dialogue.")
		return false

	var packed := load("res://UI/Intro/NewRunIntro.tscn") as PackedScene
	var intro := packed.instantiate() as NewRunIntro
	root.add_child(intro)
	await process_frame
	intro.call("_show_step", NewRunIntro.Step.EVICTION)
	await process_frame
	var panel := intro.get_node("Backdrop/PageMargin/Page/ContentPanel/ContentMargin/EvictionPanel") as Control
	var background := panel.get_node("OfficeBackground") as TextureRect
	var portrait := panel.get_node("ClerkPortrait") as TextureRect
	var dialogue := panel.get_node("DialogueBox/DialogueMargin/Dialogue/DialogueText") as RichTextLabel
	if not panel.visible or background.texture == null or portrait.texture == null:
		intro.queue_free()
		_fail("Illustrated eviction stage did not present its backdrop and clerk.")
		return false
	if not dialogue.text.contains(flow.eviction_dialogue):
		intro.queue_free()
		_fail("Eviction scene did not present the authored base dialogue.")
		return false
	intro.queue_free()
	return true


func _setup_for(occupation_id: String, start_node_id: String) -> NewRunSetup:
	var setup := NewRunSetup.new()
	setup.occupation_id = occupation_id
	setup.trait_ids = PackedStringArray(["field_sense"])
	setup.flaw_ids = PackedStringArray(["light_sleeper"])
	setup.start_node_id = start_node_id
	setup.arrival_direction = MacroGraphGenerator.arrival_direction_for_start(start_node_id)
	return setup


func _fail(message: String) -> void:
	push_error("OpeningFlowDataSmoke: " + message)
	quit(1)
