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

const SAVE_VERSION: int = 14
const MIGRATABLE_SAVE_VERSIONS: Array[int] = [12, 13]
const WORLD_GENERATION_VERSION: int = 3
const DEFAULT_SAVE_PATH: String = "user://arccross_run.json"
const VARIANT_TYPE_KEY: String = "__arccross_type"
const ENTITY_PATCH_KEYS := [
	"owner_id",
	"revision",
	"last_simulated_minute",
	"definition",
	"runtime",
	"knowledge",
	"negotiation_attempts",
]
const _PersistenceCodec := preload("res://SystemCore/RuntimePersistenceCodec.gd")
const _RecordRepository := preload("res://SystemCore/RuntimeRecordRepository.gd")
const _NodeSnapshots := preload("res://SystemCore/NodeRuntimeSnapshotRepository.gd")
const _RunSlots := preload("res://SystemCore/RunSlotRepository.gd")

var world_seed: String = ""
var world_time_minutes: int = GameTimeRules.STARTING_WORLD_MINUTES
var player_record: EntityRecord = null
var _legacy_player_coords: Vector2i = Vector2i.ZERO
var player_coords: Vector2i:
	get:
		return player_record.coords if player_record != null else _legacy_player_coords
	set(value):
		_legacy_player_coords = value
		if player_record != null:
			player_record.coords = value
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
## Run-global pairwise relationship authority. Encounter ledgers are scoped
## snapshots of this state, not competing persistent owners.
var relationship_state: Dictionary = CombatRelationshipLedger.new().to_dict()
var active_combat_handoff: CombatHandoffRecord = null
var applied_combat_encounters: Dictionary = {} # encounter_id -> world minute
var applied_world_receipts: Dictionary = {} # receipt_id -> world minute
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
	player_record = null
	player_coords = Vector2i.ZERO
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
	relationship_state = CombatRelationshipLedger.new().to_dict()
	active_combat_handoff = null
	applied_combat_encounters.clear()
	applied_world_receipts.clear()
	active_world_actions.clear()
	world_signal_records.clear()
	_pending_loaded_world = false


func has_pending_new_run_setup() -> bool:
	return not _pending_new_run_setup.is_empty()


func consume_pending_new_run_setup() -> Dictionary:
	var setup := _pending_new_run_setup.duplicate(true)
	_pending_new_run_setup.clear()
	return setup

func advance_world_time(
	elapsed_minutes: int,
	emit_notification: bool = true
) -> Dictionary:
	var elapsed := maxi(0, elapsed_minutes)
	var previous := world_time_minutes
	world_time_minutes += elapsed
	if emit_notification:
		world_time_advanced.emit(previous, world_time_minutes, elapsed)
	return get_world_time_snapshot()


func emit_world_time_commit(previous_minutes: int, elapsed_minutes: int) -> void:
	var elapsed := maxi(0, elapsed_minutes)
	if elapsed <= 0 or world_time_minutes != previous_minutes + elapsed:
		return
	world_time_advanced.emit(previous_minutes, world_time_minutes, elapsed)


func register_world_signal(signal_record: WorldSignalRecord) -> void:
	if signal_record == null or signal_record.signal_id.is_empty():
		return
	world_signal_records[signal_record.signal_id] = signal_record


func begin_world_action(request: WorldActionRequest) -> WorldActionReservationRecord:
	if request == null or request.actor_id.is_empty() or request.target_id.is_empty():
		return null
	var action_id := str(request.payload.get("action_id", ""))
	if action_id.is_empty():
		# action_id is the identity namespace for one work session. Do not derive
		# a new session from actor/verb/target: a later legal session can repeat
		# that tuple after the first reservation has been completed and released.
		action_id = _new_world_action_session_id(request)
	if active_world_actions.has(action_id):
		return null
	var reservation := WorldActionReservationRecord.new()
	reservation.action_id = action_id
	reservation.node_id = active_node_id
	reservation.actor_id = request.actor_id
	reservation.target_id = request.target_id
	reservation.target_coords = request.target_coords
	reservation.verb_id = request.verb_id
	reservation.method_id = request.method_id
	reservation.expected_actor_revision = request.expected_actor_revision
	reservation.expected_target_revision = request.expected_target_revision
	reservation.expected_hex_revision = int(request.payload.get("expected_hex_revision", -1))
	reservation.started_minute = world_time_minutes
	reservation.state = request.payload.get("reservation_state", {}).duplicate(true)
	if not reservation.validation_error().is_empty():
		return null
	active_world_actions[action_id] = reservation.to_dict()
	return reservation


func _new_world_action_session_id(request: WorldActionRequest) -> String:
	var identity_prefix := "world-session:%s:%s:%s:%s" % [
		active_node_id,
		request.actor_id,
		request.verb_id,
		request.target_id,
	]
	var action_id := "%s:%s" % [identity_prefix, str(ResourceUID.create_id())]
	while active_world_actions.has(action_id):
		action_id = "%s:%s" % [identity_prefix, str(ResourceUID.create_id())]
	return action_id


func get_world_action_reservation(action_id: String) -> WorldActionReservationRecord:
	var data: Variant = active_world_actions.get(action_id, {})
	if not data is Dictionary or data.is_empty():
		return null
	return WorldActionReservationRecord.from_dict(data)


func update_world_action_reservation(
	reservation: WorldActionReservationRecord
) -> bool:
	if reservation == null or reservation.validation_error() != "":
		return false
	if not active_world_actions.has(reservation.action_id):
		return false
	var current := get_world_action_reservation(reservation.action_id)
	if current == null or current.actor_id != reservation.actor_id:
		return false
	active_world_actions[reservation.action_id] = reservation.to_dict()
	return true


func cancel_world_action(action_id: String) -> bool:
	if action_id.is_empty() or not active_world_actions.has(action_id):
		return false
	active_world_actions.erase(action_id)
	return true


func reserve_world_action(action_id: String, state: Dictionary) -> bool:
	## Reservations are the lightweight concurrency boundary for work. A target
	## can only have one active actor/method. Compatibility callers are converted
	## into the typed record rather than becoming a second reservation format.
	if action_id.is_empty() or active_world_actions.has(action_id):
		return false
	var reservation := WorldActionReservationRecord.from_dict(state)
	reservation.action_id = action_id
	reservation.node_id = str(state.get("node_id", active_node_id))
	reservation.target_coords = state.get("target_coords", Vector2i.ZERO)
	reservation.started_minute = int(state.get("started_minute", world_time_minutes))
	reservation.state = state.duplicate(true)
	if reservation.validation_error() != "":
		return false
	active_world_actions[action_id] = reservation.to_dict()
	return true


func update_world_action(action_id: String, state: Dictionary) -> void:
	if action_id.is_empty():
		return
	var current := get_world_action_reservation(action_id)
	if current == null:
		return
	current.progress = clampf(float(state.get("progress", current.progress)), 0.0, 1.0)
	current.attempt_index = maxi(
		current.attempt_index,
		int(state.get("attempt_index", current.attempt_index))
	)
	current.expected_actor_revision = int(state.get(
		"expected_actor_revision", current.expected_actor_revision
	))
	current.expected_target_revision = int(state.get(
		"expected_target_revision", current.expected_target_revision
	))
	current.expected_hex_revision = int(state.get(
		"expected_hex_revision", current.expected_hex_revision
	))
	current.state = state.duplicate(true)
	active_world_actions[action_id] = current.to_dict()


func release_world_action(action_id: String) -> void:
	cancel_world_action(action_id)


func get_world_action(action_id: String) -> Dictionary:
	var reservation := get_world_action_reservation(action_id)
	if reservation == null:
		return {}
	var result := reservation.state.duplicate(true)
	result.merge(reservation.to_dict(), true)
	return result


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

func set_player_record(record: Dictionary, coords: Vector2i) -> bool:
	var input_error := _record_payload_error(record)
	if not input_error.is_empty():
		push_error("[STATE STORE] Refusing malformed player record: %s" % input_error)
		return false
	var previous_record := player_record
	var previous_legacy_coords := _legacy_player_coords
	var previous_player_revision := player_revision
	var had_player := player_record != null
	player_record = EntityRecord.from_dict(record)
	player_record.entity_id = "player"
	player_record.kind = GameEnums.RuntimeEntityKind.PLAYER
	player_record.coords = coords
	_legacy_player_coords = coords
	player_record.revision = maxi(
		player_record.revision,
		player_revision + 1 if had_player else player_revision
	)
	player_revision = player_record.revision
	var integrity_errors := validate_integrity()
	if not integrity_errors.is_empty():
		player_record = previous_record
		_legacy_player_coords = previous_legacy_coords
		player_revision = previous_player_revision
		push_error(
			"[STATE STORE] Refusing player record that invalidates runtime: %s"
			% "; ".join(integrity_errors)
		)
		return false
	return true

func update_player_runtime(
	runtime_state: Dictionary,
	coords: Vector2i,
	validate_after_commit: bool = true
) -> bool:
	if not runtime_state is Dictionary:
		return false
	var transaction := capture_reconciliation_snapshot() if validate_after_commit else {}
	if player_record == null:
		player_record = EntityRecord.new()
		player_record.entity_id = "player"
		player_record.kind = GameEnums.RuntimeEntityKind.PLAYER
		player_record.life_state = GameEnums.EntityLifeState.ALIVE
	player_record.coords = coords
	_legacy_player_coords = coords
	player_record.revision = maxi(player_record.revision + 1, player_revision + 1)
	player_revision = player_record.revision
	player_record.runtime = runtime_state.duplicate(true)
	player_record.life_state = (
		GameEnums.EntityLifeState.DEAD
		if runtime_state.get("is_dead", false)
		else GameEnums.EntityLifeState.ALIVE
	)
	if not validate_after_commit:
		return true
	var integrity_errors := validate_integrity()
	if not integrity_errors.is_empty():
		restore_reconciliation_snapshot(transaction)
		return false
	return true

func register_entity(record) -> String:
	var entity: EntityRecord
	if record is EntityRecord:
		entity = record
	elif record is Dictionary:
		var input_error := _record_payload_error(record)
		if not input_error.is_empty():
			push_error("[STATE STORE] Cannot register malformed record: %s" % input_error)
			return ""
		entity = EntityRecord.from_dict(record)
	else:
		push_error("[STATE STORE] Cannot register: unexpected record type.")
		return ""

	if entity.entity_id.is_empty():
		entity.entity_id = _create_entity_id()
	if entity_records.has(entity.entity_id):
		push_error(
			"[STATE STORE] Refusing duplicate entity identity: %s."
			% entity.entity_id
		)
		return ""
	if entity.life_state == GameEnums.EntityLifeState.ALIVE:
		var occupying_id := str(entity_ids_by_coords.get(entity.coords, ""))
		if not occupying_id.is_empty() and occupying_id != entity.entity_id:
			push_error(
				"[STATE STORE] Refusing entity coordinate collision at %s: %s and %s."
				% [str(entity.coords), occupying_id, entity.entity_id]
			)
			return ""
	entity_records[entity.entity_id] = entity
	if entity.life_state == GameEnums.EntityLifeState.ALIVE:
		entity_ids_by_coords[entity.coords] = entity.entity_id
	var integrity_errors := validate_integrity()
	if not integrity_errors.is_empty():
		entity_records.erase(entity.entity_id)
		if entity_ids_by_coords.get(entity.coords, "") == entity.entity_id:
			entity_ids_by_coords.erase(entity.coords)
		push_error(
			"[STATE STORE] Refusing entity that invalidates runtime: %s"
			% "; ".join(integrity_errors)
		)
		return ""
	return entity.entity_id


func _record_payload_error(record: Dictionary) -> String:
	for key in ["definition", "runtime", "knowledge"]:
		if record.has(key) and not record[key] is Dictionary:
			return "%s must be a Dictionary" % key
	return ""

func get_entity(entity_id: String) -> EntityRecord:
	## Compatibility-only live-resource accessor. Production services and
	## projections must use get_entity_snapshot() unless they are RuntimeStateStore
	## internals performing an authoritative commit.
	if not entity_records.has(entity_id):
		return null
	return entity_records[entity_id]


## Snapshot-only boundary for extracted services. Legacy callers may still use
## get_entity(), but new application services must not receive the authority.
func get_entity_snapshot(entity_id: String) -> Dictionary:
	var record := get_entity(entity_id)
	return record.to_dict().duplicate(true) if record != null else {}

func get_entity_at(coords: Vector2i) -> EntityRecord:
	## Compatibility-only live-resource accessor; use get_entity_snapshot_at() for
	## production projection and application reads.
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
	## Compatibility-only live-resource accessor; use
	## get_all_entity_snapshots() for production projection and application reads.
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

func update_entity_runtime(
	entity_id: String,
	runtime_state: Dictionary,
	validate_after_commit: bool = true
) -> bool:
	if not entity_records.has(entity_id):
		return false
	if not runtime_state is Dictionary:
		return false
	var transaction := capture_reconciliation_snapshot() if validate_after_commit else {}
	var entity: EntityRecord = entity_records[entity_id]
	var preserved_runtime := _preserved_runtime_keys(entity.runtime)
	entity.runtime = runtime_state.duplicate(true)
	for key in preserved_runtime.keys():
		if not entity.runtime.has(key):
			entity.runtime[key] = preserved_runtime[key]
	entity.revision += 1
	entity.last_simulated_minute = world_time_minutes
	if not validate_after_commit:
		return true
	var integrity_errors := validate_integrity()
	if not integrity_errors.is_empty():
		restore_reconciliation_snapshot(transaction)
		return false
	return true


func update_entity_runtime_at_coords(
	entity_id: String,
	runtime_state: Dictionary,
	target_coords: Vector2i,
	validate_after_commit: bool = true
) -> bool:
	if not entity_records.has(entity_id) or not runtime_state is Dictionary:
		return false
	var entity := entity_records[entity_id] as EntityRecord
	if entity == null or entity.life_state != GameEnums.EntityLifeState.ALIVE:
		return false
	var occupying_id := str(entity_ids_by_coords.get(target_coords, ""))
	if not occupying_id.is_empty() and occupying_id != entity_id:
		return false
	var transaction := capture_reconciliation_snapshot() if validate_after_commit else {}
	if str(entity_ids_by_coords.get(entity.coords, "")) == entity_id:
		entity_ids_by_coords.erase(entity.coords)
	entity.coords = target_coords
	entity_ids_by_coords[target_coords] = entity_id
	var preserved_runtime := _preserved_runtime_keys(entity.runtime)
	entity.runtime = runtime_state.duplicate(true)
	for key in preserved_runtime.keys():
		if not entity.runtime.has(key):
			entity.runtime[key] = preserved_runtime[key]
	entity.revision += 1
	entity.last_simulated_minute = world_time_minutes
	if not validate_after_commit:
		return true
	var integrity_errors := validate_integrity()
	if not integrity_errors.is_empty():
		restore_reconciliation_snapshot(transaction)
		return false
	return true

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
	entity.revision += 1
	entity.last_simulated_minute = world_time_minutes
	return true

func set_entity_life_state(entity_id: String, life_state: GameEnums.EntityLifeState) -> bool:
	if not entity_records.has(entity_id):
		return false
	var record: EntityRecord = entity_records[entity_id]
	if life_state == GameEnums.EntityLifeState.ALIVE:
		var occupying_id := str(entity_ids_by_coords.get(record.coords, ""))
		if not occupying_id.is_empty() and occupying_id != entity_id:
			return false
	if record.life_state == life_state:
		return true
	record.life_state = life_state
	record.revision += 1
	record.last_simulated_minute = world_time_minutes
	if life_state == GameEnums.EntityLifeState.DEAD:
		if entity_ids_by_coords.get(record.coords, "") == entity_id:
			entity_ids_by_coords.erase(record.coords)
	else:
		entity_ids_by_coords[record.coords] = entity_id
	return true

func set_entity_world_status(
	entity_id: String,
	status: GameEnums.EntityWorldStatus
) -> bool:
	if not entity_records.has(entity_id):
		return false
	var record: EntityRecord = entity_records[entity_id]
	if record.world_status == status:
		return true
	record.world_status = status
	record.revision += 1
	record.last_simulated_minute = world_time_minutes
	return true

func is_entity_hostile(entity_id: String) -> bool:
	if not entity_records.has(entity_id):
		return false
	return entity_records[entity_id].world_status == GameEnums.EntityWorldStatus.HOSTILE

func patch_entity_record(entity_id: String, patch: Dictionary) -> bool:
	if not entity_records.has(entity_id):
		return false
	var entity: EntityRecord = entity_records[entity_id]
	# Identity, lifecycle, coordinates, and revisions have dedicated invariant
	# methods.  Allowing them through a generic dictionary patch was a quiet way
	# to desynchronise entity_ids_by_coords or roll a revision backwards.
	for forbidden_key in [
		"entity_id", "kind", "life_state", "world_status", "coords"
	]:
		if patch.has(forbidden_key):
			return false
	for key in patch.keys():
		if str(key) not in ENTITY_PATCH_KEYS:
			return false
	if patch.has("definition") and not patch["definition"] is Dictionary:
		return false
	if patch.has("runtime") and not patch["runtime"] is Dictionary:
		return false
	if patch.has("knowledge") and not patch["knowledge"] is Dictionary:
		return false
	if patch.has("owner_id") and not patch["owner_id"] is String:
		return false
	if patch.has("last_simulated_minute") and not patch["last_simulated_minute"] is int:
		return false
	if patch.has("negotiation_attempts") and not patch["negotiation_attempts"] is int:
		return false
	var next_revision := entity.revision + 1
	if patch.has("revision"):
		next_revision = int(patch.get("revision", -1))
		if next_revision <= entity.revision:
			return false
	var transaction := capture_reconciliation_snapshot()
	for key in patch.keys():
		entity.set(key, patch[key])
	entity.revision = next_revision
	entity.last_simulated_minute = maxi(entity.last_simulated_minute, world_time_minutes)
	var integrity_errors := validate_integrity()
	if not integrity_errors.is_empty():
		restore_reconciliation_snapshot(transaction)
		return false
	return true

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
	## Compatibility import path for migrations and fixtures. Production WorldCore
	## mutations must use replace_hex_record() with an expected revision.
	if record is HexRecord:
		hex_records[coords] = HexRecord.from_dict(record.to_dict())
	elif record is Dictionary:
		hex_records[coords] = HexRecord.from_dict(record)


func replace_hex_record(
	coords: Vector2i,
	record: Variant,
	expected_revision: int = -1,
	increment_revision: bool = true
) -> bool:
	var current := get_hex_record(coords)
	if expected_revision >= 0:
		if current == null or current.revision != expected_revision:
			return false
	var candidate: HexRecord = null
	if record is HexRecord:
		candidate = HexRecord.from_dict(record.to_dict())
	elif record is Dictionary:
		candidate = HexRecord.from_dict(record)
	if candidate == null:
		return false
	var base_revision := current.revision if current != null else -1
	if increment_revision:
		candidate.revision = base_revision + 1
	elif candidate.revision < 0:
		return false
	var transaction := capture_reconciliation_snapshot()
	hex_records[coords] = candidate
	var errors := _hex_record_integrity_errors(coords, candidate)
	errors.append_array(_ensure_item_ownership_ledger().validate_integrity())
	if not errors.is_empty():
		restore_reconciliation_snapshot(transaction)
		return false
	return true


func replace_hex_records_atomic(changes: Dictionary) -> bool:
	if changes.is_empty():
		return true
	var transaction := capture_reconciliation_snapshot()
	for coords_value in changes.keys():
		if not coords_value is Vector2i:
			restore_reconciliation_snapshot(transaction)
			return false
		var change: Variant = changes[coords_value]
		if not change is Dictionary:
			restore_reconciliation_snapshot(transaction)
			return false
		var current := get_hex_record(coords_value)
		var expected_revision := int(change.get("expected_revision", -1))
		if current == null or current.revision != expected_revision:
			restore_reconciliation_snapshot(transaction)
			return false
		var value: Variant = change.get("record")
		var candidate: HexRecord = null
		if value is HexRecord:
			candidate = HexRecord.from_dict(value.to_dict())
		elif value is Dictionary:
			candidate = HexRecord.from_dict(value)
		if candidate == null:
			restore_reconciliation_snapshot(transaction)
			return false
		candidate.revision = current.revision + 1
		hex_records[coords_value] = candidate
	var integrity_errors := validate_integrity()
	if not integrity_errors.is_empty():
		restore_reconciliation_snapshot(transaction)
		return false
	return true


func patch_run_flags(patch: Dictionary) -> bool:
	for key in patch.keys():
		if str(key).is_empty():
			return false
	var next := run_flags.duplicate(true)
	for key in patch.keys():
		var value: Variant = patch[key]
		if value == null:
			next.erase(key)
		else:
			next[key] = value
	run_flags = next
	return true


func get_run_flags_snapshot() -> Dictionary:
	return run_flags.duplicate(true)


func set_campaign_state(
	graph_snapshot: Dictionary,
	node_id: String,
	arrival_direction: int
) -> bool:
	if not node_id.is_empty() and graph_snapshot.is_empty():
		return false
	campaign_graph = graph_snapshot.duplicate(true)
	active_node_id = node_id
	active_arrival_direction = arrival_direction
	return true


func get_campaign_graph_snapshot() -> Dictionary:
	return campaign_graph.duplicate(true)

func get_hex_record(coords: Vector2i) -> HexRecord:
	if not hex_records.has(coords):
		return null
	return hex_records[coords]


func get_hex_snapshot(coords: Vector2i) -> Dictionary:
	var record := get_hex_record(coords)
	return record.to_dict().duplicate(true) if record != null else {}


func get_hex_coordinates() -> Array:
	return hex_records.keys().duplicate()


func get_hex_records_snapshot() -> Dictionary:
	var snapshots: Dictionary = {}
	for coords in hex_records.keys():
		var record := hex_records[coords] as HexRecord
		if record != null:
			snapshots[coords] = HexRecord.from_dict(record.to_dict())
	return snapshots


func get_all_ground_item_snapshots() -> Dictionary:
	return ground_item_records.duplicate(true)


func get_all_node_runtime_snapshots() -> Dictionary:
	return node_runtime_snapshots.duplicate(true)

func add_ground_items(coords: Vector2i, item_states: Array) -> bool:
	var prepared: Array[Dictionary] = []
	var incoming_ids: Dictionary = {}
	var ledger := _ensure_item_ownership_ledger()
	for item_state in item_states:
		if not item_state is Dictionary:
			return false
		var normalized: Dictionary = (item_state as Dictionary).duplicate(true)
		if str(normalized.get("instance_id", "")).is_empty():
			return false
		var state_ids := ledger.runtime_item_ids({"inventory_items": [normalized]})
		if state_ids.is_empty():
			return false
		for instance_id in state_ids:
			if instance_id.is_empty() or incoming_ids.has(instance_id):
				return false
			var locations := ledger.find_all_item_ownership(instance_id)
			if locations.size() > 1:
				return false
			incoming_ids[instance_id] = true
		normalized["owner_id"] = ""
		normalized["physical_location"] = "ground"
		normalized.erase("container_instance_id")
		normalized["equipped_slot"] = GameEnums.EquipmentSlot.NONE
		prepared.append(normalized)
	var transaction := capture_reconciliation_snapshot()
	for normalized in prepared:
		# Ground insertion is an ownership transfer. Remove stale copies first so
		# an item cannot exist in rubble, on the ground, and in an actor inventory.
		for instance_id in ledger.runtime_item_ids({"inventory_items": [normalized]}):
			ledger.remove_item_instance(instance_id)
		if not ground_item_records.has(coords):
			ground_item_records[coords] = []
		ground_item_records[coords].append(normalized)
	var integrity_errors := validate_integrity()
	if not integrity_errors.is_empty():
		restore_reconciliation_snapshot(transaction)
		return false
	return true


func find_item_ownership(instance_id: String) -> Dictionary:
	return _ensure_item_ownership_ledger().find_item_ownership(instance_id)


func runtime_item_ids(runtime: Dictionary) -> Array[String]:
	return _ensure_item_ownership_ledger().runtime_item_ids(runtime)


func transfer_item_to_entity(entity_id: String, item_state: Dictionary) -> bool:
	return _ensure_item_ownership_ledger().transfer_item_to_entity(entity_id, item_state)


func transfer_ground_item_to_entity_with_runtime(
	coords: Vector2i,
	instance_id: String,
	entity_id: String,
	destination_runtime: Dictionary
) -> bool:
	return _ensure_item_ownership_ledger().transfer_ground_item_to_entity_with_runtime(
		coords, instance_id, entity_id, destination_runtime
	)


func commit_entity_runtime_with_ground_items(
	entity_id: String,
	destination_runtime: Dictionary,
	coords: Vector2i,
	ground_items: Array
) -> bool:
	return _ensure_item_ownership_ledger().commit_entity_runtime_with_ground_items(
		entity_id, destination_runtime, coords, ground_items
	)


func remove_ground_item(coords: Vector2i, instance_id: String) -> Dictionary:
	return _ensure_item_ownership_ledger().remove_ground_item(coords, instance_id)


func transfer_ground_item_to_entity(
	coords: Vector2i,
	instance_id: String,
	entity_id: String
) -> bool:
	return _ensure_item_ownership_ledger().transfer_ground_item_to_entity(
		coords, instance_id, entity_id
	)


func _remove_item_instance(instance_id: String) -> void:
	remove_item_instance(instance_id)


func remove_item_instance(instance_id: String) -> int:
	return _ensure_item_ownership_ledger().remove_item_instance(instance_id)

func get_ground_items(coords: Vector2i) -> Array:
	if not ground_item_records.has(coords):
		return []
	return ground_item_records[coords].duplicate(true)

func take_ground_item(coords: Vector2i, instance_id: String) -> Dictionary:
	# Compatibility shim for old callers. New code must provide a destination
	# and use a ledger transfer; this method only removes an already validated
	# ground owner and is intentionally not used by gameplay paths.
	return _ensure_item_ownership_ledger().remove_ground_item(coords, instance_id)

func has_ground_items(coords: Vector2i) -> bool:
	return ground_item_records.has(coords) and ground_item_records[coords].size() > 0


func get_relationship_state() -> Dictionary:
	return CombatRelationshipLedger.from_dict(relationship_state).to_dict()


func set_relationship_state(value: Dictionary) -> void:
	var validation_error := CombatRelationshipLedger.validation_error(value)
	if not validation_error.is_empty():
		push_error("[STATE STORE] Refusing malformed relationship state: %s" % validation_error)
		return
	relationship_state = CombatRelationshipLedger.from_dict(value).to_dict()


func relationship_between(
	left_id: String,
	right_id: String,
	fallback: int = CombatRelationshipLedger.Relation.NEUTRAL
) -> int:
	return CombatRelationshipLedger.from_dict(relationship_state).relation(
		left_id, right_id, fallback
	)


func set_relationship(left_id: String, right_id: String, relation: int) -> void:
	var ledger := CombatRelationshipLedger.from_dict(relationship_state)
	ledger.set_relation(left_id, right_id, relation)
	relationship_state = ledger.to_dict()


func adjust_relationship_trust(left_id: String, right_id: String, delta: float) -> float:
	var ledger := CombatRelationshipLedger.from_dict(relationship_state)
	var next := ledger.adjust_trust(left_id, right_id, delta)
	relationship_state = ledger.to_dict()
	return next


func commit_trade(
	enemy_id: String,
	player_runtime: Dictionary,
	enemy_runtime: Dictionary,
	enemy_definition: Dictionary,
	offered_instance_id: String,
	received_instance_id: String,
	received_source: String,
	expected_player_revision: int,
	expected_enemy_revision: int
) -> bool:
	if (
		player_record == null
		or player_runtime.is_empty()
		or enemy_runtime.is_empty()
		or enemy_id.is_empty()
		or offered_instance_id.is_empty()
		or received_instance_id.is_empty()
		or offered_instance_id == received_instance_id
	):
		return false
	var enemy := get_entity(enemy_id)
	if enemy == null:
		return false
	if player_record.revision != expected_player_revision or enemy.revision != expected_enemy_revision:
		return false
	var ownership := _ensure_item_ownership_ledger()
	var offer_locations := ownership.find_all_item_ownership(offered_instance_id)
	if offer_locations.size() != 1:
		return false
	var offer_location: Dictionary = offer_locations[0]
	if offer_location.get("location", "") != "inventory" or offer_location.get("owner_id", "") != "player":
		return false
	var received_locations := ownership.find_all_item_ownership(received_instance_id)
	if received_source == "inventory":
		if received_locations.size() != 1:
			return false
		var received_location: Dictionary = received_locations[0]
		if received_location.get("location", "") != "inventory" or received_location.get("owner_id", "") != enemy_id:
			return false
	elif received_source == "authored_loadout":
		# Authored loadout entries are templates, not runtime ownership. The
		# exchange materializes the selected instance exactly once for the player.
		if not received_locations.is_empty():
			return false
	else:
		return false
	if ownership.runtime_item_count(player_runtime, offered_instance_id) != 0:
		return false
	if ownership.runtime_item_count(player_runtime, received_instance_id) != 1:
		return false
	if ownership.runtime_item_count(enemy_runtime, offered_instance_id) != 1:
		return false
	if ownership.runtime_item_count(enemy_runtime, received_instance_id) != 0:
		return false
	var transaction := capture_reconciliation_snapshot()
	player_record.runtime = player_runtime.duplicate(true)
	player_record.revision += 1
	player_record.last_simulated_minute = world_time_minutes
	player_revision = maxi(player_revision, player_record.revision)
	enemy.runtime = enemy_runtime.duplicate(true)
	enemy.definition = enemy_definition.duplicate(true)
	enemy.revision += 1
	enemy.last_simulated_minute = world_time_minutes
	var integrity_errors := validate_integrity()
	if not integrity_errors.is_empty():
		restore_reconciliation_snapshot(transaction)
		return false
	return true


func begin_combat_handoff(encounter: CombatEncounterRecord) -> CombatHandoffRecord:
	if encounter == null or encounter.encounter_id.is_empty():
		return null
	if active_combat_handoff != null:
		push_error("[STATE STORE] Another combat handoff is already active.")
		return null
	var integrity_errors := validate_integrity()
	if not integrity_errors.is_empty():
		push_error(
			"[STATE STORE] Combat handoff rejected invalid runtime: %s"
			% "; ".join(integrity_errors)
		)
		return null
	if encounter.topology_id != "squad_7x5":
		push_error("[STATE STORE] Production handoff rejected non-squad topology.")
		return null
	if encounter.actors.size() < 2 or encounter.actors.size() > 6:
		push_error("[STATE STORE] Combat handoff actor count is outside 2..6.")
		return null
	var handoff := CombatHandoffRecord.new()
	handoff.encounter_id = encounter.encounter_id
	handoff.source_coords = encounter.source_coords
	handoff.topology_id = encounter.topology_id
	var seen: Dictionary = {}
	for actor in encounter.actors:
		var actor_id := str(actor.get("actor_id", ""))
		if actor_id.is_empty() or seen.has(actor_id):
			return null
		seen[actor_id] = true
		var runtime_record_value: Variant = actor.get("runtime_record", {})
		if not runtime_record_value is Dictionary:
			return null
		var runtime_record: Dictionary = runtime_record_value
		handoff.actor_ids.append(actor_id)
		handoff.participant_contexts[actor_id] = actor.get(
			"participant_context", {}
		).duplicate(true)
		if actor_id == "player":
			if player_record == null:
				return null
			if (
				str(runtime_record.get("entity_id", "")) != "player"
				or int(runtime_record.get("revision", -1)) != player_record.revision
				or runtime_record.get("coords", Vector2i(-999999, -999999)) != player_record.coords
			):
				return null
			handoff.participant_revisions[actor_id] = player_record.revision
		else:
			var record := get_entity(actor_id)
			if record == null or record.life_state != GameEnums.EntityLifeState.ALIVE:
				return null
			if (
				str(runtime_record.get("entity_id", "")) != record.entity_id
				or int(runtime_record.get("revision", -1)) != record.revision
				or runtime_record.get("coords", Vector2i(-999999, -999999)) != record.coords
			):
				return null
			handoff.participant_revisions[actor_id] = record.revision
	if not seen.has("player"):
		return null
	var ground_ids: Dictionary = {}
	for item_state in encounter.ground_items:
		if not item_state is Dictionary:
			return null
		var instance_id := str(item_state.get("instance_id", ""))
		if instance_id.is_empty() or ground_ids.has(instance_id):
			return null
		ground_ids[instance_id] = true
		var locations := _ensure_item_ownership_ledger().find_all_item_ownership(instance_id)
		if locations.size() != 1:
			return null
		var location: Dictionary = locations[0]
		if location.get("location", "") != "ground" or location.get("coords") != encounter.source_coords:
			return null
		handoff.initial_ground_item_ids.append(instance_id)
	active_combat_handoff = handoff
	return handoff


func get_active_combat_handoff() -> CombatHandoffRecord:
	return active_combat_handoff


func cancel_combat_handoff(encounter_id: String) -> bool:
	if active_combat_handoff == null or active_combat_handoff.encounter_id != encounter_id:
		return false
	active_combat_handoff.status = CombatHandoffRecord.Status.CANCELLED
	active_combat_handoff = null
	return true


func complete_combat_handoff(encounter_id: String) -> bool:
	if active_combat_handoff == null or active_combat_handoff.encounter_id != encounter_id:
		return false
	active_combat_handoff.status = CombatHandoffRecord.Status.APPLIED
	active_combat_handoff = null
	return true


func has_applied_combat_result(encounter_id: String) -> bool:
	return not encounter_id.is_empty() and applied_combat_encounters.has(encounter_id)


func mark_combat_result_applied(encounter_id: String) -> void:
	if encounter_id.is_empty():
		return
	applied_combat_encounters[encounter_id] = world_time_minutes
	while applied_combat_encounters.size() > 64:
		applied_combat_encounters.erase(applied_combat_encounters.keys()[0])


func has_applied_world_receipt(receipt_id: String) -> bool:
	return not receipt_id.is_empty() and applied_world_receipts.has(receipt_id)


func mark_world_receipt_applied(receipt_id: String) -> void:
	if receipt_id.is_empty():
		return
	applied_world_receipts[receipt_id] = world_time_minutes
	while applied_world_receipts.size() > 256:
		var oldest_id := ""
		var oldest_minute := 9223372036854775807
		for candidate_id in applied_world_receipts.keys():
			var minute := int(applied_world_receipts[candidate_id])
			if (
				minute < oldest_minute
				or (minute == oldest_minute and str(candidate_id) < oldest_id)
			):
				oldest_id = str(candidate_id)
				oldest_minute = minute
		if oldest_id.is_empty():
			break
		applied_world_receipts.erase(oldest_id)

func get_slot_path(slot: int) -> String:
	return _RunSlots.path_for(slot)

func get_save_metadata(slot: int) -> Dictionary:
	return _RunSlots.metadata_for(
		slot,
		SAVE_VERSION,
		WORLD_GENERATION_VERSION,
		MIGRATABLE_SAVE_VERSIONS
	)

func save_to_slot(slot: int) -> bool:
	return save_to_disk(get_slot_path(slot))

func load_from_slot(slot: int) -> bool:
	return load_from_disk(get_slot_path(slot))

func save_to_disk(path: String = DEFAULT_SAVE_PATH) -> bool:
	_last_persistence_error = ""
	if active_combat_handoff != null:
		return _fail_persistence(
			"save", "Cannot save while a combat handoff is active."
		)
	var integrity_errors := validate_integrity()
	if not integrity_errors.is_empty():
		return _fail_persistence(
			"save", "Runtime integrity failed: " + "; ".join(integrity_errors)
		)
	var encoded: Variant = _encode_variant(_capture_save_snapshot())
	var contents := JSON.stringify(encoded, "\t")
	var temporary_path := path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _fail_persistence(
			"save",
			"Could not open %s for writing. Error %d."
			% [temporary_path, FileAccess.get_open_error()]
		)
	file.store_string(contents)
	file.close()
	if not _replace_save_file(temporary_path, path):
		return _fail_persistence("save", "Could not atomically replace %s." % path)
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
	if file_version in MIGRATABLE_SAVE_VERSIONS:
		decoded = _migrate_save_snapshot(decoded, file_version)
	elif file_version != SAVE_VERSION:
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
	var candidate := RuntimeStateStore.new()
	if not candidate._restore_save_snapshot(decoded):
		candidate.free()
		return _fail_persistence("load", "Save snapshot could not be reconstructed.")
	var candidate_errors := candidate.validate_integrity()
	if not candidate_errors.is_empty():
		candidate.free()
		return _fail_persistence(
			"load", "Save integrity failed: " + "; ".join(candidate_errors)
		)
	var validated_snapshot := candidate._capture_save_snapshot()
	candidate.free()
	if not _restore_save_snapshot(validated_snapshot):
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


func clear_active_node_runtime() -> void:
	if active_combat_handoff != null:
		push_error("[STATE STORE] Cannot clear a node while combat handoff is active.")
		return
	entity_records.clear()
	entity_ids_by_coords.clear()
	hex_records.clear()
	ground_item_records.clear()
	active_world_actions.clear()
	world_signal_records.clear()


func has_node_runtime(node_id: String) -> bool:
	return node_runtime_snapshots.has(node_id)


func restore_node_runtime(node_id: String) -> bool:
	if not node_runtime_snapshots.has(node_id):
		return false
	if active_combat_handoff != null:
		return false
	var snapshot: Dictionary = node_runtime_snapshots[node_id]
	var candidate := _build_node_runtime_candidate(snapshot)
	if candidate == null:
		return false
	# The candidate has passed entity-index and full ownership validation. Swap
	# the authoritative dictionaries only after that validation succeeds; a
	# malformed node snapshot can no longer erase the currently active node.
	entity_records = candidate.entity_records
	entity_ids_by_coords = candidate.entity_ids_by_coords
	hex_records = candidate.hex_records
	ground_item_records = candidate.ground_item_records
	active_world_actions = candidate.active_world_actions
	world_signal_records = candidate.world_signal_records
	player_revision = maxi(
		player_revision,
		maxi(
			int(snapshot.get("player_revision", 0)),
			int(candidate.player_revision)
		)
	)
	candidate.free()
	return true


func transition_active_node(
	destination_node_id: String,
	arrival_direction: int,
	baseline_records: Dictionary,
	graph_snapshot: Dictionary,
	destination_player_coords: Vector2i = Vector2i.ZERO
) -> bool:
	## Capture, construct, validate, and swap a directional node as one store
	## transaction. A rejected destination leaves the source and graph untouched.
	if (
		destination_node_id.is_empty()
		or graph_snapshot.is_empty()
		or active_combat_handoff != null
	):
		return false
	var transaction := capture_reconciliation_snapshot()
	var source_node_id := active_node_id
	if not source_node_id.is_empty():
		capture_node_runtime(source_node_id)
	var candidate: RuntimeStateStore = null
	if node_runtime_snapshots.has(destination_node_id):
		candidate = _build_node_runtime_candidate(
			node_runtime_snapshots[destination_node_id]
		)
	else:
		candidate = _build_baseline_node_candidate(baseline_records)
	if candidate == null:
		restore_reconciliation_snapshot(transaction)
		return false
	entity_records = candidate.entity_records
	entity_ids_by_coords = candidate.entity_ids_by_coords
	hex_records = candidate.hex_records
	ground_item_records = candidate.ground_item_records
	active_world_actions = candidate.active_world_actions
	world_signal_records = candidate.world_signal_records
	player_revision = maxi(player_revision, candidate.player_revision)
	active_node_id = destination_node_id
	active_arrival_direction = arrival_direction
	campaign_graph = graph_snapshot.duplicate(true)
	candidate.free()
	if player_record != null and not update_player_runtime(
		player_record.runtime,
		destination_player_coords,
		false
	):
		restore_reconciliation_snapshot(transaction)
		return false
	var integrity_errors := validate_integrity()
	if not integrity_errors.is_empty():
		restore_reconciliation_snapshot(transaction)
		return false
	return true


func _build_baseline_node_candidate(
	baseline_records: Dictionary
) -> RuntimeStateStore:
	if baseline_records.is_empty():
		return null
	var candidate := RuntimeStateStore.new()
	candidate.world_time_minutes = world_time_minutes
	candidate.player_revision = player_revision
	candidate._legacy_player_coords = _legacy_player_coords
	candidate.relationship_state = relationship_state.duplicate(true)
	if player_record != null:
		candidate.player_record = EntityRecord.from_dict(player_record.to_dict())
	for coords_value in baseline_records.keys():
		if not coords_value is Vector2i:
			candidate.free()
			return null
		var value: Variant = baseline_records[coords_value]
		if value is HexRecord:
			candidate.hex_records[coords_value] = HexRecord.from_dict(value.to_dict())
		elif value is Dictionary:
			candidate.hex_records[coords_value] = HexRecord.from_dict(value)
		else:
			candidate.free()
			return null
	var errors := candidate.validate_integrity()
	if not errors.is_empty():
		candidate.free()
		return null
	return candidate


func _build_node_runtime_candidate(snapshot: Dictionary) -> RuntimeStateStore:
	if snapshot.is_empty():
		return null
	var candidate := RuntimeStateStore.new()
	candidate.world_time_minutes = world_time_minutes
	candidate.player_revision = player_revision
	candidate._legacy_player_coords = _legacy_player_coords
	candidate.relationship_state = relationship_state.duplicate(true)
	if player_record != null:
		candidate.player_record = EntityRecord.from_dict(player_record.to_dict())
	var restored := _NodeSnapshots.restore_records(snapshot)
	candidate.player_revision = maxi(
		candidate.player_revision,
		maxi(
			int(snapshot.get("player_revision", 0)),
			int(restored.get("player_revision", 0))
		)
	)
	if not candidate._restore_entity_entries(restored.get("entities", [])):
		candidate.free()
		return null
	candidate.hex_records = restored.get("hexes", {})
	for coords in candidate.hex_records.keys():
		var restored_record := candidate.hex_records[coords] as HexRecord
		if restored_record != null:
			restored_record.trace_records = candidate._active_trace_records(
				restored_record.trace_records, world_time_minutes
			)
	candidate.ground_item_records = restored.get("ground_items", {})
	candidate.active_world_actions = restored.get("active_world_actions", {})
	for signal_record in restored.get("world_signals", []):
		if signal_record is WorldSignalRecord:
			candidate.register_world_signal(signal_record)
	var integrity_errors := candidate.validate_integrity()
	if not integrity_errors.is_empty():
		push_error(
			"[STATE STORE] Node runtime snapshot rejected: %s"
			% "; ".join(integrity_errors)
		)
		candidate.free()
		return null
	return candidate


func rebuild_entity_index() -> Array[String]:
	var errors: Array[String] = []
	var rebuilt: Dictionary = {}
	var ids: Array[String] = []
	for raw_id in entity_records.keys():
		ids.append(str(raw_id))
	ids.sort()
	for entity_id in ids:
		var record := entity_records.get(entity_id) as EntityRecord
		if record == null:
			errors.append("Entity record is null: %s" % entity_id)
			continue
		if record.entity_id != entity_id:
			errors.append("Entity key/id mismatch: %s != %s" % [entity_id, record.entity_id])
			continue
		if record.life_state != GameEnums.EntityLifeState.ALIVE:
			continue
		var occupying_id := str(rebuilt.get(record.coords, ""))
		if not occupying_id.is_empty():
			errors.append(
				"Alive coordinate collision at %s: %s and %s"
				% [str(record.coords), occupying_id, entity_id]
			)
			continue
		rebuilt[record.coords] = entity_id
	entity_ids_by_coords = rebuilt
	return errors


func _hex_record_integrity_errors(
	coords: Vector2i,
	record: HexRecord
) -> Array[String]:
	var errors: Array[String] = []
	if record == null:
		return ["Null hex record at %s." % str(coords)]
	if record.revision < 0:
		errors.append("Hex revision is negative at %s." % str(coords))
	var object_ids: Dictionary = {}
	for object_value in record.world_objects:
		if not object_value is Dictionary:
			errors.append("Malformed world object at %s." % str(coords))
			continue
		var object_id := str(object_value.get("object_id", ""))
		if object_id.is_empty() or object_ids.has(object_id):
			errors.append("Duplicate or empty world object identity at %s." % str(coords))
			continue
		object_ids[object_id] = true
		if int(object_value.get("revision", 0)) < 0:
			errors.append("World object revision is negative: %s." % object_id)
	return errors


func validate_integrity() -> Array[String]:
	var errors: Array[String] = []
	var relationship_error := CombatRelationshipLedger.validation_error(relationship_state)
	if not relationship_error.is_empty():
		errors.append(relationship_error)
	if player_record != null:
		if player_record.entity_id != "player":
			errors.append("Player record identity is not 'player'.")
		if player_record.kind != GameEnums.RuntimeEntityKind.PLAYER:
			errors.append("Player record kind is not PLAYER.")
		if player_record.coords != _legacy_player_coords:
			errors.append("Player coordinate compatibility projection drifted.")
	var seen_coords: Dictionary = {}
	for entity_id_value in entity_records.keys():
		var entity_id := str(entity_id_value)
		var record := entity_records.get(entity_id) as EntityRecord
		if record == null:
			errors.append("Null entity record: %s" % entity_id)
			continue
		if record.entity_id != entity_id or entity_id.is_empty():
			errors.append("Entity identity/key mismatch: %s" % entity_id)
		if record.life_state == GameEnums.EntityLifeState.ALIVE:
			if seen_coords.has(record.coords):
				errors.append("Duplicate alive coordinate: %s" % str(record.coords))
			else:
				seen_coords[record.coords] = entity_id
			if str(entity_ids_by_coords.get(record.coords, "")) != entity_id:
				errors.append("Entity coordinate index mismatch: %s" % entity_id)
		elif str(entity_ids_by_coords.get(record.coords, "")) == entity_id:
			errors.append("Dead entity remains in the alive coordinate index: %s" % entity_id)
	for coords in entity_ids_by_coords.keys():
		var indexed_id := str(entity_ids_by_coords.get(coords, ""))
		var indexed := entity_records.get(indexed_id) as EntityRecord
		if indexed == null or indexed.life_state != GameEnums.EntityLifeState.ALIVE or indexed.coords != coords:
			errors.append("Stale entity coordinate index at %s" % str(coords))
	for coords in hex_records.keys():
		if not coords is Vector2i:
			errors.append("Hex record has a non-Vector2i key.")
			continue
		errors.append_array(_hex_record_integrity_errors(coords, hex_records[coords]))
	for action_id_value in active_world_actions.keys():
		var action_id := str(action_id_value)
		var action_data: Variant = active_world_actions[action_id_value]
		if not action_data is Dictionary:
			errors.append("World action reservation is malformed: %s" % action_id)
			continue
		var reservation := WorldActionReservationRecord.from_dict(action_data)
		if reservation.action_id != action_id:
			errors.append("World action reservation key/id mismatch: %s" % action_id)
		var reservation_error := reservation.validation_error()
		if not reservation_error.is_empty():
			errors.append(reservation_error)
		if (
			not active_node_id.is_empty()
			and not reservation.node_id.is_empty()
			and reservation.node_id != active_node_id
		):
			errors.append("World action reservation belongs to another node: %s" % action_id)
	for signal_id_value in world_signal_records.keys():
		var signal_id := str(signal_id_value)
		var signal_record := world_signal_records[signal_id_value] as WorldSignalRecord
		if signal_record == null or signal_id.is_empty() or signal_record.signal_id != signal_id:
			errors.append("World signal identity/key mismatch: %s" % signal_id)
	if applied_combat_encounters.size() > 64:
		errors.append("Applied combat encounter history exceeds its 64-entry bound.")
	for encounter_id in applied_combat_encounters.keys():
		if str(encounter_id).is_empty() or int(applied_combat_encounters[encounter_id]) < 0:
			errors.append("Applied combat encounter history contains an invalid entry.")
	if applied_world_receipts.size() > 256:
		errors.append("Applied world receipt history exceeds its 256-entry bound.")
	for receipt_id in applied_world_receipts.keys():
		if str(receipt_id).is_empty() or int(applied_world_receipts[receipt_id]) < 0:
			errors.append("Applied world receipt history contains an invalid entry.")
	errors.append_array(_ensure_item_ownership_ledger().validate_integrity())
	return errors


func capture_reconciliation_snapshot() -> Dictionary:
	var entities: Dictionary = {}
	for entity_id in entity_records.keys():
		var record := entity_records[entity_id] as EntityRecord
		if record != null:
			entities[entity_id] = record.to_dict()
	var hexes: Dictionary = {}
	for coords in hex_records.keys():
		var hex := hex_records[coords] as HexRecord
		if hex != null:
			hexes[coords] = hex.to_dict()
	return {
		"world_time_minutes": world_time_minutes,
		"campaign_graph": campaign_graph.duplicate(true),
		"active_node_id": active_node_id,
		"active_arrival_direction": active_arrival_direction,
		"run_flags": run_flags.duplicate(true),
		"node_runtime_snapshots": node_runtime_snapshots.duplicate(true),
		"player_record": player_record.to_dict() if player_record != null else {},
		"player_revision": player_revision,
		"legacy_player_coords": _legacy_player_coords,
		"entities": entities,
		"hexes": hexes,
		"ground_item_records": ground_item_records.duplicate(true),
		"relationship_state": relationship_state.duplicate(true),
		"active_combat_handoff": (
			active_combat_handoff.to_dict() if active_combat_handoff != null else {}
		),
		"applied_combat_encounters": applied_combat_encounters.duplicate(true),
		"applied_world_receipts": applied_world_receipts.duplicate(true),
		"active_world_actions": active_world_actions.duplicate(true),
		"world_signals": _world_signals_to_dict(),
	}


func restore_reconciliation_snapshot(snapshot: Dictionary) -> void:
	world_time_minutes = int(snapshot.get("world_time_minutes", world_time_minutes))
	campaign_graph = snapshot.get("campaign_graph", campaign_graph).duplicate(true)
	active_node_id = str(snapshot.get("active_node_id", active_node_id))
	active_arrival_direction = int(snapshot.get(
		"active_arrival_direction", active_arrival_direction
	))
	run_flags = snapshot.get("run_flags", run_flags).duplicate(true)
	node_runtime_snapshots = snapshot.get(
		"node_runtime_snapshots", node_runtime_snapshots
	).duplicate(true)
	var player_data: Dictionary = snapshot.get("player_record", {})
	player_record = EntityRecord.from_dict(player_data) if not player_data.is_empty() else null
	player_revision = int(snapshot.get("player_revision", 0))
	_legacy_player_coords = snapshot.get("legacy_player_coords", Vector2i.ZERO)
	entity_records.clear()
	for entity_id in snapshot.get("entities", {}).keys():
		entity_records[entity_id] = EntityRecord.from_dict(snapshot["entities"][entity_id])
	hex_records.clear()
	for coords in snapshot.get("hexes", {}).keys():
		hex_records[coords] = HexRecord.from_dict(snapshot["hexes"][coords])
	ground_item_records = snapshot.get("ground_item_records", {}).duplicate(true)
	relationship_state = snapshot.get(
		"relationship_state", CombatRelationshipLedger.new().to_dict()
	).duplicate(true)
	var handoff_data: Dictionary = snapshot.get("active_combat_handoff", {})
	active_combat_handoff = (
		CombatHandoffRecord.from_dict(handoff_data) if not handoff_data.is_empty() else null
	)
	applied_combat_encounters = _normalized_applied_encounters(
		snapshot.get("applied_combat_encounters", {})
	)
	applied_world_receipts = _normalized_applied_world_receipts(
		snapshot.get("applied_world_receipts", {})
	)
	active_world_actions = snapshot.get("active_world_actions", {}).duplicate(true)
	world_signal_records.clear()
	for signal_data in snapshot.get("world_signals", []):
		if signal_data is Dictionary:
			register_world_signal(WorldSignalRecord.from_dict(signal_data))
	rebuild_entity_index()


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
		"relationship_state": relationship_state.duplicate(true),
		"applied_combat_encounters": applied_combat_encounters.duplicate(true),
		"applied_world_receipts": applied_world_receipts.duplicate(true),
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
	_legacy_player_coords = snapshot.get("player_coords", Vector2i.ZERO)
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
		player_record.entity_id = "player"
		player_record.kind = GameEnums.RuntimeEntityKind.PLAYER
		if not player_data.has("coords"):
			player_record.coords = _legacy_player_coords
		_legacy_player_coords = player_record.coords
		player_revision = maxi(player_revision, player_record.revision)
	var loaded_relationship: Variant = snapshot.get("relationship_state", {})
	if CombatRelationshipLedger.validation_error(loaded_relationship) != "":
		return false
	relationship_state = CombatRelationshipLedger.from_dict(loaded_relationship).to_dict()
	applied_combat_encounters = _normalized_applied_encounters(
		snapshot.get("applied_combat_encounters", {})
	)
	applied_world_receipts = _normalized_applied_world_receipts(
		snapshot.get("applied_world_receipts", {})
	)
	active_combat_handoff = null

	entity_records.clear()
	entity_ids_by_coords.clear()
	hex_records.clear()
	ground_item_records.clear()
	active_world_actions.clear()
	world_signal_records.clear()

	if not _restore_entity_entries(snapshot.get("entities", [])):
		return false
	hex_records = _RecordRepository.restore_hexes(snapshot.get("hexes", []))
	ground_item_records = _RecordRepository.restore_ground_items(
		snapshot.get("ground_items", [])
	)
	active_world_actions = snapshot.get("active_world_actions", {}).duplicate(true)
	for signal_data in snapshot.get("world_signals", []):
		if signal_data is Dictionary:
			register_world_signal(WorldSignalRecord.from_dict(signal_data))

	return rebuild_entity_index().is_empty()


func _restore_entity_entries(entries: Array) -> bool:
	entity_records.clear()
	entity_ids_by_coords.clear()
	for record_data in entries:
		if not record_data is Dictionary:
			return false
		var record := EntityRecord.from_dict(record_data)
		if record.entity_id.is_empty() or entity_records.has(record.entity_id):
			return false
		entity_records[record.entity_id] = record
	return rebuild_entity_index().is_empty()


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


func _migrate_save_snapshot(snapshot: Dictionary, from_version: int) -> Dictionary:
	var migrated := snapshot.duplicate(true)
	if from_version == 12:
		migrated["relationship_state"] = migrated.get(
			"relationship_state", CombatRelationshipLedger.new().to_dict()
		)
		migrated["applied_combat_encounters"] = migrated.get(
			"applied_combat_encounters", {}
		)
		var player_data: Dictionary = migrated.get("player_record", {}).duplicate(true)
		if not player_data.is_empty():
			player_data["coords"] = player_data.get(
				"coords", migrated.get("player_coords", Vector2i.ZERO)
			)
			migrated["player_record"] = player_data
		migrated["version"] = 13
	if from_version in [12, 13]:
		migrated["applied_world_receipts"] = migrated.get(
			"applied_world_receipts", {}
		)
		var active_node := str(migrated.get("active_node_id", ""))
		migrated["active_world_actions"] = _migrate_world_action_reservations(
			migrated.get("active_world_actions", {}), active_node
		)
		for hex_entry in migrated.get("hexes", []):
			if not hex_entry is Dictionary:
				continue
			var record_data: Dictionary = hex_entry.get("record", {}).duplicate(true)
			record_data["revision"] = maxi(0, int(record_data.get("revision", 0)))
			hex_entry["record"] = record_data
		for node_id in migrated.get("node_runtime_snapshots", {}).keys():
			var node_snapshot: Dictionary = migrated["node_runtime_snapshots"][node_id]
			node_snapshot["active_world_actions"] = _migrate_world_action_reservations(
				node_snapshot.get("active_world_actions", {}), str(node_id)
			)
			migrated["node_runtime_snapshots"][node_id] = node_snapshot
		migrated["version"] = SAVE_VERSION
	return migrated


func _migrate_world_action_reservations(
	value: Variant,
	node_id: String
) -> Dictionary:
	if not value is Dictionary:
		return {}
	var migrated: Dictionary = {}
	for action_id_value in value.keys():
		var action_id := str(action_id_value)
		var state: Variant = value[action_id_value]
		if action_id.is_empty() or not state is Dictionary:
			continue
		var reservation := WorldActionReservationRecord.from_dict(state)
		reservation.action_id = action_id
		if reservation.node_id.is_empty():
			reservation.node_id = node_id
		reservation.actor_id = str(state.get("actor_id", reservation.actor_id))
		reservation.target_id = str(state.get("target_id", reservation.target_id))
		reservation.verb_id = str(state.get("verb_id", reservation.verb_id))
		reservation.started_minute = maxi(0, int(state.get("started_minute", 0)))
		reservation.progress = clampf(float(state.get("progress", 0.0)), 0.0, 1.0)
		reservation.state = state.duplicate(true)
		if reservation.validation_error().is_empty():
			migrated[action_id] = reservation.to_dict()
	return migrated


func _normalized_applied_encounters(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var entries: Array[Dictionary] = []
	for encounter_id_value in (value as Dictionary).keys():
		var encounter_id := str(encounter_id_value)
		if encounter_id.is_empty():
			continue
		entries.append({
			"encounter_id": encounter_id,
			"minute": maxi(0, int((value as Dictionary)[encounter_id_value])),
		})
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_minute := int(left.get("minute", 0))
		var right_minute := int(right.get("minute", 0))
		if left_minute != right_minute:
			return left_minute < right_minute
		return str(left.get("encounter_id", "")) < str(right.get("encounter_id", ""))
	)
	while entries.size() > 64:
		entries.pop_front()
	var normalized: Dictionary = {}
	for entry in entries:
		normalized[entry["encounter_id"]] = entry["minute"]
	return normalized


func _normalized_applied_world_receipts(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var entries: Array[Dictionary] = []
	for receipt_id_value in (value as Dictionary).keys():
		var receipt_id := str(receipt_id_value)
		if receipt_id.is_empty():
			continue
		entries.append({
			"receipt_id": receipt_id,
			"minute": maxi(0, int((value as Dictionary)[receipt_id_value])),
		})
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_minute := int(left.get("minute", 0))
		var right_minute := int(right.get("minute", 0))
		if left_minute != right_minute:
			return left_minute < right_minute
		return str(left.get("receipt_id", "")) < str(right.get("receipt_id", ""))
	)
	while entries.size() > 256:
		entries.pop_front()
	var normalized: Dictionary = {}
	for entry in entries:
		normalized[entry["receipt_id"]] = entry["minute"]
	return normalized


func _replace_save_file(temporary_path: String, final_path: String) -> bool:
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var final_absolute := ProjectSettings.globalize_path(final_path)
	var backup_absolute := final_absolute + ".previous"
	if FileAccess.file_exists(backup_absolute):
		DirAccess.remove_absolute(backup_absolute)
	var had_final := FileAccess.file_exists(final_path)
	if had_final:
		if DirAccess.rename_absolute(final_absolute, backup_absolute) != OK:
			DirAccess.remove_absolute(temporary_absolute)
			return false
	if DirAccess.rename_absolute(temporary_absolute, final_absolute) != OK:
		if had_final and FileAccess.file_exists(backup_absolute):
			DirAccess.rename_absolute(backup_absolute, final_absolute)
		return false
	if FileAccess.file_exists(backup_absolute):
		DirAccess.remove_absolute(backup_absolute)
	return true


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
