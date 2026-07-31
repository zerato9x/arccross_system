extends Node
class_name TacticalEncounterBuilder

@export var board: CombatBoard
@export var turn_manager: TacticalTurnManager


func build(
	player: HumanoidCore,
	enemy: HumanoidCore,
	encounter: CombatEncounterRecord
) -> void:
	if encounter == null:
		push_error("TacticalEncounterBuilder requires a CombatEncounterRecord.")
		return
	board.configure_from_encounter(encounter)
	var initiator: HumanoidCore
	if encounter.initiator_id == "player":
		initiator = player
	elif not encounter.initiator_id.is_empty():
		initiator = enemy
	var player_coords := Vector2i(0, 2)
	var enemy_coords := Vector2i(6, 2)
	match encounter.context:
		GameEnums.EncounterContext.PLAYER_AMBUSH:
			match encounter.ambush_position:
				GameEnums.AmbushPosition.FAR:
					player_coords.x = 0
				GameEnums.AmbushPosition.CLOSE:
					player_coords.x = 4
				_:
					player_coords.x = 3
		GameEnums.EncounterContext.ENEMY_AMBUSH:
			enemy_coords.x = 2
	var player_index := board.find_nearest_open_sector(CombatArenaState.index_for_coords(player_coords))
	var enemy_index := board.find_nearest_open_sector(CombatArenaState.index_for_coords(enemy_coords))
	if not board.force_spawn_actor(player, player_index, "player"):
		push_error("Could not deploy the player into the tactical arena.")
	if not board.force_spawn_actor(enemy, enemy_index, "enemy"):
		push_error("Could not deploy the enemy into the tactical arena.")
	turn_manager.initialize([player, enemy], initiator)
