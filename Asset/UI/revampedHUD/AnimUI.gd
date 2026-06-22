@tool
extends Control
class_name AnimUI
## Simple toggle UI animation helper (forward ↔ backward) with one call

signal animation_finished

@export_category("Animation Settings")
@export var duration: float = 0.5
@export var ease_type: Tween.EaseType = Tween.EASE_OUT
@export var trans_type: Tween.TransitionType = Tween.TRANS_CUBIC

@export_category("Target Values")
@export var target_color: Color = Color.WHITE:
	set(v):
		target_color = v
		queue_redraw()

@export var target_scale: Vector2 = Vector2.ONE:
	set(v):
		target_scale = v
		queue_redraw()

@export var target_offset: Vector2 = Vector2.ZERO: ## Relative to initial position
	set(v):
		target_offset = v
		queue_redraw()

@export var target_rotation_deg: float = 0.0:
	set(v):
		target_rotation_deg = v
		queue_redraw()


# ──────────────────────────────────────────────
# Internal state
# ──────────────────────────────────────────────

var _initial_color: Color
var _initial_scale: Vector2
var _initial_position: Vector2
var _initial_rotation_deg: float

var _tween: Tween = null
var _is_forward: bool = true


func _ready() -> void:
	_capture_initial_values()


func _capture_initial_values() -> void:
	_initial_color         = modulate
	_initial_scale         = scale
	_initial_position      = position
	_initial_rotation_deg  = rotation_degrees


## Starts or toggles the animation (forward → target values, backward → initial)
func play() -> void:
	# Clean up any running tween first
	_stop_current_tween()
	
	_tween = create_tween()
	_tween.set_ease(ease_type)
	_tween.set_trans(trans_type)
	_tween.set_parallel(true)
	
	# Decide targets based on direction
	var target_modulate  = target_color if _is_forward else _initial_color
	var target_scale     = target_scale if _is_forward else _initial_scale
	var target_pos       = _initial_position + target_offset if _is_forward else _initial_position
	var target_rotation  = target_rotation_deg if _is_forward else _initial_rotation_deg
	
	# Animate all properties in parallel
	_tween.tween_property(self, "modulate", target_modulate, duration)
	_tween.tween_property(self, "scale", target_scale, duration)
	_tween.tween_property(self, "position", target_pos, duration)
	_tween.tween_property(self, "rotation_degrees", target_rotation, duration)
	
	# Connect finish signal
	_tween.finished.connect(_on_tween_finished)
	
	# Toggle direction for next call
	_is_forward = !_is_forward


func _stop_current_tween() -> void:
	if _tween:
		_tween.kill()
		_tween = null


func _on_tween_finished() -> void:
	_tween = null
	animation_finished.emit()


## Instantly reset to initial values (no animation)
func reset_immediate() -> void:
	_stop_current_tween()
	
	modulate           = _initial_color
	scale              = _initial_scale
	position           = _initial_position
	rotation_degrees   = _initial_rotation_deg
	
	_is_forward = true


# ──────────────────────────────────────────────
# Editor visualization (shows target offset)
# ──────────────────────────────────────────────

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	
	var color := target_color if target_color.a > 0.1 else Color(1, 0.7, 0.3, 0.7)
	
	# Draw line from origin to target offset
	draw_line(Vector2.ZERO, target_offset, color, 2.5)
	
	# Small circles for clarity
	draw_circle(target_offset, 5.0, color)
	draw_circle(Vector2.ZERO, 3.0, Color(0.4, 0.8, 1.0, 0.8))  # origin point
	
	# Optional: show coordinates as text (helpful for debugging)
	draw_string(
		ThemeDB.fallback_font,
		target_offset + Vector2(8, -8),
		str(target_offset.round()),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(1,1,1,0.9)
	)
