extends Control
class_name CombatBodyTargetView

signal region_selected(region: int)

const PAPER_DOLL_SCENE := PresentationSceneRegistry.PAPER_DOLL_SCENE
const DISPLAY_REGIONS := [
	{"label": "HEAD", "region": GameEnums.LimbRegion.HEAD, "side": "left", "y": 38.0},
	{"label": "TORSO", "region": GameEnums.LimbRegion.UPPER_TORSO, "paired": GameEnums.LimbRegion.LOWER_TORSO, "side": "right", "y": 78.0},
	{"label": "LEFT ARM", "region": GameEnums.LimbRegion.LEFT_ARM, "side": "left", "y": 128.0},
	{"label": "RIGHT ARM", "region": GameEnums.LimbRegion.RIGHT_ARM, "side": "right", "y": 168.0},
	{"label": "LEFT LEG", "region": GameEnums.LimbRegion.LEFT_LEG, "side": "left", "y": 238.0},
	{"label": "RIGHT LEG", "region": GameEnums.LimbRegion.RIGHT_LEG, "side": "right", "y": 278.0},
]
const DOLL_ANCHORS := {
	GameEnums.LimbRegion.HEAD: Vector2(0.50, 0.18),
	GameEnums.LimbRegion.UPPER_TORSO: Vector2(0.50, 0.36),
	GameEnums.LimbRegion.LOWER_TORSO: Vector2(0.50, 0.51),
	GameEnums.LimbRegion.LEFT_ARM: Vector2(0.34, 0.42),
	GameEnums.LimbRegion.RIGHT_ARM: Vector2(0.66, 0.42),
	GameEnums.LimbRegion.LEFT_LEG: Vector2(0.43, 0.72),
	GameEnums.LimbRegion.RIGHT_LEG: Vector2(0.57, 0.72),
}

var selectable := false
var selected_region := -1
var actor_snapshot: Dictionary = {}
var _paper_doll: PaperDollModel
var _region_rects: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_paper_doll = PresentationSceneRegistry.instantiate_scene(PAPER_DOLL_SCENE) as PaperDollModel
	_paper_doll.custom_minimum_size = Vector2.ZERO
	_paper_doll.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_paper_doll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_paper_doll)
	gui_input.connect(_on_gui_input)
	resized.connect(_layout)
	_layout()


func set_actor_snapshot(value: Dictionary) -> void:
	actor_snapshot = value.duplicate(true)
	if is_instance_valid(_paper_doll):
		var equipment: Array = []
		for descriptor in actor_snapshot.get("equipment", actor_snapshot.get("items", [])):
			if not descriptor is Dictionary:
				continue
			if int(descriptor.get("equipment_slot", GameEnums.EquipmentSlot.NONE)) != GameEnums.EquipmentSlot.NONE:
				equipment.append(descriptor)
		_paper_doll.update_model(equipment)
	queue_redraw()


func set_selectable(value: bool) -> void:
	selectable = value
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if value else Control.CURSOR_ARROW
	if value:
		grab_focus()
	queue_redraw()


func clear_selection() -> void:
	selected_region = -1
	queue_redraw()


func _layout() -> void:
	if not is_instance_valid(_paper_doll):
		return
	var doll_width := clampf(size.x * 0.38, 108.0, 132.0)
	_paper_doll.position = Vector2((size.x - doll_width) * 0.5, 8.0)
	_paper_doll.size = Vector2(doll_width, maxf(180.0, size.y - 16.0))
	queue_redraw()


func _draw() -> void:
	_region_rects.clear()
	var functions: Dictionary = actor_snapshot.get("region_function", {})
	var qualitative_only := bool(actor_snapshot.get("qualitative_only", false))
	var scale_y := size.y / 330.0
	for entry in DISPLAY_REGIONS:
		var region := int(entry.region)
		var function := _function_value(functions, entry)
		var function_band := _function_band(functions, entry)
		var ratio := _band_ratio(function_band) if qualitative_only else clampf(function / GameEnums.SCALE_MAX, 0.0, 1.0)
		var color := _function_color(ratio)
		var row_width := clampf(size.x * 0.29, 76.0, 98.0)
		var x := 5.0 if str(entry.side) == "left" else size.x - row_width - 5.0
		var y := float(entry.y) * scale_y
		var rect := Rect2(Vector2(x, y), Vector2(row_width, 31.0))
		_region_rects[region] = rect
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(0.0, 10.0), str(entry.label), HORIZONTAL_ALIGNMENT_LEFT, row_width, 10, Color("cbd2cf"))
		var bar_rect := Rect2(rect.position + Vector2(0.0, 15.0), Vector2(row_width, 10.0))
		draw_rect(bar_rect, Color("171d20"), true)
		draw_rect(Rect2(bar_rect.position + Vector2.ONE, Vector2((bar_rect.size.x - 2.0) * ratio, 8.0)), color, true)
		var selected := region == selected_region or int(entry.get("paired", -1)) == selected_region
		draw_rect(bar_rect, Color("f2d37c") if selected else Color("65716e"), false, 1.5)
		var condition_text := function_band.to_upper() if qualitative_only else "%d/12" % roundi(function)
		if _region_has_wound(region, int(entry.get("paired", -1))):
			condition_text += "  // WOUND"
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(0.0, 30.0), condition_text, HORIZONTAL_ALIGNMENT_LEFT, row_width, 9, color)


func _on_gui_input(event: InputEvent) -> void:
	if not selectable:
		return
	if event is InputEventKey and event.pressed:
		var regions: Array[int] = []
		for entry in DISPLAY_REGIONS:
			regions.append(int(entry.region))
		if event.is_action("ui_left") or event.is_action("ui_up"):
			var previous := regions.find(selected_region)
			selected_region = regions[posmod(previous - 1, regions.size())]
			queue_redraw()
			accept_event()
		elif event.is_action("ui_right") or event.is_action("ui_down"):
			var next := regions.find(selected_region)
			selected_region = regions[posmod(next + 1, regions.size())]
			queue_redraw()
			accept_event()
		elif event.is_action("ui_accept"):
			if selected_region < 0:
				selected_region = GameEnums.LimbRegion.UPPER_TORSO
			region_selected.emit(selected_region)
			accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for region in _region_rects:
			if (_region_rects[region] as Rect2).has_point(event.position):
				selected_region = int(region)
				queue_redraw()
				region_selected.emit(selected_region)
				accept_event()
				return
		var doll_rect := Rect2(_paper_doll.position, _paper_doll.size)
		if doll_rect.has_point(event.position):
			var normalized_point: Vector2 = (event.position - doll_rect.position) / doll_rect.size
			var nearest := -1
			var nearest_distance := INF
			for region in DOLL_ANCHORS:
				var distance: float = normalized_point.distance_to(DOLL_ANCHORS[region])
				if distance < nearest_distance:
					nearest = int(region)
					nearest_distance = distance
			if nearest >= 0 and nearest_distance <= 0.18:
				selected_region = nearest
				queue_redraw()
				region_selected.emit(selected_region)
				accept_event()


func _function_value(functions: Dictionary, entry: Dictionary) -> float:
	var region := int(entry.region)
	var key := str(GameEnums.LimbRegion.keys()[region]).to_lower()
	var raw_value: Variant = functions.get(key, functions.get(region, GameEnums.SCALE_MAX))
	var value := _band_value(str(raw_value)) if raw_value is String else float(raw_value)
	var paired := int(entry.get("paired", -1))
	if paired >= 0:
		var paired_key := str(GameEnums.LimbRegion.keys()[paired]).to_lower()
		var raw_paired: Variant = functions.get(paired_key, functions.get(paired, GameEnums.SCALE_MAX))
		var paired_value := _band_value(str(raw_paired)) if raw_paired is String else float(raw_paired)
		value = minf(value, paired_value)
	return value


func _function_band(functions: Dictionary, entry: Dictionary) -> String:
	var region := int(entry.region)
	var key := str(GameEnums.LimbRegion.keys()[region]).to_lower()
	var raw_value: Variant = functions.get(key, functions.get(region, GameEnums.SCALE_MAX))
	var band := _raw_function_band(raw_value)
	var paired := int(entry.get("paired", -1))
	if paired >= 0:
		var paired_key := str(GameEnums.LimbRegion.keys()[paired]).to_lower()
		var paired_raw: Variant = functions.get(paired_key, functions.get(paired, GameEnums.SCALE_MAX))
		band = _worse_band(band, _raw_function_band(paired_raw))
	return band


func _raw_function_band(raw_value: Variant) -> String:
	if raw_value is String:
		return str(raw_value).to_lower()
	var ratio := float(raw_value) / GameEnums.SCALE_MAX
	if ratio <= 0.0:
		return "disabled"
	if ratio <= 0.5:
		return "impaired"
	if ratio < 0.95:
		return "wounded"
	return "functional"


func _worse_band(left: String, right: String) -> String:
	var order := {"functional": 0, "wounded": 1, "impaired": 2, "disabled": 3}
	return right if int(order.get(right, 1)) > int(order.get(left, 1)) else left


func _band_value(band: String) -> float:
	match band.to_lower():
		"disabled": return 0.0
		"impaired": return 4.0
		"wounded": return 8.0
		_: return GameEnums.SCALE_MAX


func _band_ratio(band: String) -> float:
	return clampf(_band_value(band) / GameEnums.SCALE_MAX, 0.0, 1.0)


func _function_color(ratio: float) -> Color:
	if ratio <= 0.25:
		return Color("e04e43")
	if ratio <= 0.55:
		return Color("e29a4a")
	return Color("62b89c")


func _region_has_wound(region: int, paired: int = -1) -> bool:
	for wound in actor_snapshot.get("wounds", []):
		var wound_region := int(wound.get("body_region", -1))
		if wound_region == region or wound_region == paired:
			return true
	return false
