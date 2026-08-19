extends SceneTree

const SAVE_PATH := "res://.godot/test-logs/world_action_session_identity.json"

var _store: RuntimeStateStore
var _generator: HexWorldGenerator
var _coordinator := MacroWorldActionCoordinator.new()
var _time_rules := MacroTimeRulesService.new()
var _execution_service := MacroWorldActionExecutionService.new()
var _receipt_application_service := MacroReceiptApplicationService.new()
var _last_application: WorldActionApplicationReceipt


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_store = _build_store()
	_configure_services(_store)

	var action_a_first := _execute_search()
	if action_a_first == null or _last_application == null:
		_fail("Action A first attempt did not commit.")
		return
	if _last_application.idempotent:
		_fail("Action A first attempt was incorrectly classified as idempotent.")
		return

	var action_a_second := _execute_search()
	if action_a_second == null or _last_application == null:
		_fail("Action A completion attempt did not commit.")
		return
	if not action_a_second.work_completed:
		_fail("Action A did not complete the controlled two-unit work session.")
		return
	if action_a_first.action_id != action_a_second.action_id:
		_fail("Two attempts in one work session changed the session identity.")
		return
	if action_a_first.receipt_id == action_a_second.receipt_id:
		_fail("Two attempts in one work session reused a receipt identity.")
		return

	var action_a_id := action_a_second.action_id
	if not _store.save_to_disk(SAVE_PATH):
		_fail("Could not save between completed action A and new action B.")
		return
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(SAVE_PATH):
		_fail("Could not load the completed action A state before action B.")
		return
	_store = loaded
	_configure_services(_store)

	var action_b_first := _execute_search()
	if action_b_first == null or _last_application == null:
		_fail("Action B did not commit after save/load.")
		return
	if not _last_application.applied or _last_application.idempotent:
		_fail("Action B was rejected or incorrectly classified as an idempotent replay.")
		return
	if action_b_first.action_id == action_a_id:
		_fail("A newly started work session reused action A's session identity.")
		return
	if action_b_first.receipt_id == action_a_second.receipt_id:
		_fail("A newly started work session reused action A's receipt identity.")
		return

	var action_b_second := _execute_search()
	if action_b_second == null or _last_application == null:
		_fail("Action B completion attempt did not commit.")
		return
	if not action_b_second.work_completed or _last_application.idempotent:
		_fail("Action B completion was not a normal non-idempotent commit.")
		return
	if action_b_first.action_id != action_b_second.action_id:
		_fail("Action B attempts did not remain in one new session.")
		return

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("WORLD_ACTION_SESSION_IDENTITY_SMOKE: PASS")
	quit(0)


func _configure_services(store: RuntimeStateStore) -> void:
	if _generator == null:
		_generator = HexWorldGenerator.new()
	_coordinator.configure(WorldActionKernel.new())
	_time_rules.configure()
	_receipt_application_service.configure(store, null, null)
	_execution_service.configure(
		store,
		_generator,
		_coordinator,
		_time_rules,
		{
			"actor_context": Callable(self, "_actor_context"),
			"commit_receipt": Callable(self, "_commit_receipt"),
		}
	)


func _execute_search() -> WorldActionReceipt:
	_last_application = null
	return _execution_service.resolve_shared_work_action(
		Vector2i.ZERO,
		WorldActionResolver.VERB_SEARCH,
		"repeatable-search",
		"",
		0.0,
		15,
		true
	)


func _actor_context() -> Dictionary:
	return {
		"actor_id": "player",
		"revision": _store.player_record.revision if _store.player_record != null else -1,
		"capabilities": [],
	}


func _commit_receipt(
	receipt: WorldActionReceipt,
	coords: Vector2i,
	target: WorldObjectRecord
) -> WorldActionApplicationReceipt:
	receipt.target_state = target.to_dict() if target != null else {}
	_last_application = _receipt_application_service.commit(receipt, coords, target)
	return _last_application


func _build_store() -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("WORLD_ACTION_SESSION_IDENTITY")
	var definition := preload("res://BiologicalCore/player_def.tres") as EntityDefinition
	var runtime := _runtime_for_definition(definition, "player")
	store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"definition": definition.to_state(),
		"runtime": runtime,
	}, Vector2i.ZERO)
	store.set_campaign_state({"seed": store.world_seed}, "node-a", 0)
	var target := WorldObjectRecord.new()
	target.object_id = "repeatable-search"
	target.node_id = "node-a"
	target.coords = Vector2i.ZERO
	target.components["container"] = {"finite": false}
	var hex := HexRecord.new()
	hex.world_objects = [target.to_dict()]
	store.set_hex_record(Vector2i.ZERO, hex)
	return store


func _runtime_for_definition(definition: EntityDefinition, actor_id: String) -> Dictionary:
	var core := EntityFactory.record_to_humanoid_core({
		"entity_id": actor_id,
		"definition": definition.to_state(),
		"runtime": {},
	}, null, actor_id)
	var runtime := core.capture_runtime_state().to_dict()
	core.free()
	return runtime


func _fail(message: String) -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	push_error("[WORLD_ACTION_SESSION_IDENTITY] " + message)
	quit(1)
