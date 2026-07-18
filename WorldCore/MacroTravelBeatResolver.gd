extends RefCounted
class_name MacroTravelBeatResolver

const KIND_ORDINARY := "ordinary"
const KIND_FIRST_SIGHT := "first_sight"
const KIND_GROUND_LOOT := "ground_loot"
const KIND_LANDMARK := "landmark_hint"
const _Snapshot := preload("res://WorldCore/MacroSnapshotBuilder.gd")


static func build_step_beat(
	origin: Vector2i,
	target: Vector2i,
	hex_data: MacroHexData,
	newly_explored: Array = [],
	has_ground_loot: bool = false
) -> Dictionary:
	if hex_data == null:
		return {}
	var feature: String = str(_Snapshot.feature_title(hex_data))
	var environment: String = str(_Snapshot.environment_summary(hex_data))
	var movement: String = str(_Snapshot.movement_note(hex_data))
	var resource: String = str(_Snapshot.resource_hint(hex_data))
	var kind := KIND_ORDINARY
	var title := "EXPLORING"
	var auto_ms := 1500
	var intensity := 0.45
	var fx_kind := "pulse"
	var movement_tag: String = movement
	if movement.contains(" // "):
		movement_tag = str(movement.split(" // ")[0])
	var tags: Array = [
		"HEX %d,%d" % [target.x, target.y],
		movement_tag,
	]
	var body_lines: PackedStringArray = [
		"You move into %s." % feature,
		environment,
		movement,
	]

	if newly_explored.size() > 0:
		kind = KIND_FIRST_SIGHT
		title = "DISCOVERED"
		auto_ms = 1900
		intensity = 0.85
		fx_kind = "discover"
		tags.append("NEW GROUND")
		body_lines.insert(
			1,
			"Fresh ground opens: %d hex(es) revealed beyond the fog." % newly_explored.size()
		)

	if has_ground_loot:
		kind = KIND_GROUND_LOOT
		title = "SIGNS OF LOOT"
		auto_ms = 2000
		intensity = 0.9
		fx_kind = "loot"
		tags.append("GROUND ITEMS")
		body_lines.append("Scattered gear lies on this hex. Act to gather what remains.")
	elif hex_data.is_poi or hex_data.has_landmark():
		kind = KIND_LANDMARK
		title = "LANDMARK AHEAD"
		auto_ms = 1850
		intensity = 0.75
		fx_kind = "landmark"
		var poi_name: String = feature
		if not hex_data.poi_name.is_empty():
			poi_name = hex_data.poi_name
		tags.append("ACT TO EXPLORE")
		body_lines.append(
			"%s can be searched here. Press Act / E to investigate." % poi_name
		)

	body_lines.append(resource)
	var step := target - origin
	if step != Vector2i.ZERO:
		tags.append("STEP %d,%d" % [step.x, step.y])

	return {
		"mode": "travel",
		"kind": kind,
		"blocking": false,
		"title": title,
		"body": "\n".join(body_lines),
		"tags": tags,
		"image_path": "",
		"choices": [],
		"fx": {
			"kind": fx_kind,
			"intensity": intensity,
			"palette": ["#d8b84a", "#4a7aaa"],
		},
		"auto_ms": auto_ms,
		"coords": target,
	}
