extends Node
class_name RealtimeEncounterBuilder

@export var lane_manager: CombatLaneManager

func build_encounter(
	player: HumanoidCore,
	enemy: HumanoidCore,
	setup: Dictionary = {}
) -> void:
	if lane_manager == null:
		push_error("RealtimeEncounterBuilder requires a lane manager.")
		return
	lane_manager.configure_duel_territories()
	player.set_meta("duel_side", "player")
	enemy.set_meta("duel_side", "enemy")

	var context: GameEnums.EncounterContext = setup.get(
		"context",
		GameEnums.EncounterContext.NEUTRAL_MEET
	)
	var player_spawn := 2
	var enemy_spawn := 9
	match context:
		GameEnums.EncounterContext.PLAYER_AMBUSH:
			match setup.get("ambush_position", GameEnums.AmbushPosition.STANDARD):
				GameEnums.AmbushPosition.FAR:
					player_spawn = 1
				GameEnums.AmbushPosition.CLOSE:
					player_spawn = 4
				_:
					player_spawn = 3
			enemy_spawn = 7
		GameEnums.EncounterContext.ENEMY_AMBUSH:
			player_spawn = 1
			enemy_spawn = 5
		_:
			pass

	_place_setup_traps(setup)
	lane_manager.force_spawn_entity(player, player_spawn)
	lane_manager.force_spawn_entity(enemy, enemy_spawn)

func _place_setup_traps(setup: Dictionary) -> void:
	var traps: Array = setup.get("traps", [])
	if traps.is_empty() and setup.has("trap_context"):
		var legacy: Dictionary = setup.get("trap_context", {})
		if not legacy.is_empty():
			traps = [{
				"lane_index": int(legacy.get("lane_index", 2)),
				"trap_item_id": str(legacy.get("trap_item_id", "trap_makeshift")),
				"trap_damage": float(legacy.get("trap_damage", 2.5)),
				"owner_side": str(legacy.get("owner_side", "player")),
			}]
	for raw_trap in traps:
		if not raw_trap is Dictionary:
			continue
		var trap: Dictionary = raw_trap
		var lane_index := int(trap.get("lane_index", -1))
		var owner_side := str(trap.get("owner_side", "player"))
		if lane_index < 0 or lane_index >= lane_manager.lane_slots.size():
			continue
		if owner_side not in ["player", "enemy"]:
			push_warning("Rejected trap with invalid owner side: %s" % owner_side)
			continue
		lane_manager.place_trap(
			lane_index,
			str(trap.get("trap_item_id", "trap_makeshift")),
			float(trap.get("trap_damage", 2.5)),
			owner_side
		)
