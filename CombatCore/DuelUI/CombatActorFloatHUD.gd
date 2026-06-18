extends Node2D
class_name CombatActorFloatHUD

const SIDE_PLAYER := "player"
const SIDE_ENEMY := "enemy"
const PANEL_SIZE := Vector2(250.0, 168.0)
const DETAIL_SIZE := Vector2(250.0, 104.0)
const COLOR_PANEL := Color(0.10, 0.11, 0.10, 0.92)
const COLOR_BORDER := Color(0.69, 0.64, 0.50, 0.9)
const COLOR_DANGER := Color(0.78, 0.34, 0.30, 1.0)
const COLOR_OK := Color(0.50, 0.61, 0.53, 1.0)

var _actor_data: Dictionary = {}
var _side := SIDE_PLAYER
var _expanded := false
var _target_local := Vector2.ZERO
var _anchor_global := Vector2.ZERO
var _viewport_origin := Vector2.ZERO
var _viewport_size := Vector2(1280.0, 720.0)
var _camera_zoom := 1.0

@onready var _panel_box: Polygon2D = %PanelBox
@onready var _border: Line2D = %Border
@onready var _pointer: Line2D = %Pointer
@onready var _pointer_triangle: Polygon2D = %PointerTriangle
@onready var _paperdoll_box: Polygon2D = %PaperDollGreybox
@onready var _detail_box: Polygon2D = %DetailBox
@onready var _hover_area: Area2D = %HoverArea
@onready var _collision_shape: CollisionShape2D = %CollisionShape2D
@onready var _name_label: Label = %NameLabel
@onready var _summary_label: Label = %SummaryLabel
@onready var _limb_strip_label: Label = %LimbStripLabel
@onready var _detail_label: Label = %DetailLabel
@onready var _limb_markers: Node2D = %LimbMarkers

func _ready() -> void:
	_apply_geometry()
	_hover_area.input_pickable = true
	_hover_area.mouse_entered.connect(_set_expanded.bind(true))
	_hover_area.mouse_exited.connect(_set_expanded.bind(false))
	_detail_box.visible = false
	_detail_label.visible = false
	visible = false

func set_actor(
	actor_data: Dictionary,
	side: String,
	anchor_global: Vector2,
	viewport_size: Vector2,
	viewport_origin: Vector2 = Vector2.ZERO,
	camera_zoom: float = 1.0
) -> void:
	_actor_data = actor_data.duplicate(true)
	_side = side
	_anchor_global = anchor_global
	_viewport_origin = viewport_origin
	_viewport_size = viewport_size
	_camera_zoom = maxf(0.01, camera_zoom)
	visible = not _actor_data.is_empty()
	if not visible:
		return

	_refresh_content()
	var height := PANEL_SIZE.y + (DETAIL_SIZE.y if _expanded else 0.0)
	var inverse_zoom := 1.0 / _camera_zoom
	scale = Vector2.ONE * inverse_zoom
	var world_viewport_size := viewport_size * inverse_zoom
	var is_left_side := anchor_global.x < (
		viewport_origin.x + world_viewport_size.x * 0.5
	)
	var x_offset := (
		-PANEL_SIZE.x * 0.24
		if is_left_side
		else -PANEL_SIZE.x * 0.76
	) * inverse_zoom
	var target := anchor_global + Vector2(
		x_offset,
		(-height - 46.0) * inverse_zoom
	)
	var margin := 18.0 * inverse_zoom
	target.x = clampf(
		target.x,
		viewport_origin.x + margin,
		maxf(
			viewport_origin.x + margin,
			viewport_origin.x
				+ world_viewport_size.x
				- PANEL_SIZE.x * inverse_zoom
				- margin
		)
	)
	target.y = clampf(
		target.y,
		viewport_origin.y + margin,
		maxf(
			viewport_origin.y + margin,
			viewport_origin.y
				+ world_viewport_size.y
				- height * inverse_zoom
				- margin
		)
	)
	global_position = target
	_target_local = to_local(anchor_global)
	_refresh_pointer()

func _apply_geometry() -> void:
	_set_box(_panel_box, PANEL_SIZE, Vector2.ZERO)
	_panel_box.color = COLOR_PANEL
	_set_outline(_border, PANEL_SIZE, Vector2.ZERO)
	_set_box(_paperdoll_box, Vector2(78.0, 118.0), Vector2(12.0, 36.0))
	_paperdoll_box.color = Color(0.22, 0.23, 0.22, 0.94)
	_set_box(_detail_box, DETAIL_SIZE, Vector2(0.0, PANEL_SIZE.y + 8.0))
	_detail_box.color = Color(0.07, 0.08, 0.08, 0.94)
	var shape := RectangleShape2D.new()
	shape.size = PANEL_SIZE + Vector2(0.0, DETAIL_SIZE.y)
	_collision_shape.shape = shape
	_collision_shape.position = Vector2(PANEL_SIZE.x * 0.5, (PANEL_SIZE.y + DETAIL_SIZE.y) * 0.5)

func _refresh_content() -> void:
	var side_label := "YOU" if _side == SIDE_PLAYER else "HOSTILE"
	_name_label.text = "%s // %s" % [
		side_label,
		str(_actor_data.get("archetype", _actor_data.get("name", "UNKNOWN"))).to_upper(),
	]
	_name_label.modulate = COLOR_OK if _side == SIDE_PLAYER else COLOR_DANGER
	_summary_label.text = (
		"BLOOD %04.1f  STANCE %02d/12\n"
		+ "AP-R %02d  %s\n"
		+ "%s%s"
	) % [
		float(_actor_data.get("blood", 0.0)),
		int(_actor_data.get("stance", 0)),
		int(_actor_data.get("reserved_ap", 0)),
		str(_actor_data.get("stance_state", "UNKNOWN")),
		str(_actor_data.get("weapon", "UNARMED")).to_upper(),
		str(_actor_data.get("weapon_detail", "")),
	]
	var limbs: Array = _actor_data.get("limbs", [])
	_limb_strip_label.text = _limb_warning_strip(limbs)
	_detail_label.text = _limb_detail_text(limbs)
	_refresh_limb_markers(limbs)

func _refresh_limb_markers(limbs: Array) -> void:
	var by_code := {}
	for raw_limb in limbs:
		var limb: Dictionary = raw_limb
		by_code[str(limb.get("code", ""))] = limb
	for marker in _limb_markers.get_children():
		var polygon := marker as Polygon2D
		if polygon == null:
			continue
		var limb: Dictionary = by_code.get(marker.name, {})
		var current := float(limb.get("current", 1.0))
		var maximum := maxf(1.0, float(limb.get("maximum", 1.0)))
		var trauma := str(limb.get("trauma", "NONE"))
		polygon.color = COLOR_DANGER if current / maximum <= 0.35 or trauma != "NONE" else COLOR_OK

func _set_expanded(value: bool) -> void:
	_expanded = value
	_detail_box.visible = _expanded
	_detail_label.visible = _expanded
	if visible:
		set_actor(
			_actor_data,
			_side,
			_anchor_global,
			_viewport_size,
			_viewport_origin,
			_camera_zoom
		)

func _refresh_pointer() -> void:
	var bottom_center := Vector2(PANEL_SIZE.x * 0.5, PANEL_SIZE.y - 2.0)
	_pointer.points = PackedVector2Array([bottom_center, _target_local])
	_pointer.default_color = Color(COLOR_BORDER, 0.7)
	var direction := (_target_local - bottom_center).normalized()
	if direction.length_squared() <= 0.0:
		direction = Vector2.DOWN
	var base := _target_local - direction * 16.0
	var tangent := Vector2(-direction.y, direction.x)
	_pointer_triangle.polygon = PackedVector2Array([
		_target_local,
		base + tangent * 8.0,
		base - tangent * 8.0,
	])
	_pointer_triangle.color = Color(COLOR_BORDER, 0.72)

func _limb_warning_strip(limbs: Array) -> String:
	var warnings := PackedStringArray()
	for raw_limb in limbs:
		var limb: Dictionary = raw_limb
		var current := float(limb.get("current", 0.0))
		var maximum := maxf(1.0, float(limb.get("maximum", 1.0)))
		var trauma := str(limb.get("trauma", "NONE"))
		if current / maximum <= 0.35 or trauma != "NONE":
			warnings.append("%s%s" % [str(limb.get("code", "??")), "!" if trauma != "NONE" else ""])
	if warnings.is_empty():
		return "LIMBS STABLE"
	return "DANGER " + "  ".join(warnings)

func _limb_detail_text(limbs: Array) -> String:
	if limbs.is_empty():
		return "NO LIMB SIGNAL"
	var rows := PackedStringArray()
	for raw_limb in limbs:
		var limb: Dictionary = raw_limb
		rows.append("%s  %s/%s  %s" % [
			str(limb.get("code", "??")),
			_compact_number(float(limb.get("current", 0.0))),
			_compact_number(float(limb.get("maximum", 0.0))),
			str(limb.get("trauma", "NONE")),
		])
	return "\n".join(rows)

func _compact_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value

func _set_box(polygon: Polygon2D, box_size: Vector2, offset: Vector2) -> void:
	polygon.polygon = PackedVector2Array([
		offset,
		offset + Vector2(box_size.x, 0.0),
		offset + box_size,
		offset + Vector2(0.0, box_size.y),
	])

func _set_outline(line: Line2D, box_size: Vector2, offset: Vector2) -> void:
	line.points = PackedVector2Array([
		offset,
		offset + Vector2(box_size.x, 0.0),
		offset + box_size,
		offset + Vector2(0.0, box_size.y),
		offset,
	])
	line.default_color = COLOR_BORDER
	line.width = 1.5
