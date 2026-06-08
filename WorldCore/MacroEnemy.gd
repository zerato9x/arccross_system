extends Node2D
class_name MacroEnemy

@export var definition: EntityDefinition

var current_hex_coords: Vector2i = Vector2i(0, 0)

func snap_to_hex(coords: Vector2i, pixel_position: Vector2) -> void:
	current_hex_coords = coords
	position = pixel_position

## Initialize from a procedurally generated EntityDefinition (from MobSpawner).
func setup_from_definition(def: EntityDefinition) -> void:
	definition = def
	
	# Faction color tint on top of the default sprite
	match def.faction:
		GameEnums.Faction.CRAVEN_HIVE:
			modulate = Color(0.7, 0.2, 0.2) # Red tint for Cravens
		GameEnums.Faction.ARCBORN_RESISTANCE:
			modulate = Color(0.3, 0.5, 1.0) # Blue tint for Arcborn
		GameEnums.Faction.SCAVENGER_CELL:
			modulate = Color(0.8, 0.7, 0.3) # Yellow tint for Scavengers
