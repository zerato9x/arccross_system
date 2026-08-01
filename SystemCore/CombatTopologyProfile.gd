extends Resource
class_name CombatTopologyProfile

enum MovementPolicy {
	ORTHOGONAL,
	LINEAR_NO_PASS,
}

@export var topology_id: String = "duel_12x1"
@export_range(1, 32) var columns: int = 12
@export_range(1, 32) var rows: int = 1
@export var movement_policy: MovementPolicy = MovementPolicy.LINEAR_NO_PASS
@export var player_deployment: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
@export var enemy_deployment: Array[Vector2i] = [Vector2i(11, 0), Vector2i(10, 0), Vector2i(9, 0)]
@export var presentation_style: String = "duel_lane"


func sector_count() -> int:
	return columns * rows


func contains(coords: Vector2i) -> bool:
	return coords.x >= 0 and coords.x < columns and coords.y >= 0 and coords.y < rows


func index_for(coords: Vector2i) -> int:
	return coords.y * columns + coords.x


func coords_for(index: int) -> Vector2i:
	return Vector2i(index % columns, index / columns)


static func load_profile(requested_id: String) -> CombatTopologyProfile:
	var profile_id := requested_id if not requested_id.is_empty() else "duel_12x1"
	var path := "res://CombatCore/Tactical/Topologies/%s.tres" % profile_id
	if not ResourceLoader.exists(path):
		push_warning("Unknown combat topology '%s'; using duel_12x1." % profile_id)
		path = "res://CombatCore/Tactical/Topologies/duel_12x1.tres"
	return load(path) as CombatTopologyProfile
