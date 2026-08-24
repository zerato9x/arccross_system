extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	if macro_map == null or macro_map.player_token == null:
		_fail("Macro world did not initialize.")
		return

	var core := macro_map.player_token.get_humanoid_core()
	var body := core.body
	# Seed the real projection, then commit it so the shipping treatment path
	# must resolve from canonical state rather than this live object.
	body.apply_targeted_hit(
		GameEnums.LimbRegion.LEFT_ARM,
		4.0,
		8.0,
		GameEnums.DamageType.SHARP
	)

	var bandage_definition := load("res://ItemCore/Items/bandage.tres") as ItemData
	if bandage_definition == null:
		_fail("Medical smoke could not load the bandage definition.")
		return
	var bandage := bandage_definition.create_runtime_instance()
	bandage.instance_id = "medical_smoke_bandage"
	bandage.stack_count = 2
	if not core.inventory.add_to_backpack(bandage):
		_fail("Medical smoke could not place a bandage in the actor inventory.")
		return
	if not macro_map._world_state.update_player_runtime(
		core.capture_runtime_state().to_dict(),
		macro_map.player_token.current_hex_coords
	):
		_fail("Medical smoke could not seed canonical wound and inventory state.")
		return

	var targets := MacroMedicalResolver.valid_limb_targets(bandage, body)
	if not targets.has(GameEnums.LimbRegion.LEFT_ARM):
		_fail("Bandage should target bleeding left arm.")
		return
	var bleeding_before := body.get_limb_bleeding_rate(GameEnums.LimbRegion.LEFT_ARM)
	var stack_before := bandage.stack_count
	var validation := MacroMedicalResolver.validate_apply_to_limb(
		core,
		bandage.instance_id,
		GameEnums.LimbRegion.LEFT_ARM
	)
	if not bool(validation.get("valid", false)):
		_fail(str(validation.get("message", "Medical validator failed.")))
		return
	if (
		body.get_limb_bleeding_rate(GameEnums.LimbRegion.LEFT_ARM) != bleeding_before
		or bandage.stack_count != stack_before
	):
		_fail("Medical validation mutated the live actor.")
		return

	var time_before := macro_map._world_state.world_time_minutes
	var revision_before := macro_map._world_state.player_record.revision
	macro_map._on_medical_action_requested(
		bandage.instance_id,
		GameEnums.LimbRegion.LEFT_ARM
	)
	var projected_core := macro_map.player_token.get_humanoid_core()
	if projected_core.body.get_limb_bleeding_rate(GameEnums.LimbRegion.LEFT_ARM) >= bleeding_before:
		_fail("Shipping medical handler did not improve the live wound projection.")
		return
	var projected_bandage := projected_core.inventory.find_item_by_instance_id(
		bandage.instance_id
	)
	if projected_bandage == null or projected_bandage.stack_count != stack_before - 1:
		_fail("Shipping medical handler did not consume exactly one live item unit.")
		return
	var stored_core := EntityFactory.record_to_humanoid_core(
		macro_map._world_state.player_record.to_dict(),
		null,
		"MacroMedicalStoredProjection"
	)
	if stored_core == null:
		_fail("Medical smoke could not reconstruct canonical player state.")
		return
	var stored_bandage := stored_core.inventory.find_item_by_instance_id(
		bandage.instance_id
	)
	if (
		stored_core.body.get_limb_bleeding_rate(GameEnums.LimbRegion.LEFT_ARM)
		!= projected_core.body.get_limb_bleeding_rate(GameEnums.LimbRegion.LEFT_ARM)
		or stored_bandage == null
		or stored_bandage.stack_count != projected_bandage.stack_count
	):
		stored_core.free()
		_fail("Live and canonical medical projections diverged after commit.")
		return
	stored_core.free()
	if (
		macro_map._world_state.world_time_minutes
		!= time_before + macro_map._time_rules_service.action_minutes("action")
	):
		_fail("Shipping medical action did not advance world time exactly once.")
		return
	if macro_map._world_state.player_record.revision != revision_before + 1:
		_fail("Shipping medical action did not advance actor revision exactly once.")
		return

	var time_after_success := macro_map._world_state.world_time_minutes
	var revision_after_success := macro_map._world_state.player_record.revision
	var runtime_after_success := macro_map._world_state.player_record.runtime.duplicate(true)
	macro_map._on_medical_action_requested(
		bandage.instance_id,
		GameEnums.LimbRegion.RIGHT_ARM
	)
	if (
		macro_map._world_state.world_time_minutes != time_after_success
		or macro_map._world_state.player_record.revision != revision_after_success
		or macro_map._world_state.player_record.runtime != runtime_after_success
	):
		_fail("Invalid medical request mutated canonical state.")
		return

	print("[TEST PASS] Macro medical transaction shipping path.")
	quit(0)

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
