extends RefCounted
class_name MacroVisibilityService

## Owns the authoritative visible/explored distinction. Rendering consumes the
## resulting dictionary; it never decides what the player can know.

var world_state: RuntimeStateStore
const _NpcSimulator := preload("res://WorldCore/MacroNpcSimulator.gd")
var world_generator: HexWorldGenerator
var vision_radius: int = 2
var visible_hexes: Dictionary = {}


func configure(
	state: RuntimeStateStore,
	generator: HexWorldGenerator,
	radius: int
) -> void:
	world_state = state
	world_generator = generator
	vision_radius = maxi(1, radius)


func update_fog(
	center_coords: Vector2i,
	actor_context: Dictionary,
	log_callback: Callable = Callable()
) -> Array[Vector2i]:
	visible_hexes.clear()
	var newly_explored: Array[Vector2i] = []
	if world_state == null or world_generator == null:
		return newly_explored
	var clock := world_state.get_world_time_snapshot()
	var phase := GameTimeRules.phase_for_hour(int(clock.get("hour", 8)))
	var light_factor := 0.55 if phase == "night" else (0.75 if phase in ["dawn", "dusk"] else 1.0)
	if actor_context.get("capabilities", []).has("light_source"):
		light_factor = minf(1.15, light_factor + 0.25)
	for coords in _NpcSimulator.coords_in_radius(center_coords, vision_radius):
		if (
			world_generator.zone_bounds_enabled
			and not world_generator.is_in_zone_bounds(coords)
		):
			continue
		var hex_data := world_generator.get_hex_at(coords)
		var obstruction_factor := 1.0
		if hex_data.structure_layer != GameEnums.MacroStructureLayer.NONE:
			obstruction_factor *= 0.82
		if hex_data.flora_layer == GameEnums.MacroFloraLayer.TREES:
			obstruction_factor *= 0.78
		if hex_data.rock_layer == GameEnums.MacroRockLayer.HILLS:
			obstruction_factor *= 0.86
		if not WorldPerceptionQuery.can_see(
			center_coords,
			coords,
			vision_radius,
			light_factor,
			obstruction_factor
		):
			continue
		visible_hexes[coords] = true
		if not hex_data.is_explored:
			hex_data.is_explored = true
			world_state.set_hex_record(coords, hex_data.to_state())
			newly_explored.append(coords)
	if log_callback.is_valid():
		log_callback.call(
			"Fog update @%s: %d visible hex(es), %d newly explored."
			% [str(center_coords), visible_hexes.size(), newly_explored.size()]
		)
	return newly_explored


func is_visible(coords: Vector2i) -> bool:
	return visible_hexes.has(coords)


func is_explored(coords: Vector2i) -> bool:
	return world_generator != null and world_generator.get_hex_at(coords).is_explored
