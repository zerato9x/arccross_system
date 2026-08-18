extends RefCounted
class_name WorldActionApplicationReceipt

## Result of applying a neutral world-action receipt to RuntimeStateStore.

var receipt_id: String = ""
var action_id: String = ""
var node_id: String = ""
var coords: Vector2i = Vector2i.ZERO
var applied: bool = false
var idempotent: bool = false
var error: String = ""
var player_runtime: Dictionary = {}
var actor_runtime: Dictionary = {}
var target_revision: int = -1
var hex_revision: int = -1


func to_dict() -> Dictionary:
	return {
		"receipt_id": receipt_id,
		"action_id": action_id,
		"node_id": node_id,
		"coords": coords,
		"applied": applied,
		"idempotent": idempotent,
		"error": error,
		"player_runtime": player_runtime.duplicate(true),
		"actor_runtime": actor_runtime.duplicate(true),
		"target_revision": target_revision,
		"hex_revision": hex_revision,
	}
