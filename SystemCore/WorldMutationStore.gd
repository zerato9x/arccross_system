extends Node

## Cross-run world mutation profile. Survives run restarts and layers on top of
## the authored map baseline from AuthoredWorldMap.

signal profile_saved(path: String)
signal core_activation_changed(activated: bool)

const SAVE_PATH := "user://arccross_world_profile.json"
const SAVE_VERSION: int = 1
const VARIANT_TYPE_KEY: String = "__arccross_type"
const _WorldMutationRules := preload("res://SystemCore/WorldMutationRules.gd")
const _AuthoredWorldMap := preload("res://WorldCore/AuthoredWorldMap.gd")

var map_id: String = ""
var core_activated: bool = false
var hex_patches: Dictionary = {} # Vector2i -> Dictionary

var _last_save_error: String = ""


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	load_profile()


func apply_patch(coords: Vector2i, hex: MacroHexData) -> void:
	_WorldMutationRules.apply_patch(hex, hex_patches.get(coords, {}))


func set_patch(coords: Vector2i, patch: Dictionary) -> void:
	if patch.is_empty():
		hex_patches.erase(coords)
		return
	hex_patches[coords] = _WorldMutationRules.merge_patches(
		hex_patches.get(coords, {}),
		patch
	)


func clear_patch(coords: Vector2i) -> void:
	hex_patches.erase(coords)


func mark_core_activated(activated: bool = true) -> void:
	if core_activated == activated:
		return
	core_activated = activated
	core_activation_changed.emit(core_activated)
	save_profile()


func capture_run_mutations(
	authored_map: Resource,
	hex_records: Dictionary,
	world_seed: String
) -> void:
	if authored_map == null or not authored_map.has_method("has_hex"):
		return
	if map_id.is_empty():
		map_id = authored_map.map_id
	elif map_id != authored_map.map_id:
		push_warning(
			"[WorldMutationStore] Run map '%s' does not match profile '%s'."
			% [authored_map.map_id, map_id]
		)

	for coords in hex_records.keys():
		if not coords is Vector2i:
			continue
		var record: HexRecord = hex_records[coords]
		if record == null:
			continue
		var baseline := _baseline_hex(authored_map, coords, world_seed)
		var patch: Dictionary = _WorldMutationRules.diff_from_baseline(baseline, record)
		if patch.is_empty():
			continue
		set_patch(coords, patch)

	save_profile()


func reset_profile() -> void:
	map_id = ""
	core_activated = false
	hex_patches.clear()
	save_profile()


func save_profile(path: String = SAVE_PATH) -> bool:
	_last_save_error = ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_last_save_error = (
			"Could not open %s for writing. Error %d."
			% [path, FileAccess.get_open_error()]
		)
		push_error("[WorldMutationStore] " + _last_save_error)
		return false

	var hex_entries: Array = []
	for coords in hex_patches.keys():
		hex_entries.append({
			"coords": coords,
			"patch": hex_patches[coords].duplicate(true),
		})

	file.store_string(
		JSON.stringify(
			_encode_variant(
				{
					"version": SAVE_VERSION,
					"map_id": map_id,
					"core_activated": core_activated,
					"hex_patches": hex_entries,
				}
			),
			"\t"
		)
	)
	file.close()
	profile_saved.emit(path)
	return true


func load_profile(path: String = SAVE_PATH) -> bool:
	_last_save_error = ""
	hex_patches.clear()
	if not FileAccess.file_exists(path):
		return true

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_last_save_error = (
			"Could not open %s for reading. Error %d."
			% [path, FileAccess.get_open_error()]
		)
		push_error("[WorldMutationStore] " + _last_save_error)
		return false

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		_last_save_error = "Invalid world profile JSON."
		push_error("[WorldMutationStore] " + _last_save_error)
		return false

	var data: Dictionary = _decode_variant(json.data)
	if int(data.get("version", -1)) != SAVE_VERSION:
		_last_save_error = "Unsupported world profile version."
		push_error("[WorldMutationStore] " + _last_save_error)
		return false

	map_id = str(data.get("map_id", ""))
	core_activated = bool(data.get("core_activated", false))
	for entry in data.get("hex_patches", []):
		if not entry is Dictionary:
			continue
		var coords: Variant = entry.get("coords")
		var patch: Variant = entry.get("patch")
		if coords is Vector2i and patch is Dictionary:
			hex_patches[coords] = patch.duplicate(true)
	return true


func get_last_save_error() -> String:
	return _last_save_error


func _baseline_hex(
	authored_map: Resource,
	coords: Vector2i,
	world_seed: String
) -> MacroHexData:
	if authored_map.has_hex(coords):
		return authored_map.build_hex_data(coords, world_seed)
	return HexWorldGenerator.build_void_hex(coords)


func _encode_variant(value):
	match typeof(value):
		TYPE_VECTOR2I:
			return {
				VARIANT_TYPE_KEY: "Vector2i",
				"x": value.x,
				"y": value.y,
			}
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


func _decode_variant(value):
	if value is Array:
		var decoded_array: Array = []
		for item in value:
			decoded_array.append(_decode_variant(item))
		return decoded_array
	if value is Dictionary:
		var encoded_type: String = value.get(VARIANT_TYPE_KEY, "")
		if encoded_type == "Vector2i":
			return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
		var decoded_dictionary: Dictionary = {}
		for key in value.keys():
			decoded_dictionary[key] = _decode_variant(value[key])
		return decoded_dictionary
	return value
