extends RefCounted
class_name LocationSnapshotQueries

## Read-only queries over the neutral macro location snapshot. UI panels use
## these helpers instead of importing WorldCore's site catalog or controllers.

const VERB_SEARCH := "search"
const VERB_SLEEP := "sleep"
const VERB_TRAP := "trap"
const DEFAULT_ACTION_MINUTES := 15
const DEFAULT_SEARCH_MINUTES := 30
const DEFAULT_CAMP_MINUTES := 480


static func fixture_by_id(site: Dictionary, fixture_id: String) -> Dictionary:
	for fixture_value in site.get("fixtures", []):
		if fixture_value is Dictionary and str(fixture_value.get("id", "")) == fixture_id:
			return fixture_value.duplicate(true)
	return {}


static func fixtures_in_room(site: Dictionary, room_id: String) -> Array:
	var result: Array = []
	for fixture_value in site.get("fixtures", []):
		if fixture_value is Dictionary and str(fixture_value.get("room_id", "")) == room_id:
			result.append(fixture_value.duplicate(true))
	return result


static func build_fixture_drop_targets(site: Dictionary, fixture_id: String) -> Array:
	var fixture := fixture_by_id(site, fixture_id)
	if fixture.is_empty():
		return []
	var verbs: Array = fixture.get("verbs", [])
	var targets: Array = []
	if VERB_SEARCH in verbs:
		targets.append({
			"id": "tool_assist",
			"label": "Tool for %s" % str(fixture.get("label", "fixture")),
			"accepted_roles": [GameEnums.InteractionItemRole.SEARCH_TOOL],
			"assigned_instance_id": "",
			"assigned_name": "",
		})
	if VERB_SLEEP in verbs:
		targets.append({
			"id": "sleep_assist",
			"label": "Sleep with…",
			"accepted_roles": [GameEnums.InteractionItemRole.CAMP_GEAR],
			"assigned_instance_id": "",
			"assigned_name": "",
		})
	if VERB_TRAP in verbs:
		targets.append({
			"id": "trap_assist",
			"label": "Arm trap",
			"accepted_roles": [GameEnums.InteractionItemRole.TRAP_GEAR],
			"assigned_instance_id": "",
			"assigned_name": "",
			"anchor_id": str(fixture.get("id", "door_frame")),
			"sector": Vector2i(1, 2),
		})
	return targets
