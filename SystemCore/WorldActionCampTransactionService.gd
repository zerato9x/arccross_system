extends RefCounted
class_name WorldActionCampTransactionService

## Detached canonical staging for one camp-rest cycle. The receipt carries the
## already-resolved deterministic recovery values; this service applies them to
## the canonical actor and hex before elapsed survival processing.

const MUTATION_TYPE := "camp_cycle_application"
const METHOD_ID := "camp"
const VERB_ID := "sleep"

var store: RuntimeStateStore


func configure(state: RuntimeStateStore) -> void:
	store = state


func has_action(receipt: WorldActionReceipt) -> bool:
	if receipt == null:
		return false
	for mutation in receipt.mutations:
		if mutation is Dictionary and str(mutation.get("type", "")) == MUTATION_TYPE:
			return true
	return false


func validation_error(receipt: WorldActionReceipt) -> String:
	if not has_action(receipt):
		return ""
	var actions: Array[Dictionary] = []
	for mutation_value in receipt.mutations:
		var mutation: Dictionary = mutation_value
		var mutation_type := str(mutation.get("type", ""))
		if mutation_type == MUTATION_TYPE:
			actions.append(mutation)
		elif mutation_type != "elapsed_time":
			return "World-action camp cycle contains conflicting mutations."
	if actions.size() != 1:
		return "World-action receipt contains duplicate camp cycles."
	if receipt.actor_id != "player":
		return "World-action camp cycles only support the player actor."
	if receipt.verb_id != VERB_ID or receipt.method_id != METHOD_ID:
		return "World-action camp cycle has the wrong verb or method."
	if receipt.target_id != "camp:" + str(receipt.target_coords):
		return "World-action camp cycle targets the wrong location identity."
	var mutation := actions[0]
	var fatigue_recovery := float(mutation.get("fatigue_recovery", -1.0))
	var healing_amount := float(mutation.get("healing_amount", -1.0))
	var rest_count_delta := int(mutation.get("camp_rest_count_delta", 0))
	if (
		fatigue_recovery < 0.0
		or healing_amount < 0.0
		or fatigue_recovery > GameEnums.SCALE_MAX
		or healing_amount > GameEnums.SCALE_MAX
		or rest_count_delta not in [1, 2]
		or receipt.elapsed_minutes <= 0
	):
		return "World-action camp recovery values are malformed."
	return ""


func stage(core: HumanoidCore, receipt: WorldActionReceipt) -> Dictionary:
	if not has_action(receipt):
		return {
			"handled": false,
			"success": true,
			"hex_state": {},
		}
	if core == null or store == null or core.body == null:
		return _failure("Camp transaction services are unavailable.")
	var current_hex := store.get_hex_record(receipt.target_coords)
	if current_hex == null:
		return _failure("Canonical camp state is unavailable.")
	var mutation := _mutation(receipt)
	var fatigue_recovery := float(mutation.get("fatigue_recovery", 0.0))
	var healing_amount := float(mutation.get("healing_amount", 0.0))
	var fatigue_before: float = core.body.fatigue
	core.body.fatigue = maxf(0.0, fatigue_before - fatigue_recovery)
	var healed := 0.0
	for limb in core.body.limb_hp.keys():
		if core.body.limb_hp[limb] <= 0.0:
			continue
		var amount := minf(
			core.body.get_limb_max(limb) - core.body.limb_hp[limb],
			healing_amount
		)
		core.body.limb_hp[limb] += amount
		healed += amount
	var next_hex := HexRecord.from_dict(current_hex.to_dict())
	next_hex.camp_rest_count += int(mutation.get("camp_rest_count_delta", 1))
	return {
		"handled": true,
		"success": true,
		"error": "",
		"hex_state": next_hex.to_dict(),
		"fatigue_recovered": fatigue_before - core.body.fatigue,
		"healed": healed,
	}


func _mutation(receipt: WorldActionReceipt) -> Dictionary:
	for mutation in receipt.mutations:
		if str(mutation.get("type", "")) == MUTATION_TYPE:
			return mutation
	return {}


func _failure(message: String) -> Dictionary:
	return {
		"handled": true,
		"success": false,
		"error": message,
		"hex_state": {},
	}
