extends SceneTree

const VITAL_LIMB := GameEnums.LimbRegion.UPPER_TORSO
const HIT_DAMAGE := 5.0
const ACTION_MINUTES := 5


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not await _test_live_vital_transition():
		return
	if not await _test_non_vital_destruction():
		return
	if not await _test_detached_hydration_reconciliation():
		return
	if not await _test_macro_world_action_defeat():
		return
	print("VITAL_LIMB_DEATH_TRANSACTION_SMOKE: PASS")
	quit(0)


func _test_live_vital_transition() -> bool:
	var core := _new_core("VitalLiveActor", root)
	if core == null:
		return _fail("Could not construct the live vital-limb fixture.")
	await process_frame
	var died := {"count": 0, "cause": ""}
	var destroyed := {"count": 0}
	core.died.connect(func(cause: String) -> void:
		died["count"] += 1
		died["cause"] = cause
	)
	core.body.limb_destroyed.connect(func(limb: GameEnums.LimbRegion) -> void:
		if limb == VITAL_LIMB:
			destroyed["count"] += 1
	)
	for index in range(4):
		core.body.apply_targeted_hit(
			VITAL_LIMB,
			HIT_DAMAGE,
			0.0,
			GameEnums.DamageType.BLUNT
		)
		if index < 3 and core.is_dead:
			core.free()
			return _fail("Sub-terminal cumulative torso damage killed the actor early.")
	if not core.is_dead or core.current_max_ap != 0:
		core.free()
		return _fail("Destroyed upper torso did not make the live actor terminal.")
	if died["count"] != 1 or died["cause"] != "Circulatory collapse":
		core.free()
		return _fail("Vital destruction did not emit one authoritative death signal.")
	if destroyed["count"] != 1:
		core.free()
		return _fail("Vital limb destruction emitted more than one transition.")
	core.body._rebuild_limb_projection(VITAL_LIMB)
	core.body._rebuild_limb_projection(VITAL_LIMB)
	if died["count"] != 1 or destroyed["count"] != 1:
		core.free()
		return _fail("Rebuilding a destroyed vital projection repeated terminal signals.")
	core.free()
	return true


func _test_non_vital_destruction() -> bool:
	var core := _new_core("NonVitalLiveActor", root)
	if core == null:
		return _fail("Could not construct the non-vital limb fixture.")
	await process_frame
	var destroyed := {"count": 0}
	core.body.limb_destroyed.connect(func(limb: GameEnums.LimbRegion) -> void:
		if limb == GameEnums.LimbRegion.LEFT_ARM:
			destroyed["count"] += 1
	)
	for _index in range(4):
		core.body.apply_targeted_hit(
			GameEnums.LimbRegion.LEFT_ARM,
			HIT_DAMAGE,
			0.0,
			GameEnums.DamageType.BLUNT
		)
	if core.is_dead:
		core.free()
		return _fail("Destroyed arm incorrectly killed the actor.")
	if destroyed["count"] != 1:
		core.free()
		return _fail("Non-vital limb destruction was not a single transition.")
	core.free()
	return true


func _test_detached_hydration_reconciliation() -> bool:
	var source := _new_core("VitalHydrationSource", root)
	if source == null:
		return _fail("Could not construct the vital hydration source.")
	await process_frame
	for _index in range(4):
		source.body.apply_targeted_hit(
			VITAL_LIMB,
			HIT_DAMAGE,
			0.0,
			GameEnums.DamageType.BLUNT
		)
	var record := EntityFactory.humanoid_core_to_record(source, "player")
	record["runtime"]["is_dead"] = false
	record["life_state"] = GameEnums.EntityLifeState.ALIVE
	source.free()
	var restored := EntityFactory.record_to_humanoid_core(
		record,
		null,
		"DetachedVitalHydration"
	)
	if restored == null:
		return _fail("Could not reconstruct the detached vital hydration fixture.")
	if not restored.is_dead or restored.current_max_ap != 0:
		restored.free()
		return _fail("Detached hydration resurrected destroyed vital anatomy.")
	restored.free()
	return true


func _test_macro_world_action_defeat() -> bool:
	var packed := load("res://SystemCore/game_director.tscn") as PackedScene
	var director := packed.instantiate() as GameDirector
	root.add_child(director)
	await process_frame
	await process_frame
	var macro := director.get_node_or_null("MainWorld") as MacroGameManager
	if macro == null or macro.player_token == null:
		return _fail("Macro vital-death fixture did not initialize.")
	var core := macro.player_token.get_humanoid_core()
	for _index in range(3):
		core.body.apply_targeted_hit(
			VITAL_LIMB,
			HIT_DAMAGE,
			0.0,
			GameEnums.DamageType.BLUNT
		)
	if core.is_dead or core.body.get_limb_function(VITAL_LIMB) <= 0.0:
		return _fail("Macro vital-death fixture became terminal before the receipt.")
	var store := macro.get_runtime_state_store()
	if not store.update_player_runtime(
		core.capture_runtime_state().to_dict(),
		macro.player_token.current_hex_coords
	):
		return _fail("Could not seed canonical pre-terminal vital damage.")
	var revision_before := store.player_revision
	var time_before := store.world_time_minutes
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = "vital-hazard"
	request.target_coords = macro.player_token.current_hex_coords
	request.verb_id = "search"
	request.method_id = "hazard"
	request.expected_actor_revision = revision_before
	request.payload["world_time_minutes"] = time_before
	var receipt := macro._world_action_coordinator.resolve_direct_action(
		request,
		ACTION_MINUTES,
		1.0,
		0.0,
		"The hazard caused a terminal injury."
	)
	receipt.mutations.append({
		"type": "biological_hit",
		"limb_region": VITAL_LIMB,
		"damage": HIT_DAMAGE,
		"armor": 0.0,
	})
	var application := macro._commit_world_action_receipt(
		receipt,
		macro.player_token.current_hex_coords
	)
	await process_frame
	if application == null or not application.applied:
		return _fail("Canonical vital world action was rejected: %s" % (
			application.error if application != null else "missing application"
		))
	if store.player_revision != revision_before + 1:
		return _fail("Vital world action did not advance actor revision exactly once.")
	if store.world_time_minutes != time_before + ACTION_MINUTES:
		return _fail("Vital world action did not advance time exactly once.")
	if (
		store.player_record.life_state != GameEnums.EntityLifeState.DEAD
		or not bool(store.player_record.runtime.get("is_dead", false))
	):
		return _fail("Vital world action did not commit canonical player death.")
	if not macro.player_token.get_humanoid_core().is_dead:
		return _fail("Canonical player death was not restored to the live projection.")
	if director.defeat_panel == null or not director.defeat_panel.is_open():
		return _fail("Macro vital death did not open the defeat surface.")
	if macro.visible or macro.is_processing_unhandled_input():
		return _fail("Macro commands remained active after canonical player death.")
	director.free()
	return true


func _new_core(unit_name: String, parent: Node) -> HumanoidCore:
	var definition := preload("res://BiologicalCore/player_def.tres") as EntityDefinition
	return EntityFactory.record_to_humanoid_core({
		"entity_id": "player",
		"definition": definition.to_state(),
		"runtime": {},
	}, parent, unit_name)


func _fail(message: String) -> bool:
	push_error("[VITAL_LIMB_DEATH_TRANSACTION] " + message)
	quit(1)
	return false
