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
	# Create a real wound so treatment exercises the authoritative wound model.
	body.apply_targeted_hit(
		GameEnums.LimbRegion.LEFT_ARM,
		4.0,
		8.0,
		GameEnums.DamageType.SHARP
	)

	var bandage: ItemData = null
	for item in core.inventory.get_all_items():
		if item != null and item.consumable_effect == GameEnums.ConsumableEffect.STOP_BLEEDING:
			bandage = item
			break
	if bandage == null:
		var bandage_definition := load("res://ItemCore/Items/bandage.tres") as ItemData
		if bandage_definition == null:
			_fail("Medical smoke could not load the bandage definition.")
			return
		bandage = bandage_definition.duplicate(true) as ItemData
		bandage.instance_id = "medical_smoke_bandage"
		if not core.inventory.add_to_backpack(bandage):
			_fail("Medical smoke could not place a bandage in the actor inventory.")
			return

	var targets := MacroMedicalResolver.valid_limb_targets(bandage, body)
	if not targets.has(GameEnums.LimbRegion.LEFT_ARM):
		_fail("Bandage should target bleeding left arm.")
		return
	var bleeding_before := body.get_limb_bleeding_rate(GameEnums.LimbRegion.LEFT_ARM)

	var result := MacroMedicalResolver.resolve_apply_to_limb(
		core,
		bandage.instance_id,
		GameEnums.LimbRegion.LEFT_ARM
	)
	if not bool(result.get("success", false)):
		_fail(str(result.get("message", "Medical resolver failed.")))
		return
	if body.get_limb_bleeding_rate(GameEnums.LimbRegion.LEFT_ARM) >= bleeding_before:
		_fail("Bandage should reduce the authoritative bleeding rate.")
		return

	print("[TEST PASS] Macro medical drag resolver.")
	quit(0)

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
