extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://CombatCore/WaveMode.tscn") as PackedScene
	if scene == null:
		_fail("WaveMode scene did not load.")
		return
	var wave_mode := scene.instantiate() as WaveMode
	root.add_child(wave_mode)
	await process_frame
	await process_frame

	if not wave_mode.precombat_screen.visible:
		_fail("WaveMode skipped the unified pre-combat workstation.")
		return
	if wave_mode.get_current_arena() != null:
		_fail("WaveMode spawned combat before START WAVE.")
		return
	if wave_mode.get_catalog_item_count() < 150:
		_fail("The workstation did not expose the complete authored catalogue.")
		return
	if wave_mode.get_node_or_null("%DebugSpawner") != null:
		_fail("The obsolete debug-spawner overlay still exists.")
		return
	if wave_mode.combat_hud.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("The Wave combat overlay still blocks TacticalCombatHUD mouse input.")
		return

	var auto_supply := wave_mode.stage_item(
		"carbon_pistol",
		false,
		true,
		GameEnums.EquipmentSlot.HAND
	)
	if not bool(auto_supply.get("ok", false)):
		_fail("A firearm could not be staged for automatic ammunition provisioning.")
		return
	var supply_result: Dictionary = auto_supply.get("auto_supplies", {})
	if not str(supply_result.get("source", "")).ends_with("arcborn_loadout.tres"):
		_fail("Carbon-pistol ammunition did not come from the authored loadout preset.")
		return
	var supplied_state := wave_mode.get_staged_loadout_state(false)
	var supplied_items: Array = supplied_state.get("starting_items", [])
	if supplied_items.count("res://ItemCore/Items/pistol_round.tres") < 16:
		_fail("The authored carbon-pistol round count was not auto-provisioned.")
		return
	if not supplied_items.has("res://ItemCore/Items/carbon_pistol_magazine.tres"):
		_fail("The authored carbon-pistol magazine was not auto-provisioned.")
		return

	var requests := [
		wave_mode.stage_item(
			"service_pistol",
			false,
			true,
			GameEnums.EquipmentSlot.HAND
		),
		wave_mode.stage_item(
			"armor_service",
			false,
			true,
			GameEnums.EquipmentSlot.OUTER_TORSO
		),
		wave_mode.stage_item("bandage", false, false, 0, 2),
		wave_mode.stage_item(
			"knife_service",
			true,
			true,
			GameEnums.EquipmentSlot.HAND
		),
		wave_mode.stage_item("bandage", true, false, 0, 2),
	]
	for request in requests:
		if not bool(request.get("ok", false)):
			_fail("A legal staging request failed: %s" % request)
			return
	var validation := wave_mode.get_staging_validation()
	if not bool(validation.get("valid", false)):
		_fail("Legal staged loadouts were rejected: %s" % validation)
		return

	wave_mode.start_staged_run()
	await process_frame
	await process_frame
	await process_frame

	var arena := wave_mode.get_current_arena()
	if arena == null:
		_fail("WaveMode did not create a combat arena.")
		return
	if wave_mode.precombat_screen.visible or not wave_mode.combat_hud.visible:
		_fail("The setup workstation did not disappear for combat.")
		return
	if arena.enemy_core == null or arena.player_core == null:
		_fail("The normal entity initialization pipeline did not create both combatants.")
		return
	var player_weapon: ItemData = arena.player_core.inventory.paper_doll.get(
		GameEnums.EquipmentSlot.HAND
	)
	var player_armor: ItemData = arena.player_core.inventory.paper_doll.get(
		GameEnums.EquipmentSlot.OUTER_TORSO
	)
	var enemy_weapon: ItemData = arena.enemy_core.inventory.paper_doll.get(
		GameEnums.EquipmentSlot.HAND
	)
	if player_weapon == null or player_weapon.id != "service_pistol":
		_fail("The staged player weapon did not materialize in HAND.")
		return
	if player_armor == null or player_armor.id != "armor_service":
		_fail("The staged player armor did not materialize on the paper doll.")
		return
	if enemy_weapon == null or enemy_weapon.id != "knife_service":
		_fail("The staged enemy weapon did not reach combat presentation state.")
		return
	if not arena.player_core.inventory.backpack_array.any(
		func(item: ItemData) -> bool: return item.id == "bandage"
	):
		_fail("Player loose inventory did not materialize at combat start.")
		return
	var service_magazine: ItemData = null
	for carried_item in arena.player_core.inventory.backpack_array:
		if carried_item.id == "service_pistol_magazine":
			service_magazine = carried_item
			break
	if service_magazine == null or service_magazine.loaded_rounds != 8:
		_fail("The automatically staged service-pistol magazine was not loaded.")
		return
	if not arena.enemy_core.inventory.backpack_array.any(
		func(item: ItemData) -> bool: return item.id == "bandage"
	):
		_fail("Enemy loose inventory did not materialize at combat start.")
		return
	if arena.enemy_core.inventory.paper_doll.get(
		GameEnums.EquipmentSlot.BACKPACK
	) == null:
		_fail("Enemy loose items did not receive legal auto-provisioned storage.")
		return

	print(
		"[WAVE_MODE_SMOKE] PASS // catalog=",
		wave_mode.get_catalog_item_count(),
		" player_weapon=",
		player_weapon.id,
		" enemy_weapon=",
		enemy_weapon.id
	)
	quit(0)

func _fail(message: String) -> void:
	push_error("[WAVE_MODE_SMOKE] " + message)
	quit(1)
