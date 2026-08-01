extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://SystemCore/game_director.tscn") as PackedScene
	var director := packed.instantiate()
	root.add_child(director)
	await process_frame
	await process_frame
	await process_frame
	var macro := director.get_node_or_null("MainWorld") as MacroGameManager
	if macro == null or macro.macro_hud == null or macro.inventory_panel == null:
		_fail("Macro world work-surface dependencies did not initialize.")
		return

	macro.open_hex_world_map()
	var overlay := macro.macro_hud.get_node_or_null(
		"Root/MacroHexWorldMapOverlay"
	) as MacroHexWorldMapOverlay
	if overlay == null or not overlay.is_open():
		_fail("Fullscreen Hex World map did not open.")
		return
	var map_view := overlay.get_node_or_null(
		"Shell/Margin/Column/Body/MapFrame/MapView"
	) as MacroMinimapView
	if map_view == null or map_view.get_cell_count() != GameEnums.MACRO_ZONE_CELL_COUNT:
		_fail("Fullscreen Hex World map did not receive all 469 cells.")
		return
	if macro.is_node_map_open():
		_fail("Opening the Hex World map also opened the separate Node Map.")
		return

	var selected_before: Vector2i = macro.get("_selected_hex_coords")
	macro.call("_select_hex_for_hud", selected_before + Vector2i(1, 0))
	if macro.get("_selected_hex_coords") != selected_before:
		_fail("World selection changed while the Hex World map owned input.")
		return

	macro.open_inventory()
	if overlay.is_open() or not macro.inventory_panel.is_open():
		_fail("Inventory did not replace the Hex World map as the primary surface.")
		return
	if macro.get_active_work_surface() != MacroGameManager.WorkSurface.INVENTORY:
		_fail("Inventory was not reported as the active work surface.")
		return
	if macro.inventory_panel.mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail("Fullscreen inventory does not stop mouse input at its root.")
		return

	var camera := macro.get_node_or_null("Camera2D") as MacroCamera
	var zoom_before: float = camera.get("_desired_zoom")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	camera._unhandled_input(wheel)
	if not is_equal_approx(zoom_before, float(camera.get("_desired_zoom"))):
		_fail("World camera zoom changed behind fullscreen inventory.")
		return

	macro.call(
		"_close_ordinary_work_surfaces",
		MacroGameManager.WorkSurface.SETTINGS
	)
	macro.macro_hud.open_settings()
	if macro.inventory_panel.is_open():
		_fail("Settings stacked on top of fullscreen inventory.")
		return
	if macro.get_active_work_surface() != MacroGameManager.WorkSurface.SETTINGS:
		_fail("Settings was not reported as the active work surface.")
		return

	macro.macro_hud.close_settings()
	var compact_target := selected_before + Vector2i(1, 0)
	macro.call("_select_hex_for_hud", compact_target)
	if macro.get("_selected_hex_coords") != compact_target:
		_fail("Compact HUD state incorrectly blocked ordinary world selection.")
		return

	macro.open_node_map()
	if not macro.is_node_map_open() or macro.macro_hud.is_hex_world_map_open():
		_fail("Node Map and Hex World map were not kept as separate surfaces.")
		return
	print("[TEST PASS] Macro work-surface ownership and fullscreen Hex World map.")
	director.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
