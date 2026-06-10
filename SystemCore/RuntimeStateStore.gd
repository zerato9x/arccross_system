extends Node
class_name RuntimeStateStore

## Authoritative in-memory state. Records contain only engine primitives,
## dictionaries, arrays, and values defined by GameEnums.

signal world_time_advanced(
	previous_minutes: int,
	current_minutes: int,
	elapsed_minutes: int
)
signal save_completed(path: String)
signal load_completed(path: String)
signal persistence_failed(operation: String, message: String)

const SAVE_VERSION: int = 1
const DEFAULT_SAVE_PATH: String = "user://arccross_run.json"
const VARIANT_TYPE_KEY: String = "__arccross_type"

var world_seed: String = ""
var world_time_minutes: int = GameTimeRules.STARTING_WORLD_MINUTES
var player_coords: Vector2i = Vector2i.ZERO
var player_record: Dictionary = {}

var entity_records: Dictionary = {} # String entity_id -> Dictionary
var entity_ids_by_coords: Dictionary = {} # Vector2i -> String entity_id
var hex_records: Dictionary = {} # Vector2i -> Dictionary
var ground_item_records: Dictionary = {} # Vector2i -> Array[Dictionary]

var _pending_loaded_world: bool = false
var _last_persistence_error: String = ""

func _ready() -> void:
	if Engine.is_editor_hint() or OS.get_cmdline_args().has("--script"):
		return
	if has_save_file():
		load_from_disk()

func begin_new_world(seed: String) -> void:
	world_seed = seed
	world_time_minutes = GameTimeRules.STARTING_WORLD_MINUTES
	player_coords = Vector2i.ZERO
	player_record.clear()
	entity_records.clear()
	entity_ids_by_coords.clear()
	hex_records.clear()
	ground_item_records.clear()
	_pending_loaded_world = false

func advance_world_time(elapsed_minutes: int) -> Dictionary:
	var elapsed := maxi(0, elapsed_minutes)
	var previous := world_time_minutes
	world_time_minutes += elapsed
	world_time_advanced.emit(previous, world_time_minutes, elapsed)
	return get_world_time_snapshot()

func get_world_time_snapshot() -> Dictionary:
	return GameTimeRules.clock_snapshot(world_time_minutes)

func set_player_record(record: Dictionary, coords: Vector2i) -> void:
	player_record = record.duplicate(true)
	player_coords = coords

func update_player_runtime(runtime_state: Dictionary, coords: Vector2i) -> void:
	player_coords = coords
	if player_record.is_empty():
		player_record = {
			"entity_id": "player",
			"kind": GameEnums.RuntimeEntityKind.PLAYER,
			"life_state": GameEnums.EntityLifeState.ALIVE,
		}
	player_record["coords"] = coords
	player_record["runtime"] = runtime_state.duplicate(true)
	player_record["life_state"] = (
		GameEnums.EntityLifeState.DEAD
		if runtime_state.get("is_dead", false)
		else GameEnums.EntityLifeState.ALIVE
	)

func register_entity(record: Dictionary) -> String:
	var entity_id: String = record.get("entity_id", "")
	if entity_id.is_empty():
		entity_id = _create_entity_id()
		record["entity_id"] = entity_id

	var stored_record := record.duplicate(true)
	entity_records[entity_id] = stored_record

	if stored_record.has("coords"):
		entity_ids_by_coords[stored_record["coords"]] = entity_id

	return entity_id

func get_entity(entity_id: String) -> Dictionary:
	if not entity_records.has(entity_id):
		return {}
	return entity_records[entity_id].duplicate(true)

func get_entity_at(coords: Vector2i) -> Dictionary:
	var entity_id: String = entity_ids_by_coords.get(coords, "")
	return get_entity(entity_id)

func has_entity_at(coords: Vector2i) -> bool:
	return entity_ids_by_coords.has(coords)

func get_all_entity_records() -> Array:
	var records: Array = []
	for record in entity_records.values():
		records.append(record.duplicate(true))
	return records

func update_entity_runtime(entity_id: String, runtime_state: Dictionary) -> void:
	if not entity_records.has(entity_id):
		return
	entity_records[entity_id]["runtime"] = runtime_state.duplicate(true)

func set_entity_life_state(entity_id: String, life_state: GameEnums.EntityLifeState) -> void:
	if not entity_records.has(entity_id):
		return
	entity_records[entity_id]["life_state"] = life_state

func set_entity_world_status(
	entity_id: String,
	status: GameEnums.EntityWorldStatus
) -> void:
	if not entity_records.has(entity_id):
		return
	entity_records[entity_id]["world_status"] = status

func is_entity_hostile(entity_id: String) -> bool:
	if not entity_records.has(entity_id):
		return false
	return entity_records[entity_id].get(
		"world_status",
		GameEnums.EntityWorldStatus.HOSTILE
	) == GameEnums.EntityWorldStatus.HOSTILE

func patch_entity_record(entity_id: String, patch: Dictionary) -> void:
	if not entity_records.has(entity_id):
		return
	for key in patch.keys():
		entity_records[entity_id][key] = patch[key]

func is_entity_alive(entity_id: String) -> bool:
	if not entity_records.has(entity_id):
		return false
	return entity_records[entity_id].get(
		"life_state",
		GameEnums.EntityLifeState.ALIVE
	) == GameEnums.EntityLifeState.ALIVE

func set_hex_record(coords: Vector2i, record: Dictionary) -> void:
	hex_records[coords] = record.duplicate(true)

func get_hex_record(coords: Vector2i) -> Dictionary:
	if not hex_records.has(coords):
		return {}
	return hex_records[coords].duplicate(true)

func add_ground_items(coords: Vector2i, item_states: Array) -> void:
	if not ground_item_records.has(coords):
		ground_item_records[coords] = []
	for item_state in item_states:
		ground_item_records[coords].append(item_state.duplicate(true))

func get_ground_items(coords: Vector2i) -> Array:
	if not ground_item_records.has(coords):
		return []
	return ground_item_records[coords].duplicate(true)

func take_ground_item(coords: Vector2i, instance_id: String) -> Dictionary:
	if not ground_item_records.has(coords) or instance_id.is_empty():
		return {}

	var items: Array = ground_item_records[coords]
	for index in range(items.size()):
		var item_state: Dictionary = items[index]
		if item_state.get("instance_id", "") != instance_id:
			continue
		items.remove_at(index)
		if items.is_empty():
			ground_item_records.erase(coords)
		return item_state.duplicate(true)
	return {}

func has_ground_items(coords: Vector2i) -> bool:
	return ground_item_records.has(coords) and ground_item_records[coords].size() > 0

func save_to_disk(path: String = DEFAULT_SAVE_PATH) -> bool:
	_last_persistence_error = ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail_persistence(
			"save",
			"Could not open %s for writing. Error %d."
			% [path, FileAccess.get_open_error()]
		)

	var encoded: Variant = _encode_variant(_capture_save_snapshot())
	file.store_string(JSON.stringify(encoded, "\t"))
	file.close()
	save_completed.emit(path)
	return true

func load_from_disk(path: String = DEFAULT_SAVE_PATH) -> bool:
	_last_persistence_error = ""
	if not FileAccess.file_exists(path):
		return _fail_persistence("load", "Save file does not exist: %s" % path)

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail_persistence(
			"load",
			"Could not open %s for reading. Error %d."
			% [path, FileAccess.get_open_error()]
		)

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return _fail_persistence(
			"load",
			"Invalid save JSON at line %d: %s"
			% [json.get_error_line(), json.get_error_message()]
		)

	var decoded: Variant = _decode_variant(json.data)
	if not decoded is Dictionary:
		return _fail_persistence("load", "Save root is not a Dictionary.")
	if int(decoded.get("version", -1)) != SAVE_VERSION:
		return _fail_persistence(
			"load",
			"Unsupported save version %s. Expected %d."
			% [str(decoded.get("version", "missing")), SAVE_VERSION]
		)
	if not _restore_save_snapshot(decoded):
		return false

	_pending_loaded_world = true
	load_completed.emit(path)
	return true

func has_save_file(path: String = DEFAULT_SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)

func delete_save_file(path: String = DEFAULT_SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var absolute_path := ProjectSettings.globalize_path(path)
	var error := DirAccess.remove_absolute(absolute_path)
	if error != OK:
		return _fail_persistence(
			"delete",
			"Could not delete %s. Error %d." % [path, error]
		)
	return true

func consume_pending_loaded_world() -> bool:
	if not _pending_loaded_world:
		return false
	_pending_loaded_world = false
	return true

func get_last_persistence_error() -> String:
	return _last_persistence_error

func _capture_save_snapshot() -> Dictionary:
	var entities: Array = []
	for record in entity_records.values():
		entities.append(record.duplicate(true))

	var hexes: Array = []
	for coords in hex_records.keys():
		hexes.append({
			"coords": coords,
			"record": hex_records[coords].duplicate(true),
		})

	var ground_items: Array = []
	for coords in ground_item_records.keys():
		ground_items.append({
			"coords": coords,
			"items": ground_item_records[coords].duplicate(true),
		})

	return {
		"version": SAVE_VERSION,
		"world_seed": world_seed,
		"world_time_minutes": world_time_minutes,
		"player_coords": player_coords,
		"player_record": player_record.duplicate(true),
		"entities": entities,
		"hexes": hexes,
		"ground_items": ground_items,
	}

func _restore_save_snapshot(snapshot: Dictionary) -> bool:
	var loaded_seed: String = snapshot.get("world_seed", "")
	if loaded_seed.is_empty():
		return _fail_persistence("load", "Save is missing its world seed.")

	world_seed = loaded_seed
	world_time_minutes = maxi(
		0,
		int(snapshot.get(
			"world_time_minutes",
			GameTimeRules.STARTING_WORLD_MINUTES
		))
	)
	player_coords = snapshot.get("player_coords", Vector2i.ZERO)
	player_record = snapshot.get("player_record", {}).duplicate(true)
	entity_records.clear()
	entity_ids_by_coords.clear()
	hex_records.clear()
	ground_item_records.clear()

	for record in snapshot.get("entities", []):
		if record is Dictionary:
			register_entity(record.duplicate(true))

	for entry in snapshot.get("hexes", []):
		if not entry is Dictionary:
			continue
		var coords = entry.get("coords")
		if coords is Vector2i:
			set_hex_record(coords, entry.get("record", {}))

	for entry in snapshot.get("ground_items", []):
		if not entry is Dictionary:
			continue
		var coords = entry.get("coords")
		if coords is Vector2i:
			ground_item_records[coords] = entry.get("items", []).duplicate(true)

	return true

func _encode_variant(value):
	match typeof(value):
		TYPE_VECTOR2I:
			return {
				VARIANT_TYPE_KEY: "Vector2i",
				"x": value.x,
				"y": value.y,
			}
		TYPE_VECTOR2:
			return {
				VARIANT_TYPE_KEY: "Vector2",
				"x": value.x,
				"y": value.y,
			}
		TYPE_COLOR:
			return {
				VARIANT_TYPE_KEY: "Color",
				"r": value.r,
				"g": value.g,
				"b": value.b,
				"a": value.a,
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
		match encoded_type:
			"Vector2i":
				return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
			"Vector2":
				return Vector2(
					float(value.get("x", 0.0)),
					float(value.get("y", 0.0))
				)
			"Color":
				return Color(
					float(value.get("r", 0.0)),
					float(value.get("g", 0.0)),
					float(value.get("b", 0.0)),
					float(value.get("a", 1.0))
				)

		var decoded_dictionary: Dictionary = {}
		for key in value.keys():
			decoded_dictionary[key] = _decode_variant(value[key])
		return decoded_dictionary

	return value

func _fail_persistence(operation: String, message: String) -> bool:
	_last_persistence_error = message
	push_error("[PERSISTENCE] " + message)
	persistence_failed.emit(operation, message)
	return false

func _create_entity_id() -> String:
	return "entity_" + str(ResourceUID.create_id())
