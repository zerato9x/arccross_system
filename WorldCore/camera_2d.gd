extends Camera2D
class_name MacroCamera

@export var target: Node2D
var follow_speed: float = 6.0 # The lower the number, the lazier the camera
const PAN_SPEED = 5000.0
const ZOOM_SPEED = 0.15
const MIN_ZOOM = 0.1
const MAX_ZOOM = 10

func _ready() -> void:
	if not target:
		push_error("Camera has no target. It will stare at the void forever.")
		return
		
	# Instantly snap to the player on boot so we don't pan from coordinate 0,0
	position = target.position

func _process(delta: float) -> void:
	if target:
		# Godot's built-in linear interpolation (lerp) creates a buttery smooth follow effect
		position = position.lerp(target.position, follow_speed * delta)
		
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
