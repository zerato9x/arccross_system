@tool
extends Node2D
class_name HexDecorProp

## Scaled map decoration. Place in world_map_editor under Decorations, assign a
## sprite_path, drag to position, and resize with Godot's scale handles (or the
## Scale property). Does NOT use TileMap tile_size — each prop has its own scale.

@export_group("Editor Helpers")
@export var coord_layer: TileMapLayer
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
	if Engine.is_editor_hint() and coord_layer == null:
		coord_layer = _guess_coord_layer()
	_refresh_preview()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		uniform_scale = (absf(scale.x) + absf(scale.y)) * 0.5


func _guess_coord_layer() -> TileMapLayer:
	var root := get_tree().edited_scene_root
	if root == null:
		root = get_parent()
	while root != null:
		var candidate := root.get_node_or_null("TerrainLayer")
		if candidate is TileMapLayer:
			return candidate as TileMapLayer
		root = root.get_parent()
	return null


func sync_coords_from_position(layer: TileMapLayer = null, snap_to_center: bool = false) -> void:
	var resolved := layer if layer != null else coord_layer
	if resolved == null:
		resolved = _guess_coord_layer()
	if resolved == null:
		push_warning("[HexDecorProp] No coord layer set; cannot sync coords.")
		return
	var local_pos := resolved.to_local(global_position)
	hex_coords = resolved.local_to_map(local_pos)
	if snap_to_center:
		global_position = resolved.to_global(resolved.map_to_local(hex_coords))


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
