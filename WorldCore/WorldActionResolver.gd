extends RefCounted
class_name WorldActionResolver

## Shared affordance and work-resolution kernel. The current macro manager can
## adopt this incrementally: player UI and NPC planners both submit the same
## WorldActionRequest and consume the same WorldActionReceipt.

const VERB_INSPECT := "inspect"
const VERB_SEARCH := "search"
const VERB_REPAIR := "repair"
const VERB_DISMANTLE := "dismantle"
const VERB_OPEN := "open"
const VERB_FORCE := "force"
const VERB_SLEEP := "sleep"
const VERB_PICK_UP := "pick_up"
const VERB_TRAP := "trap"
const DEFAULT_WORK_CATALOG: WorldWorkTaskCatalog = preload(
	"res://WorldCore/world_work_tasks.tres"
)
const DEFAULT_INTERACTION_CATALOG: WorldInteractionCatalog = preload(
	"res://SystemCore/world_interactions.tres"
)
const DEFAULT_TIME_RULES: TimeRulesProfile = preload(
	"res://SystemCore/default_time_rules.tres"
)


static func profile_for_id(profile_id: String) -> WorldWorkTaskProfile:
	var catalog_profile := DEFAULT_WORK_CATALOG.profile_for_id(profile_id)
	if catalog_profile != null:
		return catalog_profile
	return _legacy_profile_for_id(profile_id)


static func _legacy_profile_for_id(profile_id: String) -> WorldWorkTaskProfile:
	var profile := WorldWorkTaskProfile.new()
	profile.profile_id = profile_id
	match profile_id:
		"repair_manual":
			profile.work_units = 4
			profile.base_success_window = 0.24
			profile.base_noise = 1.25
			profile.base_tool_wear = 0.08
			profile.miss_resets_stage = true
		"salvage_manual", "search_manual":
			profile.work_units = 2
			profile.base_success_window = 0.30
			profile.base_noise = 0.85
		"force_manual":
			profile.work_units = 3
			profile.base_success_window = 0.20
			profile.base_noise = 2.0
			profile.base_tool_wear = 0.12
			profile.miss_resets_stage = true
		"trap_manual":
			profile.work_units = 1
			profile.base_success_window = 0.36
			profile.base_noise = 0.55
		_:
			profile.work_units = 1
	return profile


static func apply_method_profile(profile: WorldWorkTaskProfile, method_id: String) -> void:
	if profile == null:
		return
	if DEFAULT_WORK_CATALOG.apply_method_profile(profile, method_id):
		return
	_legacy_apply_method_profile(profile, method_id)


static func _legacy_apply_method_profile(profile: WorldWorkTaskProfile, method_id: String) -> void:
	if profile == null:
		return
	match method_id:
		"crowbar":
			profile.base_success_window = minf(0.82, profile.base_success_window + 0.12)
			profile.base_noise += 1.0
			profile.base_tool_wear += 0.10
		"multitool":
			profile.work_units = maxi(1, profile.work_units - 1)
			profile.base_noise = maxf(0.1, profile.base_noise - 0.25)
			profile.base_tool_wear += 0.16
		"hands":
			profile.base_success_window = maxf(0.08, profile.base_success_window - 0.08)
			profile.base_noise += 0.35

static func query_affordances(
	actor_context: Dictionary,
	target: WorldObjectRecord,
	interaction_catalog: WorldInteractionCatalog = null
) -> Array[WorldAffordance]:
	var result: Array[WorldAffordance] = []
	if target == null:
		return result
	var catalog := interaction_catalog if interaction_catalog != null else DEFAULT_INTERACTION_CATALOG
	var has_rubble := target.has_component("rubble")
	var rubble := target.component("rubble")
	var rubble_depleted := has_rubble and bool(rubble.get("depleted", false))
	var has_debris := target.has_component("debris")
	var debris := target.component("debris")
	var debris_depleted := has_debris and int(debris.get("material_units", 0)) <= 0
	var has_container := target.has_component("container")
	var container := target.component("container")
	var container_depleted := (
		has_container
		and bool(container.get("finite", false))
		and int(container.get("remaining_searches", 1)) <= 0
	)
	if (
		(has_container or has_rubble or has_debris)
		and _definition_allows(target, VERB_SEARCH, catalog)
		and not rubble_depleted
		and not debris_depleted
		and not container_depleted
	):
		result.append(_affordance(
			VERB_SEARCH,
			"Search",
			target,
			[],
			"search_manual",
			catalog
		))
	var repairable_active := target.has_component("repairable")
	if repairable_active and target.has_component("shelter"):
		var shelter_state := str(target.component("shelter").get("state", "ruined"))
		var repairable := target.component("repairable")
		var stages: Array = repairable.get("stages", [])
		var completed_stage := int(target.runtime.get("service_stage", 0))
		# A secured hub is already fully serviced. Damage is represented by the
		# explicit secured_damaged state, which re-opens ordinary repair without
		# making a healthy hub advertise an infinite repair loop.
		if shelter_state == "secured":
			repairable_active = false
		elif not stages.is_empty() and completed_stage >= stages.size() and shelter_state != "secured_damaged":
			repairable_active = false
	if repairable_active and _definition_allows(target, VERB_REPAIR, catalog):
		result.append(_affordance(
			VERB_REPAIR,
			"Repair",
			target,
			["material"],
			str(target.component("repairable").get("task_profile_id", "repair_manual")),
			catalog
		))
	if target.has_component("dismantlable") and _definition_allows(target, VERB_DISMANTLE, catalog):
		var dismantle_methods: Array = target.component("dismantlable").get("methods", [])
		var dismantle_requirements: Array = []
		if not dismantle_methods.has("hands"):
			if dismantle_methods.has("multitool"):
				dismantle_requirements.append("repair_tool")
			if dismantle_methods.has("crowbar"):
				dismantle_requirements.append("force_tool")
		result.append(_affordance(
			VERB_DISMANTLE,
			"Dismantle",
			target,
			dismantle_requirements,
			"salvage_manual",
			catalog
		))
	if target.has_component("door"):
		var door := target.component("door")
		if bool(door.get("open", false)):
			if _definition_allows(target, VERB_INSPECT, catalog):
				result.append(_affordance(VERB_INSPECT, "Inspect", target, [], "", catalog))
		else:
			if _definition_allows(target, VERB_OPEN, catalog):
				result.append(_affordance(VERB_OPEN, "Open", target, [], "", catalog))
			if bool(door.get("locked", false)) and _definition_allows(target, VERB_FORCE, catalog):
				result.append(_affordance(VERB_FORCE, "Force", target, ["force_tool"], "force_manual", catalog))
	var has_bed := target.has_component("bed")
	var bed := target.component("bed")
	var has_shelter := target.has_component("shelter")
	var shelter := target.component("shelter")
	var bed_usable := has_bed and str(bed.get("state", "unusable")) == "usable"
	var shelter_usable := has_shelter and str(shelter.get("state", "ruined")) in [
		"habitable", "secured", "secured_damaged"
	]
	if (bed_usable or shelter_usable) and _definition_allows(target, VERB_SLEEP, catalog):
		# A real bed/shelter supplies the sleeping surface. Ground camping still
		# uses the existing camp gear workflow, but an actor is not required to
		# carry a bedroll to use an intact service.
		result.append(_affordance(VERB_SLEEP, "Sleep", target, [], "", catalog))
	if target.has_component("trap_anchor") and _definition_allows(target, VERB_TRAP, catalog):
		result.append(_affordance(
			VERB_TRAP, "Set trap", target, ["trap_gear"], "trap_manual", catalog
		))
	if target.has_component("ground_item") and _definition_allows(target, VERB_PICK_UP, catalog):
		result.append(_affordance(VERB_PICK_UP, "Pick up", target, [], "", catalog))
	return result


static func build_preview(
	request: WorldActionRequest,
	affordance: WorldAffordance,
	actor_context: Dictionary,
	target_context: Dictionary,
	task_profile: WorldWorkTaskProfile = null,
	interaction_catalog: WorldInteractionCatalog = null,
	time_rules: TimeRulesProfile = null
) -> WorldActionPreview:
	var preview := WorldActionPreview.new()
	preview.task_profile_id = affordance.task_profile_id if affordance != null else ""
	preview.reservation_key = "%s:%s" % [request.actor_id, request.target_id]
	if affordance == null or not affordance.allowed:
		preview.reason = affordance.denial_reason if affordance != null else "Action unavailable."
		return preview
	if not _requirements_met(affordance.requirements, actor_context):
		preview.reason = "Required capability or tool is unavailable."
		return preview
	if request.expected_actor_revision >= 0 and int(actor_context.get("revision", -1)) != request.expected_actor_revision:
		preview.reason = "The actor changed before work could begin."
		return preview
	if request.expected_target_revision >= 0 and int(target_context.get("revision", -1)) != request.expected_target_revision:
		preview.reason = "The target changed before work could begin."
		return preview
	preview.allowed = true
	preview.reason = ""
	var catalog := interaction_catalog if interaction_catalog != null else DEFAULT_INTERACTION_CATALOG
	var rules := time_rules if time_rules != null else DEFAULT_TIME_RULES
	var authored_action := catalog.action_for_verb(request.verb_id)
	var default_minutes := rules.minutes_for(request.verb_id, 15)
	preview.elapsed_minutes = int(target_context.get("elapsed_minutes", default_minutes))
	preview.exertion = float(target_context.get("exertion", 0.5))
	preview.noise_intensity = float(target_context.get("noise_intensity", 0.0))
	preview.light_intensity = float(target_context.get("light_intensity", 0.0))
	preview.tool_wear = float(target_context.get("tool_wear", 0.0))
	preview.risk = target_context.get("risk", {}).duplicate(true)
	preview.uncertainty = target_context.get("uncertainty", {}).duplicate(true)
	var owner_id := str(target_context.get("owner_id", ""))
	var actor_id := str(actor_context.get("actor_id", request.actor_id))
	if not owner_id.is_empty() and not actor_id.is_empty() and owner_id != actor_id:
		preview.risk["trespass"] = true
		if request.verb_id in [VERB_SEARCH, VERB_PICK_UP, VERB_DISMANTLE]:
			preview.risk["theft"] = true
	if task_profile != null:
		preview.task_profile_id = task_profile.profile_id
		preview.elapsed_minutes = maxi(
			preview.elapsed_minutes,
			task_profile.normalized_units() * 15
		)
		preview.noise_intensity += task_profile.base_noise
		preview.tool_wear += task_profile.base_tool_wear
	if authored_action != null:
		preview.elapsed_minutes = maxi(preview.elapsed_minutes, authored_action.elapsed_minutes)
		preview.exertion += authored_action.exertion
		preview.noise_intensity += authored_action.noise_intensity
	return preview


static func resolve_work_attempt(
	request: WorldActionRequest,
	profile: WorldWorkTaskProfile,
	work_state: Dictionary,
	hit_success_window: bool,
	severe_miss: bool = false
) -> WorldActionReceipt:
	var receipt := WorldActionReceipt.new()
	receipt.action_id = str(work_state.get("action_id", ""))
	receipt.receipt_id = str(work_state.get(
		"receipt_id",
		"%s:attempt:%d" % [receipt.action_id, int(work_state.get("attempt_index", 0))]
	))
	receipt.node_id = str(request.payload.get("node_id", ""))
	receipt.actor_id = request.actor_id
	receipt.target_id = request.target_id
	receipt.target_coords = request.target_coords
	receipt.verb_id = request.verb_id
	receipt.method_id = request.method_id
	receipt.expected_actor_revision = request.expected_actor_revision
	receipt.expected_target_revision = request.expected_target_revision
	receipt.expected_hex_revision = int(request.payload.get("expected_hex_revision", -1))
	receipt.committed = true
	receipt.elapsed_minutes = maxi(1, int(work_state.get("elapsed_minutes", 15)))
	receipt.exertion = maxf(0.1, float(profile.normalized_units()) * 0.45)
	receipt.noise_intensity = maxf(0.0, profile.base_noise)
	receipt.tool_wear = maxf(0.0, profile.base_tool_wear)
	var completed_units := int(work_state.get("completed_units", 0))
	var misses := int(work_state.get("misses", 0))
	if hit_success_window:
		completed_units += 1
		receipt.events.append({"type": "work_success", "unit": completed_units})
		if bool(work_state.get("emit_success_signal", false)) and profile.base_noise > 0.0:
			var success_noise := WorldSignalRecord.new()
			success_noise.signal_id = "%s:noise:%d" % [receipt.action_id, completed_units]
			success_noise.signal_type = "noise"
			success_noise.source_id = request.actor_id
			success_noise.coords = request.target_coords
			success_noise.intensity = profile.base_noise
			success_noise.created_minute = int(work_state.get("world_time_minutes", 0))
			success_noise.expires_minute = success_noise.created_minute + 30
			receipt.add_signal(success_noise)
	else:
		misses += 1
		receipt.events.append({"type": "work_miss", "misses": misses})
		var noise := WorldSignalRecord.new()
		noise.signal_id = "%s:miss:%d" % [receipt.action_id, misses]
		noise.signal_type = "noise"
		noise.source_id = request.actor_id
		noise.coords = request.target_coords
		noise.intensity = profile.base_noise + float(misses)
		receipt.noise_intensity = noise.intensity
		noise.created_minute = int(work_state.get("world_time_minutes", 0))
		noise.expires_minute = noise.created_minute + 30
		receipt.add_signal(noise)
		if profile.miss_resets_stage or severe_miss:
			completed_units = 0
			receipt.events.append({
				"type": "work_stage_reset",
				"severe": severe_miss,
				"failure": profile.failure_payload.duplicate(true),
			})
	receipt.interrupted = severe_miss
	receipt.message = (
		"The work cycle completed."
		if hit_success_window
		else "The work slipped and made noise."
	)
	receipt.work_progress = float(completed_units) / float(profile.normalized_units())
	receipt.work_completed = completed_units >= profile.normalized_units()
	receipt.mutations.append({
		"type": "work_progress",
		"target_id": request.target_id,
		"completed_units": completed_units,
		"work_units": profile.normalized_units(),
		"completed": receipt.work_completed,
	})
	receipt.presentation = {
		"animation": "work_success" if hit_success_window else "work_miss",
		"vfx": "work_contact" if hit_success_window else "work_slip",
		"sfx": "work_contact" if hit_success_window else "work_miss",
		"commit_marker": "contact_marker",
		"timeline": [
			{"phase": "preview", "duration": 0.16},
			{"phase": "approach", "duration": 0.24},
			{"phase": "work_cycle", "duration": profile.cycle_duration()},
			{"phase": "contact_marker", "duration": 0.0},
			{"phase": "reaction", "duration": 0.18},
			{"phase": "settle", "duration": 0.24},
		],
	}
	return receipt


static func resolve_ai_work(
	request: WorldActionRequest,
	profile: WorldWorkTaskProfile,
	actor_context: Dictionary,
	work_state: Dictionary,
	seed: int
) -> WorldActionReceipt:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var skill := clampf(float(actor_context.get("work_skill", 0.5)), 0.0, 1.0)
	var tools := clampf(float(actor_context.get("tool_bonus", 0.0)), -0.5, 0.8)
	var chance := clampf(profile.success_window() + skill * 0.35 + tools, 0.08, 0.95)
	var hit := rng.randf() <= chance
	var severe := not hit and rng.randf() > chance + 0.35
	return resolve_work_attempt(request, profile, work_state, hit, severe)


static func resolve_direct_action(
	request: WorldActionRequest,
	elapsed_minutes: int,
	exertion: float = 0.0,
	noise_intensity: float = 0.0,
	message: String = "Action committed.",
	action_catalog: WorldActionCatalog = null
) -> WorldActionReceipt:
	## Direct actions still produce a receipt. They simply skip the timing bar;
	## movement, pickup, inspection, eating, drinking, talking, and rest can
	## therefore share the same clock, signal, and presentation boundary.
	var receipt := WorldActionReceipt.new()
	receipt.action_id = str(request.payload.get("action_id", ""))
	if receipt.action_id.is_empty():
		receipt.action_id = "world-session:%s:%s:%s:%s" % [
		request.actor_id,
		request.verb_id,
		request.target_id,
		str(ResourceUID.create_id()),
	]
	receipt.receipt_id = str(request.payload.get(
		"receipt_id",
		"%s:attempt:%d" % [
			receipt.action_id,
			int(request.payload.get("attempt_index", 0)),
		]
	))
	receipt.node_id = str(request.payload.get("node_id", ""))
	receipt.actor_id = request.actor_id
	receipt.target_id = request.target_id
	receipt.target_coords = request.target_coords
	receipt.verb_id = request.verb_id
	receipt.method_id = request.method_id
	receipt.expected_actor_revision = request.expected_actor_revision
	receipt.expected_target_revision = request.expected_target_revision
	receipt.expected_hex_revision = int(request.payload.get("expected_hex_revision", -1))
	receipt.committed = true
	receipt.elapsed_minutes = maxi(0, elapsed_minutes)
	receipt.exertion = maxf(0.0, exertion)
	receipt.noise_intensity = maxf(0.0, noise_intensity)
	receipt.message = message
	receipt.mutations.append({
		"type": "elapsed_time",
		"elapsed_minutes": receipt.elapsed_minutes,
	})
	if receipt.noise_intensity > 0.0:
		var noise := WorldSignalRecord.new()
		noise.signal_id = "%s:noise" % receipt.action_id
		noise.signal_type = "noise"
		noise.source_id = request.actor_id
		noise.coords = request.target_coords
		noise.intensity = receipt.noise_intensity
		noise.created_minute = int(request.payload.get("world_time_minutes", 0))
		noise.expires_minute = noise.created_minute + 30
		receipt.add_signal(noise)
	var vfx := "none"
	var sfx := "none"
	match request.verb_id:
		VERB_OPEN:
			vfx = "door_open"
			sfx = "door_open"
		VERB_PICK_UP:
			vfx = "item_transfer"
			sfx = "item_transfer"
		VERB_SLEEP:
			vfx = "rest_settle"
			sfx = "rest_settle"
		"talk":
			sfx = "conversation"
	var catalog := action_catalog if action_catalog != null else DEFAULT_INTERACTION_CATALOG
	var authored_action := catalog.action_for_verb(request.verb_id)
	if authored_action != null:
		vfx = str(authored_action.presentation.get("vfx", vfx))
		sfx = str(authored_action.presentation.get("sfx", sfx))
		if not authored_action.effect_payload.is_empty():
			receipt.mutations.append({
				"type": "authored_effect",
				"action_id": authored_action.action_id,
				"payload": authored_action.effect_payload.duplicate(true),
			})
	receipt.presentation = {
		"animation": "direct_action",
		"vfx": vfx,
		"sfx": sfx,
		"commit_marker": "contact_marker",
		"timeline": [
			{"phase": "preview", "duration": 0.12},
			{"phase": "approach", "duration": 0.16},
			{"phase": "contact_marker", "duration": 0.0},
			{"phase": "reaction", "duration": 0.14},
			{"phase": "settle", "duration": 0.20},
		],
	}
	return receipt


static func _affordance(
	verb_id: String,
	label: String,
	target: WorldObjectRecord,
	requirements: Array,
	task_profile_id: String,
	interaction_catalog: WorldInteractionCatalog = null
) -> WorldAffordance:
	var affordance := WorldAffordance.new()
	var catalog := interaction_catalog if interaction_catalog != null else DEFAULT_INTERACTION_CATALOG
	var authored_action := catalog.action_for_verb(verb_id)
	affordance.verb_id = verb_id
	affordance.label = authored_action.label if authored_action != null and not authored_action.label.is_empty() else label
	affordance.target_id = target.object_id
	affordance.task_profile_id = (
		authored_action.task_profile_id
		if authored_action != null and not authored_action.task_profile_id.is_empty()
		else task_profile_id
	)
	if authored_action != null and requirements.is_empty() and not authored_action.requirements.is_empty():
		requirements = authored_action.requirements.duplicate()
	var methods: Array = []
	if authored_action != null and not authored_action.method_ids.is_empty():
		methods = authored_action.method_ids.duplicate()
	elif verb_id == VERB_FORCE:
		methods = ["crowbar"]
	elif verb_id == VERB_OPEN or verb_id == VERB_INSPECT or verb_id == VERB_SLEEP:
		methods = ["hands"]
	elif target.has_component("repairable"):
		methods = target.component("repairable").get("methods", [])
	elif target.has_component("dismantlable"):
		methods = target.component("dismantlable").get("methods", [])
	if methods.is_empty():
		methods = requirements.duplicate()
	for method in methods:
		affordance.method_ids.append(str(method))
	if not requirements.is_empty():
		affordance.requirements["capabilities"] = requirements.duplicate()
	return affordance


static func _definition_allows(
	target: WorldObjectRecord,
	verb_id: String,
	interaction_catalog: WorldInteractionCatalog = null
) -> bool:
	if target == null:
		return false
	var catalog := interaction_catalog if interaction_catalog != null else DEFAULT_INTERACTION_CATALOG
	var definition := catalog.object_for_id(target.definition_id)
	if definition == null or definition.affordance_ids.is_empty():
		return true
	return definition.affordance_ids.has(verb_id)


static func _requirements_met(requirements: Dictionary, actor_context: Dictionary) -> bool:
	var capabilities: Array = actor_context.get("capabilities", [])
	for required in requirements.get("capabilities", []):
		if not capabilities.has(required):
			return false
	return true
