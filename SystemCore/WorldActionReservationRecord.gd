extends RefCounted
class_name WorldActionReservationRecord

## Typed, node-scoped ownership of an in-progress world action. One action may
## produce multiple attempt receipts; attempt_index distinguishes those commits.

var action_id: String = ""
var node_id: String = ""
var actor_id: String = ""
var target_id: String = ""
var target_coords: Vector2i = Vector2i.ZERO
var verb_id: String = ""
var method_id: String = ""
var expected_actor_revision: int = -1
var expected_target_revision: int = -1
var expected_hex_revision: int = -1
var started_minute: int = 0
var attempt_index: int = 0
var progress: float = 0.0
var state: Dictionary = {}


func next_receipt_id() -> String:
	return "%s:attempt:%d" % [action_id, attempt_index]


func validation_error() -> String:
	if action_id.is_empty() or actor_id.is_empty() or target_id.is_empty():
		return "World action reservation has an empty identity."
	if started_minute < 0 or attempt_index < 0:
		return "World action reservation has invalid timing or attempt state."
	if progress < 0.0 or progress > 1.0:
		return "World action reservation progress is outside 0..1."
	return ""


func to_dict() -> Dictionary:
	return {
		"action_id": action_id,
		"node_id": node_id,
		"actor_id": actor_id,
		"target_id": target_id,
		"target_coords": target_coords,
		"verb_id": verb_id,
		"method_id": method_id,
		"expected_actor_revision": expected_actor_revision,
		"expected_target_revision": expected_target_revision,
		"expected_hex_revision": expected_hex_revision,
		"started_minute": started_minute,
		"attempt_index": attempt_index,
		"progress": progress,
		"state": state.duplicate(true),
	}


static func from_dict(data: Dictionary) -> WorldActionReservationRecord:
	var record := WorldActionReservationRecord.new()
	record.action_id = str(data.get("action_id", ""))
	record.node_id = str(data.get("node_id", ""))
	record.actor_id = str(data.get("actor_id", ""))
	record.target_id = str(data.get("target_id", ""))
	record.target_coords = data.get("target_coords", Vector2i.ZERO)
	record.verb_id = str(data.get("verb_id", ""))
	record.method_id = str(data.get("method_id", ""))
	record.expected_actor_revision = int(data.get("expected_actor_revision", -1))
	record.expected_target_revision = int(data.get("expected_target_revision", -1))
	record.expected_hex_revision = int(data.get("expected_hex_revision", -1))
	record.started_minute = maxi(0, int(data.get("started_minute", 0)))
	record.attempt_index = maxi(0, int(data.get("attempt_index", 0)))
	record.progress = clampf(float(data.get("progress", 0.0)), 0.0, 1.0)
	record.state = data.get("state", {}).duplicate(true)
	return record
