extends SceneTree

## Paints the example macro sector into world_map_editor.tscn and bakes
## res://WorldCore/Maps/example_sector.tres
## Run: godot --headless --path . --script res://Tools/BakeExampleSector.gd

const SCENE_PATH := "res://WorldCore/world_map_editor.tscn"
const OUTPUT_MAP := "res://WorldCore/Maps/example_sector.tres"
const SINGLE_TILE := Vector2i(0, 0)

const TERRAIN := {
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
const FLORA := {Vector2i(0, 1): 290, Vector2i(-1, 1): 292}
const ROCK := {Vector2i(-1, 0): 260}
const STRUCTURE := {Vector2i(1, 0): 265}
const SHRUB_PATH := (
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub H.png"
)
const CRATE_PATH := (
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Homestead Crates Size1.png"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("[BakeExampleSector] Missing scene: %s" % SCENE_PATH)
		quit(1)
		return

	var editor: Node2D = packed.instantiate()
	root.add_child(editor)

	var terrain: TileMapLayer = editor.get_node("TerrainLayer") as TileMapLayer
	var flora: TileMapLayer = editor.get_node("FloraLayer") as TileMapLayer
	var rock: TileMapLayer = editor.get_node("RockLayer") as TileMapLayer
	var structure: TileMapLayer = editor.get_node("StructureLayer") as TileMapLayer
	var decor_root: Node2D = editor.get_node("Decorations") as Node2D
	var marker_root: Node2D = editor.get_node("Markers") as Node2D
	var baker: Node = editor.get_node("AuthoredWorldMapBaker")

	_clear_example(decor_root, marker_root, terrain, flora, rock, structure)
	_paint_layers(terrain, flora, rock, structure)
	_spawn_decor(decor_root, terrain)
	_spawn_marker(marker_root, terrain)

	if baker.has_method("_auto_wire_references"):
		baker.call("_auto_wire_references")
	baker.set("output_path", OUTPUT_MAP)
	baker.set("map_id", "example_sector")
	baker.set("display_name", "Example Sector")
	baker.set("start_coords", Vector2i(0, 0))
	baker.set("core_coords", Vector2i(0, 0))

	var baked: Resource = baker.call("bake_to_resource", true)
	if baked == null:
		push_error("[BakeExampleSector] Bake failed.")
		quit(1)
		return

	var out_scene := PackedScene.new()
	var pack_err := out_scene.pack(editor)
	if pack_err != OK:
		push_error("[BakeExampleSector] Scene pack failed: %d" % pack_err)
		quit(1)
		return
	var save_err := ResourceSaver.save(out_scene, SCENE_PATH)
	if save_err != OK:
		push_error("[BakeExampleSector] Scene save failed: %d" % save_err)
		quit(1)
		return

	print(
		"[BakeExampleSector] Wrote %s and updated %s"
		% [OUTPUT_MAP, SCENE_PATH]
	)
	quit(0)


func _clear_example(
	decor_root: Node2D,
	marker_root: Node2D,
	terrain: TileMapLayer,
	flora: TileMapLayer,
	rock: TileMapLayer,
	structure: TileMapLayer
) -> void:
	for child in decor_root.get_children():
		if str(child.name).begins_with("ExampleSector"):
			child.free()
	for child in marker_root.get_children():
		if str(child.name).begins_with("ExampleSector"):
			child.free()
	for coords in TERRAIN.keys():
		terrain.erase_cell(coords)
		flora.erase_cell(coords)
		rock.erase_cell(coords)
		structure.erase_cell(coords)


func _paint_layers(
	terrain: TileMapLayer,
	flora: TileMapLayer,
	rock: TileMapLayer,
	structure: TileMapLayer
) -> void:
	for coords in TERRAIN.keys():
		terrain.set_cell(coords, TERRAIN[coords], SINGLE_TILE)
	for coords in FLORA.keys():
		flora.set_cell(coords, FLORA[coords], SINGLE_TILE)
	for coords in ROCK.keys():
		rock.set_cell(coords, ROCK[coords], SINGLE_TILE)
	for coords in STRUCTURE.keys():
		structure.set_cell(coords, STRUCTURE[coords], SINGLE_TILE)


func _spawn_decor(decor_root: Node2D, terrain: TileMapLayer) -> void:
	_add_decor(
		decor_root,
		terrain,
		"ExampleSectorShrubSmall",
		Vector2i(0, 0),
		Vector2(72.0, -28.0),
		0.14,
		SHRUB_PATH
	)
	_add_decor(
		decor_root,
		terrain,
		"ExampleSectorShrubLarge",
		Vector2i(-1, 1),
		Vector2(-48.0, 36.0),
		0.22,
		SHRUB_PATH
	)
	_add_decor(
		decor_root,
		terrain,
		"ExampleSectorCrateProp",
		Vector2i(2, 0),
		Vector2(-64.0, 18.0),
		0.16,
		CRATE_PATH
	)


func _add_decor(
	root: Node2D,
	terrain: TileMapLayer,
	node_name: String,
	coords: Vector2i,
	offset: Vector2,
	uniform: float,
	sprite: String
) -> void:
	var prop := HexDecorProp.new()
	prop.name = node_name
	prop.coord_layer = terrain
	prop.sprite_path = sprite
	prop.uniform_scale = uniform
	prop.hex_coords = coords
	root.add_child(prop)
	prop.position = terrain.map_to_local(coords) + offset


func _spawn_marker(marker_root: Node2D, terrain: TileMapLayer) -> void:
	var marker := HexMapMarker.new()
	marker.name = "ExampleSectorHomesteadPoi"
	marker.coord_layer = terrain
	marker.hex_coords = Vector2i(1, 0)
	marker.is_poi = true
	marker.poi_id = "example_homestead"
	marker.poi_name = "Example Homestead"
	marker.zone_id = "example_sector"
	marker.hazard_level = 0.5
	marker_root.add_child(marker)
	marker.position = terrain.map_to_local(Vector2i(1, 0))
