extends RefCounted
class_name MacroTurnResolutionState

## Presentation-neutral state for one player-owned macro turn transaction.
##
## The rules still live in the existing world-action and NPC services. This
## object only owns the lifecycle that keeps input, movement, presentation,
## and audio consumers from guessing whether a turn is finished.

const PHASE_IDLE := "idle"
const PHASE_WALKING := "walking"
const PHASE_ARRIVAL := "resolving"
const PHASE_WORLD_TURN := "world_turn"
const PHASE_PRESENTATION := "presentation"

var data: Dictionary = _idle_state()
var _serial := 0


func begin(
	kind: String,
	from_coords: Vector2i,
	destination_coords: Vector2i,
	total_steps: int,
	can_cancel: bool
) -> int:
	if is_active():
		return 0
	_serial += 1
	var normalized_steps := maxi(1, total_steps)
	data = {
		"active": true,
		"resolution_id": _serial,
		"kind": kind,
		"phase": PHASE_WALKING,
		"from_coords": from_coords,
		"current_coords": from_coords,
		"step_target_coords": from_coords,
		"destination_coords": destination_coords,
		"total_steps": normalized_steps,
		"completed_steps": 0,
		"remaining_steps": normalized_steps,
		"can_cancel": can_cancel,
		"message": "TURN RESOLVE // %s" % kind.to_upper(),
	}
	return _serial


func replace_state(value: Dictionary) -> void:
	data = value.duplicate(true)
	if int(data.get("resolution_id", 0)) > _serial:
		_serial = int(data.get("resolution_id", 0))


func is_active() -> bool:
	return bool(data.get("active", false))


func resolution_id() -> int:
	return int(data.get("resolution_id", 0))


func set_phase(phase: String, message: String = "") -> bool:
	if not is_active():
		return false
	data["phase"] = phase
	if not message.is_empty():
		data["message"] = message
	return true


func set_step_target(coords: Vector2i) -> void:
	data["step_target_coords"] = coords


func mark_step_committed(coords: Vector2i, route_total_steps: int) -> void:
	var completed := int(data.get("completed_steps", 0)) + 1
	var total := maxi(1, route_total_steps)
	data["completed_steps"] = completed
	data["remaining_steps"] = maxi(0, total - completed)
	data["current_coords"] = coords
	data["step_target_coords"] = coords


func finish(message: String, terminal_phase: String = PHASE_IDLE) -> void:
	data["active"] = false
	data["phase"] = terminal_phase
	data["can_cancel"] = false
	data["remaining_steps"] = 0
	data["total_steps"] = 0
	data["completed_steps"] = 0
	data["message"] = message


func snapshot() -> Dictionary:
	return data.duplicate(true)


static func _idle_state() -> Dictionary:
	return {
		"active": false,
		"resolution_id": 0,
		"kind": "travel",
		"phase": PHASE_IDLE,
		"from_coords": Vector2i.ZERO,
		"current_coords": Vector2i.ZERO,
		"step_target_coords": Vector2i.ZERO,
		"destination_coords": Vector2i.ZERO,
		"total_steps": 0,
		"completed_steps": 0,
		"remaining_steps": 0,
		"can_cancel": false,
		"message": "",
	}
