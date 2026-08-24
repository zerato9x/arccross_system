extends RefCounted
class_name MacroInventoryActionService

## Macro inventory orchestration. The live player is never used for rule
## resolution: validation runs on a disposable canonical projection and the
## authoritative application boundary repeats the command inside its rollback
## snapshot before committing player and ground state together.

const RECEIPT_MUTATION := "inventory_action"
const RECEIPT_METHOD := "inventory"
const REPAIR_MINUTES := 30

var world_state: RuntimeStateStore
var action_coordinator: MacroWorldActionCoordinator
var time_rules: MacroTimeRulesService
var commit_receipt: Callable


func configure(
	state: RuntimeStateStore,
	coordinator: MacroWorldActionCoordinator,
	rules: MacroTimeRulesService,
	commit_callback: Callable
) -> void:
	world_state = state
	action_coordinator = coordinator
	time_rules = rules
	commit_receipt = commit_callback


func resolve(
	action_id: String,
	instance_id: String,
	equipment_slot: int,
	coords: Vector2i,
	action_payload: Dictionary = {}
) -> Dictionary:
	if world_state == null or world_state.player_record == null:
		return {"committed": false, "message": "Canonical player state is unavailable."}
	if action_coordinator == null or not commit_receipt.is_valid():
		return {"committed": false, "message": "Inventory transaction services are unavailable."}
	if instance_id.is_empty():
		return {"committed": false, "message": "The inventory item identity is missing."}

	var payload := action_payload.duplicate(true)
	# A repair roll belongs to the receipt. Generating it once prevents validation
	# and canonical staging from consulting two different random universes.
	if (
		action_id == GameEnums.MACRO_INV_REPAIR
		and float(payload.get("roll_override", -1.0)) < 0.0
	):
		payload["roll_override"] = randf()

	var validation := _evaluate_canonical(
		action_id,
		instance_id,
		equipment_slot,
		payload,
		coords,
		"InventoryValidationActor"
	)
	if not bool(validation.get("committed", false)):
		return validation

	# Knowledge inspection changes meta/campaign knowledge, not carried runtime.
	# The manager applies it only after this canonical validation succeeds.
	if action_id == GameEnums.MACRO_INV_INSPECT:
		validation["player_runtime"] = world_state.player_record.runtime.duplicate(true)
		return validation

	var elapsed_minutes := (
		REPAIR_MINUTES
		if action_id == GameEnums.MACRO_INV_REPAIR
		else time_rules.action_minutes("action")
	)
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = instance_id
	request.target_coords = coords
	request.verb_id = (
		WorldActionResolver.VERB_PICK_UP
		if action_id == GameEnums.MACRO_INV_TAKE
		else action_id
	)
	request.method_id = RECEIPT_METHOD
	request.expected_actor_revision = world_state.player_record.revision
	request.payload = {
		"world_time_minutes": world_state.world_time_minutes,
		"action_id": "inventory:%s:%s:%d" % [
			action_id,
			instance_id,
			world_state.player_record.revision,
		],
	}
	var receipt := action_coordinator.resolve_direct_action(
		request,
		elapsed_minutes,
		0.0,
		0.0,
		"Inventory action committed."
	)
	receipt.mutations.append({
		"type": RECEIPT_MUTATION,
		"action_id": action_id,
		"instance_id": instance_id,
		"equipment_slot": equipment_slot,
		"action_payload": payload.duplicate(true),
	})
	var application: WorldActionApplicationReceipt = commit_receipt.call(receipt, coords)
	validation["action_receipt"] = receipt.to_dict()
	if application == null or not application.applied:
		world_state.cancel_world_action(receipt.action_id)
		validation["committed"] = false
		validation["message"] = (
			application.error
			if application != null and not application.error.is_empty()
			else "The inventory transaction was rejected without changing world state."
		)
		validation["player_runtime"] = world_state.player_record.runtime.duplicate(true)
		return validation
	validation["player_runtime"] = world_state.player_record.runtime.duplicate(true)
	return validation


func _evaluate_canonical(
	action_id: String,
	instance_id: String,
	equipment_slot: int,
	action_payload: Dictionary,
	coords: Vector2i,
	actor_name: String
) -> Dictionary:
	var core := EntityFactory.record_to_humanoid_core(
		world_state.player_record.to_dict(),
		null,
		actor_name
	)
	if core == null:
		return {"committed": false, "message": "Could not reconstruct canonical player state."}
	var resolver := HumanoidInventoryActionService.new()
	var result := resolver.apply(
		core,
		action_id,
		instance_id,
		equipment_slot,
		action_payload,
		world_state.get_ground_items(coords)
	)
	core.free()
	return result
