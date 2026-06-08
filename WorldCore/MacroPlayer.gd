extends Node2D
class_name MacroPlayer

@export var definition: EntityDefinition

var current_hex_coords: Vector2i = Vector2i(0, 0)

func snap_to_hex(coords: Vector2i, pixel_position: Vector2) -> void:
	current_hex_coords = coords
	position = pixel_position

func walk_to_hex(coords: Vector2i, pixel_position: Vector2) -> void:
	current_hex_coords = coords
	# A smooth, 0.2-second hop to the next tile
	var tween = create_tween()
	tween.tween_property(self, "position", pixel_position, 0.2).set_trans(Tween.TRANS_SINE)
