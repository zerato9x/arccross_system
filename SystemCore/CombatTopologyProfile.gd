@tool
extends Resource
class_name CombatTopologyProfile

enum MovementPolicy {
	ORTHOGONAL,
	LINEAR_NO_PASS,
}

## Canonical production topology. Legacy duel resources remain loadable for
## old Lab fixtures, but no newly-authored encounter should default to them.
@export var topology_id: String = "squad_7x5"
@export_range(1, 32) var columns: int = 7
@export_range(1, 32) var rows: int = 5
@export var movement_policy: MovementPolicy = MovementPolicy.ORTHOGONAL
@export var player_deployment: Array[Vector2i] = [Vector2i(0, 2), Vector2i(0, 1), Vector2i(0, 3), Vector2i(1, 2)]
@export var enemy_deployment: Array[Vector2i] = [Vector2i(6, 2), Vector2i(6, 1), Vector2i(6, 3), Vector2i(5, 2)]
@export var presentation_style: String = "tactical_grid"


func sector_count() -> int:
	return columns * rows


func contains(coords: Vector2i) -> bool:
	return coords.x >= 0 and coords.x < columns and coords.y >= 0 and coords.y < rows


func index_for(coords: Vector2i) -> int:
	return coords.y * columns + coords.x


func coords_for(index: int) -> Vector2i:
	return Vector2i(index % columns, floori(float(index) / float(columns)))
