extends RefCounted
class_name WorldPerceptionQuery

## One neutral perception query for sight, sound, and physical traces. The
## renderer can choose how to present the answer; AI and player information
## consume the same attenuation rules.

static func can_see(
	observer_coords: Vector2i,
	target_coords: Vector2i,
	base_radius: int,
	light_factor: float = 1.0,
	obstruction_factor: float = 1.0
) -> bool:
	if base_radius <= 0:
		return false
	var distance := _hex_distance(observer_coords, target_coords)
	var reach := float(base_radius) * clampf(light_factor, 0.25, 1.2)
	# A directly adjacent hex is physically observable even when its own
	# structure/terrain reduces the useful sight distance beyond it. Applying
	# obstruction after the minimum reach made adjacent rubble/buildings remain
	# unexplored and therefore impossible to route to.
	reach = maxf(1.0, reach * clampf(obstruction_factor, 0.25, 1.0))
	return float(distance) <= reach


static func can_hear(
	signal_record: WorldSignalRecord,
	observer_coords: Vector2i,
	observer_hex: MacroHexData = null,
	source_hex: MacroHexData = null,
	acuity: float = 1.0
) -> bool:
	if signal_record == null:
		return false
	var distance := _hex_distance(observer_coords, signal_record.coords)
	if distance <= 0:
		return true
	var intensity := maxf(0.0, signal_record.intensity)
	var propagation := 1.0
	if observer_hex != null and observer_hex.road_mask != 0:
		propagation += 0.08
	if source_hex != null and source_hex.road_mask != 0:
		propagation += 0.12
	if observer_hex != null and observer_hex.structure_layer != GameEnums.MacroStructureLayer.NONE:
		propagation *= 0.82
	if source_hex != null and source_hex.structure_layer != GameEnums.MacroStructureLayer.NONE:
		propagation *= 0.82
	var received := intensity * propagation * exp(-float(distance) * 0.22)
	return received * clampf(acuity, 0.35, 2.0) >= 0.65


static func track_confidence(
	trace: Dictionary,
	now_minutes: int,
	capability: float = 1.0,
	weather_decay: float = 1.0
) -> float:
	if trace.is_empty():
		return 0.0
	var age := maxi(0, now_minutes - int(trace.get("created_minute", now_minutes)))
	if trace.has("age_minutes"):
		age = maxi(age, int(trace.get("age_minutes", 0)))
	var freshness := exp(-float(age) / maxf(1.0, 90.0 * weather_decay))
	return clampf(freshness * clampf(capability, 0.1, 2.0), 0.0, 1.0)


static func _hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	var delta := to_coords - from_coords
	return maxi(abs(delta.x), maxi(abs(delta.y), abs(delta.x + delta.y)))
