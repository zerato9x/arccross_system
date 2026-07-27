extends SceneTree

## Smoke: Innawoods paperdoll surfaces on macro inventory, hex inspect, and
## collision sessions.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	if main_scene == null:
		_fail("Could not load game_director.tscn.")
		return
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	if macro_map == null or macro_map.macro_hud == null:
		_fail("Macro world / HUD did not initialize.")
		return

	macro_map.debug_step_player_to(Vector2i(0, 0))
	await process_frame
	macro_map._refresh_world_hud()
	await process_frame

	var inventory_panel := macro_map.macro_hud.get_inventory_corner_panel()
	if inventory_panel == null:
		_fail("Macro inventory corner missing.")
		return
	var preview := inventory_panel.find_child(
		"MacroInventoryPreview",
		true,
		false
	) as MacroInventoryPreview
	if preview == null:
		_fail("MacroInventoryPreview missing under inventory corner.")
		return
	var doll := preview.get_node_or_null("%PaperDollModel") as PaperDollModel
	if doll == null:
		_fail("Always-on inventory paperdoll missing.")
		return
	var gear_list := preview.get_node_or_null("%GearList") as VBoxContainer
	if gear_list == null:
		_fail("Always-on key-gear list missing.")
		return

	var inventory_snapshot := macro_map._build_inventory_snapshot()
	var equipment := PaperDollPresenter.equipment_from_inventory_snapshot(
		inventory_snapshot
	)
	var tiles := PaperDollPresenter.key_gear_tiles(
		equipment,
		inventory_snapshot.get("backpack", [])
	)
	if tiles.is_empty() and not equipment.is_empty():
		_fail("Key-gear tiles empty despite equipped items.")
		return

	if not macro_map.debug_spawn_enemy_near_player(
		GameEnums.Faction.SCAVENGER_CELL,
		1
	):
		_fail("Could not spawn enemy for inspect/collision smoke.")
		return
	await process_frame
	await process_frame

	var enemy: MacroEnemy = null
	for coords in macro_map.active_enemies.keys():
		enemy = macro_map.active_enemies[coords] as MacroEnemy
		if enemy != null:
			break
	if enemy == null:
		_fail("Spawned enemy token missing from active_enemies.")
		return

	var record := macro_map._world_state.get_entity(enemy.entity_id)
	if record == null:
		_fail("Spawned enemy has no EntityRecord.")
		return
	var summary := MacroEntityCollisionResolver.build_opponent_summary(record)
	if not summary.has("appearance"):
		_fail("Opponent summary missing appearance payload.")
		return
	var summary_equipment: Array = summary.get("equipment", [])
	if summary_equipment.is_empty() and summary.get("appearance", {}).is_empty():
		_fail("Opponent summary missing equipment and appearance.")
		return

	macro_map.macro_hud.show_entity_inspect(summary)
	await process_frame
	var inspect := macro_map.macro_hud.get_node_or_null(
		"%MacroEntityInspectCard"
	) as MacroEntityInspectCard
	if inspect == null or not inspect.is_showing():
		_fail("Entity inspect card did not show.")
		return
	macro_map.macro_hud.hide_entity_inspect()

	var hex_descriptor := macro_map._build_hex_descriptor(enemy.current_hex_coords)
	if hex_descriptor.get("entity_inspect", {}).is_empty():
		_fail("Hex descriptor missing entity_inspect payload.")
		return

	var session := MacroEntityCollisionResolver.build_root_session(record)
	session["player"] = {
		"name": "YOU",
		"equipment": equipment,
		"appearance": PaperDollPresenter.appearance_from_equipment(equipment),
	}
	macro_map.macro_hud.open_event(session)
	await process_frame
	await process_frame
	var stage := macro_map.macro_hud.get_exploration_stage()
	if stage == null or not stage.is_open():
		_fail("Collision stage did not open.")
		return
	var face := stage.find_child("OpponentFaceDoll", true, false) as PaperDollModel
	if face == null:
		_fail("Collision opponent paperdoll face missing.")
		return
	var tokens: Array = stage.get("_field_tokens")
	if tokens.size() < 2:
		_fail("Collision field tokens missing (expected player + enemy).")
		return

	stage.close_event(false)
	print("[TEST PASS] PaperdollSurfaceSmoke")
	quit(0)


func _fail(message: String) -> void:
	push_error("[TEST FAIL] PaperdollSurfaceSmoke: " + message)
	quit(1)
