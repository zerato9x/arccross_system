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
		var participant_context: Dictionary = _participant_context(actor_id, encounter)
		var entry_direction := int(participant_context.get("relative_entry_direction", GameEnums.MacroTravelDirection.NONE))
		if preferred == Vector2i(-1, -1) or not profile.contains(preferred):
			var directional := _directional_deployment(profile, side, entry_direction, deployment)
			preferred = directional[mini(slot, directional.size() - 1)] if not directional.is_empty() else deployment[mini(slot, deployment.size() - 1)]
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
	## Missing pairs are neutral unless the participant data explicitly commits
	## them. Team/faction names are not permission to manufacture hostility.
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
			var relation := CombatRelationshipLedger.Relation.NEUTRAL
			var left_context: Dictionary = left.get_meta("participant_context", {})
			var right_context: Dictionary = right.get_meta("participant_context", {})
			var left_squad := str(left_context.get("squad_id", left.get_meta("combat_team_id", "")))
			var right_squad := str(right_context.get("squad_id", right.get_meta("combat_team_id", "")))
			if not left_squad.is_empty() and left_squad == right_squad:
				relation = CombatRelationshipLedger.Relation.FRIENDLY
			board.set_relation(left, right, relation)


func _participant_context(actor_id: String, encounter: CombatEncounterRecord) -> Dictionary:
	if encounter == null:
		return {}
	for record in encounter.actors:
		if str(record.get("actor_id", "")) == actor_id:
			return record.get("participant_context", {}).duplicate(true)
	return {}


func _directional_deployment(
	profile: CombatTopologyProfile,
	_side: String,
	entry_direction: int,
	base: Array[Vector2i]
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var edge := ""
	match entry_direction:
		GameEnums.MacroTravelDirection.EAST, GameEnums.MacroTravelDirection.NORTHEAST, GameEnums.MacroTravelDirection.SOUTHEAST:
			edge = "east"
		GameEnums.MacroTravelDirection.WEST, GameEnums.MacroTravelDirection.NORTHWEST, GameEnums.MacroTravelDirection.SOUTHWEST:
			edge = "west"
		GameEnums.MacroTravelDirection.NORTH:
			edge = "north"
		GameEnums.MacroTravelDirection.SOUTH:
			edge = "south"
		_:
			return base.duplicate()
	for y in range(profile.rows):
		for x in range(profile.columns):
			var coords := Vector2i(x, y)
			var on_edge := (edge == "west" and x == 0) or (edge == "east" and x == profile.columns - 1) or (edge == "north" and y == 0) or (edge == "south" and y == profile.rows - 1)
			if on_edge and profile.contains(coords):
				result.append(coords)
	if result.is_empty():
		return base.duplicate()
	result.sort_custom(func(left, right):
		if left.y != right.y:
			return left.y < right.y
		return left.x < right.x
	)
	return result


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
				result.x = floori(float(profile.columns) / 3.0)
	elif encounter.context == GameEnums.EncounterContext.ENEMY_AMBUSH and side == "enemy":
		result.x = mini(profile.columns - 1, 3)
	return result
