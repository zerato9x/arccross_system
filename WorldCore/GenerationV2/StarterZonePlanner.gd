extends RefCounted
class_name StarterZonePlanner

const DIRECTIONS := HexCoordUtils.AXIAL_DIRECTIONS
const _Stamp := preload("res://WorldCore/GenerationV2/HexStampTemplate.gd")


static func build_plan(
	zone_seed: String,
	radius: int,
	start_coords: Vector2i,
	outward_coords: Vector2i,
	hexes: Dictionary,
	profile: ZoneGenerationProfile,
	include_settlement: bool = false
) -> GeneratedZonePlan:
	var plan := GeneratedZonePlan.new()
	plan.profile_id = profile.profile_id
	plan.zone_seed = zone_seed
	plan.radius = radius
	for coords in HexCoordUtils.cells_in_radius(radius):
		plan.cell_roles[coords] = "quiet_plains"

	var orientation := _nearest_direction_index(outward_coords)
	plan.has_settlement = include_settlement
	if include_settlement:
		var stamp := _Stamp.starter_settlement(orientation)
		# Main-node logistics are authored truth, not seed output. The alpha
		# settlement occupies the same rotated position in every campaign.
		plan.settlement_coords = _rotate_axial(Vector2i(2, 0), orientation)
		plan.gameplay_anchor_coords = plan.settlement_coords + stamp.gameplay_anchor_offset
		_apply_stamp(plan, stamp)
	else:
		plan.settlement_coords = Vector2i.ZERO
		plan.gameplay_anchor_coords = Vector2i.ZERO

	# The arterial is a fixed rotated skeleton. Seeded terrain may grow around
	# it, but hills, forests, arrival order, and discovery can never reroute it.
	var road_path := _build_fixed_spine(start_coords, outward_coords, orientation)
	_apply_road(plan, road_path)
	_add_service_spur(plan, radius, orientation)
	_place_rubble(plan, profile, hexes)
	_add_activity_traces(plan)
	_validate(plan, profile, start_coords, outward_coords, include_settlement)
	_validate_road_sockets(plan)
	_validate_required_reachability(plan, start_coords, hexes)
	return plan


static func _build_fixed_spine(
	start_coords: Vector2i,
	outward_coords: Vector2i,
	orientation: int
) -> Array[Vector2i]:
	var canonical_waypoints: Array[Vector2i] = [
		Vector2i(-12, 0),
		Vector2i(-8, 0),
		Vector2i(-5, 1),
		Vector2i(-2, 1),
		Vector2i.ZERO,
		Vector2i(3, 0),
		Vector2i(6, -1),
		Vector2i(9, -1),
		Vector2i(12, 0),
	]
	var waypoints: Array[Vector2i] = []
	for coords in canonical_waypoints:
		waypoints.append(_rotate_axial(coords, orientation))
	waypoints[0] = start_coords
	waypoints[waypoints.size() - 1] = outward_coords
	var path: Array[Vector2i] = []
	for index in range(waypoints.size() - 1):
		for coords in _axial_line(waypoints[index], waypoints[index + 1]):
			if path.is_empty() or path.back() != coords:
				path.append(coords)
	return path


static func _pick_settlement_anchor(
	zone_seed: String,
	radius: int,
	start_coords: Vector2i,
	outward_coords: Vector2i,
	stamp: HexStampTemplate,
	hexes: Dictionary
) -> Vector2i:
	var candidates: Array[Dictionary] = []
	for coords in HexCoordUtils.cells_in_radius(radius - 3):
		if HexCoordUtils.distance(coords, start_coords) < 5:
			continue
		if HexCoordUtils.distance(coords, outward_coords) < 5:
			continue
		if not _stamp_fits(coords, stamp, radius):
			continue
		var hex: MacroHexData = hexes.get(coords)
		if hex == null:
			continue
		var line_distance := _distance_to_segment(coords, start_coords, outward_coords)
		var terrain_penalty := 8.0 if hex.impassable else 0.0
		terrain_penalty += 2.0 if hex.rock_layer == GameEnums.MacroRockLayer.HILLS else 0.0
		var jitter := float(absi((zone_seed + ":settlement:" + str(coords)).hash()) % 1000) / 1000.0
		candidates.append({
			"coords": coords,
			"score": line_distance * 4.0 + terrain_penalty + jitter,
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", INF)) < float(b.get("score", INF))
	)
	return candidates[0].get("coords", Vector2i.ZERO) if not candidates.is_empty() else Vector2i.ZERO


static func _stamp_fits(anchor: Vector2i, stamp: HexStampTemplate, radius: int) -> bool:
	for entry in stamp.cells:
		var offset: Vector2i = entry.get("offset", Vector2i.ZERO)
		if not HexCoordUtils.is_in_radius(anchor + offset, radius):
			return false
	return true


static func _apply_stamp(plan: GeneratedZonePlan, stamp: HexStampTemplate) -> void:
	for entry in stamp.cells:
		var coords: Vector2i = plan.settlement_coords + entry.get("offset", Vector2i.ZERO)
		var cell := entry.duplicate(true)
		cell["template_id"] = stamp.template_id
		cell["orientation"] = stamp.orientation
		cell["stamp_instance_id"] = "%s@%d,%d:r%d" % [
			stamp.template_id, plan.settlement_coords.x, plan.settlement_coords.y, stamp.orientation
		]
		plan.stamp_cells[coords] = cell
		plan.cell_roles[coords] = str(cell.get("role", "settlement_frame"))


static func _find_path(
	start: Vector2i,
	goal: Vector2i,
	radius: int,
	hexes: Dictionary,
	salt: String
) -> Array[Vector2i]:
	var frontier: Array[Vector2i] = [start]
	var came_from: Dictionary = {start: start}
	var cost_so_far: Dictionary = {start: 0.0}
	while not frontier.is_empty():
		frontier.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var a_score := float(cost_so_far.get(a, INF)) + float(HexCoordUtils.distance(a, goal))
			var b_score := float(cost_so_far.get(b, INF)) + float(HexCoordUtils.distance(b, goal))
			if is_equal_approx(a_score, b_score):
				return (salt + str(a)).hash() < (salt + str(b)).hash()
			return a_score < b_score
		)
		var current: Vector2i = frontier.pop_front()
		if current == goal:
			break
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if not HexCoordUtils.is_in_radius(next, radius):
				continue
			var hex: MacroHexData = hexes.get(next)
			var step_cost := 1.0
			if hex != null:
				step_cost += 8.0 if hex.impassable else 0.0
				step_cost += 2.0 if hex.rock_layer == GameEnums.MacroRockLayer.HILLS else 0.0
				step_cost += 0.75 if hex.flora_layer == GameEnums.MacroFloraLayer.TREES else 0.0
			step_cost += float(absi((salt + str(next)).hash()) % 31) / 100.0
			var new_cost := float(cost_so_far.get(current, 0.0)) + step_cost
			if not cost_so_far.has(next) or new_cost < float(cost_so_far[next]):
				cost_so_far[next] = new_cost
				came_from[next] = current
				if not frontier.has(next):
					frontier.append(next)
	if not came_from.has(goal):
		return _axial_line(start, goal)
	var reverse_path: Array[Vector2i] = []
	var cursor := goal
	while cursor != start:
		reverse_path.append(cursor)
		cursor = came_from[cursor]
	reverse_path.append(start)
	reverse_path.reverse()
	return reverse_path


static func _apply_road(plan: GeneratedZonePlan, path: Array[Vector2i]) -> void:
	var path_set: Dictionary = {}
	for coords in path:
		path_set[coords] = true
		if not str(plan.cell_roles.get(coords, "")).begins_with("settlement_"):
			plan.cell_roles[coords] = "paved_spine"
	for coords in path:
		var mask := 0
		for index in range(DIRECTIONS.size()):
			if path_set.has(coords + DIRECTIONS[index]):
				mask |= 1 << index
		plan.road_cells[coords] = mask


static func _add_service_spur(plan: GeneratedZonePlan, radius: int, orientation: int) -> void:
	# Start at the nearest paved cell outside any settlement footprint, then
	# pick a free side socket. This keeps the dirt branch legible beside the
	# arterial instead of hiding it underneath tents or structures.
	var junctions: Array[Vector2i] = []
	for coords in plan.road_cells.keys():
		if not plan.stamp_cells.has(coords):
			junctions.append(coords)
	junctions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (
			HexCoordUtils.distance(a, plan.gameplay_anchor_coords)
			< HexCoordUtils.distance(b, plan.gameplay_anchor_coords)
		)
	)
	var placed := false
	for junction in junctions:
		for offset in [2, 4, 1, 5, 0, 3]:
			var direction_index: int = posmod(orientation + int(offset), 6)
			var first: Vector2i = junction + Vector2i(DIRECTIONS[direction_index])
			var second: Vector2i = first + Vector2i(DIRECTIONS[direction_index])
			if not HexCoordUtils.is_in_radius(second, radius):
				continue
			if (
				plan.road_cells.has(first)
				or plan.stamp_cells.has(first)
				or plan.stamp_cells.has(second)
			):
				continue
			plan.road_cells[first] = 0
			plan.road_cells[second] = 0
			plan.cell_roles[first] = "dirt_service_spur"
			plan.cell_roles[second] = "dirt_service_spur"
			placed = true
			break
		if placed:
			break
	_recompute_road_masks(plan)


static func _recompute_road_masks(plan: GeneratedZonePlan) -> void:
	for coords in plan.road_cells.keys():
		var mask := 0
		for index in range(DIRECTIONS.size()):
			if plan.road_cells.has(Vector2i(coords) + Vector2i(DIRECTIONS[index])):
				mask |= 1 << index
		plan.road_cells[coords] = mask


static func _nearest_direction_index(outward_coords: Vector2i) -> int:
	var best_index := 0
	var best_distance := 999999
	for index in range(DIRECTIONS.size()):
		var scaled := Vector2i(DIRECTIONS[index]) * HexCoordUtils.distance_from_origin(outward_coords)
		var distance := HexCoordUtils.distance(scaled, outward_coords)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


static func _place_rubble(
	plan: GeneratedZonePlan,
	profile: ZoneGenerationProfile,
	hexes: Dictionary
) -> void:
	var candidates: Array[Dictionary] = []
	for coords in plan.cell_roles.keys():
		if plan.role_at(coords) != "quiet_plains":
			continue
		if plan.has_settlement and HexCoordUtils.distance(coords, plan.settlement_coords) <= 3:
			continue
		var hex: MacroHexData = hexes.get(coords)
		if hex == null or hex.impassable:
			continue
		var road_distance := _nearest_distance(coords, plan.road_cells.keys())
		var score := float(road_distance) * 1.4
		score += float(absi((plan.zone_seed + ":rubble:" + str(coords)).hash()) % 1000) / 1000.0
		candidates.append({"coords": coords, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", INF)) < float(b.get("score", INF))
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = (plan.zone_seed + ":rubble_budgets").hash()
	var search_count := rng.randi_range(profile.rubble_search_min, profile.rubble_search_max)
	var visual_count := rng.randi_range(profile.visual_rubble_min, profile.visual_rubble_max)
	for entry in candidates:
		var coords: Vector2i = entry.get("coords", Vector2i.ZERO)
		if plan.rubble_search_cells.size() < search_count:
			plan.rubble_search_cells.append(coords)
			plan.cell_roles[coords] = "rubble_search"
		elif plan.visual_rubble_cells.size() < visual_count:
			plan.visual_rubble_cells.append(coords)
			plan.cell_roles[coords] = "rubble_visual"
		else:
			break


static func _add_activity_traces(plan: GeneratedZonePlan) -> void:
	plan.trace_records = []
	if plan.has_settlement:
		plan.trace_records.append({
			"trace_id": "settlement_smoke",
			"type": "smoke",
			"coords": plan.settlement_coords,
			"created_minute": 0,
			"expires_minute": -1,
		})
	if not plan.rubble_search_cells.is_empty():
		plan.trace_records.append({
			"trace_id": "old_tracks",
			"type": "tracks",
			"coords": plan.rubble_search_cells[0],
			"created_minute": 0,
			"expires_minute": 24 * 60,
		})


static func _validate(
	plan: GeneratedZonePlan,
	profile: ZoneGenerationProfile,
	start_coords: Vector2i,
	outward_coords: Vector2i,
	require_settlement: bool
) -> void:
	var expected := 1 + 3 * plan.radius * (plan.radius + 1)
	if plan.cell_roles.size() != expected:
		plan.validation_errors.append("Expected %d cells, got %d." % [expected, plan.cell_roles.size()])
	if not plan.road_cells.has(start_coords) or not plan.road_cells.has(outward_coords):
		plan.validation_errors.append("Paved spine does not reach both required rims.")
	if require_settlement and not plan.road_cells.has(plan.gameplay_anchor_coords):
		plan.validation_errors.append("Paved spine does not cross the settlement anchor.")
	if require_settlement and plan.stamp_cells.size() < 13:
		plan.validation_errors.append("Required starter settlement stamp is missing.")
	if not require_settlement and not plan.stamp_cells.is_empty():
		plan.validation_errors.append("Non-settlement starter node contains an inhabited stamp.")
	if plan.rubble_search_cells.size() < profile.rubble_search_min or plan.rubble_search_cells.size() > profile.rubble_search_max:
		plan.validation_errors.append("Searchable rubble budget is out of range.")
	var quiet_count := 0
	for role in plan.cell_roles.values():
		if str(role) == "quiet_plains":
			quiet_count += 1
	if float(quiet_count) / float(expected) < profile.quiet_ratio_min:
		plan.validation_errors.append("Quiet terrain ratio is below profile minimum.")


static func _validate_road_sockets(plan: GeneratedZonePlan) -> void:
	for coords in plan.road_cells.keys():
		var mask := int(plan.road_cells[coords])
		for index in range(DIRECTIONS.size()):
			if mask & (1 << index) == 0:
				continue
			var neighbor: Vector2i = Vector2i(coords) + Vector2i(DIRECTIONS[index])
			var reciprocal := int(plan.road_cells.get(neighbor, 0)) & (1 << ((index + 3) % 6))
			if reciprocal == 0:
				plan.road_socket_violations.append({"coords": coords, "direction": index})
	if not plan.road_socket_violations.is_empty():
		plan.validation_errors.append("Road contains non-reciprocal sockets.")


static func _validate_required_reachability(
	plan: GeneratedZonePlan,
	start_coords: Vector2i,
	hexes: Dictionary
) -> void:
	var visited := {start_coords: true}
	var frontier: Array[Vector2i] = [start_coords]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for direction in DIRECTIONS:
			var next: Vector2i = current + Vector2i(direction)
			if visited.has(next) or not plan.cell_roles.has(next):
				continue
			var source_hex: MacroHexData = hexes.get(next)
			var composition_clears_blocker := (
				plan.road_cells.has(next)
				or plan.stamp_cells.has(next)
				or plan.rubble_search_cells.has(next)
			)
			if source_hex != null and source_hex.impassable and not composition_clears_blocker:
				continue
			visited[next] = true
			frontier.append(next)
	var required: Array[Vector2i] = [plan.gameplay_anchor_coords]
	required.append_array(plan.rubble_search_cells)
	for coords in required:
		if not visited.has(coords):
			plan.unreachable_cells.append(coords)
	if not plan.unreachable_cells.is_empty():
		plan.validation_errors.append("Required gameplay cells are unreachable.")


static func _distance_to_segment(point: Vector2i, a: Vector2i, b: Vector2i) -> float:
	var p := HexCoordUtils.axial_to_visual_vector(point)
	var start := HexCoordUtils.axial_to_visual_vector(a)
	var end := HexCoordUtils.axial_to_visual_vector(b)
	var length_squared := start.distance_squared_to(end)
	if length_squared <= 0.0001:
		return p.distance_to(start)
	var t := clampf((p - start).dot(end - start) / length_squared, 0.0, 1.0)
	return p.distance_to(start.lerp(end, t))


static func _nearest_distance(coords: Vector2i, others: Array) -> int:
	var best := 999
	for other in others:
		best = mini(best, HexCoordUtils.distance(coords, other))
	return best


static func _axial_line(from_coords: Vector2i, to_coords: Vector2i) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	var n := HexCoordUtils.distance(from_coords, to_coords)
	if n == 0:
		return [from_coords]
	for index in range(n + 1):
		var t := float(index) / float(n)
		var q := int(round(lerpf(float(from_coords.x), float(to_coords.x), t)))
		var r := int(round(lerpf(float(from_coords.y), float(to_coords.y), t)))
		var coords := Vector2i(q, r)
		if results.is_empty() or results.back() != coords:
			results.append(coords)
	return results


static func _rotate_axial(coords: Vector2i, steps: int) -> Vector2i:
	var rotated := coords
	for _index in range(posmod(steps, 6)):
		rotated = Vector2i(-rotated.y, rotated.x + rotated.y)
	return rotated
