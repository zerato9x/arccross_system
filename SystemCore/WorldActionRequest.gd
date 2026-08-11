extends RefCounted
class_name WorldActionRequest

## Intent submitted by either the player UI or an AI planner.

var actor_id: String = ""
var target_id: String = ""
var target_coords: Vector2i = Vector2i.ZERO
var verb_id: String = ""
var method_id: String = ""
var tool_instance_ids: Array[String] = []
var expected_actor_revision: int = -1
var expected_target_revision: int = -1
var payload: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		"actor_id": actor_id,
		"target_id": target_id,
		"target_coords": target_coords,
		"verb_id": verb_id,
		"method_id": method_id,
		"tool_instance_ids": tool_instance_ids.duplicate(),
		"expected_actor_revision": expected_actor_revision,
		"expected_target_revision": expected_target_revision,
		"payload": payload.duplicate(true),
	}

static func from_dict(data: Dictionary) -> WorldActionRequest:
	var request := WorldActionRequest.new()
	request.actor_id = str(data.get("actor_id", ""))
	request.target_id = str(data.get("target_id", ""))
	request.target_coords = data.get("target_coords", Vector2i.ZERO)
	request.verb_id = str(data.get("verb_id", ""))
	request.method_id = str(data.get("method_id", ""))
	for value in data.get("tool_instance_ids", []):
		request.tool_instance_ids.append(str(value))
	request.expected_actor_revision = int(data.get("expected_actor_revision", -1))
	request.expected_target_revision = int(data.get("expected_target_revision", -1))
	request.payload = data.get("payload", {}).duplicate(true)
	return request
