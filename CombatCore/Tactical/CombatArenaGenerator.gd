extends RefCounted
class_name CombatArenaGenerator

const DEFAULT_CATALOG := preload(
	"res://CombatCore/Tactical/combat_terrain_catalog.tres"
)
const _MapComposition := preload("res://CombatCore/Tactical/CombatMapComposition.gd")
const _MapVariantCatalog := preload("res://CombatCore/Tactical/TacticalMapVariantCatalog.gd")
const DEFAULT_VARIANT_CATALOG := preload("res://CombatCore/Tactical/default_tactical_map_variant_catalog.tres")

const AXIAL_DIRECTIONS := [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]

var catalog: TacticalTerrainCatalog
var variant_catalog = DEFAULT_VARIANT_CATALOG


func _init(profile_catalog: TacticalTerrainCatalog = null) -> void:
	catalog = profile_catalog if profile_catalog != null else DEFAULT_CATALOG


func generate(encounter: CombatEncounterRecord) -> CombatArenaState:
	var arena := CombatArenaState.new()
	var topology := CombatTopologyCatalog.load_profile(encounter.topology_id)
	arena.configure_topology(topology)
	arena.source_coords = encounter.source_coords
	arena.orientation_step = _orientation_step(
		encounter.source_coords - encounter.approach_from
	)
	arena.baseline_seed = _stable_seed(encounter)
	arena.backdrop_asset_path = _backdrop_path(encounter)
	arena.lighting = _lighting_descriptor(encounter.world_time)
	var layer_assets := _layer_assets(encounter.presentation)
	for index in range(arena.sector_count()):
		var sector := TacticalSectorRecord.new()
		sector.index = index
		sector.coords = arena.coords_for(index)
		_configure_base(sector, encounter.center_hex, layer_assets)
		if topology.movement_policy == CombatTopologyProfile.MovementPolicy.LINEAR_NO_PASS:
			sector.cover_edges.clear()
			sector.object_state.clear()
			sector.blocked = false
			sector.spawnable = true
		arena.sectors.append(sector)

	if topology.movement_policy != CombatTopologyProfile.MovementPolicy.LINEAR_NO_PASS:
		_apply_road(arena, encounter.center_hex, layer_assets)
		_apply_water(arena, encounter, layer_assets)
		_apply_scattered_layers(arena, encounter.center_hex, layer_assets)
		_apply_presentation_props(arena, encounter.presentation, arena.baseline_seed)
	_apply_traps(arena, encounter.traps)
	_apply_persistent_state(arena, encounter.center_hex)
	_configure_edges(arena)
	arena.map_composition = _compose_map(arena, encounter).to_dict()
	return arena


func _compose_map(arena: CombatArenaState, encounter: CombatEncounterRecord):
	var result = _MapComposition.new()
	result.map_seed = arena.baseline_seed
	var hex := encounter.center_hex
	var family := str(hex.terrain_tile if hex != null else 0)
	var variant := variant_catalog.choose(family, result.map_seed)
	result.variant_id = str(variant.get("id", "%s_00" % family))
	var presentation_assets := _layer_assets(encounter.presentation)
	var source_ground := _source_ground_path(hex, encounter.presentation)
	var catalog_ground := catalog.ground_asset_path(int(hex.terrain_tile)) if hex != null else ""
	var overrides: Dictionary = variant.get("overrides", {})
	var override_ground := str(overrides.get("ground_path", variant.get("override_ground_path", "")))
	var variant_ground := str(variant.get("base_ground_path", ""))
	var generic_ground := "res://Asset/HexTiles/_BIOMES/biome_plains/bg_plains.png"
	var ground_path := ""
	var ground_source := ""
	if not override_ground.is_empty() and ResourceLoader.exists(override_ground):
		ground_path = override_ground
		ground_source = "combat_variant_override"
	elif not catalog_ground.is_empty() and ResourceLoader.exists(catalog_ground):
		ground_path = catalog_ground
		ground_source = "combat_terrain_catalog"
	elif not source_ground.is_empty() and ResourceLoader.exists(source_ground):
		ground_path = source_ground
		ground_source = "source_hex"
	elif not variant_ground.is_empty() and ResourceLoader.exists(variant_ground):
		ground_path = variant_ground
		ground_source = "combat_variant"
	if ground_path.is_empty() or not ResourceLoader.exists(ground_path):
		ground_path = generic_ground if ResourceLoader.exists(generic_ground) else arena.backdrop_asset_path
		ground_source = "generic_fallback"
	result.base_ground_path = ground_path
	result.base_ground_modulation = _color_value(variant.get("palette_modulation", Color.WHITE))
	result.palette = variant.get("palette", {}).duplicate(true)
	result.variant_overrides = overrides.duplicate(true)
	var source_road := str(presentation_assets.get("road", ""))
	var override_road := str(overrides.get("road_path", variant.get("road_overlay_path", "")))
	var variant_road := _variant_layer_path(variant, "road")
	var road_path := ""
	var road_source := ""
	if not override_road.is_empty() and ResourceLoader.exists(override_road):
		road_path = override_road
		road_source = "combat_variant_override"
	elif not source_road.is_empty() and ResourceLoader.exists(source_road):
		road_path = source_road
		road_source = "source_hex"
	elif not variant_road.is_empty() and ResourceLoader.exists(variant_road):
		road_path = variant_road
		road_source = "combat_variant"
	result.road_overlay_path = road_path
	result.source_provenance = {
		"ground": ground_source,
		"source_hex": source_ground,
		"override": override_ground,
		"road": road_source,
		"source_road": source_road,
		"variant_id": result.variant_id,
		"family": family,
	}
	result.layer_metadata = variant.get("layers", []).duplicate(true)
	for sector in arena.sectors:
		if sector.surface_id == "road":
			result.road_cells.append(sector.coords)
		if sector.surface_id in ["shallow_water", "deep_water"]:
			result.water_cells.append(sector.coords)
		result.sector_facts[str(sector.index)] = {
			"surface_id": sector.surface_id,
			"cover_edges": sector.cover_edges.duplicate(true),
			"hazards": sector.hazard_state.duplicate(true),
			"blocked": sector.blocked,
		}
		if not sector.object_state.is_empty():
			var instance := sector.object_state.duplicate(true)
			instance["coords"] = sector.coords
			result.props.append(instance)
			result.prop_instances.append({
				"id": str(instance.get("id", "prop_%d" % sector.index)),
				"coords": sector.coords,
				"asset_path": str(instance.get("asset_path", "")),
				"presentation_only": bool(instance.get("decorative", false)),
				"layer": int(instance.get("layer", 60)),
			})
	if hex != null:
		var landmark_id := hex.landmark_id
		if landmark_id.is_empty() and hex.is_poi:
			landmark_id = hex.poi_id
		if landmark_id.is_empty() and hex.structure_layer != GameEnums.MacroStructureLayer.NONE:
			landmark_id = "structure_%d" % int(hex.structure_layer)
		if not landmark_id.is_empty():
			var landmark_asset := _landmark_asset_path(hex, encounter.presentation, variant)
			result.dominant_landmark = {
				"id": landmark_id,
				"label": hex.poi_name if hex.is_poi and not hex.poi_name.is_empty() else landmark_id,
				"coords": Vector2i(floori(float(arena.width) / 2.0), floori(float(arena.height) / 2.0)),
				"asset_path": landmark_asset,
				"layer": int(variant.get("landmark_layer", 55)),
				"scale": float(variant.get("landmark_scale", 0.72)),
				"offset": variant.get("landmark_offset", Vector2.ZERO),
				"provenance": "source_hex" if not landmark_asset.is_empty() else "combat_variant_or_fallback",
			}
			result.landmark_instances.append(result.dominant_landmark.duplicate(true))
	return result


static func _source_ground_path(hex: HexRecord, presentation: Dictionary) -> String:
	var authored := str(hex.terrain_sprite_path if hex != null else "")
	if not authored.is_empty() and ResourceLoader.exists(authored):
		return authored
	for layer in presentation.get("layers", []):
		if layer is Dictionary and str(layer.get("kind", "")) == "terrain":
			var path := str(layer.get("path", ""))
			if not path.is_empty() and ResourceLoader.exists(path):
				return path
	return authored


static func _variant_layer_path(variant: Dictionary, kind: String) -> String:
	for layer in variant.get("layers", []):
		if layer is Dictionary and str(layer.get("kind", "")) == kind:
			return str(layer.get("path", ""))
	return ""


static func _landmark_asset_path(hex: HexRecord, presentation: Dictionary, variant: Dictionary) -> String:
	var authored := str(hex.structure_sprite_path if hex != null else "")
	if not authored.is_empty() and ResourceLoader.exists(authored):
		return authored
	var override_path := str(variant.get("overrides", {}).get("landmark_path", ""))
	if not override_path.is_empty() and ResourceLoader.exists(override_path):
		return override_path
	for layer in presentation.get("layers", []):
		if layer is Dictionary and str(layer.get("kind", "")) == "structure":
			var path := str(layer.get("path", ""))
			if not path.is_empty() and ResourceLoader.exists(path):
				return path
	return ""


static func _color_value(value: Variant) -> Color:
	if value is Color:
		return value
	if value is String and not str(value).is_empty():
		return Color(str(value))
	return Color.WHITE


func _configure_base(
	sector: TacticalSectorRecord,
	hex: HexRecord,
	assets: Dictionary
) -> void:
	var profile := catalog.terrain(hex.terrain_tile) if hex != null else {}
	sector.surface_id = str(profile.get("id", "plains"))
	sector.surface_label = str(profile.get("label", "PLAINS"))
	sector.ground_asset_path = str(assets.get("terrain", ""))
	sector.movement_modifier = int(profile.get("movement_modifier", 0))
	sector.visibility_penalty = float(profile.get("visibility_penalty", 0.0))
	sector.concealment = float(profile.get("concealment", 0.0))
	sector.opaque = bool(profile.get("opaque", false))
	sector.blocked = bool(profile.get("blocked", false)) or (hex != null and hex.impassable)
	sector.spawnable = bool(profile.get("spawnable", not sector.blocked)) and not sector.blocked
	sector.hazard_state = _hazard_fields(profile)


func _apply_road(
	arena: CombatArenaState,
	hex: HexRecord,
	assets: Dictionary
) -> void:
	if hex == null or hex.road_mask <= 0:
		return
	var ports: Array[Vector2i] = []
	for direction_index in range(6):
		if (hex.road_mask & (1 << direction_index)) != 0:
			ports.append(_edge_port_for_direction(arena, direction_index))
	if ports.is_empty():
		return
	for coords in _connected_paths(arena, ports):
		var sector := arena.sector_at(coords)
		sector.surface_id = "road"
		sector.surface_label = "DIRT ROAD" if hex.composition_role == "dirt_service_spur" else "ROAD"
		sector.overlay_asset_path = str(assets.get("road", ""))
		sector.movement_modifier = mini(sector.movement_modifier, -1)
		sector.spawnable = not sector.blocked
		sector.hazard_state["road_mask"] = hex.road_mask


func _apply_water(
	arena: CombatArenaState,
	encounter: CombatEncounterRecord,
	assets: Dictionary
) -> void:
	var hex := encounter.center_hex
	if hex == null or hex.water_layer == GameEnums.MacroWaterLayer.NONE:
		return
	var profile := catalog.water(hex.water_layer)
	var ports: Array[Vector2i] = []
	for direction_index in range(mini(6, encounter.neighbor_hexes.size())):
		var neighbor := encounter.neighbor_hexes[direction_index]
		if neighbor != null and neighbor.water_layer == hex.water_layer:
			ports.append(_edge_port_for_direction(arena, direction_index))
	if ports.is_empty():
		# A standalone authored water hex is a local pool crossing the center.
		ports = [Vector2i(3, 1), Vector2i(3, 3)]
	for coords in _connected_paths(arena, ports):
		var sector := arena.sector_at(coords)
		_apply_profile(sector, profile)
		sector.overlay_asset_path = str(assets.get("water", ""))


func _apply_scattered_layers(
	arena: CombatArenaState,
	hex: HexRecord,
	assets: Dictionary
) -> void:
	if hex == null:
		return
	_apply_scatter(arena, catalog.flora(hex.flora_layer), str(assets.get("flora", "")), "flora", arena.baseline_seed + 101)
	_apply_scatter(arena, catalog.rock(hex.rock_layer), str(assets.get("rock", "")), "rock", arena.baseline_seed + 211)
	_apply_scatter(arena, catalog.structure(hex.structure_layer), str(assets.get("structure", "")), "structure", arena.baseline_seed + 307)


func _apply_scatter(
	arena: CombatArenaState,
	profile: Dictionary,
	asset_path: String,
	kind: String,
	seed_value: int
) -> void:
	if profile.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var candidates: Array[TacticalSectorRecord] = []
	for sector in arena.sectors:
		if sector.coords.x in [0, arena.width - 1]:
			continue
		if sector.surface_id in ["road", "shallow_water", "deep_water"]:
			continue
		candidates.append(sector)
	if candidates.is_empty():
		return
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var current := candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = current
	var count := clampi(roundi(float(profile.get("density", 0.0)) * candidates.size()), 1, candidates.size())
	for index in range(count):
		var sector := candidates[index]
		_apply_profile(sector, profile)
		if not asset_path.is_empty():
			sector.object_state = {
				"id": "%s_%02d" % [kind, sector.index],
				"type": str(profile.get("object_type", kind)),
				"label": str(profile.get("label", kind.capitalize())),
				"asset_path": asset_path,
				"durability": float(profile.get("durability", 0.0)),
				"persistent": true,
			}
		var blocked_fraction := float(profile.get("blocked_fraction", 0.0))
		if blocked_fraction > 0.0 and rng.randf() < blocked_fraction:
			sector.blocked = true
			sector.spawnable = false
		if not sector.object_state.is_empty():
			sector.cover_edges = _cover_for_object(profile, rng)


func _apply_presentation_props(
	arena: CombatArenaState,
	presentation: Dictionary,
	seed_value: int
) -> void:
	var scene: Dictionary = presentation.get("scene", {})
	var props: Array = scene.get("props", [])
	for prop_index in range(props.size()):
		var prop: Variant = props[prop_index]
		if not prop is Dictionary:
			continue
		var anchor: Vector2 = prop.get("anchor", Vector2(0.5, 0.5))
		var coords := Vector2i(
			clampi(roundi(anchor.x * float(arena.width - 1)), 1, maxi(1, arena.width - 2)),
			clampi(roundi(anchor.y * float(arena.height - 1)), 0, arena.height - 1)
		)
		var sector := arena.sector_at(coords)
		if sector == null or not sector.object_state.is_empty():
			sector = _nearest_free_object_sector(arena, coords, seed_value + prop_index)
		if sector == null:
			continue
		sector.object_state = {
			"id": str(prop.get("id", "prop_%02d" % prop_index)),
			"type": "poi_prop",
			"label": str(prop.get("label", "Terrain fixture")),
			"asset_path": str(prop.get("sprite_path", "")),
			"durability": 12.0,
			"persistent": true,
			"decorative": bool(prop.get("decorative", false)),
		}
		if not bool(prop.get("decorative", false)):
			sector.cover_edges = {"north": 0.5, "east": 0.5, "south": 0.5, "west": 0.5}


func _apply_traps(arena: CombatArenaState, traps: Array[Dictionary]) -> void:
	for trap_index in range(traps.size()):
		var trap := traps[trap_index]
		var coords: Vector2i = trap.get("sector", Vector2i(1, floori(float(arena.height) / 2.0)))
		if not arena.contains(coords):
			coords = Vector2i(mini(1, arena.width - 1), floori(float(arena.height) / 2.0))
		var sector := arena.sector_at(coords)
		sector.trap_state = trap.duplicate(true)
		sector.trap_state["armed"] = bool(trap.get("armed", true))
		sector.trap_state["id"] = str(trap.get("instance_id", "trap_%02d" % trap_index))


func _apply_persistent_state(arena: CombatArenaState, hex: HexRecord) -> void:
	if hex == null or hex.combat_site_state.is_empty():
		return
	var stored_topology := str(hex.combat_site_state.get("topology_id", ""))
	if not stored_topology.is_empty() and stored_topology != arena.topology_id:
		return
	if stored_topology.is_empty() and arena.topology_id != "squad_7x5":
		return
	arena.mutations = hex.combat_site_state.duplicate(true)
	var patches: Dictionary = hex.combat_site_state.get("sector_patches", {})
	for key in patches.keys():
		var index := int(key)
		if index < 0 or index >= arena.sectors.size():
			continue
		var patch: Dictionary = patches[key]
		var sector := arena.sectors[index]
		if patch.has("object_state"):
			sector.object_state = patch.object_state.duplicate(true)
		if patch.has("hazard_state"):
			sector.hazard_state = patch.hazard_state.duplicate(true)
		if patch.has("trap_state"):
			sector.trap_state = patch.trap_state.duplicate(true)
		if patch.has("surface_id"):
			sector.surface_id = str(patch.surface_id)
		if patch.has("blocked"):
			sector.blocked = bool(patch.blocked)
		if patch.has("cover_edges"):
			sector.cover_edges = patch.cover_edges.duplicate(true)
	# Terminal handoffs are not active occupants, but their exact sector remains
	# part of the persisted site so macro conversation/looting can find it.
	for raw_handoff in arena.mutations.get("incapacitated", []):
		if not raw_handoff is Dictionary:
			continue
		var handoff_index := int(raw_handoff.get("sector_index", -1))
		var handoff_id := str(raw_handoff.get("actor_id", ""))
		if handoff_index >= 0 and handoff_index < arena.sectors.size() and not handoff_id.is_empty():
			if handoff_id not in arena.sectors[handoff_index].incapacitated_entity_ids:
				arena.sectors[handoff_index].incapacitated_entity_ids.append(handoff_id)
	for raw_body in arena.mutations.get("bodies", []):
		if not raw_body is Dictionary:
			continue
		var body_index := int(raw_body.get("sector_index", -1))
		var body_id := str(raw_body.get("actor_id", ""))
		if body_index >= 0 and body_index < arena.sectors.size() and not body_id.is_empty():
			if body_id not in arena.sectors[body_index].body_entity_ids:
				arena.sectors[body_index].body_entity_ids.append(body_id)
	for raw_surrender in arena.mutations.get("surrendered", []):
		if not raw_surrender is Dictionary:
			continue
		var surrender_index := int(raw_surrender.get("sector_index", -1))
		var surrender_id := str(raw_surrender.get("actor_id", ""))
		if surrender_index >= 0 and surrender_index < arena.sectors.size() and not surrender_id.is_empty():
			if surrender_id not in arena.sectors[surrender_index].surrendered_entity_ids:
				arena.sectors[surrender_index].surrendered_entity_ids.append(surrender_id)


func _configure_edges(arena: CombatArenaState) -> void:
	for y in range(arena.height):
		var player_edge := arena.sector_at(Vector2i(0, y))
		player_edge.escape_side = "player" if not player_edge.blocked else ""
		player_edge.territory_side = "player"
		player_edge.spawnable = player_edge.spawnable and not player_edge.blocked
		var enemy_edge := arena.sector_at(Vector2i(arena.width - 1, y))
		enemy_edge.escape_side = "enemy" if not enemy_edge.blocked else ""
		enemy_edge.territory_side = "enemy"
		enemy_edge.spawnable = enemy_edge.spawnable and not enemy_edge.blocked
	for sector in arena.sectors:
		if sector.coords.x > 0 and sector.coords.x < arena.width - 1:
			sector.territory_side = "neutral"


func _apply_profile(sector: TacticalSectorRecord, profile: Dictionary) -> void:
	if profile.is_empty():
		return
	sector.surface_id = str(profile.get("id", sector.surface_id))
	sector.surface_label = str(profile.get("label", sector.surface_label))
	sector.movement_modifier += int(profile.get("movement_modifier", 0))
	sector.elevation = maxi(sector.elevation, int(profile.get("elevation", 0)))
	sector.visibility_penalty = clampf(sector.visibility_penalty + float(profile.get("visibility_penalty", 0.0)), 0.0, 1.0)
	sector.concealment = clampf(sector.concealment + float(profile.get("concealment", 0.0)), 0.0, 1.0)
	sector.opaque = sector.opaque or bool(profile.get("opaque", false))
	sector.blocked = sector.blocked or bool(profile.get("blocked", false))
	sector.spawnable = sector.spawnable and bool(profile.get("spawnable", not sector.blocked))
	for key in _hazard_fields(profile).keys():
		sector.hazard_state[key] = profile[key]


func _hazard_fields(profile: Dictionary) -> Dictionary:
	var fields: Dictionary = {}
	for key in ["trip_risk", "contaminates_wounds", "cold_exposure", "leaves_tracks", "wet_exposure"]:
		if profile.has(key):
			fields[key] = profile[key]
	return fields


func _cover_for_object(profile: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var direction: String = ["north", "east", "south", "west"][rng.randi_range(0, 3)]
	var strength := 0.65 if str(profile.get("object_type", "")).contains("hard") else 0.35
	return {direction: strength}


func _nearest_free_object_sector(
	arena: CombatArenaState,
	origin: Vector2i,
	_seed_value: int
) -> TacticalSectorRecord:
	for radius in range(1, 5):
		for y in range(arena.height):
			for x in range(1, arena.width - 1):
				var coords := Vector2i(x, y)
				if absi(coords.x - origin.x) + absi(coords.y - origin.y) != radius:
					continue
				var sector := arena.sector_at(coords)
				if sector != null and sector.object_state.is_empty():
					return sector
	return null


func _layer_assets(presentation: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for layer in presentation.get("layers", []):
		if layer is Dictionary:
			var kind := str(layer.get("kind", ""))
			if not kind.is_empty() and not result.has(kind):
				result[kind] = str(layer.get("path", ""))
	return result


func _backdrop_path(encounter: CombatEncounterRecord) -> String:
	var scene: Dictionary = encounter.presentation.get("scene", {})
	var path := str(scene.get("background_path", ""))
	if not path.is_empty():
		return path
	return str(_layer_assets(encounter.presentation).get("terrain", ""))


func _lighting_descriptor(world_time: Dictionary) -> Dictionary:
	var hour := int(world_time.get("hour", 12))
	var phase := "day"
	var visibility := 0.0
	if hour < 6 or hour >= 20:
		phase = "night"
		visibility = 0.22
	elif hour < 8 or hour >= 18:
		phase = "twilight"
		visibility = 0.10
	return {"phase": phase, "visibility_penalty": visibility, "hour": hour}


func _stable_seed(encounter: CombatEncounterRecord) -> int:
	var hex := encounter.center_hex
	return absi(("%s|%s|%s|%s|%s|%s" % [
		encounter.world_seed,
		str(encounter.source_coords),
		hex.zone_id if hex != null else "",
		hex.world_generation_version if hex != null else 0,
		hex.visual_variant_hash if hex != null else 0,
		hex.stamp_instance_id if hex != null else "",
	]).hash())


func _orientation_step(delta: Vector2i) -> int:
	var index := AXIAL_DIRECTIONS.find(delta)
	return index if index >= 0 else 0


func _edge_port_for_direction(arena: CombatArenaState, direction_index: int) -> Vector2i:
	var incoming_direction := (arena.orientation_step + 3) % 6
	var relative := (direction_index - incoming_direction + 6) % 6
	var center_x := floori(float(arena.width) / 2.0)
	var center_y := floori(float(arena.height) / 2.0)
	match relative:
		0:
			return Vector2i(0, center_y)
		1:
			return Vector2i(maxi(0, center_x - 1), 0)
		2:
			return Vector2i(mini(arena.width - 1, center_x + 1), 0)
		3:
			return Vector2i(arena.width - 1, center_y)
		4:
			return Vector2i(mini(arena.width - 1, center_x + 1), arena.height - 1)
		_:
			return Vector2i(maxi(0, center_x - 1), arena.height - 1)


func _connected_paths(arena: CombatArenaState, ports: Array[Vector2i]) -> Array[Vector2i]:
	var center := Vector2i(floori(float(arena.width) / 2.0), floori(float(arena.height) / 2.0))
	var cells: Array[Vector2i] = [center]
	for port in ports:
		var cursor := port
		while cursor.x != center.x:
			if cursor not in cells:
				cells.append(cursor)
			cursor.x += 1 if cursor.x < center.x else -1
		while cursor.y != center.y:
			if cursor not in cells:
				cells.append(cursor)
			cursor.y += 1 if cursor.y < center.y else -1
		if cursor not in cells:
			cells.append(cursor)
	return cells
