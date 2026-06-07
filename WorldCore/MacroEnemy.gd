extends Node2D
class_name MacroEnemy

@export var definition: EntityDefinition # This is where you will drag scavenger_def.tres

var current_hex_coords: Vector2i = Vector2i(0, 0)

func snap_to_hex(coords: Vector2i, pixel_position: Vector2) -> void:
	current_hex_coords = coords
	position = pixel_position

# Eventually, we will add AI roaming logic here so they patrol the map,
# but for now, they will just stand perfectly still waiting to die.
