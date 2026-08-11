extends RefCounted
class_name WorldActionKernel

## Injected application seam for world actions.  The compatibility resolver
## remains static for old callers while new orchestration can own one kernel
## instance and one catalog.

const DEFAULT_CATALOG: WorldWorkTaskCatalog = preload("res://WorldCore/world_work_tasks.tres")
const DEFAULT_INTERACTION_CATALOG: WorldInteractionCatalog = preload(
	"res://SystemCore/world_interactions.tres"
)
const DEFAULT_TIME_RULES: TimeRulesProfile = preload(
	"res://SystemCore/default_time_rules.tres"
)

var work_catalog: WorldWorkTaskCatalog
var interaction_catalog: WorldInteractionCatalog
var time_rules: TimeRulesProfile


func _init(
	catalog: WorldWorkTaskCatalog = null,
	action_catalog: WorldInteractionCatalog = null,
	rules: TimeRulesProfile = null
) -> void:
	work_catalog = catalog if catalog != null else DEFAULT_CATALOG
	interaction_catalog = (
		action_catalog if action_catalog != null else DEFAULT_INTERACTION_CATALOG
	)
	time_rules = rules if rules != null else DEFAULT_TIME_RULES


func profile_for_id(profile_id: String) -> WorldWorkTaskProfile:
	var profile := work_catalog.profile_for_id(profile_id) if work_catalog != null else null
	return profile if profile != null else WorldActionResolver.profile_for_id(profile_id)


func apply_method_profile(profile: WorldWorkTaskProfile, method_id: String) -> void:
	if work_catalog != null and work_catalog.apply_method_profile(profile, method_id):
		return
	WorldActionResolver.apply_method_profile(profile, method_id)


func method_ids() -> PackedStringArray:
	return work_catalog.method_ids() if work_catalog != null else PackedStringArray()


func query_affordances(actor_context: Dictionary, target: WorldObjectRecord) -> Array[WorldAffordance]:
	return WorldActionResolver.query_affordances(
		actor_context,
		target,
		interaction_catalog
	)


func build_preview(
	request: WorldActionRequest,
	affordance: WorldAffordance,
	actor_context: Dictionary,
	target_context: Dictionary,
	task_profile: WorldWorkTaskProfile = null
) -> WorldActionPreview:
	return WorldActionResolver.build_preview(
		request,
		affordance,
		actor_context,
		target_context,
		task_profile,
		interaction_catalog,
		time_rules
	)


func resolve_work_attempt(
	request: WorldActionRequest,
	profile: WorldWorkTaskProfile,
	work_state: Dictionary,
	hit_success_window: bool,
	severe_miss: bool = false
) -> WorldActionReceipt:
	return WorldActionResolver.resolve_work_attempt(
		request,
		profile,
		work_state,
		hit_success_window,
		severe_miss
	)


func resolve_ai_work(
	request: WorldActionRequest,
	profile: WorldWorkTaskProfile,
	actor_context: Dictionary,
	work_state: Dictionary,
	seed: int
) -> WorldActionReceipt:
	return WorldActionResolver.resolve_ai_work(
		request,
		profile,
		actor_context,
		work_state,
		seed
	)


func resolve_direct_action(
	request: WorldActionRequest,
	elapsed_minutes: int,
	exertion: float = 0.0,
	noise_intensity: float = 0.0,
	message: String = "Action committed."
) -> WorldActionReceipt:
	return WorldActionResolver.resolve_direct_action(
		request,
		elapsed_minutes,
		exertion,
		noise_intensity,
		message,
		interaction_catalog
	)


func commit(
	request: WorldActionRequest,
	profile: WorldWorkTaskProfile = null,
	work_state: Dictionary = {},
	hit_success_window: bool = true,
	severe_miss: bool = false
) -> WorldActionReceipt:
	## Unified commit entry point. Work actions use the task kernel; direct
	## actions still produce the same typed receipt contract.
	if request == null:
		return WorldActionReceipt.new()
	if profile != null:
		return resolve_work_attempt(
			request,
			profile,
			work_state,
			hit_success_window,
			severe_miss
		)
	var elapsed_minutes := int(request.payload.get("elapsed_minutes", 0))
	var exertion := float(request.payload.get("exertion", 0.0))
	var noise := float(request.payload.get("noise_intensity", 0.0))
	return resolve_direct_action(request, elapsed_minutes, exertion, noise)


func apply_work_consequences(
	target: WorldObjectRecord,
	verb_id: String,
	receipt: WorldActionReceipt
) -> void:
	## Consequences mutate only the detached record supplied by the application
	## adapter. The catalog selects the action; this kernel owns the small set of
	## algorithmic component transitions that cannot be represented as a scalar.
	if target == null or receipt == null:
		return
	if receipt.interrupted:
		target.condition = maxf(0.0, target.condition - 0.20)
		target.runtime["damage_state"] = "damaged"
		target.components["debris"] = {
			"material_units": 1,
			"source": target.definition_id,
		}
		if target.has_component("shelter"):
			var shelter := target.component("shelter").duplicate(true)
			if str(shelter.get("state", "")) == "secured":
				shelter["state"] = "secured_damaged"
				target.components["shelter"] = shelter
				target.components["structure"]["state"] = "secured_damaged"
		receipt.mutations.append({
			"type": "target_damaged",
			"target_id": target.object_id,
			"condition": target.condition,
		})
		if target.condition <= 0.0:
			target.components.erase("repairable")
			target.components.erase("door")
			target.components.erase("container")
			target.components.erase("dismantlable")
			target.components["debris"] = {
				"material_units": 2,
				"source": target.definition_id,
			}
			target.runtime["broken"] = true
			receipt.mutations.append({
				"type": "target_became_debris",
				"target_id": target.object_id,
			})
	if not receipt.work_completed:
		return
	match verb_id:
		WorldActionResolver.VERB_FORCE:
			var door := target.component("door")
			if not door.is_empty():
				door["locked"] = false
				door["open"] = true
				door["state"] = "forced_open"
				target.components["door"] = door
				target.condition = maxf(0.25, target.condition - 0.30)
				receipt.mutations.append({"type": "forced_entry", "target_id": target.object_id})
		WorldActionResolver.VERB_DISMANTLE:
			target.condition = maxf(0.0, target.condition - 0.55)
			target.components.erase("container")
			target.components.erase("dismantlable")
			target.components["debris"] = {
				"material_units": 2,
				"source": target.definition_id,
			}
			target.runtime["dismantled"] = true
			receipt.mutations.append({"type": "dismantled", "target_id": target.object_id})


func apply_receipt(
	receipt: WorldActionReceipt,
	target_state: Dictionary = {}
) -> Dictionary:
	## Apply neutral receipt mutations to a copied component state. The caller
	## must submit the returned state to RuntimeStateStore; this method never
	## exposes or mutates an authoritative record.
	var next_state := target_state.duplicate(true)
	if receipt == null or not receipt.committed:
		return next_state
	for mutation in receipt.mutations:
		if not mutation is Dictionary:
			continue
		match str(mutation.get("type", "")):
			"work_progress":
				next_state["completed_units"] = int(mutation.get("completed_units", 0))
				next_state["work_units"] = int(mutation.get("work_units", 0))
				next_state["work_completed"] = bool(mutation.get("completed", false))
			"elapsed_time":
				next_state["last_elapsed_minutes"] = int(mutation.get("elapsed_minutes", 0))
			"authored_effect":
				var effects: Array = next_state.get("authored_effects", [])
				effects.append(mutation.get("payload", {}).duplicate(true))
				next_state["authored_effects"] = effects
			_:
				next_state["last_mutation"] = mutation.duplicate(true)
	next_state["last_receipt"] = receipt.to_dict()
	next_state["revision"] = int(next_state.get("revision", 0)) + 1
	return next_state
