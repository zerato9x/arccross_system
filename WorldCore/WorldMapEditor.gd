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

const LAYER_NAMES := ["Terrain", "Flora", "Rock", "Structure", "Props"]
const LAYER_Z := [0, 1, 2, 3, 4]


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_configure_layer_stack()
	_apply_layer_focus()


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
		layer.modulate = Color(1, 1, 1, 1.0 if index == focused_layer else 0.45)
		layer.visible = true


func _all_layers() -> Array:
	return [terrain_layer, flora_layer, rock_layer, structure_layer, props_layer]


func _layer_for_focus() -> TileMapLayer:
	var layers := _all_layers()
	if focused_layer < 0 or focused_layer >= layers.size():
		return terrain_layer
	return layers[focused_layer]


@export_tool_button("Focus Active Layer")
func _editor_focus_active_layer() -> void:
	if not Engine.is_editor_hint():
		return
	var layer := _layer_for_focus()
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


@export_tool_button("Show All Layers")
func _editor_show_all_layers() -> void:
	if not Engine.is_editor_hint():
		return
	for layer in _all_layers():
		if layer != null:
			layer.modulate = Color.WHITE
			layer.visible = true
