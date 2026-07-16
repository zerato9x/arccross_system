@tool
extends Node2D
class_name HexMapSocket

## Authored placement hook. Sockets describe where runtime systems may place
## content; they are not content themselves and never become decorative sprites.

enum SocketKind {
	POI,
	ENCOUNTER,
	QUEST_ITEM,
	ARRIVAL,
	EXIT,
}

@export_group("Editor Helpers")
@export var coord_layer: TileMapLayer
@export var hex_coords: Vector2i = Vector2i.ZERO

@export_group("Socket Contract")
@export var socket_id: String = ""
@export var kind: SocketKind = SocketKind.POI
@export var direction: GameEnums.MacroTravelDirection = (
	GameEnums.MacroTravelDirection.NONE
)
@export var profile_tags: PackedStringArray = PackedStringArray()
@export var required: bool = false
@export var enabled: bool = true
@export_multiline var author_note: String = ""


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	if coord_layer == null:
		coord_layer = _guess_coord_layer()
	call_deferred("_refresh_editor_preview")


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color := _socket_color()
	draw_circle(Vector2.ZERO, 20.0, Color(color, 0.28))
	draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 24, color, 4.0, true)
	draw_line(Vector2(-12, 0), Vector2(12, 0), color, 3.0, true)
	draw_line(Vector2(0, -12), Vector2(0, 12), color, 3.0, true)
	var label: String = socket_id if not socket_id.is_empty() else str(name)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(28, 6),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		16,
		color
	)


func _refresh_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	if coord_layer == null:
		coord_layer = _guess_coord_layer()
	if coord_layer != null:
		global_position = coord_layer.to_global(coord_layer.map_to_local(hex_coords))
	queue_redraw()


func _socket_color() -> Color:
	match kind:
		SocketKind.POI:
			return Color("#e7bd58")
		SocketKind.ENCOUNTER:
			return Color("#d9675d")
		SocketKind.QUEST_ITEM:
			return Color("#ba83e6")
		SocketKind.ARRIVAL:
			return Color("#62b8d9")
		SocketKind.EXIT:
			return Color("#70c986")
	return Color.WHITE


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


func sync_coords_from_position(
	layer: TileMapLayer = null,
	snap_to_center: bool = false
) -> void:
	var resolved := layer if layer != null else coord_layer
	if resolved == null:
		resolved = _guess_coord_layer()
	if resolved == null:
		push_warning("[HexMapSocket] No terrain layer; cannot sync coordinates.")
		return
	var local_pos := resolved.to_local(global_position)
	hex_coords = resolved.local_to_map(local_pos)
	if snap_to_center:
		global_position = resolved.to_global(resolved.map_to_local(hex_coords))


func to_record() -> Dictionary:
	return {
		"socket_id": socket_id if not socket_id.is_empty() else name.to_snake_case(),
		"kind": int(kind),
		"coords": hex_coords,
		"direction": int(direction),
		"profile_tags": Array(profile_tags),
		"required": required,
		"enabled": enabled,
		"author_note": author_note,
	}
