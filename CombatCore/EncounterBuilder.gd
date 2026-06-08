extends Node
class_name EncounterBuilder

@export var lane_manager: CombatLaneManager
@export var turn_manager: CombatTurnManager

func build_encounter(player: HumanoidCore, enemy: HumanoidCore, context: GameEnums.EncounterContext) -> void:
	print("\n--- CONSTRUCTING ENCOUNTER ---")
	
	var initiator: HumanoidCore = null
	
	# The mathematical grid bounds for where entities are allowed to spawn based on context
	var player_spawn_idx: int
	var enemy_spawn_idx: int

	match context:
		GameEnums.EncounterContext.NEUTRAL_MEET:
			player_spawn_idx = 2
			enemy_spawn_idx = 9
			# initiator = null (The clock will roll for dexterity)
			
		GameEnums.EncounterContext.PLAYER_AMBUSH:
			# Player starts practically on top of the enemy, Enemy is pushed back
			player_spawn_idx = 4
			enemy_spawn_idx = 7
			initiator = player
			print("Context: Player initiated an Ambush.")
			
		GameEnums.EncounterContext.ENEMY_AMBUSH:
			# Player is caught near their escape grid, Enemy is aggressively pushed up
			player_spawn_idx = 1
			enemy_spawn_idx = 5 # Right on the edge of the void
			initiator = enemy
			print("Context: Enemy initiated an Ambush.")
			
		GameEnums.EncounterContext.DIALOGUE_BREAKDOWN:
			# A mugging gone wrong. They are literally one step away from a Melee Lock.
			player_spawn_idx = 4
			enemy_spawn_idx = 7
			# initiator = whoever failed the speech check (You pass this logic later)
			print("Context: Negotiations failed. Close quarters combat.")

	# 1. Place the bodies in the mud
	lane_manager.force_spawn_entity(player, player_spawn_idx)
	lane_manager.force_spawn_entity(enemy, enemy_spawn_idx)
	
	# 2. Wire the lane reference into the turn manager for ActionGroup validation
	turn_manager.lane_manager = lane_manager
	
	# 3. Start the clock and pass the initiative advantage
	turn_manager.initialize_duel([player, enemy], initiator)
