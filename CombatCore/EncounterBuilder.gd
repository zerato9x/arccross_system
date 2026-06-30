extends Node
class_name EncounterBuilder

@export var lane_manager: CombatLaneManager
@export var turn_manager: CombatTurnManager

func build_encounter(
	player: HumanoidCore,
	enemy: HumanoidCore,
	setup: Dictionary = {}
) -> void:
	print("\n--- CONSTRUCTING ENCOUNTER ---")
	
	var initiator: HumanoidCore = null
	var context: GameEnums.EncounterContext = setup.get(
		"context",
		GameEnums.EncounterContext.NEUTRAL_MEET
	)
	var initiator_id: String = setup.get("initiator_id", "")
	if initiator_id == "player":
		initiator = player
	elif not initiator_id.is_empty():
		initiator = enemy
	
	# The mathematical grid bounds for where entities are allowed to spawn based on context
	var player_spawn_idx: int
	var enemy_spawn_idx: int

	match context:
		GameEnums.EncounterContext.NEUTRAL_MEET:
			player_spawn_idx = 2
			enemy_spawn_idx = 9
			
		GameEnums.EncounterContext.PLAYER_AMBUSH:
			var ambush_position: GameEnums.AmbushPosition = setup.get(
				"ambush_position",
				GameEnums.AmbushPosition.STANDARD
			)
			match ambush_position:
				GameEnums.AmbushPosition.FAR:
					player_spawn_idx = 1
				GameEnums.AmbushPosition.CLOSE:
					player_spawn_idx = 4
				_:
					player_spawn_idx = 3
			enemy_spawn_idx = 7
			print("Context: Player initiated an Ambush.")
			
		GameEnums.EncounterContext.ENEMY_AMBUSH:
			player_spawn_idx = 1
			enemy_spawn_idx = 5
			print("Context: Enemy initiated an Ambush.")
			
		GameEnums.EncounterContext.DIALOGUE_BREAKDOWN:
			player_spawn_idx = 2
			enemy_spawn_idx = 9
			print("Context: Negotiations failed. Ordinary deployment.")

	var trap_context: Dictionary = setup.get("trap_context", {})
	if not trap_context.is_empty() and lane_manager:
		var lane_index := int(trap_context.get("lane_index", 2))
		lane_manager.place_trap(
			lane_index,
			str(trap_context.get("trap_item_id", "trap_makeshift")),
			float(trap_context.get("trap_damage", 2.5))
		)
		print(
			"Context: Macro trap armed on lane ",
			lane_index,
			" (",
			trap_context.get("trap_item_id", ""),
			")."
		)

	# 1. Place the bodies in the mud
	lane_manager.force_spawn_entity(player, player_spawn_idx)
	lane_manager.force_spawn_entity(enemy, enemy_spawn_idx)
	
	# 2. Wire the lane reference into the turn manager for ActionGroup validation
	turn_manager.lane_manager = lane_manager
	
	# 3. Start the clock and pass the initiative advantage
	turn_manager.initialize_duel([player, enemy], initiator)
