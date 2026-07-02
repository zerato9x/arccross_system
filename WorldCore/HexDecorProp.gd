@tool
extends Node2D
class_name HexDecorProp

## Scaled map decoration. Place in world_map_editor under Decorations, assign a
## sprite_path, drag to position, and resize with Godot's scale handles (or the
## Scale property). Does NOT use TileMap tile_size — each prop has its own scale.

@export_file("*.png") var sprite_path: String = "":
	set(value):
		sprite_path = value
		_refresh_preview()

@export var hex_coords: Vector2i = Vector2i.ZERO
@export_enum("Flora", "Rock", "Structure", "Props") var decor_layer: int = 3
@export_range(0.01, 4.0) var uniform_scale: float = 0.18:
	set(value):
		uniform_scale = value
		scale = Vector2.ONE * uniform_scale

var _sprite: Sprite2D


func _ready() -> void:
	if scale.is_equal_approx(Vector2.ONE):
		scale = Vector2.ONE * uniform_scale
	_refresh_preview()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		uniform_scale = (absf(scale.x) + absf(scale.y)) * 0.5


func to_record() -> Dictionary:
	return {
		"coords": hex_coords,
		"sprite_path": sprite_path,
		"scale": Vector2(scale.x, scale.y),
		"offset": position,
		"layer": decor_layer,
	}


func _refresh_preview() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "PreviewSprite"
		add_child(_sprite)
	if sprite_path.is_empty():
		_sprite.texture = null
		return
	var texture := load(sprite_path) as Texture2D
	_sprite.texture = texture
	if texture != null:
		_sprite.centered = true
