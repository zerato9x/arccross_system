extends Node2D
class_name CombatGridSlot

signal hovered(slot_index: int)
signal unhovered(slot_index: int)

const COLOR_EMPTY := Color(0.23, 0.24, 0.23, 0.78)
const COLOR_PLAYER := Color(0.36, 0.42, 0.39, 0.92)
const COLOR_ENEMY := Color(0.43, 0.35, 0.35, 0.92)
const COLOR_LOCK := Color(0.47, 0.43, 0.31, 0.98)
const COLOR_BORDER := Color(0.66, 0.66, 0.61, 0.9)
const COLOR_HOVER := Color(0.84, 0.72, 0.48, 0.95)

@export var slot_index := 0
@export var slot_size := Vector2(132.0, 88.0)

var _slot_data: Dictionary = {}
var _hovered := false

@onready var _floor_box: Polygon2D = %FloorBox
@onready var _border: Line2D = %Border
@onready var _object_box: Polygon2D = %ObjectBox
@onready var _hover_area: Area2D = %HoverArea
@onready var _collision_shape: CollisionShape2D = %CollisionShape2D
@onready var _index_label: Label = %IndexLabel
@onready var _floor_label: Label = %FloorLabel
@onready var _object_label: Label = %ObjectLabel

func _ready() -> void:
	_apply_geometry()
	_hover_area.input_pickable = true
	_hover_area.mouse_entered.connect(_on_mouse_entered)
	_hover_area.mouse_exited.connect(_on_mouse_exited)
	_index_label.text = "%02d" % slot_index
	_refresh()

func show_slot_data(slot_data: Dictionary) -> void:
	_slot_data = slot_data.duplicate(true)
	_refresh()

func set_slot_size(value: Vector2) -> void:
	slot_size = value
	if is_inside_tree():
		_apply_geometry()
		_refresh()

func set_highlighted(value: bool) -> void:
	_hovered = value
	_refresh()

func get_actor_anchor(side: String, shared_lane: bool = false) -> Vector2:
	var offset := 0.0
	if shared_lane:
		offset = -18.0 if side == "player" else 18.0
	return global_position + Vector2(offset, -12.0)

func _apply_geometry() -> void:
	var half := slot_size * 0.5
	var points := PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	_floor_box.polygon = points
	_border.points = PackedVector2Array([
		points[0],
		points[1],
		points[2],
		points[3],
		points[0],
	])
	_object_box.polygon = PackedVector2Array([
		Vector2(-half.x * 0.28, -half.y * 0.22),
		Vector2(half.x * 0.28, -half.y * 0.22),
		Vector2(half.x * 0.28, half.y * 0.20),
		Vector2(-half.x * 0.28, half.y * 0.20),
	])
	var shape := RectangleShape2D.new()
	shape.size = slot_size
	_collision_shape.shape = shape
	_index_label.position = Vector2(-half.x + 8.0, -half.y - 23.0)
	_floor_label.position = Vector2(-half.x + 8.0, half.y + 3.0)
	_floor_label.size = Vector2(slot_size.x - 16.0, 18.0)
	_object_label.position = Vector2(-half.x + 8.0, -9.0)
	_object_label.size = Vector2(slot_size.x - 16.0, 18.0)

func _refresh() -> void:
	if not is_inside_tree():
		return
	_index_label.text = "%02d" % slot_index
	var occupants: Array = _slot_data.get("occupants", [])
	var has_player := false
	var has_enemy := false
	for occupant in occupants:
		has_player = has_player or occupant.get("side", "") == "player"
		has_enemy = has_enemy or occupant.get("side", "") == "enemy"

	if _slot_data.get("is_melee_locked", false):
		_floor_box.color = COLOR_LOCK
	elif has_player:
		_floor_box.color = COLOR_PLAYER
	elif has_enemy:
		_floor_box.color = COLOR_ENEMY
	else:
		_floor_box.color = COLOR_EMPTY

	var floor_name := str(_slot_data.get("background", "OPEN"))
	var object_name := str(_slot_data.get("cover", "NONE"))
	_floor_label.text = floor_name
	_object_label.text = object_name if object_name != "NONE" else ""
	_object_box.visible = object_name != "NONE"
	_object_box.color = Color(0.18, 0.18, 0.17, 0.92)
	_border.default_color = COLOR_HOVER if _hovered else COLOR_BORDER
	_border.width = 3.0 if _hovered else 1.5

func _on_mouse_entered() -> void:
	set_highlighted(true)
	hovered.emit(slot_index)

func _on_mouse_exited() -> void:
	set_highlighted(false)
	unhovered.emit(slot_index)
