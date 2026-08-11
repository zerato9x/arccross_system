extends SceneTree

const HELMET_PATH := "res://ItemCore/Items/helmet.tres"
const HELMET_2_PATH := "res://ItemCore/Items/helmet_2.tres"
const HELMET_3_PATH := "res://ItemCore/Items/helmet_3.tres"
const BACKPACK_PATH := "res://ItemCore/Items/backpack_service_big.tres"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://CombatCore/WaveMode.tscn") as PackedScene
	var wave_mode := scene.instantiate() as WaveMode
	root.add_child(wave_mode)
	await process_frame
	await process_frame

	if wave_mode.get_node_or_null("%LoadoutSelect") != null:
		_fail("The retired equipment-selector overlay still exists.")
		return
	if wave_mode.get_node_or_null("%DebugSpawner") != null:
		_fail("The retired debug-spawner overlay still exists.")
		return
	for slot_name in WaveMode.SLOT_BUTTON_NAMES.values():
		if wave_mode.get_node_or_null("%" + str(slot_name)) == null:
			_fail("Missing authored paper-doll slot button: %s" % slot_name)
			return

	var invalid := wave_mode.stage_item(
		HELMET_PATH,
		false,
		true,
		GameEnums.EquipmentSlot.FEET
	)
	if bool(invalid.get("ok", false)):
		_fail("Invalid HEAD-to-FEET assignment was silently accepted.")
		return
	var first := wave_mode.stage_item(
		HELMET_PATH,
		false,
		true,
		GameEnums.EquipmentSlot.HEAD
	)
	var replacement := wave_mode.stage_item(
		HELMET_2_PATH,
		false,
		true,
		GameEnums.EquipmentSlot.HEAD
	)
	if not bool(first.get("ok", false)) or not bool(replacement.get("ok", false)):
		_fail("A legal HEAD equipment operation failed.")
		return
	if str(replacement.get("replaced_path", "")) != HELMET_PATH:
		_fail("Equipment replacement did not report the displaced template path.")
		return
	var unequip := wave_mode.unequip_staged_slot(
		false,
		GameEnums.EquipmentSlot.HEAD
	)
	if not bool(unequip.get("ok", false)):
		_fail("UNEQUIP did not move the helmet into legal loose storage.")
		return
	var final_head := wave_mode.stage_item(
		HELMET_3_PATH,
		false,
		true,
		GameEnums.EquipmentSlot.HEAD
	)
	if not bool(final_head.get("ok", false)):
		_fail("The final HEAD item could not be staged.")
		return

	var enemy_inventory := wave_mode.stage_item("bandage", true, false, 0, 3)
	if not bool(enemy_inventory.get("ok", false)):
		_fail("Enemy loose items could not provision legal lab storage.")
		return
	var enemy_state := wave_mode.get_staged_loadout_state(true)
	var enemy_backpack := str(enemy_state.get("backpack_gear", ""))
	if enemy_backpack.is_empty() or not ResourceLoader.exists(enemy_backpack):
		_fail("Enemy worn storage was not explicit in SpawnLoadout state.")
		return
	if bool(enemy_inventory.get("auto_storage", false)) and enemy_backpack != BACKPACK_PATH:
		_fail("Auto-provisioned enemy storage did not serialize its authored backpack path.")
		return
	var player_state := wave_mode.get_staged_loadout_state(false)
	if str(player_state.get("head", "")) != HELMET_3_PATH:
		_fail("The extended HEAD slot was not serialized by SpawnLoadout state.")
		return
	var materialized := SpawnLoadout.from_state(player_state)
	if materialized.head == null or materialized.head.resource_path != HELMET_3_PATH:
		_fail("SpawnLoadout.from_state did not restore the extended HEAD slot.")
		return

	wave_mode.search_edit.text = "helmet"
	wave_mode._on_catalog_filter_changed("helmet")
	if wave_mode.catalog_list.item_count <= 0 or wave_mode.catalog_list.item_count >= wave_mode.get_catalog_item_count():
		_fail("The full authored catalogue search did not filter by resource identity.")
		return

	print(
		"[WAVE_PRECOMBAT_WORKSTATION_SMOKE] PASS // catalog=",
		wave_mode.get_catalog_item_count(),
		" filtered=",
		wave_mode.catalog_list.item_count,
		" head=",
		materialized.head.id,
		" enemy_items=",
		enemy_state.get("starting_items", []).size()
	)
	quit(0)

func _fail(message: String) -> void:
	push_error("[WAVE_PRECOMBAT_WORKSTATION_SMOKE] " + message)
	quit(1)
