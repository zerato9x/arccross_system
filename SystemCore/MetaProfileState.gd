extends RefCounted
class_name MetaProfileState

## In-memory cross-run profile value object. It contains no runtime/run state.

var completed_events: Dictionary = {}
var gateway_states: Dictionary = {}
var core_states: Dictionary = {}
var node_profile_patches: Dictionary = {}
var permanent_node_hex_patches: Dictionary = {}
var shelter_states: Dictionary = {}
var codex_entries: Dictionary = {}
var central_locked: bool = true


func to_dict() -> Dictionary:
	var node_patch_entries: Array = []
	for node_id in permanent_node_hex_patches.keys():
		var hex_entries: Array = []
		var node_patches: Dictionary = permanent_node_hex_patches[node_id]
		for coords in node_patches.keys():
			hex_entries.append({"coords": coords, "patch": node_patches[coords]})
		node_patch_entries.append({"node_id": node_id, "hexes": hex_entries})
	return {
		"completed_events": completed_events.duplicate(true),
		"gateway_states": gateway_states.duplicate(true),
		"core_states": core_states.duplicate(true),
		"node_profile_patches": node_profile_patches.duplicate(true),
		"permanent_node_hex_patches": node_patch_entries,
		"shelter_states": shelter_states.duplicate(true),
		"codex_entries": codex_entries.duplicate(true),
		"central_locked": central_locked,
	}


static func from_dict(data: Dictionary) -> MetaProfileState:
	var state := MetaProfileState.new()
	state.completed_events = data.get("completed_events", {}).duplicate(true)
	state.gateway_states = data.get("gateway_states", {}).duplicate(true)
	state.core_states = data.get("core_states", {}).duplicate(true)
	state.node_profile_patches = data.get("node_profile_patches", {}).duplicate(true)
	state.shelter_states = data.get("shelter_states", {}).duplicate(true)
	state.codex_entries = data.get("codex_entries", {}).duplicate(true)
	state.central_locked = bool(data.get("central_locked", true))
	for node_entry in data.get("permanent_node_hex_patches", []):
		if not node_entry is Dictionary:
			continue
		var node_id := str(node_entry.get("node_id", ""))
		if node_id.is_empty():
			continue
		var node_patches: Dictionary = {}
		for hex_entry in node_entry.get("hexes", []):
			if not hex_entry is Dictionary:
				continue
			var coords: Variant = hex_entry.get("coords")
			if coords is Vector2i:
				node_patches[coords] = hex_entry.get("patch", {}).duplicate(true)
		state.permanent_node_hex_patches[node_id] = node_patches
	return state
