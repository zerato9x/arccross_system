extends Node
class_name TacticalEncounterBuilder

@export var board: CombatBoard
@export var turn_manager: TacticalTurnManager


func build(actors: Array[HumanoidCore], encounter: CombatEncounterRecord) -> void:
	if encounter == null:
		push_error("TacticalEncounterBuilder requires a CombatEncounterRecord.")
		return
	board.configure_from_encounter(encounter)
	turn_manager.balance_profile = board.balance_profile
	board.configure_communication_points(actors, encounter)
	_apply_default_relations(actors)
	var initiator: HumanoidCore
	var profile := CombatTopologyCatalog.load_profile(encounter.topology_id)
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
		var preferred := _authored_start_sector(actor_id, encounter)
		if preferred == Vector2i(-1, -1) or not profile.contains(preferred):
			preferred = deployment[mini(slot, deployment.size() - 1)]
			if profile.movement_policy == CombatTopologyProfile.MovementPolicy.LINEAR_NO_PASS:
				preferred = _linear_ambush_position(preferred, side, encounter, profile)
		var preferred_index := board.arena_state.index_for(preferred) if board.arena_state.contains(preferred) else -1
		var shared_hostile := false
		if preferred_index >= 0 and board.actor_at(preferred_index) != null:
			shared_hostile = board.is_hostile(actor, board.actor_at(preferred_index))
		var index := board.find_nearest_open_sector(preferred_index, actor, shared_hostile)
		if index < 0:
			# An authored shared sector is only legal for a hostile Engagement. If
			# the lane is full or friendly stacking is requested, find the next
			# legal deployment cell instead of silently overfilling the board.
			index = board.find_nearest_open_sector(preferred_index)
		if not board.force_spawn_actor(actor, index, side, shared_hostile):
			push_error("Could not deploy %s into %s." % [actor_id, profile.topology_id])
	var encounter_seed := encounter.combat_seed
	if encounter_seed == 0 and not encounter.world_seed.is_empty():
		encounter_seed = abs(hash(encounter.world_seed))
	turn_manager.initialize(actors, initiator, encounter_seed)


func _apply_default_relations(actors: Array[HumanoidCore]) -> void:
	## Team IDs are only an encounter-construction default. Explicit authored
	## relationship_state entries always win through CombatBoard's ledger.
	for left_index in range(actors.size()):
		var left := actors[left_index]
		if left == null:
			continue
		for right_index in range(left_index + 1, actors.size()):
			var right := actors[right_index]
			if right == null:
				continue
			var key := CombatRelationshipLedger.pair_key(
				str(left.get_meta("actor_id", left.name)),
				str(right.get_meta("actor_id", right.name))
			)
			if board.relationship_ledger.relation_by_pair.has(key):
				continue
			var left_team := str(left.get_meta("combat_team_id", left.get_meta("combat_side", "")))
			var right_team := str(right.get_meta("combat_team_id", right.get_meta("combat_side", "")))
			var relation := CombatRelationshipLedger.Relation.FRIENDLY if left_team == right_team else CombatRelationshipLedger.Relation.HOSTILE
			board.set_relation(left, right, relation)


func _authored_start_sector(actor_id: String, encounter: CombatEncounterRecord) -> Vector2i:
	if encounter == null or actor_id.is_empty():
		return Vector2i(-1, -1)
	var raw: Variant = encounter.actor_starting_sectors.get(actor_id, null)
	if raw == null:
		for record in encounter.actors:
			if str(record.get("actor_id", "")) == actor_id:
				raw = record.get("starting_sector", record.get("start_sector", record.get("start_coords", null)))
				break
	if raw is Vector2i:
		return raw
	if raw is Vector2:
		return Vector2i(roundi(raw.x), roundi(raw.y))
	if raw is Dictionary:
		return Vector2i(int(raw.get("x", -1)), int(raw.get("y", -1)))
	return Vector2i(-1, -1)


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
