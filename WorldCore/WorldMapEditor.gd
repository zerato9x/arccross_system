@tool
extends Node2D
class_name WorldMapEditor

## Editor workspace for hand-authored radius-12 local zones.
## Paint gameplay layers with the TileMap tools, place freeform art beneath
## Decorations, place metadata beneath Markers, and place runtime hooks beneath
## Sockets. AuthoredWorldMapBaker turns the scene into a runtime .tres.

@export_multiline var workflow_guide: String = (
	"1. Fill the radius-12 TerrainLayer (469 cells).\n"
	+ "2. Paint Water, Flora, Rock, Structure, and Props only where intended.\n"
	+ "3. Use HexDecorProp for freeform visual art; it has no gameplay authority.\n"
	+ "4. Use HexMapMarker for POI, hazard, blocker, and region metadata.\n"
	+ "5. Use HexMapSocket for arrivals, exits, encounters, quests, and variable POIs.\n"
	+ "6. Keep all eight arrival/exit corridors clear, then bake the .tres."
)

@export_group("Paint Layers")
@export var terrain_layer: TileMapLayer
@export var water_layer: TileMapLayer
@export var flora_layer: TileMapLayer
@export var rock_layer: TileMapLayer
@export var structure_layer: TileMapLayer
@export var props_layer: TileMapLayer
@export var baker: Node

@export_group("Editor Focus")
@export_enum("Terrain", "Water", "Flora", "Rock", "Structure", "Props")
var focused_layer: int = 0:
	set(value):
		focused_layer = value
		if Engine.is_editor_hint():
			_apply_layer_focus()

@export_group("Template Setup")
@export var base_terrain_source_id: int = 122
@export var initialize_radius_12: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			call_deferred("_editor_initialize_radius_12")
		initialize_radius_12 = false
@export var erase_outside_radius_12: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			call_deferred("_editor_erase_outside_radius_12")
		erase_outside_radius_12 = false

const LAYER_Z := [0, 1, 2, 3, 4, 5]
const SINGLE_TILE := Vector2i.ZERO


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_auto_wire_references()
	_configure_layer_stack()
	_apply_layer_focus()
	if baker != null:
		baker.call("_auto_wire_references")


func _auto_wire_references() -> void:
	terrain_layer = _resolve_layer(terrain_layer, "TerrainLayer")
	water_layer = _resolve_layer(water_layer, "WaterLayer")
	flora_layer = _resolve_layer(flora_layer, "FloraLayer")
	rock_layer = _resolve_layer(rock_layer, "RockLayer")
	structure_layer = _resolve_layer(structure_layer, "StructureLayer")
	props_layer = _resolve_layer(props_layer, "PropsLayer")
	if baker == null:
		baker = get_node_or_null("AuthoredWorldMapBaker")


func _resolve_layer(current: TileMapLayer, node_name: String) -> TileMapLayer:
	if current != null:
		return current
	return get_node_or_null(node_name) as TileMapLayer


func _all_layers() -> Array[TileMapLayer]:
	return [
		terrain_layer,
		water_layer,
		flora_layer,
		rock_layer,
		structure_layer,
		props_layer,
	]


func _configure_layer_stack() -> void:
	var layers := _all_layers()
	for index in range(layers.size()):
		var layer := layers[index]
		if layer == null:
			continue
		layer.z_index = LAYER_Z[index]
		layer.y_sort_enabled = false


func _apply_layer_focus() -> void:
	var layers := _all_layers()
	for index in range(layers.size()):
		var layer := layers[index]
		if layer == null:
			continue
		layer.modulate = Color.WHITE if index == focused_layer else Color(1, 1, 1, 0.35)
		layer.visible = true


func _editor_focus_active_layer() -> void:
	if not Engine.is_editor_hint():
		return
	var layers := _all_layers()
	if focused_layer < 0 or focused_layer >= layers.size():
		return
	var layer := layers[focused_layer]
	if layer == null:
		return
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(layer)


func _editor_show_all_layers() -> void:
	for layer in _all_layers():
		if layer != null:
			layer.modulate = Color.WHITE
			layer.visible = true


func _editor_initialize_radius_12() -> void:
	_auto_wire_references()
	if terrain_layer == null or base_terrain_source_id < 0:
		push_warning("[WorldMapEditor] Assign TerrainLayer and a valid base source ID.")
		return
	for coords in HexCoordUtils.cells_in_radius(GameEnums.MACRO_ZONE_RADIUS):
		if terrain_layer.get_cell_source_id(coords) < 0:
			terrain_layer.set_cell(coords, base_terrain_source_id, SINGLE_TILE)
	print("[WorldMapEditor] Radius-12 baseline ready: 469 playable cells.")


func _editor_erase_outside_radius_12() -> void:
	for layer in _all_layers():
		if layer == null:
			continue
		for coords in layer.get_used_cells():
			if not HexCoordUtils.is_in_radius(coords, GameEnums.MACRO_ZONE_RADIUS):
				layer.erase_cell(coords)


func _editor_sync_selected() -> void:
	_sync_selection(false)


func _editor_snap_selected() -> void:
	_sync_selection(true)


func _sync_selection(snap_to_center: bool) -> void:
	if not Engine.is_editor_hint() or terrain_layer == null:
		return
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is HexMapMarker:
			(node as HexMapMarker).sync_coords_from_position(terrain_layer, snap_to_center)
		elif node is HexDecorProp:
			(node as HexDecorProp).sync_coords_from_position(terrain_layer, snap_to_center)
		elif node is HexMapSocket:
			(node as HexMapSocket).sync_coords_from_position(terrain_layer, snap_to_center)


func _editor_create_marker() -> void:
	_create_helper(HexMapMarker.new(), "Markers", "Marker")


func _editor_create_decor_prop() -> void:
	_create_helper(HexDecorProp.new(), "Decorations", "DecorProp")


func _editor_create_socket() -> void:
	_create_helper(HexMapSocket.new(), "Sockets", "Socket")


func _create_helper(helper: Node2D, root_name: String, node_name: String) -> void:
	if not Engine.is_editor_hint() or terrain_layer == null:
		return
	var root := get_node_or_null(root_name)
	if root == null:
		push_warning("[WorldMapEditor] Missing %s root." % root_name)
		return
	helper.name = node_name
	helper.set("coord_layer", terrain_layer)
	root.add_child(helper, true)
	helper.owner = get_tree().edited_scene_root
	helper.global_position = global_position
	helper.call("sync_coords_from_position", terrain_layer, false)


func hex_center_global(coords: Vector2i) -> Vector2:
	if terrain_layer == null:
		return global_position
	return terrain_layer.to_global(terrain_layer.map_to_local(coords))
