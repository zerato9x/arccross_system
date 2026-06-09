extends Node
class_name RuntimeStateStore

## Authoritative in-memory state. Records contain only engine primitives,
## dictionaries, arrays, and values defined by GameEnums.

var world_seed: String = ""
var player_coords: Vector2i = Vector2i.ZERO
var player_record: Dictionary = {}

var entity_records: Dictionary = {} # String entity_id -> Dictionary
var entity_ids_by_coords: Dictionary = {} # Vector2i -> String entity_id
var hex_records: Dictionary = {} # Vector2i -> Dictionary
var ground_item_records: Dictionary = {} # Vector2i -> Array[Dictionary]

func begin_new_world(seed: String) -> void:
	world_seed = seed
	player_coords = Vector2i.ZERO
	player_record.clear()
	entity_records.clear()
	entity_ids_by_coords.clear()
	hex_records.clear()
	ground_item_records.clear()

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

func has_ground_items(coords: Vector2i) -> bool:
	return ground_item_records.has(coords) and ground_item_records[coords].size() > 0

func _create_entity_id() -> String:
	return "entity_" + str(ResourceUID.create_id())
