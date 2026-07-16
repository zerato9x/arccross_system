extends RefCounted
class_name HexCoordUtils

const AXIAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]

## Optional odd-R offset <-> axial helpers for rectangular hex wedges.
## Campaign node zones use the axial square [0, size)^2 (a rhombus on pointy
## TileMaps) — do NOT gate zone membership with is_in_offset_rect.


static func odd_r_to_axial(col: int, row: int) -> Vector2i:
	var q := col - (row - (row & 1)) / 2
	return Vector2i(q, row)


static func axial_to_odd_r(axial: Vector2i) -> Vector2i:
	var col := axial.x + (axial.y - (axial.y & 1)) / 2
	return Vector2i(col, axial.y)


## True when the axial cell lies inside an odd-R [0, size)^2 rectangle.
## For optional rectangular wedges only — not the campaign node zone footprint.
static func is_in_offset_rect(axial: Vector2i, size: int) -> bool:
	var offset := axial_to_odd_r(axial)
	return (
		offset.x >= 0
		and offset.y >= 0
		and offset.x < size
		and offset.y < size
	)


static func offset_center_south(size: int) -> Vector2i:
	return odd_r_to_axial(size / 2, size - 2)


static func offset_center_north(size: int) -> Vector2i:
	return odd_r_to_axial(size / 2, 1)


static func distance_from_origin(coords: Vector2i) -> int:
	return maxi(abs(coords.x), maxi(abs(coords.y), abs(coords.x + coords.y)))


static func distance(a: Vector2i, b: Vector2i) -> int:
	return distance_from_origin(b - a)


static func is_in_radius(coords: Vector2i, radius: int) -> bool:
	return distance_from_origin(coords) <= radius


static func cells_in_radius(radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		var r_min := maxi(-radius, -q - radius)
		var r_max := mini(radius, -q + radius)
		for r in range(r_min, r_max + 1):
			cells.append(Vector2i(q, r))
	return cells


static func cells_in_ring(radius: int) -> Array[Vector2i]:
	if radius <= 0:
		return [Vector2i.ZERO]
	var cells: Array[Vector2i] = []
	for coords in cells_in_radius(radius):
		if distance_from_origin(coords) == radius:
			cells.append(coords)
	return cells


static func opposite_travel_direction(direction: int) -> int:
	match direction:
		GameEnums.MacroTravelDirection.NORTH:
			return GameEnums.MacroTravelDirection.SOUTH
		GameEnums.MacroTravelDirection.EAST:
			return GameEnums.MacroTravelDirection.WEST
		GameEnums.MacroTravelDirection.SOUTH:
			return GameEnums.MacroTravelDirection.NORTH
		GameEnums.MacroTravelDirection.WEST:
			return GameEnums.MacroTravelDirection.EAST
		GameEnums.MacroTravelDirection.NORTHEAST:
			return GameEnums.MacroTravelDirection.SOUTHWEST
		GameEnums.MacroTravelDirection.SOUTHEAST:
			return GameEnums.MacroTravelDirection.NORTHWEST
		GameEnums.MacroTravelDirection.SOUTHWEST:
			return GameEnums.MacroTravelDirection.NORTHEAST
		GameEnums.MacroTravelDirection.NORTHWEST:
			return GameEnums.MacroTravelDirection.SOUTHEAST
		_:
			return GameEnums.MacroTravelDirection.NONE


static func travel_direction_for_step(step: Vector2i) -> int:
	match step:
		Vector2i(0, -1):
			return GameEnums.MacroTravelDirection.NORTHWEST
		Vector2i(0, 1):
			return GameEnums.MacroTravelDirection.SOUTHEAST
		Vector2i(1, 0):
			return GameEnums.MacroTravelDirection.EAST
		Vector2i(1, -1):
			return GameEnums.MacroTravelDirection.NORTHEAST
		Vector2i(-1, 0):
			return GameEnums.MacroTravelDirection.WEST
		Vector2i(-1, 1):
			return GameEnums.MacroTravelDirection.SOUTHWEST
		_:
			return GameEnums.MacroTravelDirection.NONE


## Matches the pointy-top MacroTileSet basis: q advances horizontally while r
## advances half a cell right and three quarters of a cell down.
static func axial_to_visual_vector(coords: Vector2i) -> Vector2:
	return Vector2(float(coords.x) + float(coords.y) * 0.5, float(coords.y) * 0.75)


static func travel_direction_for_coords(coords: Vector2i) -> int:
	var vector := axial_to_visual_vector(coords)
	if vector.is_zero_approx():
		return GameEnums.MacroTravelDirection.NONE
	var raw_octant := int(round(atan2(vector.y, vector.x) / (PI / 4.0)))
	var octant := (raw_octant % 8 + 8) % 8
	match octant:
		0:
			return GameEnums.MacroTravelDirection.EAST
		1:
			return GameEnums.MacroTravelDirection.SOUTHEAST
		2:
			return GameEnums.MacroTravelDirection.SOUTH
		3:
			return GameEnums.MacroTravelDirection.SOUTHWEST
		4:
			return GameEnums.MacroTravelDirection.WEST
		5:
			return GameEnums.MacroTravelDirection.NORTHWEST
		6:
			return GameEnums.MacroTravelDirection.NORTH
		_:
			return GameEnums.MacroTravelDirection.NORTHEAST


static func travel_direction_for_boundary_target(target_coords: Vector2i) -> int:
	return travel_direction_for_coords(target_coords)


static func travel_direction_vector(direction: int) -> Vector2:
	match direction:
		GameEnums.MacroTravelDirection.NORTH:
			return Vector2.UP
		GameEnums.MacroTravelDirection.NORTHEAST:
			return Vector2(1.0, -1.0).normalized()
		GameEnums.MacroTravelDirection.EAST:
			return Vector2.RIGHT
		GameEnums.MacroTravelDirection.SOUTHEAST:
			return Vector2(1.0, 1.0).normalized()
		GameEnums.MacroTravelDirection.SOUTH:
			return Vector2.DOWN
		GameEnums.MacroTravelDirection.SOUTHWEST:
			return Vector2(-1.0, 1.0).normalized()
		GameEnums.MacroTravelDirection.WEST:
			return Vector2.LEFT
		GameEnums.MacroTravelDirection.NORTHWEST:
			return Vector2(-1.0, -1.0).normalized()
		_:
			return Vector2.ZERO


static func rim_anchor(direction: int, radius: int) -> Vector2i:
	var target := travel_direction_vector(direction)
	if target.is_zero_approx() or radius <= 0:
		return Vector2i.ZERO
	var best := Vector2i.ZERO
	var best_dot := -INF
	for coords in cells_in_ring(radius):
		var visual := axial_to_visual_vector(coords).normalized()
		var score := visual.dot(target)
		if score > best_dot:
			best_dot = score
			best = coords
	return best
