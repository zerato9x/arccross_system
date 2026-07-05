@tool
extends Node2D
class_name WorldMapEditor

## Hand-painted macro map workspace. Select a paint layer in the scene tree,
## pick any tile from MacroTileSet in the TileMap bottom panel, and paint.
## Flora / rock / structure layers stack on top of terrain for detail props.

@export_group("Paint Layers")
@export var terrain_layer: TileMapLayer
@export var flora_layer: TileMapLayer
@export var rock_layer: TileMapLayer
@export var structure_layer: TileMapLayer
@export var props_layer: TileMapLayer
@export var baker: Node

@export_group("Editor Focus")
@export_enum("Terrain", "Flora", "Rock", "Structure", "Props") var focused_layer: int = 0:
	set(value):
		focused_layer = value
		if Engine.is_editor_hint():
			_apply_layer_focus()

@export_group("Example Sector")
@export var paint_example_sector: bool = false:
	set(value):
		if not value:
			paint_example_sector = false
			return
		if Engine.is_editor_hint():
			call_deferred("_editor_paint_example_sector")
		paint_example_sector = false

const LAYER_NAMES := ["Terrain", "Flora", "Rock", "Structure", "Props"]
const LAYER_Z := [0, 1, 2, 3, 4]
const SINGLE_TILE := Vector2i(0, 0)

const EXAMPLE_TERRAIN_SOURCES := {
	Vector2i(0, 0): 122,
	Vector2i(1, 0): 121,
	Vector2i(-1, 0): 120,
	Vector2i(0, 1): 119,
	Vector2i(0, -1): 118,
	Vector2i(1, -1): 117,
	Vector2i(-1, 1): 116,
	Vector2i(2, 0): 123,
	Vector2i(-2, 0): 114,
}
const EXAMPLE_FLORA := {Vector2i(0, 1): 290, Vector2i(-1, 1): 292}
const EXAMPLE_ROCK := {Vector2i(-1, 0): 260}
const EXAMPLE_STRUCTURE := {Vector2i(1, 0): 265}
const EXAMPLE_SHRUB_PATH := (
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub H.png"
)


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_auto_wire_references()
	_configure_layer_stack()
	_apply_layer_focus()
	if baker != null:
		baker.call("_auto_wire_references")


func _auto_wire_references() -> void:
	if terrain_layer == null:
		terrain_layer = get_node_or_null("TerrainLayer") as TileMapLayer
	if flora_layer == null:
		flora_layer = get_node_or_null("FloraLayer") as TileMapLayer
	if rock_layer == null:
		rock_layer = get_node_or_null("RockLayer") as TileMapLayer
	if structure_layer == null:
		structure_layer = get_node_or_null("StructureLayer") as TileMapLayer
	if props_layer == null:
		props_layer = get_node_or_null("PropsLayer") as TileMapLayer
	if baker == null:
		baker = get_node_or_null("AuthoredWorldMapBaker")


func _configure_layer_stack() -> void:
	var layers := _all_layers()
	for index in range(layers.size()):
		var layer: TileMapLayer = layers[index]
		if layer == null:
			continue
		layer.z_index = LAYER_Z[index]
		layer.y_sort_enabled = false


func _apply_layer_focus() -> void:
	var layers := _all_layers()
	for index in range(layers.size()):
		var layer: TileMapLayer = layers[index]
		if layer == null:
			continue
		layer.modulate = Color(1, 1, 1, 1.0 if index == focused_layer else 0.45)
		layer.visible = true


func _all_layers() -> Array:
	return [terrain_layer, flora_layer, rock_layer, structure_layer, props_layer]


func _layer_for_focus() -> TileMapLayer:
	var layers := _all_layers()
	if focused_layer < 0 or focused_layer >= layers.size():
		return terrain_layer
	return layers[focused_layer]


func _editor_focus_active_layer() -> void:
	if not Engine.is_editor_hint():
		return
	var layer: TileMapLayer = _layer_for_focus()
	if layer == null:
		push_warning("[WorldMapEditor] No layer assigned for focus index %d." % focused_layer)
		return
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(layer)
	if baker != null:
		match focused_layer:
			0:
				baker.set("terrain_layer", layer)
			1:
				baker.set("flora_layer", layer)
			2:
				baker.set("rock_layer", layer)
			3:
				baker.set("structure_layer", layer)
			4:
				baker.set("props_layer", layer)


func _editor_show_all_layers() -> void:
	if not Engine.is_editor_hint():
		return
	for layer: TileMapLayer in _all_layers():
		if layer != null:
			layer.modulate = Color.WHITE
			layer.visible = true


func _editor_sync_selected_markers() -> void:
	if not Engine.is_editor_hint():
		return
	var selection := EditorInterface.get_selection()
	if selection == null:
		return
	var nodes := selection.get_selected_nodes()
	for node in nodes:
		if node is HexMapMarker:
			(node as HexMapMarker).sync_coords_from_position(terrain_layer, false)


func _editor_snap_selected_markers() -> void:
	if not Engine.is_editor_hint():
		return
	var selection := EditorInterface.get_selection()
	if selection == null:
		return
	var nodes := selection.get_selected_nodes()
	for node in nodes:
		if node is HexMapMarker:
			(node as HexMapMarker).sync_coords_from_position(terrain_layer, true)


func _editor_sync_selected_decor() -> void:
	if not Engine.is_editor_hint():
		return
	var selection := EditorInterface.get_selection()
	if selection == null:
		return
	var nodes := selection.get_selected_nodes()
	for node in nodes:
		if node is HexDecorProp:
			(node as HexDecorProp).sync_coords_from_position(terrain_layer, false)


func _editor_create_marker() -> void:
	if not Engine.is_editor_hint():
		return
	var root := get_node_or_null("Markers")
	if root == null:
		push_warning("[WorldMapEditor] Missing 'Markers' node.")
		return
	var marker := HexMapMarker.new()
	marker.name = "Marker"
	marker.coord_layer = terrain_layer
	root.add_child(marker, true)
	marker.owner = get_tree().edited_scene_root
	marker.global_position = global_position
	marker.sync_coords_from_position(terrain_layer, false)


func _editor_create_decor_prop() -> void:
	if not Engine.is_editor_hint():
		return
	var root := get_node_or_null("Decorations")
	if root == null:
		push_warning("[WorldMapEditor] Missing 'Decorations' node.")
		return
	var prop := HexDecorProp.new()
	prop.name = "DecorProp"
	prop.coord_layer = terrain_layer
	root.add_child(prop, true)
	prop.owner = get_tree().edited_scene_root
	prop.global_position = global_position
	prop.sync_coords_from_position(terrain_layer, false)


func _editor_paint_example_sector() -> void:
	if not Engine.is_editor_hint():
		return
	_auto_wire_references()
	if baker != null:
		baker.call("_auto_wire_references")
	_clear_example_sector()
	_paint_example_tiles()
	_spawn_example_decor()
	_spawn_example_markers()
	print("[WorldMapEditor] Example sector painted. Bake when ready.")


func _clear_example_sector() -> void:
	for layer: TileMapLayer in _all_layers():
		if layer == null:
			continue
		for coords in EXAMPLE_TERRAIN_SOURCES.keys():
			layer.erase_cell(coords)
	for coords in EXAMPLE_FLORA.keys():
		if flora_layer != null:
			flora_layer.erase_cell(coords)
	for coords in EXAMPLE_ROCK.keys():
		if rock_layer != null:
			rock_layer.erase_cell(coords)
	for coords in EXAMPLE_STRUCTURE.keys():
		if structure_layer != null:
			structure_layer.erase_cell(coords)
	var decor_root := get_node_or_null("Decorations")
	if decor_root != null:
		for child in decor_root.get_children():
			if child.name.begins_with("ExampleSector"):
				child.queue_free()
	var marker_root := get_node_or_null("Markers")
	if marker_root != null:
		for child in marker_root.get_children():
			if child.name.begins_with("ExampleSector"):
				child.queue_free()


func _paint_example_tiles() -> void:
	for coords in EXAMPLE_TERRAIN_SOURCES.keys():
		_paint_cell(terrain_layer, coords, EXAMPLE_TERRAIN_SOURCES[coords])
	for coords in EXAMPLE_FLORA.keys():
		_paint_cell(flora_layer, coords, EXAMPLE_FLORA[coords])
	for coords in EXAMPLE_ROCK.keys():
		_paint_cell(rock_layer, coords, EXAMPLE_ROCK[coords])
	for coords in EXAMPLE_STRUCTURE.keys():
		_paint_cell(structure_layer, coords, EXAMPLE_STRUCTURE[coords])


func _paint_cell(layer: TileMapLayer, coords: Vector2i, source_id: int) -> void:
	if layer == null or source_id < 0:
		return
	layer.set_cell(coords, source_id, SINGLE_TILE)


func _spawn_example_markers() -> void:
	var marker_root := get_node_or_null("Markers")
	if marker_root == null:
		return
	var marker := HexMapMarker.new()
	marker.name = "ExampleSectorHomesteadPoi"
	marker.coord_layer = terrain_layer
	marker.hex_coords = Vector2i(1, 0)
	marker.is_poi = true
	marker.poi_id = "example_homestead"
	marker.poi_name = "Example Homestead"
	marker.zone_id = "example_sector"
	marker.hazard_level = 0.5
	marker_root.add_child(marker, true)
	marker.owner = get_tree().edited_scene_root
	marker.global_position = hex_center_global(Vector2i(1, 0))


func _spawn_example_decor() -> void:
	var decor_root := get_node_or_null("Decorations")
	if decor_root == null or terrain_layer == null:
		return
	_add_example_decor(
		decor_root,
		"ExampleSectorShrubSmall",
		Vector2i(0, 0),
		Vector2(72.0, -28.0),
		0.14,
		0
	)
	_add_example_decor(
		decor_root,
		"ExampleSectorShrubLarge",
		Vector2i(-1, 1),
		Vector2(-48.0, 36.0),
		0.22,
		0
	)
	_add_example_decor(
		decor_root,
		"ExampleSectorCrateProp",
		Vector2i(2, 0),
		Vector2(-64.0, 18.0),
		0.16,
		3,
		"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Homestead Crates Size1.png"
	)


func _add_example_decor(
	root: Node2D,
	node_name: String,
	coords: Vector2i,
	offset: Vector2,
	uniform: float,
	layer_index: int,
	sprite: String = EXAMPLE_SHRUB_PATH
) -> void:
	var prop := HexDecorProp.new()
	prop.name = node_name
	prop.coord_layer = terrain_layer
	prop.decor_layer = layer_index
	prop.hex_coords = coords
	root.add_child(prop, true)
	prop.owner = get_tree().edited_scene_root
	prop.sprite_path = sprite
	prop.uniform_scale = uniform
	prop.global_position = hex_center_global(coords) + offset


func hex_center_global(coords: Vector2i) -> Vector2:
	if terrain_layer == null:
		return global_position
	return terrain_layer.to_global(terrain_layer.map_to_local(coords))

