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
	if health.get_node("%PreviewRoot").get_node_or_null("MacroStatusPanel") == null:
		_fail("Health corner is not using MacroStatusPanel as preview.")
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
	if not health.is_expanded() or not inventory.is_expanded():
		_fail("Opening inventory should keep health open and expand inventory too.")
		return
	if hud.get_layout_manager().get_expanded_count() != 2:
		_fail("Layout manager should allow health and inventory to coexist.")
		return
	if not _assert_panel_size(vp, inventory, "inventory"):
		return
	if not _assert_rect_inside_viewport(inventory.get_global_rect(), vp, "inventory"):
		return
	if not _assert_rects_do_not_overlap(health.get_global_rect(), inventory.get_global_rect(), "health/inventory"):
		return
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

	var camera := macro_map.get_node_or_null("Camera2D") as MacroCamera
	if camera == null:
		_fail("Macro camera missing.")
		return

	var poi_coords := Vector2i(4, 0)
	macro_map.debug_step_player_to(poi_coords)
	await process_frame
	var poi_hex := macro_map.world_generator.get_hex_at(poi_coords)
	if poi_hex == null or not poi_hex.has_landmark():
		_fail("Demonstration landmark was not present at (4, 0).")
		return
	macro_map.debug_begin_poi_interaction(poi_coords, poi_hex)
	await process_frame
	await process_frame
	if not health.is_expanded() or not inventory.is_expanded() or not hex.is_expanded():
		_fail("Opening hex exploration should leave health and inventory open too.")
		return
	if hud.get_layout_manager().get_expanded_count() != 3:
		_fail("Layout manager should allow all three major macro panels to stay open.")
		return
	if not _assert_panel_size(vp, hex, "hex"):
		return
	if not _assert_rect_inside_viewport(hex.get_global_rect(), vp, "hex"):
		return
	if not _assert_rects_do_not_overlap(health.get_global_rect(), hex.get_global_rect(), "health/hex"):
		return
	if not _assert_rects_do_not_overlap(inventory.get_global_rect(), world_status.get_global_rect(), "inventory/world status"):
		return
	if not macro_map.exploration_window.is_open():
		_fail("Hex exploration window did not open inside the expanded host.")
		return
	var exploration_panel := macro_map.exploration_window.get_node_or_null(
		"%ExplorationPanel"
	) as Control
	if exploration_panel == null:
		_fail("Exploration panel missing from the hex work surface.")
		return
	if not _assert_rect_inside_rect(
		exploration_panel.get_global_rect(),
		hex.get_global_rect(),
		"hex exploration panel"
	):
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
	if health.is_expanded() or not inventory.is_expanded() or not hex.is_expanded():
		_fail("Collapsing health should leave inventory and hex exploration open.")
		return
	if not world_status.visible:
		_fail("World status panel disappeared during work-surface switching.")
		return

	hud.get_layout_manager().collapse_all()
	await process_frame
	print("[TEST PASS] Macro HUD cockpit layout, copy, and exploration docking.")
	quit(0)

func _assert_panel_size(
	viewport_size: Vector2,
	panel: MacroCornerPanel,
	label: String
) -> bool:
	var expected := Vector2(
		_expected_axis(
			viewport_size.x,
			panel.expand_width_ratio,
			panel.expanded_min_size.x,
			panel.expanded_max_size.x
		),
		_expected_axis(
			viewport_size.y,
			panel.expand_height_ratio,
			panel.expanded_min_size.y,
			panel.expanded_max_size.y
		)
	)
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

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
