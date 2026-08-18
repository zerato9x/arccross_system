extends RefCounted
class_name MacroShelterRuntimeService

## Applies the pure shelter transition kernel to the detached world-object
## record, then persists the resulting run/meta projections. The manager keeps
## compatibility wrappers because combat and interaction callers already use
## the public shelter hooks.

const _NpcSimulator := preload("res://WorldCore/MacroNpcSimulator.gd")
const _ProgressionService := preload(
	"res://WorldCore/MacroShelterProgressionService.gd"
)

var world_state: RuntimeStateStore
var world_generator: HexWorldGenerator
var meta_progress: Node
var profile: ShelterProgressionProfile
var progression: MacroShelterProgressionService


func configure(
	state: RuntimeStateStore,
	generator: HexWorldGenerator,
	meta: Node,
	shelter_profile: ShelterProgressionProfile
) -> void:
	world_state = state
	world_generator = generator
	meta_progress = meta
	profile = shelter_profile
	progression = _ProgressionService.new(profile)


func apply_repair(
	campaign: MacroProgressController,
	coords: Vector2i,
	target_id: String,
	receipt: WorldActionReceipt
) -> void:
	if receipt == null or not receipt.work_completed:
		return
	if world_state == null or world_generator == null or progression == null:
		return
	var hex := world_generator.get_hex_at(coords)
	for index in range(hex.world_objects.size()):
		var object_value := hex.world_objects[index]
		if not object_value is Dictionary:
			continue
		if str(object_value.get("object_id", "")) != target_id:
			continue
		var target := WorldObjectRecord.from_dict(object_value)
		if not target.has_component("shelter"):
			return
		var transition := progression.apply_repair(
			target,
			_shelter_hostile_present(coords)
		)
		if transition.is_empty():
			return
		var next_state := str(transition.get("state", "ruined"))
		var service_stage := int(transition.get("service_stage", 0))
		target.last_simulated_minute = world_state.world_time_minutes
		target.revision += 1
		hex.world_objects[index] = target.to_dict()
		world_generator.commit_hex_projection(coords, hex)
		_persist_transition(campaign, next_state, service_stage)
		return


func preserve_after_player_defeat(campaign: MacroProgressController) -> void:
	## Death consumes the run, not work already committed to the permanent node.
	if not _is_active_shelter(campaign) or world_state == null or world_generator == null:
		return
	var hex := world_generator.get_hex_at(Vector2i.ZERO)
	for index in range(hex.world_objects.size()):
		var object_value := hex.world_objects[index]
		if not object_value is Dictionary:
			continue
		var target := WorldObjectRecord.from_dict(object_value)
		if not target.has_component("shelter"):
			continue
		var before_state := str(target.component("shelter").get("state", "ruined"))
		var transition := progression.preserve_after_player_defeat(target)
		if transition.is_empty():
			return
		var state := str(transition.get("state", "ruined"))
		if state == before_state:
			return
		target.revision += 1
		var service_stage := int(transition.get("service_stage", 0))
		hex.world_objects[index] = target.to_dict()
		world_generator.commit_hex_projection(Vector2i.ZERO, hex)
		_persist_transition(campaign, state, service_stage)
		return


func reconcile_after_hostile_change(campaign: MacroProgressController) -> void:
	## Re-evaluate a fully repaired shelter after the final hostile leaves.
	if not _is_active_shelter(campaign) or world_state == null or world_generator == null:
		return
	var hex := world_generator.get_hex_at(Vector2i.ZERO)
	for index in range(hex.world_objects.size()):
		var object_value := hex.world_objects[index]
		if not object_value is Dictionary:
			continue
		var target := WorldObjectRecord.from_dict(object_value)
		if not target.has_component("shelter"):
			continue
		var transition := progression.reconcile_after_hostile_change(
			target,
			_shelter_hostile_present(Vector2i.ZERO)
		)
		if transition.is_empty():
			return
		target.last_simulated_minute = world_state.world_time_minutes
		target.revision += 1
		hex.world_objects[index] = target.to_dict()
		world_generator.commit_hex_projection(Vector2i.ZERO, hex)
		_persist_transition(
			campaign,
			str(transition.get("state", profile.secured_state)),
			int(transition.get("service_stage", 0))
		)
		return


func _is_active_shelter(campaign: MacroProgressController) -> bool:
	return (
		campaign != null
		and profile != null
		and campaign.active_node_id == profile.profile_id
	)


func _shelter_hostile_present(center_coords: Vector2i) -> bool:
	if world_state == null:
		return false
	for record in world_state.get_all_entity_snapshots():
		if int(record.get("life_state", GameEnums.EntityLifeState.DEAD)) != GameEnums.EntityLifeState.ALIVE:
			continue
		if int(record.get("world_status", -1)) != GameEnums.EntityWorldStatus.HOSTILE:
			continue
		if _NpcSimulator.hex_distance(record.get("coords", Vector2i.ZERO), center_coords) <= 3:
			return true
	return false


func _persist_transition(
	campaign: MacroProgressController,
	state: String,
	service_stage: int
) -> void:
	if meta_progress != null and meta_progress.has_method("set_shelter_state"):
		meta_progress.set_shelter_state(profile.profile_id, {
			"state": state,
			"service_stage": service_stage,
			"last_action_minute": world_state.world_time_minutes,
		}, true)
	if (
		campaign != null
		and campaign.active_node_id == profile.profile_id
		and meta_progress != null
		and meta_progress.has_method("capture_node_mutations")
	):
		meta_progress.capture_node_mutations(
			profile.profile_id,
			campaign.zone_generator.permanent_baseline_records,
			world_state.get_hex_records_snapshot()
		)
