extends Node2D

# Minimal runtime driver for QA sanity checks.
# Safe to remove for static captures.

@onready var dissolve_mat := $Lanes/LaneDissolve.material as ShaderMaterial
@onready var heat_mat := $Lanes/LaneDistort.material as ShaderMaterial
@onready var flash_mat := $Lanes/LaneFlash.material as ShaderMaterial
@onready var radial_mat := $Lanes/LaneRadial.material as ShaderMaterial

var _t := 0.0

func _process(delta: float) -> void:
	_t += delta

	if dissolve_mat:
		var dissolve_v := 0.5 + 0.5 * sin(_t * 1.2)
		dissolve_mat.set_shader_parameter("_Dissolve", dissolve_v)

	if heat_mat:
		var heat_strength := 0.018 + 0.012 * (0.5 + 0.5 * sin(_t * 1.7))
		heat_mat.set_shader_parameter("_Strength", heat_strength)

	if flash_mat:
		var flash_v := 0.5 + 0.5 * sin(_t * 6.0)
		flash_mat.set_shader_parameter("_FlashAmount", flash_v)

	if radial_mat:
		var radial_v := fmod(_t * 0.2, 1.0)
		radial_mat.set_shader_parameter("_Progress", radial_v)
