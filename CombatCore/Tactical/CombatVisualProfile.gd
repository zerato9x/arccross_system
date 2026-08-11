@tool
extends Resource
class_name CombatVisualProfile

## Data-only battlefield exposure and contrast. This does not change terrain
## rules; it controls how the tactical projection remains readable.

@export var profile_id: String = "readable_moody"
@export var arena_base_color := Color("1f2823")
@export var backdrop_modulate := Color(0.94, 0.96, 0.90, 0.98)
@export_range(0.0, 1.0, 0.01) var duel_surface_alpha: float = 0.44
@export_range(0.0, 1.0, 0.01) var ground_texture_alpha: float = 0.90
@export_range(0.0, 1.0, 0.01) var grid_alpha: float = 0.44
@export_range(0.0, 1.0, 0.01) var panel_opacity: float = 0.78
@export var token_modulate := Color(1.0, 1.0, 0.96, 1.0)
