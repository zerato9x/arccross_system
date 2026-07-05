extends Camera2D
class_name MacroCamera

@export var target: Node2D
var follow_speed: float = 6.0
const PAN_SPEED = 5000.0
const ZOOM_SPEED = 0.15
const MIN_ZOOM = 0.1
const MAX_ZOOM = 10


func _ready() -> void:
	if not target:
		push_error("Camera has no target. It will stare at the void forever.")
		return
	position = target.position


func set_viewport_insets(_insets: Rect2i) -> void:
	pass


func _process(delta: float) -> void:
	if not target:
		return
	var desired := _get_desired_position()
	position = position.lerp(desired, follow_speed * delta)


func _get_desired_position() -> Vector2:
	if target == null:
		return position
	return target.position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_zoom(ZOOM_SPEED)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_zoom(-ZOOM_SPEED)


func _adjust_zoom(amount: float) -> void:
	var new_zoom = zoom.x + amount
	new_zoom = clamp(new_zoom, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(new_zoom, new_zoom)
