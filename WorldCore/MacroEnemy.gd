extends Node2D
class_name MacroEnemy

var entity_id: String = ""
var current_hex_coords: Vector2i = Vector2i(0, 0)

func snap_to_hex(coords: Vector2i, pixel_position: Vector2) -> void:
	current_hex_coords = coords
	position = pixel_position

## Initialize presentation from a neutral persistent record.
func setup_from_record(record: Dictionary) -> void:
	entity_id = record.get("entity_id", "")
	var definition_state: Dictionary = record.get("definition", {})
	var faction: GameEnums.Faction = definition_state.get(
		"faction",
		GameEnums.Faction.UNALIGNED
	)
	
	# Faction color tint on top of the default sprite
	match faction:
		GameEnums.Faction.CRAVEN_HIVE:
			modulate = Color(0.7, 0.2, 0.2) # Red tint for Cravens
		GameEnums.Faction.ARCBORN_RESISTANCE:
			modulate = Color(0.3, 0.5, 1.0) # Blue tint for Arcborn
		GameEnums.Faction.SCAVENGER_CELL:
			modulate = Color(0.8, 0.7, 0.3) # Yellow tint for Scavengers
