extends RefCounted
class_name WorldSignalRecord

## A physical signal emitted by a world event. Audio/VFX may present it, but
## AI perception consumes this record rather than inspecting presentation nodes.

var signal_id: String = ""
var signal_type: String = ""
var source_id: String = ""
var node_id: String = ""
var coords: Vector2i = Vector2i.ZERO
var created_minute: int = 0
var expires_minute: int = -1
var intensity: float = 0.0
var direction: Vector2i = Vector2i.ZERO
var payload: Dictionary = {}

func is_active(current_minute: int) -> bool:
	return expires_minute < 0 or expires_minute > current_minute

func to_dict() -> Dictionary:
	return {
		"signal_id": signal_id,
		"signal_type": signal_type,
		"source_id": source_id,
		"node_id": node_id,
		"coords": coords,
		"created_minute": created_minute,
		"expires_minute": expires_minute,
		"intensity": intensity,
		"direction": direction,
		"payload": payload.duplicate(true),
	}

static func from_dict(data: Dictionary) -> WorldSignalRecord:
	var record := WorldSignalRecord.new()
	record.signal_id = str(data.get("signal_id", ""))
	record.signal_type = str(data.get("signal_type", ""))
	record.source_id = str(data.get("source_id", ""))
	record.node_id = str(data.get("node_id", ""))
	record.coords = data.get("coords", Vector2i.ZERO)
	record.created_minute = int(data.get("created_minute", 0))
	record.expires_minute = int(data.get("expires_minute", -1))
	record.intensity = clampf(float(data.get("intensity", 0.0)), 0.0, 12.0)
	record.direction = data.get("direction", Vector2i.ZERO)
	record.payload = data.get("payload", {}).duplicate(true)
	return record
