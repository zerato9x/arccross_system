extends Node
class_name TacticalEncounterBuilder

@export var board: CombatBoard
@export var turn_manager: TacticalTurnManager


func build(actors: Array[HumanoidCore], encounter: CombatEncounterRecord) -> void:
	if encounter == null:
		push_error("TacticalEncounterBuilder requires a CombatEncounterRecord.")
		return
	board.configure_from_encounter(encounter)
	var initiator: HumanoidCore
	var profile := CombatTopologyProfile.load_profile(encounter.topology_id)
	var player_slot := 0
	var enemy_slot := 0
	for actor in actors:
		if actor == null:
			continue
		var actor_id := str(actor.get_meta("actor_id", actor.name))
		var side := str(actor.get_meta("combat_side", "enemy"))
		if actor_id == encounter.initiator_id or (encounter.initiator_id == "player" and side == "player"):
			initiator = actor
		var deployment := profile.player_deployment if side == "player" else profile.enemy_deployment
		var slot := player_slot if side == "player" else enemy_slot
		if side == "player":
			player_slot += 1
		else:
			enemy_slot += 1
		if deployment.is_empty():
			push_error("Combat topology %s has no %s deployment cells." % [profile.topology_id, side])
			continue
		var preferred := deployment[mini(slot, deployment.size() - 1)]
		if profile.movement_policy == CombatTopologyProfile.MovementPolicy.LINEAR_NO_PASS:
			preferred = _linear_ambush_position(preferred, side, encounter, profile)
		var index := board.find_nearest_open_sector(board.arena_state.index_for(preferred))
		if not board.force_spawn_actor(actor, index, side):
			push_error("Could not deploy %s into %s." % [actor_id, profile.topology_id])
	turn_manager.initialize(actors, initiator)


func _linear_ambush_position(
	preferred: Vector2i,
	side: String,
	encounter: CombatEncounterRecord,
	profile: CombatTopologyProfile
) -> Vector2i:
	var result := preferred
	if encounter.context == GameEnums.EncounterContext.PLAYER_AMBUSH and side == "player":
		match encounter.ambush_position:
			GameEnums.AmbushPosition.CLOSE:
				result.x = maxi(0, profile.columns - 4)
			GameEnums.AmbushPosition.STANDARD:
				result.x = profile.columns / 3
	elif encounter.context == GameEnums.EncounterContext.ENEMY_AMBUSH and side == "enemy":
		result.x = mini(profile.columns - 1, 3)
	return result
