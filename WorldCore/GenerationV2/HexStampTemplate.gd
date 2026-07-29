extends Resource
class_name HexStampTemplate

@export var template_id: String = ""
@export var gameplay_anchor_offset: Vector2i = Vector2i.ZERO
@export var cells: Array[Dictionary] = []
@export var road_socket_offsets: Array[Vector2i] = []
@export var orientation_variants: PackedInt32Array = [0, 1, 2, 3, 4, 5]
@export_range(0, 5) var orientation: int = 0


static func starter_settlement(orientation_steps: int = 0) -> HexStampTemplate:
	var stamp := HexStampTemplate.new()
	stamp.template_id = "starter_settlement_v2"
	stamp.orientation = posmod(orientation_steps, 6)
	stamp.gameplay_anchor_offset = Vector2i.ZERO
	stamp.road_socket_offsets = [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0)]
	stamp.cells = [
		_cell(Vector2i.ZERO, "settlement_anchor", "anchor"),
		_cell(Vector2i(1, 0), "settlement_structure", "homestead_b"),
		_cell(Vector2i(0, 1), "settlement_structure", "homestead_d"),
		_cell(Vector2i(-1, 1), "settlement_structure", "shed_a"),
		_cell(Vector2i(2, -1), "settlement_structure", "warehouse_b"),
		_cell(Vector2i(-1, 0), "settlement_tent", "tent"),
		_cell(Vector2i(1, -1), "settlement_tent", "tent"),
		_cell(Vector2i(0, -1), "settlement_tent", "tent"),
		_cell(Vector2i(-2, 1), "settlement_tent", "tent"),
		_cell(Vector2i(1, 1), "settlement_tent", "tent"),
		_cell(Vector2i(0, 2), "settlement_tent", "tent"),
		_cell(Vector2i(2, -2), "settlement_rubble", "rubble"),
		_cell(Vector2i(-2, 0), "settlement_rubble", "rubble"),
		_cell(Vector2i(-1, 2), "settlement_rubble", "rubble"),
		_cell(Vector2i(2, 0), "settlement_rubble", "rubble"),
	]
	if stamp.orientation != 0:
		for cell in stamp.cells:
			cell["offset"] = _rotate_axial(cell.get("offset", Vector2i.ZERO), stamp.orientation)
		for index in range(stamp.road_socket_offsets.size()):
			stamp.road_socket_offsets[index] = _rotate_axial(stamp.road_socket_offsets[index], stamp.orientation)
	return stamp


static func _cell(offset: Vector2i, role: String, dressing: String) -> Dictionary:
	return {
		"offset": offset,
		"role": role,
		"dressing": dressing,
		"blocks": false,
	}


static func _rotate_axial(coords: Vector2i, steps: int) -> Vector2i:
	var rotated := coords
	for _index in range(posmod(steps, 6)):
		# Cube rotation with axial q=x, r=z: (q,r) -> (-r,q+r).
		rotated = Vector2i(-rotated.y, rotated.x + rotated.y)
	return rotated
