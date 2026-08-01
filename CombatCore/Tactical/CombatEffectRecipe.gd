extends Resource
class_name CombatEffectRecipe

## Data-only procedural acting layered over the available humanoid animation.

@export var recipe_id: String = "neutral"
@export var lunge_pixels: float = 0.0
@export var recoil_pixels: float = 0.0
@export var shake_amplitude: float = 0.0
@export var shake_frequency: float = 24.0
@export var hit_stop_seconds: float = 0.0
@export var camera_impulse_pixels: float = 0.0
@export var impact_scale: float = 0.0
@export var impact_rotation_degrees: float = 0.0
@export var projectile_speed_cells_per_second: float = 12.0
@export var persistent_indicator_id: String = ""
