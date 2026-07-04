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
	# Force a bleeding limb for bandage targeting.
	body.limb_trauma[GameEnums.LimbRegion.LEFT_ARM] = GameEnums.TraumaType.BLEEDING

	var bandage: ItemData = null
	for item in core.inventory.items:
		if item != null and item.consumable_effect == GameEnums.ConsumableEffect.STOP_BLEEDING:
			bandage = item
			break
	if bandage == null:
		print("[TEST SKIP] No bandage in starter inventory.")
		quit(0)
		return

	var targets := MacroMedicalResolver.valid_limb_targets(bandage, body)
	if not targets.has(GameEnums.LimbRegion.LEFT_ARM):
		_fail("Bandage should target bleeding left arm.")
		return

	var result := MacroMedicalResolver.resolve_apply_to_limb(
		core,
		bandage.instance_id,
		GameEnums.LimbRegion.LEFT_ARM
	)
	if not bool(result.get("success", false)):
		_fail(str(result.get("message", "Medical resolver failed.")))
		return
	if body.limb_trauma.get(GameEnums.LimbRegion.LEFT_ARM, GameEnums.TraumaType.NONE) != GameEnums.TraumaType.NONE:
		_fail("Bleeding should be cleared after bandage.")
		return

	print("[TEST PASS] Macro medical drag resolver.")
	quit(0)

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
