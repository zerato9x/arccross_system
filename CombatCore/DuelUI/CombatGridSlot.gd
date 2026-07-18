extends Node2D
class_name CombatGridSlot

signal hovered(slot_index: int)
signal unhovered(slot_index: int)

const COLOR_EMPTY := Color(0.12, 0.13, 0.11, 0.16)
const COLOR_PLAYER := Color(0.30, 0.44, 0.38, 0.30)
const COLOR_ENEMY := Color(0.48, 0.26, 0.24, 0.30)
const COLOR_LOCK := Color(0.62, 0.45, 0.20, 0.38)
const COLOR_BORDER := Color(0.66, 0.66, 0.61, 0.9)
const COLOR_HOVER := Color(0.84, 0.72, 0.48, 0.95)
const COLOR_OBJECT_FALLBACK := Color(0.12, 0.105, 0.085, 0.82)

@export var slot_index := 0
@export var slot_size := Vector2(132.0, 88.0)

var _slot_data: Dictionary = {}
var _hovered := false
var _texture_cache: Dictionary = {}
var _duel_focus_active := false
var _duel_focus_slot := -1

@onready var _ground_sprite: Sprite2D = %GroundSprite
@onready var _surface_sprite: Sprite2D = %SurfaceSprite
@onready var _floor_box: Polygon2D = %FloorBox
@onready var _object_sprite: Sprite2D = %ObjectSprite
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

func set_duel_focus(active: bool, lock_slot: int) -> void:
	_duel_focus_active = active
	_duel_focus_slot = lock_slot
	modulate.a = 1.0 if not active or slot_index == lock_slot else 0.26
	_hover_area.input_pickable = not active or slot_index == lock_slot

func get_duel_focus_alpha() -> float:
	return modulate.a

func get_actor_anchor(side: String, shared_lane: bool = false) -> Vector2:
	var offset := maxf(10.0, slot_size.x * 0.12)
	if side == "player":
		offset *= -1.0
	if shared_lane:
		var shared_offset := maxf(32.0, slot_size.x * 0.30)
		offset = -shared_offset if side == "player" else shared_offset
	return global_position + Vector2(offset, -maxf(34.0, slot_size.y * 0.48))

func _apply_geometry() -> void:
	var half := slot_size * 0.5
	var points := PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	_floor_box.polygon = points
	_ground_sprite.position = Vector2.ZERO
	_surface_sprite.position = Vector2.ZERO
	_object_sprite.position = Vector2(0.0, -half.y * 0.14)
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
	_refresh_asset_layers()
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

	var floor_name := _tile_label()
	var object_name := str(_slot_data.get("object_name", _slot_data.get("cover", "NONE")))
	_floor_label.text = floor_name
	_object_label.text = object_name if object_name != "NONE" else ""
	_object_box.visible = object_name != "NONE" and not _object_sprite.visible
	_object_box.color = COLOR_OBJECT_FALLBACK
	_border.default_color = COLOR_HOVER if _hovered else COLOR_BORDER
	_border.width = 3.0 if _hovered else 1.5

func _refresh_asset_layers() -> void:
	var ground_path := str(
		_slot_data.get("ground_asset", CombatLaneSlot.PLAINS_GROUND_ASSET)
	)
	_ground_sprite.texture = _load_texture(ground_path)
	_ground_sprite.visible = _ground_sprite.texture != null
	_fit_sprite_to_slot(_ground_sprite, 1.08)

	var surface_path := str(_slot_data.get("surface_asset", ""))
	_surface_sprite.texture = _load_texture(surface_path)
	_surface_sprite.visible = _surface_sprite.texture != null
	_fit_sprite_to_slot(_surface_sprite, 1.0)

	var object_path := str(_slot_data.get("object_asset", ""))
	_object_sprite.texture = _load_texture(object_path)
	_object_sprite.visible = _object_sprite.texture != null
	_fit_object_sprite(_object_sprite)

func _load_texture(path: String) -> Texture2D:
	if path.strip_edges().is_empty():
		return null
	if not _texture_cache.has(path):
		_texture_cache[path] = load(path) as Texture2D
	return _texture_cache[path]

func _fit_sprite_to_slot(sprite: Sprite2D, fill_scale: float) -> void:
	if sprite == null or sprite.texture == null:
		return
	var texture_size := sprite.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var scale_factor := maxf(
		slot_size.x / texture_size.x,
		slot_size.y / texture_size.y
	) * fill_scale
	sprite.scale = Vector2.ONE * scale_factor

func _fit_object_sprite(sprite: Sprite2D) -> void:
	if sprite == null or sprite.texture == null:
		return
	var texture_size := sprite.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var scale_factor := minf(
		(slot_size.x * 0.74) / texture_size.x,
		(slot_size.y * 0.78) / texture_size.y
	)
	sprite.scale = Vector2.ONE * scale_factor
	sprite.position = Vector2(0.0, -slot_size.y * 0.14)

func _tile_label() -> String:
	var background_label := str(
		_slot_data.get("background_label", _slot_data.get("background", "PLAINS"))
	)
	var surface_label := str(_slot_data.get("surface_label", "GRASS"))
	if background_label == "MUD":
		return "MUD +TRIP"
	if surface_label == "DIRT ROAD":
		return "ROAD"
	return background_label

func _on_mouse_entered() -> void:
	set_highlighted(true)
	hovered.emit(slot_index)

func _on_mouse_exited() -> void:
	set_highlighted(false)
	unhovered.emit(slot_index)
