extends Control
class_name CombatBodyTargetView

signal region_selected(region: int)

const PAPER_DOLL_SCENE := preload("res://UI/Inventory/PaperDollModel.tscn")
const REGION_ANCHORS := {
	GameEnums.LimbRegion.HEAD: Vector2(0.50, 0.18),
	GameEnums.LimbRegion.UPPER_TORSO: Vector2(0.50, 0.36),
	GameEnums.LimbRegion.LOWER_TORSO: Vector2(0.50, 0.51),
	GameEnums.LimbRegion.LEFT_ARM: Vector2(0.35, 0.43),
	GameEnums.LimbRegion.RIGHT_ARM: Vector2(0.65, 0.43),
	GameEnums.LimbRegion.LEFT_LEG: Vector2(0.43, 0.72),
	GameEnums.LimbRegion.RIGHT_LEG: Vector2(0.57, 0.72),
}

var selectable := false
var selected_region := -1
var actor_snapshot: Dictionary = {}
var _paper_doll: PaperDollModel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_paper_doll = PAPER_DOLL_SCENE.instantiate()
	_paper_doll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paper_doll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_paper_doll)
	move_child(_paper_doll, 0)
	gui_input.connect(_on_gui_input)
	resized.connect(queue_redraw)


func set_actor_snapshot(value: Dictionary) -> void:
	actor_snapshot = value.duplicate(true)
	if is_instance_valid(_paper_doll):
		_paper_doll.update_model([])
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


func _draw() -> void:
	var functions: Dictionary = actor_snapshot.get("region_function", {})
	for region in REGION_ANCHORS:
		var anchor: Vector2 = REGION_ANCHORS[region]
		var center := size * anchor
		var region_name := str(GameEnums.LimbRegion.keys()[int(region)])
		var function := float(functions.get(region_name, functions.get(int(region), GameEnums.SCALE_MAX)))
		var ratio := clampf(function / GameEnums.SCALE_MAX, 0.0, 1.0)
		var color := Color("70b7a0").lerp(Color("d15f52"), 1.0 - ratio)
		var radius := 15.0 if int(region) in [GameEnums.LimbRegion.UPPER_TORSO, GameEnums.LimbRegion.LOWER_TORSO] else 11.0
		draw_circle(center, radius, Color(color, 0.24))
		draw_circle(center, radius, Color("f2d37c") if int(region) == selected_region else color, false, 2.0)
		if _region_has_wound(int(region)):
			draw_circle(center + Vector2(radius * 0.65, -radius * 0.65), 3.5, Color("e4584f"))


func _on_gui_input(event: InputEvent) -> void:
	if selectable and event is InputEventKey and event.pressed:
		var regions: Array = REGION_ANCHORS.keys()
		regions.sort()
		if event.is_action("ui_left") or event.is_action("ui_up"):
			var previous := regions.find(selected_region)
			selected_region = int(regions[posmod(previous - 1, regions.size())])
			queue_redraw()
			accept_event()
			return
		if event.is_action("ui_right") or event.is_action("ui_down"):
			var next := regions.find(selected_region)
			selected_region = int(regions[posmod(next + 1, regions.size())])
			queue_redraw()
			accept_event()
			return
		if event.is_action("ui_accept"):
			if selected_region < 0:
				selected_region = GameEnums.LimbRegion.UPPER_TORSO
			region_selected.emit(selected_region)
			accept_event()
			return
	if not selectable or not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var nearest := -1
	var nearest_distance := INF
	for region in REGION_ANCHORS:
		var anchor: Vector2 = REGION_ANCHORS[region]
		var distance: float = event.position.distance_to(size * anchor)
		if distance < nearest_distance:
			nearest = int(region)
			nearest_distance = distance
	if nearest >= 0 and nearest_distance <= 30.0:
		selected_region = nearest
		queue_redraw()
		region_selected.emit(nearest)
		accept_event()


func _region_has_wound(region: int) -> bool:
	for wound in actor_snapshot.get("wounds", []):
		if int(wound.get("body_region", -1)) == region:
			return true
	return false
