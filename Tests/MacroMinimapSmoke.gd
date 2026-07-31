extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	if not await _verify_standalone_view():
		return
	if not await _verify_world_integration():
		return
	print("[TEST PASS] Full-zone minimap colors, fog, symbols, layout, and selection.")
	quit(0)


func _verify_standalone_view() -> bool:
	var view := MacroMinimapView.new()
	view.size = Vector2(396.0, 142.0)
	root.add_child(view)
	await process_frame
	var cells: Array[Dictionary] = []
	for coords in HexCoordUtils.cells_in_radius(GameEnums.MACRO_ZONE_RADIUS):
		cells.append(_cell(coords))
	var water := cells[0]
	water["water"] = GameEnums.MacroWaterLayer.DEEP_WATER
	water["rock"] = GameEnums.MacroRockLayer.ROCKS
	var rocks := cells[1]
	rocks["rock"] = GameEnums.MacroRockLayer.ROCKS
	rocks["terrain"] = GameEnums.MacroTerrainTile.HUB_CONCRETE
	var concrete := cells[2]
	concrete["terrain"] = GameEnums.MacroTerrainTile.HUB_CONCRETE
	var snow := cells[3]
	snow["terrain"] = GameEnums.MacroTerrainTile.SNOW_TRANSITION
	var mud := cells[4]
	mud["terrain"] = GameEnums.MacroTerrainTile.MUD_YELLOW
	var forest := cells[5]
	forest["flora"] = GameEnums.MacroFloraLayer.TREES
	var unknown := cells[cells.size() - 1]
	unknown["explored"] = false
	unknown["is_poi"] = true
	var hostile_coords: Vector2i = cells[6]["coords"]
	var exit_coords: Vector2i = cells[7]["coords"]
	var explored_dimmed := cells[8]
	explored_dimmed["visible"] = false
	water["is_poi"] = true
	view.set_minimap_snapshot({
		"cells": cells,
		"player_coords": Vector2i.ZERO,
		"selected_coords": concrete["coords"],
		"visible_hostiles": [hostile_coords, unknown["coords"]],
		"exits": [
			{"coords": exit_coords, "direction": GameEnums.MacroTravelDirection.EAST},
			{"coords": unknown["coords"], "direction": GameEnums.MacroTravelDirection.WEST},
		],
	})
	await process_frame
	if view.get_cell_count() != GameEnums.MACRO_ZONE_CELL_COUNT:
		return _fail_bool("Minimap did not retain all 469 zone cells.")
	var host := Rect2(Vector2.ZERO, view.size)
	if not host.encloses(view.get_drawn_bounds()):
		return _fail_bool("Minimap geometry escaped its control bounds.")
	if view.get_cell_color(water["coords"]) != MacroMinimapView.DEEP_WATER_COLOR:
		return _fail_bool("Water did not override rock terrain color.")
	if view.get_cell_color(rocks["coords"]) != MacroMinimapView.ROCKS_COLOR:
		return _fail_bool("Rock did not override concrete terrain color.")
	if view.get_cell_color(concrete["coords"]) != MacroMinimapView.CONCRETE_COLOR:
		return _fail_bool("Concrete minimap color missing.")
	if view.get_cell_color(snow["coords"]) != MacroMinimapView.SNOW_COLOR:
		return _fail_bool("Snow minimap color missing.")
	if view.get_cell_color(mud["coords"]) != MacroMinimapView.MUD_COLOR:
		return _fail_bool("Mud minimap color missing.")
	if view.get_cell_color(forest["coords"]) != MacroMinimapView.FOREST_COLOR:
		return _fail_bool("Forest minimap color missing.")
	if view.get_cell_color(unknown["coords"]) != MacroMinimapView.UNKNOWN_COLOR:
		return _fail_bool("Unknown terrain was not fog-darkened.")
	if view.get_cell_color(explored_dimmed["coords"]) != MacroMinimapView.PLAINS_COLOR.darkened(
		MacroMinimapView.EXPLORED_DARKEN
	):
		return _fail_bool("Explored terrain did not use the dimmed terrain color.")
	if view.has_poi_symbol_at(unknown["coords"]):
		return _fail_bool("Unknown POI leaked through minimap fog.")
	if view.has_hostile_symbol_at(unknown["coords"]):
		return _fail_bool("Hostile symbol leaked through minimap fog.")
	if view.has_exit_symbol_at(unknown["coords"]):
		return _fail_bool("Exit symbol leaked through minimap fog.")
	if not view.has_poi_symbol_at(water["coords"]):
		return _fail_bool("Explored POI symbol missing.")
	if not view.has_hostile_symbol_at(hostile_coords):
		return _fail_bool("Visible hostile symbol missing.")
	if not view.has_exit_symbol_at(exit_coords):
		return _fail_bool("Discovered exit symbol missing.")
	view.queue_free()
	await process_frame
	return true


func _verify_world_integration() -> bool:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame
	await process_frame
	var macro_map := game_director.get_node_or_null("MainWorld") as MacroGameManager
	if macro_map == null or macro_map.macro_hud == null:
		return _fail_bool("Macro world/HUD failed to initialize.")
	var world_status := macro_map.macro_hud.get_node_or_null("%MacroWorldStatusPanel") as MacroWorldStatusPanel
	var minimap := (
		world_status.get_node_or_null("%MacroMinimapView") as MacroMinimapView
		if world_status != null else null
	)
	var ticker := (
		world_status.get_node_or_null("%LatestEventTicker") as Label
		if world_status != null else null
	)
	if minimap == null or ticker == null:
		return _fail_bool("World Signal minimap or latest-event ticker missing.")
	if minimap.get_cell_count() != GameEnums.MACRO_ZONE_CELL_COUNT:
		return _fail_bool("World snapshot did not feed the complete active zone to the minimap.")
	var player_before := macro_map.player_token.current_hex_coords
	var selectable := Vector2i(999999, 999999)
	var unknown := Vector2i(999999, 999999)
	for coords in macro_map.world_generator.world_hex_cache.keys():
		var hex_data: MacroHexData = macro_map.world_generator.world_hex_cache[coords]
		if hex_data.is_explored and coords != player_before and selectable.x == 999999:
			selectable = coords
		elif not hex_data.is_explored and unknown.x == 999999:
			unknown = coords
	if selectable.x == 999999 or unknown.x == 999999:
		return _fail_bool("Test zone did not contain both explored and unknown cells.")
	var selections: Array[Vector2i] = []
	minimap.hex_selected.connect(func(coords: Vector2i): selections.append(coords))
	_send_click(minimap, selectable)
	if selections.is_empty() or selections[-1] != selectable:
		return _fail_bool("Explored minimap click did not emit selection.")
	if macro_map.get("_selected_hex_coords") != selectable:
		return _fail_bool("Minimap selection did not reach MacroGameManager.")
	if macro_map.player_token.current_hex_coords != player_before:
		return _fail_bool("Minimap selection moved the player.")
	var emitted_count := selections.size()
	_send_click(minimap, unknown)
	if selections.size() != emitted_count:
		return _fail_bool("Unknown minimap cell accepted selection.")
	game_director.queue_free()
	await process_frame
	return true


func _cell(coords: Vector2i) -> Dictionary:
	return {
		"coords": coords,
		"terrain": GameEnums.MacroTerrainTile.PLAINS_GRASS,
		"flora": GameEnums.MacroFloraLayer.NONE,
		"rock": GameEnums.MacroRockLayer.NONE,
		"water": GameEnums.MacroWaterLayer.NONE,
		"structure": GameEnums.MacroStructureLayer.NONE,
		"explored": true,
		"visible": true,
		"is_poi": false,
		"has_landmark": false,
		"label": "Test Hex",
	}


func _send_click(view: MacroMinimapView, coords: Vector2i) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = view.get_cell_screen_center(coords)
	view._gui_input(event)


func _fail_bool(message: String) -> bool:
	push_error("[TEST FAIL] " + message)
	quit(1)
	return false
