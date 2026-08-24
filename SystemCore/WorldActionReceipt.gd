extends RefCounted
class_name WorldActionReceipt

## Authoritative result of a committed action or work attempt.

var action_id: String = ""
## Unique application identity. action_id groups a multi-cycle work session;
## receipt_id identifies exactly one committed attempt within it.
var receipt_id: String = ""
var node_id: String = ""
var actor_id: String = ""
var target_id: String = ""
var target_coords: Vector2i = Vector2i.ZERO
var verb_id: String = ""
var method_id: String = ""
var expected_actor_revision: int = -1
var expected_target_revision: int = -1
var expected_hex_revision: int = -1
var committed: bool = false
var interrupted: bool = false
var elapsed_minutes: int = 0
var exertion: float = 0.0
var noise_intensity: float = 0.0
## Wear is semantic receipt data, not a presentation-side guess. The owning
## inventory/object system may apply the mutation immediately, while UI and
## AI logs can still explain why a tool changed condition.
var tool_wear: float = 0.0
var work_progress: float = 0.0
var work_completed: bool = false
var mutations: Array[Dictionary] = []
var signals: Array[Dictionary] = []
var events: Array[Dictionary] = []
var presentation: Dictionary = {}
## Legacy detached post-resolution actor runtime. New production actions stage
## semantic mutations against canonical state; this field remains serialized
## only so older receipts and compatibility fixtures can still be read.
var actor_state: Dictionary = {}
## Detached post-resolution object state. The application boundary validates
## its identity and revision before replacing the object in the canonical hex.
var target_state: Dictionary = {}
var message: String = ""

func add_signal(signal_record: WorldSignalRecord) -> void:
	signals.append(signal_record.to_dict())

func to_dict() -> Dictionary:
	return {
		"action_id": action_id,
		"receipt_id": receipt_id,
		"node_id": node_id,
		"actor_id": actor_id,
		"target_id": target_id,
		"target_coords": target_coords,
		"verb_id": verb_id,
		"method_id": method_id,
		"expected_actor_revision": expected_actor_revision,
		"expected_target_revision": expected_target_revision,
		"expected_hex_revision": expected_hex_revision,
		"committed": committed,
		"interrupted": interrupted,
		"elapsed_minutes": elapsed_minutes,
		"exertion": exertion,
		"noise_intensity": noise_intensity,
		"tool_wear": tool_wear,
		"work_progress": work_progress,
		"work_completed": work_completed,
		"mutations": mutations.duplicate(true),
		"signals": signals.duplicate(true),
		"events": events.duplicate(true),
		"presentation": presentation.duplicate(true),
		"actor_state": actor_state.duplicate(true),
		"target_state": target_state.duplicate(true),
		"message": message,
	}


static func from_dict(data: Dictionary) -> WorldActionReceipt:
	var receipt := WorldActionReceipt.new()
	receipt.action_id = str(data.get("action_id", ""))
	receipt.receipt_id = str(data.get("receipt_id", ""))
	receipt.node_id = str(data.get("node_id", ""))
	receipt.actor_id = str(data.get("actor_id", ""))
	receipt.target_id = str(data.get("target_id", ""))
	receipt.target_coords = data.get("target_coords", Vector2i.ZERO)
	receipt.verb_id = str(data.get("verb_id", ""))
	receipt.method_id = str(data.get("method_id", ""))
	receipt.expected_actor_revision = int(data.get("expected_actor_revision", -1))
	receipt.expected_target_revision = int(data.get("expected_target_revision", -1))
	receipt.expected_hex_revision = int(data.get("expected_hex_revision", -1))
	receipt.committed = bool(data.get("committed", false))
	receipt.interrupted = bool(data.get("interrupted", false))
	receipt.elapsed_minutes = int(data.get("elapsed_minutes", 0))
	receipt.exertion = float(data.get("exertion", 0.0))
	receipt.noise_intensity = float(data.get("noise_intensity", 0.0))
	receipt.tool_wear = float(data.get("tool_wear", 0.0))
	receipt.work_progress = float(data.get("work_progress", 0.0))
	receipt.work_completed = bool(data.get("work_completed", false))
	receipt.mutations = data.get("mutations", []).duplicate(true)
	receipt.signals = data.get("signals", []).duplicate(true)
	receipt.events = data.get("events", []).duplicate(true)
	receipt.presentation = data.get("presentation", {}).duplicate(true)
	receipt.actor_state = data.get("actor_state", {}).duplicate(true)
	receipt.target_state = data.get("target_state", {}).duplicate(true)
	receipt.message = str(data.get("message", ""))
	return receipt
