extends Node2D

## Interactive Generator V2 inspector. Open Tools/generator_v2_preview.tscn.
## It renders composition authority, not a second implementation of generation.

const MAP_CENTER := Vector2(690.0, 430.0)
const HEX_SIZE_FULL := 27.0
const HEX_SIZE_TRUTH := 58.0
const ARM_IDS := ["north", "east", "south", "west"]

@export var start_in_truth_view: bool = false

var seed_value := "NORTH_ROUTE_1_REFERENCE"
var arm_id := "north"
var view_radius := 12
var zone: MacroZoneGenerator
var inspected_coords := Vector2i.ZERO
var toggles := {
	"terrain": true,
	"roads": true,
	"stamps": true,
	"loot": true,
	"hazards": false,
	"npc": true,
	"traces": true,
}
var inspector_label: RichTextLabel
var seed_edit: LineEdit
var arm_select: OptionButton
var radius_select: OptionButton


func _ready() -> void:
	_build_ui()
	regenerate()


func regenerate() -> void:
	seed_value = seed_edit.text.strip_edges() if seed_edit != null else seed_value
	arm_id = ARM_IDS[arm_select.selected] if arm_select != null else arm_id
	view_radius = 3 if radius_select != null and radius_select.selected == 0 else 12
	var graph := MacroGraphGenerator.generate_web(seed_value)
	var node_id := "%s_random_1" % arm_id
	var node := graph.get_node(node_id) as MacroNodeData
	zone = MacroZoneGenerator.new()
	zone.configure_seed(seed_value)
	var arrival := MacroGraphGenerator.arrival_direction_for_start(node_id)
	zone.generate_node_zone(node, arrival, [arrival, HexCoordUtils.opposite_travel_direction(arrival)])
	inspected_coords = zone.starter_settlement_coords
	_refresh_inspector()
	queue_redraw()


func _draw() -> void:
	if zone == null or zone.generated_plan == null:
		return
	var center := zone.starter_settlement_coords if view_radius == 3 else Vector2i.ZERO
	var size := HEX_SIZE_TRUTH if view_radius == 3 else HEX_SIZE_FULL
	for coords in zone.world_hex_cache.keys():
		if HexCoordUtils.distance(coords, center) > view_radius:
			continue
		var hex: MacroHexData = zone.world_hex_cache[coords]
		var pos := MAP_CENTER + _axial_screen(coords - center, size)
		var color := _terrain_color(hex)
		if toggles["stamps"] and hex.stamp_instance_id != "":
			color = Color("#9a7145")
		if toggles["loot"] and hex.composition_role == "rubble_search":
			color = Color("#d29a39")
		draw_colored_polygon(_hex_polygon(pos, size), color)
		draw_polyline(_closed_hex(pos, size), Color(0.09, 0.10, 0.08, 0.50), 1.4, true)
		if toggles["roads"] and hex.road_mask > 0:
			_draw_road(pos, size, hex.road_mask)
		if toggles["hazards"] and hex.hazard_level > 0.0:
			draw_circle(pos, minf(size * 0.30, hex.hazard_level * 2.2), Color(0.75, 0.16, 0.10, 0.42))
		if toggles["npc"] and coords == zone.starter_npc_coords:
			draw_circle(pos, size * 0.17, Color("#63d7e8"))
		if toggles["traces"] and not hex.trace_records.is_empty():
			draw_circle(pos + Vector2(size * 0.26, -size * 0.28), size * 0.09, Color("#e8e4d4"))
		if coords == inspected_coords:
			draw_polyline(_closed_hex(pos, size * 0.88), Color("#ffe36d"), 3.0, true)


func _terrain_color(hex: MacroHexData) -> Color:
	if not toggles["terrain"]:
		return Color("#333633")
	if hex.rock_layer == GameEnums.MacroRockLayer.ROCKS:
		return Color("#63705d")
	if hex.rock_layer == GameEnums.MacroRockLayer.HILLS:
		return Color("#718461")
	if hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
		return Color("#557d4e")
	return Color("#83a765")


func _draw_road(pos: Vector2, size: float, mask: int) -> void:
	for index in range(HexCoordUtils.AXIAL_DIRECTIONS.size()):
		if mask & (1 << index) == 0:
			continue
		var target := pos + _axial_screen(HexCoordUtils.AXIAL_DIRECTIONS[index], size) * 0.52
		draw_line(pos, target, Color("#3d3b37"), maxf(3.0, size * 0.22), true)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if zone == null:
		return
	var center := zone.starter_settlement_coords if view_radius == 3 else Vector2i.ZERO
	var size := HEX_SIZE_TRUTH if view_radius == 3 else HEX_SIZE_FULL
	var best := 999999.0
	for coords in zone.world_hex_cache.keys():
		if HexCoordUtils.distance(coords, center) > view_radius:
			continue
		var distance: float = event.position.distance_to(MAP_CENTER + _axial_screen(Vector2i(coords) - center, size))
		if distance < best:
			best = distance
			inspected_coords = coords
	_refresh_inspector()
	queue_redraw()


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-390, 18)
	panel.size = Vector2(370, 820)
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "HEX WORLD GENERATOR V2"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	seed_edit = LineEdit.new()
	seed_edit.text = seed_value
	seed_edit.placeholder_text = "Seed"
	box.add_child(seed_edit)
	arm_select = OptionButton.new()
	for entry in ARM_IDS:
		arm_select.add_item(entry.capitalize())
	box.add_child(arm_select)
	radius_select = OptionButton.new()
	radius_select.add_item("Radius 3 truth view")
	radius_select.add_item("Radius 12 full zone")
	radius_select.selected = 0 if start_in_truth_view else 1
	box.add_child(radius_select)
	var generate_button := Button.new()
	generate_button.text = "Generate"
	generate_button.pressed.connect(regenerate)
	box.add_child(generate_button)
	for key in toggles.keys():
		var check := CheckButton.new()
		check.text = str(key).capitalize()
		check.button_pressed = bool(toggles[key])
		check.toggled.connect(func(enabled: bool) -> void:
			toggles[key] = enabled
			queue_redraw()
		)
		box.add_child(check)
	var export_button := Button.new()
	export_button.text = "Export screenshot + JSON"
	export_button.pressed.connect(_export_diagnostics)
	box.add_child(export_button)
	inspector_label = RichTextLabel.new()
	inspector_label.custom_minimum_size = Vector2(340, 420)
	inspector_label.fit_content = false
	box.add_child(inspector_label)


func _refresh_inspector() -> void:
	if inspector_label == null or zone == null or zone.generated_plan == null:
		return
	var hex := zone.get_hex_at(inspected_coords)
	var catalog := load("res://Asset/MacroTileCatalog.tres") as MacroTileCatalog
	var terrain_source := catalog.resolve_asset_id(hex.terrain_asset_id) if catalog != null else -1
	inspector_label.text = (
		"[b]Cell %s[/b]\nasset: %s (source %d)\nedges: %s\nrole: %s\nstamp: %s\nroad mask: %02d\nhazard: %.2f\npassable: %s\nloot tier: %s\ntraces: %s\n\n[b]Plan[/b]\n%s"
		% [
			str(inspected_coords), hex.terrain_asset_id, terrain_source,
			str(catalog.edge_signature_for_source(terrain_source) if catalog != null else []),
			hex.composition_role, hex.stamp_instance_id, hex.road_mask,
			hex.hazard_level, str(hex.is_passable()), hex.loot_tier_id,
			str(hex.trace_records), JSON.stringify(zone.generated_plan.diagnostic_report(), "  ")
		]
	)


func _export_diagnostics() -> void:
	if zone == null or zone.generated_plan == null:
		return
	var report_path := "user://generator_v2_preview_report.json"
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(zone.generated_plan.diagnostic_report(), "  "))
		file.close()
	await RenderingServer.frame_post_draw
	var screenshot_path := "user://generator_v2_preview.png"
	get_viewport().get_texture().get_image().save_png(screenshot_path)
	inspector_label.text += "\n\nExported:\n%s\n%s" % [
		ProjectSettings.globalize_path(report_path),
		ProjectSettings.globalize_path(screenshot_path),
	]


func _axial_screen(coords: Vector2i, size: float) -> Vector2:
	return Vector2(
		size * 1.5 * float(coords.x),
		size * sqrt(3.0) * (float(coords.y) + float(coords.x) * 0.5)
	)


func _hex_polygon(center: Vector2, size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(6):
		var angle := deg_to_rad(60.0 * float(index))
		points.append(center + Vector2(cos(angle), sin(angle)) * size)
	return points


func _closed_hex(center: Vector2, size: float) -> PackedVector2Array:
	var points := _hex_polygon(center, size)
	points.append(points[0])
	return points
