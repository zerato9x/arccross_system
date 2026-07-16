extends Node
class_name MetaProgressionStore

## Cross-run profile. No character, inventory, fog, ordinary loot, ground-item,
## or procedural NPC state belongs here.

signal profile_saved(path: String)
signal meta_event_completed(event_id: String)
signal gateway_state_changed(gateway_id: String, unsealed: bool)

const SAVE_PATH := "user://arccross_meta_progression.json"
const LEGACY_WORLD_PROFILE_PATH := "user://arccross_world_profile.json"
const SAVE_VERSION := 1
const VARIANT_TYPE_KEY := "__arccross_type"
const STRUCTURAL_FIELDS := [
	"biome",
	"terrain_tile",
	"flora_layer",
	"rock_layer",
	"structure_layer",
	"region",
	"arm_direction",
	"zone_id",
	"biome_pack",
	"landmark_id",
	"impassable",
	"terrain_sprite_path",
	"flora_sprite_path",
	"rock_sprite_path",
	"structure_sprite_path",
	"sleep_anchor",
	"is_poi",
	"poi_id",
	"poi_name",
	"hazard_level",
]

var completed_events: Dictionary = {} # event_id -> true
var gateway_states: Dictionary = {} # gateway_id -> bool
var core_states: Dictionary = {} # core_id -> neutral Dictionary
var node_profile_patches: Dictionary = {} # node_id -> neutral Dictionary
var permanent_node_hex_patches: Dictionary = {} # node_id -> Vector2i -> patch

var _last_save_error := ""
var profile_path := SAVE_PATH


func _ready() -> void:
	if Engine.is_editor_hint() or OS.get_cmdline_args().has("--script"):
		return
	load_profile()


func get_meta_flags() -> Dictionary:
	var flags := gateway_states.duplicate(true)
	for event_id in completed_events.keys():
		flags[str(event_id)] = bool(completed_events[event_id])
	return flags


func is_event_completed(event_id: String) -> bool:
	return bool(completed_events.get(event_id, false))


func complete_event(event_id: String, effects: Array = []) -> bool:
	if event_id.is_empty():
		return false
	var was_completed := is_event_completed(event_id)
	completed_events[event_id] = true
	apply_effects(effects, false)
	if not was_completed:
		meta_event_completed.emit(event_id)
	save_profile()
	return not was_completed


func apply_effects(effects: Array, save_after: bool = true) -> void:
	for effect in effects:
		if not effect is Dictionary:
			continue
		match str(effect.get("type", "")):
			"set_gateway":
				set_gateway_unsealed(
					str(effect.get("gateway_id", "")),
					bool(effect.get("unsealed", true)),
					false
				)
			"patch_node_profile":
				var node_id := str(effect.get("node_id", ""))
				var patch: Dictionary = effect.get("patch", {})
				if not node_id.is_empty() and not patch.is_empty():
					var merged: Dictionary = node_profile_patches.get(node_id, {}).duplicate(true)
					merged.merge(patch, true)
					node_profile_patches[node_id] = merged
			"set_core_state":
				var core_id := str(effect.get("core_id", ""))
				if not core_id.is_empty():
					core_states[core_id] = effect.get("state", {}).duplicate(true)
	if save_after:
		save_profile()


func set_gateway_unsealed(
	gateway_id: String,
	unsealed: bool = true,
	save_after: bool = true
) -> void:
	if gateway_id.is_empty():
		return
	var flag_id := gateway_id
	if not flag_id.begins_with("gateway_"):
		flag_id = "gateway_%s_unsealed" % gateway_id
	elif not flag_id.ends_with("_unsealed"):
		flag_id += "_unsealed"
	if bool(gateway_states.get(flag_id, false)) == unsealed:
		return
	gateway_states[flag_id] = unsealed
	gateway_state_changed.emit(flag_id, unsealed)
	if save_after:
		save_profile()


func is_gateway_unsealed(gateway_id: String) -> bool:
	var flag_id := gateway_id
	if not flag_id.begins_with("gateway_"):
		flag_id = "gateway_%s_unsealed" % gateway_id
	elif not flag_id.ends_with("_unsealed"):
		flag_id += "_unsealed"
	return bool(gateway_states.get(flag_id, false))


func get_node_profile_patch(node_id: String) -> Dictionary:
	return node_profile_patches.get(node_id, {}).duplicate(true)


func get_core_state(core_id: String) -> Dictionary:
	return core_states.get(core_id, {}).duplicate(true)


func apply_patch_to_record(node_id: String, coords: Vector2i, record: HexRecord) -> void:
	if node_id.is_empty() or record == null:
		return
	var node_patches: Dictionary = permanent_node_hex_patches.get(node_id, {})
	var patch: Dictionary = node_patches.get(coords, {})
	for field_name in STRUCTURAL_FIELDS:
		if patch.has(field_name):
			record.set(field_name, patch[field_name])


func capture_node_mutations(
	node_id: String,
	baseline_records: Dictionary,
	hex_records: Dictionary
) -> void:
	if node_id.is_empty():
		return
	var node_patches: Dictionary = permanent_node_hex_patches.get(node_id, {}).duplicate(true)
	for patched_coords in node_patches.keys():
		if not baseline_records.has(patched_coords):
			node_patches.erase(patched_coords)
	# A permanent node can mutate only coordinates in its stable authored
	# baseline. Runtime boundary probes and procedural spillover are never Meta.
	for coords in baseline_records.keys():
		if not coords is Vector2i:
			continue
		var record: HexRecord = hex_records.get(coords)
		if record == null:
			continue
		var baseline: HexRecord = baseline_records.get(coords)
		if baseline == null:
			continue
		var patch: Dictionary = {}
		for field_name in STRUCTURAL_FIELDS:
			var baseline_value: Variant = baseline.get(field_name)
			var current_value: Variant = record.get(field_name)
			if baseline_value != current_value:
				patch[field_name] = current_value
		if patch.is_empty():
			node_patches.erase(coords)
		else:
			node_patches[coords] = patch
	permanent_node_hex_patches[node_id] = node_patches
	save_profile()


func reset_profile() -> void:
	completed_events.clear()
	gateway_states.clear()
	core_states.clear()
	node_profile_patches.clear()
	permanent_node_hex_patches.clear()
	save_profile()


func save_profile(path: String = "") -> bool:
	if path.is_empty():
		path = profile_path
	_last_save_error = ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_last_save_error = "Could not open %s for writing. Error %d." % [
			path, FileAccess.get_open_error()
		]
		push_error("[MetaProgressionStore] " + _last_save_error)
		return false
	var node_patch_entries: Array = []
	for node_id in permanent_node_hex_patches.keys():
		var hex_entries: Array = []
		var node_patches: Dictionary = permanent_node_hex_patches[node_id]
		for coords in node_patches.keys():
			hex_entries.append({"coords": coords, "patch": node_patches[coords]})
		node_patch_entries.append({"node_id": node_id, "hexes": hex_entries})
	var payload := {
		"version": SAVE_VERSION,
		"completed_events": completed_events.duplicate(true),
		"gateway_states": gateway_states.duplicate(true),
		"core_states": core_states.duplicate(true),
		"node_profile_patches": node_profile_patches.duplicate(true),
		"permanent_node_hex_patches": node_patch_entries,
	}
	file.store_string(JSON.stringify(_encode_variant(payload), "\t"))
	file.close()
	profile_saved.emit(path)
	return true


func load_profile(path: String = "") -> bool:
	if path.is_empty():
		path = profile_path
	_last_save_error = ""
	completed_events.clear()
	gateway_states.clear()
	core_states.clear()
	node_profile_patches.clear()
	permanent_node_hex_patches.clear()
	if not FileAccess.file_exists(path):
		_migrate_legacy_profile()
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_last_save_error = "Could not open %s for reading." % path
		return false
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		_last_save_error = "Invalid Meta Progress JSON."
		return false
	var data: Dictionary = _decode_variant(json.data)
	if int(data.get("version", -1)) != SAVE_VERSION:
		_last_save_error = "Unsupported Meta Progress version."
		return false
	completed_events = data.get("completed_events", {}).duplicate(true)
	gateway_states = data.get("gateway_states", {}).duplicate(true)
	core_states = data.get("core_states", {}).duplicate(true)
	node_profile_patches = data.get("node_profile_patches", {}).duplicate(true)
	for node_entry in data.get("permanent_node_hex_patches", []):
		if not node_entry is Dictionary:
			continue
		var node_id := str(node_entry.get("node_id", ""))
		var node_patches: Dictionary = {}
		for hex_entry in node_entry.get("hexes", []):
			if not hex_entry is Dictionary:
				continue
			var coords: Variant = hex_entry.get("coords")
			if coords is Vector2i:
				node_patches[coords] = hex_entry.get("patch", {}).duplicate(true)
		permanent_node_hex_patches[node_id] = node_patches
	return true


func get_last_save_error() -> String:
	return _last_save_error


func _migrate_legacy_profile() -> void:
	## Preserve the only safely mappable legacy Meta flag. The old coordinate-only
	## patches stay in their original file rather than leaking into every node.
	if not FileAccess.file_exists(LEGACY_WORLD_PROFILE_PATH):
		return
	var file := FileAccess.open(LEGACY_WORLD_PROFILE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		return
	if bool(json.data.get("core_activated", false)):
		completed_events["legacy_core_activated"] = true
	save_profile()


func _encode_variant(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2I:
			return {VARIANT_TYPE_KEY: "Vector2i", "x": value.x, "y": value.y}
		TYPE_ARRAY:
			var encoded_array: Array = []
			for item in value:
				encoded_array.append(_encode_variant(item))
			return encoded_array
		TYPE_DICTIONARY:
			var encoded_dictionary: Dictionary = {}
			for key in value.keys():
				encoded_dictionary[str(key)] = _encode_variant(value[key])
			return encoded_dictionary
		_:
			return value


func _decode_variant(value: Variant) -> Variant:
	if value is Array:
		var decoded_array: Array = []
		for item in value:
			decoded_array.append(_decode_variant(item))
		return decoded_array
	if value is Dictionary:
		if str(value.get(VARIANT_TYPE_KEY, "")) == "Vector2i":
			return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
		var decoded_dictionary: Dictionary = {}
		for key in value.keys():
			decoded_dictionary[key] = _decode_variant(value[key])
		return decoded_dictionary
	return value
