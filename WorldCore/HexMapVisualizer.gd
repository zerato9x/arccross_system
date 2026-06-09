extends TileMapLayer
class_name HexMapVisualizer

@export var world_generator: HexWorldGenerator

# Map the Lexicon biomes directly to the Source IDs Godot assigns your individual images.
# NOTE: You must check the TileSet panel to see which ID Godot gave to which image.
const BIOME_TO_SOURCE_ID = {
	GameEnums.GridBiome.PLAINS: 0,  
	GameEnums.GridBiome.FOREST: 1,  
	GameEnums.GridBiome.HILLS: 2,   
	GameEnums.GridBiome.MUD: 3,     
	GameEnums.GridBiome.SWAMP: 4    
}

# Because each PNG is just a single tile, the internal coordinate is always zero.
const SINGLE_TILE_COORD = Vector2i(0, 0)

var rendered_cells: Dictionary = {}
var poi_markers: Dictionary = {}

func _ready() -> void:
	if not world_generator:
		push_error("Visualizer cannot see the Cartographer. Hook it up.")
		return

## Call this to render a "Chunk" of the map around the player
func render_radius(center_coords: Vector2i, radius: int) -> void:
	for q in range(-radius, radius + 1):
		for r in range(max(-radius, -q - radius), min(radius, -q + radius) + 1):
			var check_coord = center_coords + Vector2i(q, r)
			_paint_single_hex(check_coord)
	_prune_outside_radius(center_coords, radius + 2)

func _paint_single_hex(coords: Vector2i) -> void:
	var hex_data: MacroHexData = world_generator.get_hex_at(coords)
	
	# THE FIX: We grab the dynamic Source ID instead of an Atlas Coordinate
	var source_id: int = BIOME_TO_SOURCE_ID[hex_data.biome]
	
	# We pass the dynamic Source ID and the locked (0,0) Atlas Coordinate
	set_cell(coords, source_id, SINGLE_TILE_COORD)
	rendered_cells[coords] = true
	
	if hex_data.is_poi:
		_mark_poi_visually(coords, hex_data.poi_name)

func _mark_poi_visually(coords: Vector2i, poi_name: String) -> void:
	if poi_markers.has(coords):
		poi_markers[coords].text = "[ " + poi_name + " ]"
		return

	# In a graybox, we just spawn a label over the hex so you know it's special
	var pixel_pos = map_to_local(coords) # Godot's built-in Hex-to-Pixel math!
	
	var label = Label.new()
	label.text = "[ " + poi_name + " ]"
	label.position = pixel_pos - Vector2(50, 10) # Center it roughly
	add_child(label)
	poi_markers[coords] = label

func _prune_outside_radius(center_coords: Vector2i, radius: int) -> void:
	for coords in rendered_cells.keys().duplicate():
		if _hex_distance(center_coords, coords) <= radius:
			continue
		erase_cell(coords)
		rendered_cells.erase(coords)
		if poi_markers.has(coords):
			poi_markers[coords].queue_free()
			poi_markers.erase(coords)

func _hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	var delta := to_coords - from_coords
	return maxi(abs(delta.x), maxi(abs(delta.y), abs(delta.x + delta.y)))
