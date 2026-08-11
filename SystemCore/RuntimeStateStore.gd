extends Node
class_name RuntimeStateStore

## Authoritative in-memory state. Top-level records use typed Resources
## (EntityRecord, HexRecord). Cross-domain payloads within those records
## remain as neutral Dictionaries to preserve domain isolation.

signal world_time_advanced(
	previous_minutes: int,
	current_minutes: int,
	elapsed_minutes: int
)
signal save_completed(path: String)
signal load_completed(path: String)
signal persistence_failed(operation: String, message: String)

const SAVE_VERSION: int = 12
const WORLD_GENERATION_VERSION: int = 3
const DEFAULT_SAVE_PATH: String = "user://arccross_run.json"
const VARIANT_TYPE_KEY: String = "__arccross_type"
const _PersistenceCodec := preload("res://SystemCore/RuntimePersistenceCodec.gd")
const _RecordRepository := preload("res://SystemCore/RuntimeRecordRepository.gd")
const _NodeSnapshots := preload("res://SystemCore/NodeRuntimeSnapshotRepository.gd")
const _RunSlots := preload("res://SystemCore/RunSlotRepository.gd")

var world_seed: String = ""
var world_time_minutes: int = GameTimeRules.STARTING_WORLD_MINUTES
var player_coords: Vector2i = Vector2i.ZERO
var player_record: EntityRecord = null
var player_revision: int = 0
## Campaign node-graph state (MacroMapGraph.to_dict()). Empty until a campaign begins.
var campaign_graph: Dictionary = {}
var active_node_id: String = ""
var active_arrival_direction: int = GameEnums.MacroTravelDirection.SOUTH
## Character/run-owned opening state. Permanent infrastructure stays in MetaProgression.
var run_flags: Dictionary = {}
## Run-local zone snapshots. Cleared with the disposable run and never written
## to the cross-run Meta Progress profile.
var node_runtime_snapshots: Dictionary = {} # node_id -> neutral snapshot

var entity_records: Dictionary = {} # String entity_id -> EntityRecord
var entity_ids_by_coords: Dictionary = {} # Vector2i -> String entity_id
var hex_records: Dictionary = {} # Vector2i -> HexRecord
var ground_item_records: Dictionary = {} # Vector2i -> Array[Dictionary]
## Shared action/signal state. These records remain neutral and are serialized
## with the active node snapshot so presentation cannot become authoritative.
var active_world_actions: Dictionary = {} # action_id -> request/work state
var world_signal_records: Dictionary = {} # signal_id -> WorldSignalRecord

var _pending_loaded_world: bool = false
var _pending_new_run_setup: Dictionary = {}
var _last_persistence_error: String = ""
var _item_ownership_ledger: RuntimeItemOwnershipLedger

func _ready() -> void:
	if Engine.is_editor_hint() or OS.get_cmdline_args().has("--script"):
		return
	# Start waiting for MainMenu to load/start instead of autoloading.
	_ensure_item_ownership_ledger()


func _ensure_item_ownership_ledger() -> RuntimeItemOwnershipLedger:
	if _item_ownership_ledger == null:
		_item_ownership_ledger = RuntimeItemOwnershipLedger.new(self)
	return _item_ownership_ledger

func begin_new_world(seed_value: String, setup_state: Dictionary = {}) -> void:
	world_seed = seed_value
	world_time_minutes = GameTimeRules.STARTING_WORLD_MINUTES
	player_coords = Vector2i.ZERO
	player_record = null
	player_revision = 0
	campaign_graph = {}
	active_node_id = ""
	active_arrival_direction = GameEnums.MacroTravelDirection.SOUTH
	run_flags = {"world_generation_version": WORLD_GENERATION_VERSION}
	_pending_new_run_setup = setup_state.duplicate(true)
	if not setup_state.is_empty():
		run_flags = {
			"eviction_completed": true,
			"chosen_start_node_id": str(setup_state.get("start_node_id", "")),
			"intro_version": int(setup_state.get("intro_version", 1)),
			"world_generation_version": WORLD_GENERATION_VERSION,
		}
	node_runtime_snapshots.clear()
	entity_records.clear()
	entity_ids_by_coords.clear()
	hex_records.clear()
	ground_item_records.clear()
	active_world_actions.clear()
	world_signal_records.clear()
	_pending_loaded_world = false


func has_pending_new_run_setup() -> bool:
	return not _pending_new_run_setup.is_empty()


func consume_pending_new_run_setup() -> Dictionary:
	var setup := _pending_new_run_setup.duplicate(true)
	_pending_new_run_setup.clear()
	return setup

func advance_world_time(elapsed_minutes: int) -> Dictionary:
	var elapsed := maxi(0, elapsed_minutes)
	var previous := world_time_minutes
	world_time_minutes += elapsed
	world_time_advanced.emit(previous, world_time_minutes, elapsed)
	return get_world_time_snapshot()


func register_world_signal(signal_record: WorldSignalRecord) -> void:
	if signal_record == null or signal_record.signal_id.is_empty():
		return
	world_signal_records[signal_record.signal_id] = signal_record


func reserve_world_action(action_id: String, state: Dictionary) -> bool:
	## Reservations are the lightweight concurrency boundary for work. A target
	## can only have one active actor/method until the receipt is committed or
	## interrupted; planners must re-query after a rejected reservation.
	if action_id.is_empty() or active_world_actions.has(action_id):
		return false
	active_world_actions[action_id] = state.duplicate(true)
	return true


func update_world_action(action_id: String, state: Dictionary) -> void:
	if action_id.is_empty():
		return
	active_world_actions[action_id] = state.duplicate(true)


func release_world_action(action_id: String) -> void:
	if not action_id.is_empty():
		active_world_actions.erase(action_id)


func get_world_action(action_id: String) -> Dictionary:
	return active_world_actions.get(action_id, {}).duplicate(true)


func get_active_world_signals() -> Array[WorldSignalRecord]:
	var active: Array[WorldSignalRecord] = []
	for value in world_signal_records.values():
		var signal_record := value as WorldSignalRecord
		if signal_record != null and signal_record.is_active(world_time_minutes):
			active.append(signal_record)
	return active


func prune_world_signals() -> void:
	for signal_id in world_signal_records.keys():
		var signal_record := world_signal_records[signal_id] as WorldSignalRecord
		if signal_record == null or not signal_record.is_active(world_time_minutes):
			world_signal_records.erase(signal_id)

func get_world_time_snapshot() -> Dictionary:
	return GameTimeRules.clock_snapshot(world_time_minutes)

func set_player_record(record: Dictionary, coords: Vector2i) -> void:
	player_record = EntityRecord.from_dict(record)
	player_coords = coords
	player_revision = maxi(player_revision, player_record.revision)

func update_player_runtime(runtime_state: Dictionary, coords: Vector2i) -> void:
	player_coords = coords
	if player_record == null:
		player_record = EntityRecord.new()
		player_record.entity_id = "player"
		player_record.kind = GameEnums.RuntimeEntityKind.PLAYER
		player_record.life_state = GameEnums.EntityLifeState.ALIVE
	player_record.coords = coords
	player_record.revision = maxi(player_record.revision + 1, player_revision + 1)
	player_revision = player_record.revision
	player_record.runtime = runtime_state.duplicate(true)
	player_record.life_state = (
		GameEnums.EntityLifeState.DEAD
		if runtime_state.get("is_dead", false)
		else GameEnums.EntityLifeState.ALIVE
	)

func register_entity(record) -> String:
	var entity: EntityRecord
	if record is EntityRecord:
		entity = record
	elif record is Dictionary:
		entity = EntityRecord.from_dict(record)
	else:
		push_error("[STATE STORE] Cannot register: unexpected record type.")
		return ""

	if entity.entity_id.is_empty():
		entity.entity_id = _create_entity_id()

	entity_records[entity.entity_id] = entity
	entity_ids_by_coords[entity.coords] = entity.entity_id
	return entity.entity_id

func get_entity(entity_id: String) -> EntityRecord:
	if not entity_records.has(entity_id):
		return null
	return entity_records[entity_id]


## Snapshot-only boundary for extracted services. Legacy callers may still use
## get_entity(), but new application services must not receive the authority.
func get_entity_snapshot(entity_id: String) -> Dictionary:
	var record := get_entity(entity_id)
	return record.to_dict().duplicate(true) if record != null else {}

func get_entity_at(coords: Vector2i) -> EntityRecord:
	var entity_id: String = entity_ids_by_coords.get(coords, "")
	return get_entity(entity_id)


func get_entity_snapshot_at(coords: Vector2i) -> Dictionary:
	var entity_id: String = entity_ids_by_coords.get(coords, "")
	return get_entity_snapshot(entity_id)


func get_entity_id_at(coords: Vector2i) -> String:
	return str(entity_ids_by_coords.get(coords, ""))

func has_entity_at(coords: Vector2i) -> bool:
	return entity_ids_by_coords.has(coords)

func get_all_entity_records() -> Array:
	var records: Array = []
	for record in entity_records.values():
		records.append(record)
	return records


func get_all_entity_snapshots() -> Array:
	var snapshots: Array = []
	for record_value in entity_records.values():
		if record_value is EntityRecord:
			snapshots.append((record_value as EntityRecord).to_dict().duplicate(true))
	return snapshots

func update_entity_runtime(entity_id: String, runtime_state: Dictionary) -> void:
	if not entity_records.has(entity_id):
		return
	var entity: EntityRecord = entity_records[entity_id]
	var preserved_runtime := _preserved_runtime_keys(entity.runtime)
	entity.runtime = runtime_state.duplicate(true)
	for key in preserved_runtime.keys():
		if not entity.runtime.has(key):
			entity.runtime[key] = preserved_runtime[key]

func move_entity(entity_id: String, target_coords: Vector2i) -> bool:
	if not entity_records.has(entity_id):
		return false
	var entity: EntityRecord = entity_records[entity_id]
	if entity.life_state != GameEnums.EntityLifeState.ALIVE:
		return false

	var occupying_id: String = entity_ids_by_coords.get(target_coords, "")
	if not occupying_id.is_empty() and occupying_id != entity_id:
		var occupying_record := get_entity(occupying_id)
		if (
			occupying_record != null
			and occupying_record.life_state == GameEnums.EntityLifeState.ALIVE
		):
			return false

	var old_coords := entity.coords
	if entity_ids_by_coords.get(old_coords, "") == entity_id:
		entity_ids_by_coords.erase(old_coords)
	entity.coords = target_coords
	entity_ids_by_coords[target_coords] = entity_id
	return true

func set_entity_life_state(entity_id: String, life_state: GameEnums.EntityLifeState) -> void:
	if not entity_records.has(entity_id):
		return
	var record: EntityRecord = entity_records[entity_id]
	record.life_state = life_state
	if life_state == GameEnums.EntityLifeState.DEAD:
		if entity_ids_by_coords.get(record.coords, "") == entity_id:
			entity_ids_by_coords.erase(record.coords)

func set_entity_world_status(
	entity_id: String,
	status: GameEnums.EntityWorldStatus
) -> void:
	if not entity_records.has(entity_id):
		return
	entity_records[entity_id].world_status = status

func is_entity_hostile(entity_id: String) -> bool:
	if not entity_records.has(entity_id):
		return false
	return entity_records[entity_id].world_status == GameEnums.EntityWorldStatus.HOSTILE

func patch_entity_record(entity_id: String, patch: Dictionary) -> void:
	if not entity_records.has(entity_id):
		return
	var entity: EntityRecord = entity_records[entity_id]
	for key in patch.keys():
		if entity.get(key) != null or key in [
			"entity_id", "kind", "life_state", "world_status",
			"coords", "definition", "runtime", "negotiation_attempts"
		]:
			entity.set(key, patch[key])

func _preserved_runtime_keys(runtime_state: Dictionary) -> Dictionary:
	var preserved: Dictionary = {}
	for key in runtime_state.keys():
		if str(key).begins_with("macro_"):
			preserved[key] = runtime_state[key]
	return preserved

func is_entity_alive(entity_id: String) -> bool:
	if not entity_records.has(entity_id):
		return false
	return entity_records[entity_id].life_state == GameEnums.EntityLifeState.ALIVE

func set_hex_record(coords: Vector2i, record) -> void:
	if record is HexRecord:
		hex_records[coords] = record
	elif record is Dictionary:
		hex_records[coords] = HexRecord.from_dict(record)

func get_hex_record(coords: Vector2i) -> HexRecord:
	if not hex_records.has(coords):
		return null
	return hex_records[coords]


func get_hex_snapshot(coords: Vector2i) -> Dictionary:
	var record := get_hex_record(coords)
	return record.to_dict().duplicate(true) if record != null else {}


func get_hex_coordinates() -> Array:
	return hex_records.keys().duplicate()

func add_ground_items(coords: Vector2i, item_states: Array) -> void:
	for item_state in item_states:
		if not item_state is Dictionary:
			continue
		var normalized: Dictionary = (item_state as Dictionary).duplicate(true)
		var instance_id := str(normalized.get("instance_id", ""))
		if instance_id.is_empty():
			continue
		# Ground insertion is an ownership transfer. Remove stale copies first so
		# an item cannot exist in rubble, on the ground, and in an actor inventory.
		_ensure_item_ownership_ledger().remove_item_instance(instance_id)
		normalized["owner_id"] = ""
		normalized["physical_location"] = "ground"
		if not ground_item_records.has(coords):
			ground_item_records[coords] = []
		ground_item_records[coords].append(normalized)


func find_item_ownership(instance_id: String) -> Dictionary:
	return _ensure_item_ownership_ledger().find_item_ownership(instance_id)


func transfer_item_to_entity(entity_id: String, item_state: Dictionary) -> bool:
	return _ensure_item_ownership_ledger().transfer_item_to_entity(entity_id, item_state)


func _remove_item_instance(instance_id: String) -> void:
	_ensure_item_ownership_ledger().remove_item_instance(instance_id)

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

func get_slot_path(slot: int) -> String:
	return _RunSlots.path_for(slot)

func get_save_metadata(slot: int) -> Dictionary:
	return _RunSlots.metadata_for(slot, SAVE_VERSION, WORLD_GENERATION_VERSION)

func save_to_slot(slot: int) -> bool:
	return save_to_disk(get_slot_path(slot))

func load_from_slot(slot: int) -> bool:
	return load_from_disk(get_slot_path(slot))

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
	var file_version := int(decoded.get("version", -1))
	if file_version != SAVE_VERSION:
		_backup_incompatible_save(path, file_version)
		return _fail_persistence(
			"load",
			"This run save uses world-system version %s; version %d is required after the pre-combat-overhaul and hex-world migration. A new run is required; permanent meta progression is preserved."
			% [str(decoded.get("version", "missing")), SAVE_VERSION]
		)
	var file_generation := int(decoded.get("world_generation_version", -1))
	if file_generation != WORLD_GENERATION_VERSION:
		_backup_incompatible_save(path, file_generation)
		return _fail_persistence(
			"load",
			"This run was generated with world version %s; version %d is required after the pre-combat-overhaul and hex-world migration. A new run is required; permanent meta progression is preserved."
			% [str(decoded.get("world_generation_version", "missing")), WORLD_GENERATION_VERSION]
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


func capture_node_runtime(node_id: String) -> void:
	if node_id.is_empty():
		return
	node_runtime_snapshots[node_id] = _NodeSnapshots.capture(
		entity_records,
		hex_records,
		ground_item_records,
		active_world_actions,
		world_signal_records,
		world_time_minutes,
		player_revision
	)


func has_node_runtime(node_id: String) -> bool:
	return node_runtime_snapshots.has(node_id)


func restore_node_runtime(node_id: String) -> bool:
	if not node_runtime_snapshots.has(node_id):
		return false
	var snapshot: Dictionary = node_runtime_snapshots[node_id]
	player_revision = maxi(player_revision, int(snapshot.get("player_revision", 0)))
	entity_records.clear()
	entity_ids_by_coords.clear()
	hex_records.clear()
	ground_item_records.clear()
	active_world_actions.clear()
	world_signal_records.clear()
	var restored := _NodeSnapshots.restore_records(snapshot)
	player_revision = maxi(player_revision, int(restored.get("player_revision", 0)))
	_RecordRepository.restore_entities(
		restored.get("entities", []),
		Callable(self, "register_entity")
	)
	hex_records = restored.get("hexes", {})
	for coords in hex_records.keys():
		var restored_record := hex_records[coords] as HexRecord
		if restored_record != null:
			restored_record.trace_records = _active_trace_records(
				restored_record.trace_records, world_time_minutes
			)
	ground_item_records = restored.get("ground_items", {})
	active_world_actions = restored.get("active_world_actions", {})
	for signal_record in restored.get("world_signals", []):
		if signal_record is WorldSignalRecord:
			register_world_signal(signal_record)
	return true


func _active_trace_records(records: Array[Dictionary], current_minute: int) -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	for trace in records:
		var expires := int(trace.get("expires_minute", -1))
		if expires < 0 or expires > current_minute:
			active.append(trace.duplicate(true))
	return active

# ---------------------------------------------------------
# SERIALIZATION BOUNDARY — Resources flatten to Dicts here
# ---------------------------------------------------------

func _capture_save_snapshot() -> Dictionary:
	var entities: Array = _RecordRepository.capture_entities(entity_records)
	var hexes: Array = _RecordRepository.capture_hexes(hex_records)
	var ground_items: Array = _RecordRepository.capture_ground_items(ground_item_records)

	return {
		"version": SAVE_VERSION,
		"world_generation_version": WORLD_GENERATION_VERSION,
		"world_seed": world_seed,
		"world_time_minutes": world_time_minutes,
		"player_revision": player_revision,
		"player_coords": player_coords,
		"player_record": player_record.to_dict() if player_record else {},
		"entities": entities,
		"hexes": hexes,
		"ground_items": ground_items,
		"campaign_graph": campaign_graph.duplicate(true),
		"active_node_id": active_node_id,
		"active_arrival_direction": active_arrival_direction,
		"run_flags": run_flags.duplicate(true),
		"node_runtime_snapshots": node_runtime_snapshots.duplicate(true),
		"active_world_actions": active_world_actions.duplicate(true),
		"world_signals": _world_signals_to_dict(),
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
	player_revision = maxi(0, int(snapshot.get("player_revision", 0)))
	campaign_graph = snapshot.get("campaign_graph", {}).duplicate(true)
	active_node_id = str(snapshot.get("active_node_id", ""))
	active_arrival_direction = int(snapshot.get(
		"active_arrival_direction",
		GameEnums.MacroTravelDirection.SOUTH
	))
	run_flags = snapshot.get("run_flags", {}).duplicate(true)
	_pending_new_run_setup.clear()
	node_runtime_snapshots = snapshot.get("node_runtime_snapshots", {}).duplicate(true)

	var player_data: Dictionary = snapshot.get("player_record", {})
	player_record = EntityRecord.from_dict(player_data) if not player_data.is_empty() else null
	if player_record != null:
		player_revision = maxi(player_revision, player_record.revision)

	entity_records.clear()
	entity_ids_by_coords.clear()
	hex_records.clear()
	ground_item_records.clear()
	active_world_actions.clear()
	world_signal_records.clear()

	_RecordRepository.restore_entities(
		snapshot.get("entities", []),
		Callable(self, "register_entity")
	)
	hex_records = _RecordRepository.restore_hexes(snapshot.get("hexes", []))
	ground_item_records = _RecordRepository.restore_ground_items(
		snapshot.get("ground_items", [])
	)
	active_world_actions = snapshot.get("active_world_actions", {}).duplicate(true)
	for signal_data in snapshot.get("world_signals", []):
		if signal_data is Dictionary:
			register_world_signal(WorldSignalRecord.from_dict(signal_data))

	return true


func _world_signals_to_dict() -> Array:
	var result: Array = []
	for signal_record in world_signal_records.values():
		if signal_record is WorldSignalRecord:
			result.append(signal_record.to_dict())
	return result

func _encode_variant(value):
	return _PersistenceCodec.encode_variant(value)

func _decode_variant(value):
	return _PersistenceCodec.decode_variant(value)

func _fail_persistence(operation: String, message: String) -> bool:
	_last_persistence_error = message
	push_error("[PERSISTENCE] " + message)
	persistence_failed.emit(operation, message)
	return false


func _backup_incompatible_save(path: String, old_version: int) -> void:
	## Keep rejected user saves recoverable without polluting project fixtures.
	if not path.begins_with("user://") or not FileAccess.file_exists(path):
		return
	var absolute_path := ProjectSettings.globalize_path(path)
	var contents := FileAccess.get_file_as_string(path)
	if contents.is_empty():
		return
	var backup_path := "%s.v%s.bak" % [absolute_path, old_version]
	var backup := FileAccess.open(backup_path, FileAccess.WRITE)
	if backup != null:
		backup.store_string(contents)
		backup.close()

func _create_entity_id() -> String:
	return "entity_" + str(ResourceUID.create_id())
