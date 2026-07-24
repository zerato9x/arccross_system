extends CanvasLayer
class_name VisionVignetteOverlay

## Soft screen-space vision vignette for the macro map.
## Corner vignette + player-centered soft vision disk (no world-space squares).

const SHADER_PATH := "res://WorldCore/Shaders/vision_vignette.gdshader"

@export var strength: float = 0.38
@export var softness: float = 0.55
@export var inner: float = 0.14
@export var vision_strength: float = 0.72
@export var breathe_amount: float = 0.03
@export var breathe_half_sec: float = 1.45

var _root: Control
var _rect: ColorRect
var _material: ShaderMaterial
var _breathe_tween: Tween
var _focus_px := Vector2.ZERO
var _vision_inner_px := 420.0
var _vision_soft_px := 220.0
var _has_focus := false
var _vignette_color := Color(0.015, 0.02, 0.015, 1.0)
var _base_breathe_amount: float = 0.03
var _lighting_phase: String = "morning"


func _ready() -> void:
	layer = 2
	follow_viewport_enabled = false
	_base_breathe_amount = breathe_amount
	_root = Control.new()
	_root.name = "VignetteRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_rect = ColorRect.new()
	_rect.name = "VignetteRect"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(1, 1, 1, 1)
	_root.add_child(_rect)
	_material = ShaderMaterial.new()
	var shader := load(SHADER_PATH) as Shader
	if shader != null:
		_material.shader = shader
	_rect.material = _material
	apply_lighting_phase(GameTimeRules.phase_for_hour(8))
	_fit_to_viewport()
	if not get_viewport().size_changed.is_connected(_fit_to_viewport):
		get_viewport().size_changed.connect(_fit_to_viewport)
	_start_breathe()


func set_enabled(enabled: bool) -> void:
	visible = enabled


## Apply shared day/night lighting presets from GameTimeRules.
func apply_lighting_phase(phase: String) -> void:
	_lighting_phase = phase
	var lighting: Dictionary = GameTimeRules.lighting_for_phase(phase)
	_vignette_color = lighting.get("vignette_color", _vignette_color) as Color
	strength = float(lighting.get("strength", strength))
	vision_strength = float(lighting.get("vision_strength", vision_strength))
	var breathe_scale := float(lighting.get("breathe_scale", 1.0))
	breathe_amount = _base_breathe_amount * breathe_scale
	_apply_params()
	_start_breathe()


func get_lighting_phase() -> String:
	return _lighting_phase


func get_vignette_color() -> Color:
	return _vignette_color


## Push player-centered soft vision disk in screen pixels.
func set_vision_disk(focus_px: Vector2, inner_px: float, soft_px: float) -> void:
	_focus_px = focus_px
	_vision_inner_px = maxf(inner_px, 32.0)
	_vision_soft_px = maxf(soft_px, 24.0)
	_has_focus = true
	_apply_params()


func _fit_to_viewport() -> void:
	if _root == null or _rect == null:
		return
	var size := get_viewport().get_visible_rect().size
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.offset_left = 0.0
	_root.offset_top = 0.0
	_root.offset_right = 0.0
	_root.offset_bottom = 0.0
	_root.set_deferred("size", size)
	_root.set_deferred("position", Vector2.ZERO)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.set_deferred("size", size)
	_rect.set_deferred("position", Vector2.ZERO)
	_apply_params()


func _apply_params() -> void:
	if _material == null:
		return
	var size := get_viewport().get_visible_rect().size
	_material.set_shader_parameter("strength", strength)
	_material.set_shader_parameter("softness", softness)
	_material.set_shader_parameter("inner", inner)
	_material.set_shader_parameter("breathe", 0.0)
	_material.set_shader_parameter("vignette_color", _vignette_color)
	_material.set_shader_parameter("viewport_size", size)
	_material.set_shader_parameter("vision_strength", vision_strength)
	if _has_focus:
		_material.set_shader_parameter("focus_px", _focus_px)
		_material.set_shader_parameter("vision_inner_px", _vision_inner_px)
		_material.set_shader_parameter("vision_soft_px", _vision_soft_px)
	else:
		_material.set_shader_parameter("focus_px", size * 0.5)
		_material.set_shader_parameter("vision_inner_px", minf(size.x, size.y) * 0.28)
		_material.set_shader_parameter("vision_soft_px", minf(size.x, size.y) * 0.18)


func _start_breathe() -> void:
	if _material == null or breathe_amount <= 0.0:
		return
	if _breathe_tween != null and _breathe_tween.is_valid():
		_breathe_tween.kill()
	_breathe_tween = create_tween().set_loops()
	_breathe_tween.tween_method(
		func(value: float) -> void:
			if _material != null:
				_material.set_shader_parameter("breathe", value),
		0.0,
		breathe_amount,
		breathe_half_sec
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breathe_tween.tween_method(
		func(value: float) -> void:
			if _material != null:
				_material.set_shader_parameter("breathe", value),
		breathe_amount,
		0.0,
		breathe_half_sec
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
