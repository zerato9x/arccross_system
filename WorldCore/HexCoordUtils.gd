extends RefCounted
class_name HexCoordUtils

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
