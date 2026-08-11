extends SceneTree

const WORLD_WORK_CATALOG_PATH := "res://WorldCore/world_work_tasks.tres"
const WORLD_INTERACTION_CATALOG_PATH := "res://SystemCore/world_interactions.tres"
const TIME_PROFILE_PATH := "res://SystemCore/default_time_rules.tres"
const CONDITION_PROFILE_PATH := "res://ItemCore/default_item_condition_profile.tres"
const NPC_PROFILE_PATH := "res://WorldCore/npc_behavior_profiles.tres"
const TOPOLOGY_CATALOG_PATH := "res://CombatCore/Tactical/default_combat_topology_catalog.tres"
const ZONE_PROFILE_CATALOG_PATH := "res://WorldCore/GenerationV2/starter_zone_profiles.tres"
const SHELTER_PROFILE_PATH := "res://WorldCore/default_shelter_progression_profile.tres"
const REQUIRED_PROFILES := [
	"repair_manual",
	"salvage_manual",
	"search_manual",
	"force_manual",
	"trap_manual",
]
const REQUIRED_METHODS := ["hands", "crowbar", "multitool"]


func _init() -> void:
	var catalog := load(WORLD_WORK_CATALOG_PATH) as WorldWorkTaskCatalog
	if catalog == null:
		_fail("World work catalog failed to load.")
		return
	var profile_ids := catalog.profile_ids()
	var method_ids := catalog.method_ids()
	for profile_id in REQUIRED_PROFILES:
		if not profile_ids.has(profile_id):
			_fail("World work catalog is missing profile '%s'." % profile_id)
			return
	for method_id in REQUIRED_METHODS:
		if not method_ids.has(method_id):
			_fail("World work catalog is missing method '%s'." % method_id)
			return
	if profile_ids.size() != catalog.profiles.size():
		_fail("World work profile IDs must be unique.")
		return
	if method_ids.size() != catalog.methods.size():
		_fail("World work method IDs must be unique.")
		return
	var interaction_catalog := load(WORLD_INTERACTION_CATALOG_PATH) as WorldInteractionCatalog
	if interaction_catalog == null or not interaction_catalog.validate_ids().is_empty():
		_fail("World interaction action IDs are invalid.")
		return
	if not interaction_catalog.validate_object_ids().is_empty():
		_fail("World interaction object IDs are invalid.")
		return
	if not interaction_catalog.validate_references().is_empty():
		_fail("World interaction object references are invalid.")
		return
	var time_profile := load(TIME_PROFILE_PATH) as TimeRulesProfile
	if time_profile == null:
		_fail("Time rules profile failed to load.")
		return
	if time_profile.minutes_for("search", 0) <= 0 or time_profile.camp_minutes <= 0:
		_fail("Time rules profile is missing authored search/camp durations.")
		return
	var condition_profile := load(CONDITION_PROFILE_PATH) as ItemConditionProfile
	if condition_profile == null:
		_fail("Item condition profile failed to load.")
		return
	if condition_profile.repair_recipe(GameEnums.RepairDomain.FIREARM).is_empty():
		_fail("Item condition profile is missing the firearm repair recipe.")
		return
	var shelter_profile := load(SHELTER_PROFILE_PATH) as ShelterProgressionProfile
	if shelter_profile == null or shelter_profile.stages.size() < 4:
		_fail("Shelter progression profile is missing authored service stages.")
		return
	var npc_catalog := load(NPC_PROFILE_PATH) as NpcBehaviorProfileCatalog
	if npc_catalog == null or npc_catalog.profile_ids().is_empty():
		_fail("NPC behavior catalog failed to load.")
		return
	var topology_catalog := load(TOPOLOGY_CATALOG_PATH) as CombatTopologyCatalog
	if topology_catalog == null or topology_catalog.profile_for_id("duel_12x1") == null:
		_fail("Combat topology catalog failed to load.")
		return
	var zone_catalog := load(ZONE_PROFILE_CATALOG_PATH) as ZoneGenerationProfileCatalog
	if zone_catalog == null or not zone_catalog.validate_ids().is_empty():
		_fail("Starter zone profile catalog failed validation.")
		return
	for arm_key in ["north", "east", "south", "west"]:
		var profile := zone_catalog.profile_for_arm(arm_key, false)
		if profile == null:
			_fail("Starter zone profile catalog is missing %s." % arm_key)
			return
		if profile.terrain_asset_ids.size() != 54:
			_fail("Starter zone profile %s must author all 54 terrain asset IDs." % arm_key)
			return
	print("[PASS] Resource catalogs loaded with unique stable IDs.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
