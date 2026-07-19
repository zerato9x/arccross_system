extends SceneTree

const _PoiController := preload("res://WorldCore/MacroPoiController.gd")
const _BANNED_COPY := [
	"SLEEP SPOT",
	"CAMP GEAR",
	"TRAP SLOT",
	"TOOL SLOT",
	"STOP REST",
	"OPEN INVENTORY",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	if macro_map == null or macro_map.macro_hud == null:
		_fail("Macro HUD did not initialize.")
		return

	var hud := macro_map.macro_hud
	var health := hud.get_node_or_null("%MacroHealthPanel") as MacroHealthCornerPanel
	var inventory := hud.get_node_or_null("%MacroInventoryPanel") as MacroInventoryCornerPanel
	var hex := hud.get_node_or_null("%MacroHexPanel") as MacroHexCornerPanel
	var world_status := hud.get_node_or_null("%MacroWorldStatusPanel") as MacroWorldStatusPanel
	if health == null:
		_fail("Health corner panel missing.")
		return
	if inventory == null:
		_fail("Inventory corner panel missing.")
		return
	if hex == null:
		_fail("Hex corner panel missing.")
		return
	if world_status == null:
		_fail("World status panel missing.")
		return
	if not world_status.visible:
		_fail("World status panel should remain visible as the fixed anchor.")
		return

	var vp: Vector2 = hud.get_viewport().get_visible_rect().size
	var world_status_rect := world_status.get_global_rect()

	hud.toggle_health_panel()
	await process_frame
	if health.get_node("%PreviewRoot").get_node_or_null("FieldHealthPreview") == null:
		_fail("Health corner is not using the authored FieldHealthHUD preview.")
		return
	if health.get_node("%ExpandedRoot").get_node_or_null("FieldHealthDetail") == null:
		_fail("Health corner is not using the authored FieldHealthHUD detail view.")
		return
	if hud.get_exploration_stage() == null:
		_fail("MacroExplorationStage missing from MacroHudShell.")
		return
	if not health.is_expanded() or hud.get_layout_manager().get_expanded_count() != 1:
		_fail("Health should expand without disturbing the other previews.")
		return
	if not _assert_panel_size(vp, health, "health"):
		return
	if not _assert_rect_inside_viewport(health.get_global_rect(), vp, "health"):
		return

	hud.toggle_inventory_panel()
	await process_frame
	if not health.is_expanded() or inventory.is_expanded():
		_fail("Inventory should open as a modal without expanding its corner preview.")
		return
	if hud.get_layout_manager().get_expanded_count() != 1:
		_fail("Fullscreen inventory must not reserve a second corner inset.")
		return
	if not macro_map.inventory_panel.is_fullscreen():
		_fail("PACK did not open the authored fullscreen inventory route.")
		return
	if not (macro_map.inventory_panel.get_node("%PaperDollPanel") as Control).visible:
		_fail("Fullscreen PACK route hid the Innawoods paper-doll region.")
		return
	if not (macro_map.inventory_panel.get_node("%InspectorPanel") as Control).visible:
		_fail("Fullscreen PACK route hid the persistent item inspector.")
		return
	var authored_slots := macro_map.inventory_panel.get_node("%EquipmentSlots").find_children(
		"*", "InventorySlot", true, false
	)
	if authored_slots.size() != 15:
		_fail("Fullscreen PACK route did not expose all 15 equipment slots.")
		return
	var inventory_layer := macro_map.inventory_panel.get_parent() as CanvasLayer
	if inventory_layer == null or inventory_layer.layer <= hud.layer:
		_fail(
			"Fullscreen inventory did not render above the macro HUD "
			+ "(inventory layer %s, HUD layer %s, parent %s)."
			% [
				str(inventory_layer.layer if inventory_layer else -1),
				str(hud.layer),
				str(macro_map.inventory_panel.get_parent()),
			]
		)
		return
	root.size = Vector2i(2860, 1734)
	await process_frame
	await process_frame
	var ultrawide_vp := Vector2(2860, 1734)
	var inventory_shell := macro_map.inventory_panel.get_node("%InventoryShell") as Control
	if not _assert_rect_inside_viewport(
		inventory_shell.get_global_rect(), ultrawide_vp, "ultrawide inventory shell"
	):
		return
	var paper_width := (macro_map.inventory_panel.get_node("%PaperDollPanel") as Control).size.x
	var items_width := (macro_map.inventory_panel.get_node("%ItemsPanel") as Control).size.x
	var inspector_width := (macro_map.inventory_panel.get_node("%InspectorPanel") as Control).size.x
	if paper_width < 700.0 or items_width < 760.0 or inspector_width < 520.0:
		_fail(
			"2860px inventory did not distribute space across all three regions "
			+ "(paper %.1f, items %.1f, inspector %.1f)."
			% [paper_width, items_width, inspector_width]
		)
		return
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	if inventory.get_node("%PreviewRoot").get_node_or_null("MacroInventoryPreview") == null:
		_fail("Inventory corner is not using MacroInventoryPreview.")
		return
	if hex.get_node("%PreviewRoot").get_node_or_null("MacroHexPreviewPanel") == null:
		_fail("Hex corner is not using MacroHexPreviewPanel as preview.")
		return
	var insets := hud.get_layout_manager().compute_viewport_insets()
	if insets == Rect2i():
		_fail("Viewport insets should be non-zero with expanded panels.")
		return
	if not _rects_close(world_status_rect, world_status.get_global_rect(), 2.0):
		_fail("World status panel shifted while a work surface expanded.")
		return
	macro_map.open_inventory()
	await process_frame
	if macro_map.inventory_panel.is_open():
		_fail("Fullscreen inventory did not close through the shared toggle route.")
		return

	var camera := macro_map.get_node_or_null("Camera2D") as MacroCamera
	if camera == null:
		_fail("Macro camera missing.")
		return

	var poi_coords := Vector2i(4, 0)
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	_ensure_demo_homestead(macro_map, world_state, poi_coords)
	macro_map.debug_teleport_player(poi_coords + Vector2i(-1, 0))
	await process_frame
	macro_map.debug_step_player_to(poi_coords)
	await process_frame
	var poi_hex := macro_map.world_generator.get_hex_at(poi_coords)
	if poi_hex == null or not poi_hex.has_landmark():
		_fail("Demonstration landmark was not present at (4, 0).")
		return
	macro_map.debug_begin_poi_interaction(poi_coords, poi_hex)
	await process_frame
	await process_frame
	if not health.is_expanded() or inventory.is_expanded():
		_fail("Opening exploration disturbed the corner-preview/modal separation.")
		return
	if not _assert_panel_size(vp, health, "health"):
		return
	if not macro_map.exploration_window.is_open():
		_fail("Exploration window did not open on the exploration stage.")
		return
	var exploration_panel := macro_map.exploration_window.get("_panel") as Control
	if exploration_panel == null:
		_fail("Exploration panel missing from the stage work surface.")
		return
	if exploration_panel.get_parent() != macro_map.exploration_window:
		_fail("Exploration panel should remain owned by MacroExplorationWindow.")
		return
	if not _assert_rect_inside_viewport(exploration_panel.get_global_rect(), vp, "stage exploration panel"):
		return

	macro_map.exploration_window.call("_set_mode", GameEnums.PoiAction.CAMP)
	await process_frame
	var drop_row := macro_map.exploration_window.get_node_or_null("%DropRow") as HBoxContainer
	if drop_row == null:
		_fail("Camp/search drop tray missing.")
		return
	if drop_row.get_child_count() != 6:
		_fail("Camp mode should render six compact drop slots in the shared tray.")
		return
	for child in drop_row.get_children():
		if not child is InteractionDropTarget:
			continue
		var target := child as InteractionDropTarget
		if target.custom_minimum_size != HUDAssetLibrary.MACRO_SLOT_SIZE:
			_fail("Drop slot did not use the shared macro slot size.")
			return
		if _contains_banned_copy(target.get_slot_label()):
			_fail("Camp slot label is still code-shaped: " + target.get_slot_label())
			return
	_check_camp_target_copy(poi_hex)

	health.collapse()
	await process_frame
	if health.is_expanded() or inventory.is_expanded():
		_fail("Corner panels did not return to preview state during exploration.")
		return
	if not world_status.visible:
		_fail("World status panel disappeared during work-surface switching.")
		return
	if not macro_map.exploration_window.is_open():
		_fail("Closing health should not dismiss stage exploration.")
		return

	hud.get_layout_manager().collapse_all()
	await process_frame
	print("[TEST PASS] Macro HUD cockpit layout, copy, and exploration stage hosting.")
	quit(0)

func _assert_panel_size(
	viewport_size: Vector2,
	panel: MacroCornerPanel,
	label: String
) -> bool:
	var expected := panel.expanded_size_for_viewport(viewport_size)
	if panel.size.distance_to(expected) > 10.0:
		_fail("%s expanded size mismatch: got %s expected %s." % [
			label,
			str(panel.size),
			str(expected),
		])
		return false
	return true

func _expected_axis(
	viewport_axis: float,
	ratio: float,
	min_axis: float,
	max_axis: float
) -> float:
	var available := maxf(1.0, viewport_axis - MacroCornerPanel.PREVIEW_MARGIN * 2.0)
	var capped_max := available if max_axis <= 0.0 else minf(max_axis, available)
	var capped_min := minf(min_axis, capped_max)
	return clampf(viewport_axis * ratio, capped_min, capped_max)

func _assert_rect_inside_viewport(rect: Rect2, viewport_size: Vector2, label: String) -> bool:
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	if not _rect_inside(rect, viewport_rect, 2.0):
		_fail("%s rect escaped the viewport: %s / %s." % [
			label,
			str(rect),
			str(viewport_rect),
		])
		return false
	return true

func _assert_rect_inside_rect(rect: Rect2, host: Rect2, label: String) -> bool:
	if not _rect_inside(rect, host, 2.0):
		_fail("%s escaped its host: %s / %s." % [
			label,
			str(rect),
			str(host),
		])
		return false
	return true

func _assert_rects_do_not_overlap(a: Rect2, b: Rect2, label: String) -> bool:
	if not a.intersects(b):
		return true
	_fail("%s rects overlap: %s / %s." % [label, str(a), str(b)])
	return false

func _rect_inside(rect: Rect2, host: Rect2, tolerance: float) -> bool:
	return (
		rect.position.x >= host.position.x - tolerance
		and rect.position.y >= host.position.y - tolerance
		and rect.end.x <= host.end.x + tolerance
		and rect.end.y <= host.end.y + tolerance
	)

func _rects_close(a: Rect2, b: Rect2, tolerance: float) -> bool:
	return (
		a.position.distance_to(b.position) <= tolerance
		and a.size.distance_to(b.size) <= tolerance
	)

func _check_camp_target_copy(hex_data: MacroHexData) -> void:
	var targets := _PoiController.build_camp_drop_targets(hex_data)
	for target in targets:
		if not target is Dictionary:
			continue
		var label := str(target.get("label", ""))
		if _contains_banned_copy(label) or label.contains("_"):
			_fail("Camp target label is not player-facing: " + label)
			return

func _contains_banned_copy(value: String) -> bool:
	for banned in _BANNED_COPY:
		if value.contains(banned):
			return true
	return false


func _ensure_demo_homestead(
	macro_map: MacroGameManager,
	world_state: RuntimeStateStore,
	coords: Vector2i = Vector2i(4, 0)
) -> Vector2i:
	var hex := macro_map.world_generator.get_hex_at(coords)
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.water_layer = GameEnums.MacroWaterLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	hex.is_poi = true
	hex.landmark_id = "homestead_b"
	hex.poi_id = "plains_homestead"
	hex.poi_name = "Abandoned Homestead"
	hex.sleep_anchor = "ground"
	macro_map.world_generator.world_hex_cache[coords] = hex
	if world_state != null:
		world_state.set_hex_record(coords, hex.to_state())
	return coords


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
