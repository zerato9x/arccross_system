extends SceneTree

const DUEL_SCENE := preload("res://CombatCore/MainDuelScene.tscn")
const PLAYER_DEFINITION := preload("res://BiologicalCore/player_def.tres")
const ENEMY_DEFINITION := preload("res://BiologicalCore/scavenger_def.tres")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var arena = DUEL_SCENE.instantiate()
	root.add_child(arena)
	await process_frame

	var player: HumanoidCore = arena._fabricate_humanoid(
		"Position_Player",
		PLAYER_DEFINITION,
		false
	)
	arena.setup_duel(player, {
		"entity_id": "position_invariant_enemy",
		"definition": ENEMY_DEFINITION.to_state(),
		"runtime": {},
	})
	await process_frame

	var lanes: CombatLaneManager = arena.lane_manager
	var enemy: HumanoidCore = arena.enemy_core
	var enemy_ai: CombatAIEvaluator = enemy.get_node("CombatAIEvaluator")
	enemy_ai.target_core = player

	# Establish the enemy's facing while the combatants occupy separate lanes.
	if enemy_ai._direction_toward_target() != -1:
		_fail("Enemy facing did not point toward the player before melee contact.")
		return

	# Direct movement may enter the opposing lane, but may never pass beyond it.
	if lanes.move_entity(player, 2, 10):
		_fail("A combatant crossed through an opponent in the lane.")
		return
	if lanes._find_entity_lane(player) != 2 or lanes._find_entity_lane(enemy) != 9:
		_fail("Rejected crossing movement changed a combatant's lane.")
		return

	if not lanes.move_entity(player, 2, 9):
		_fail("A combatant could not enter the opponent's lane to form melee lock.")
		return
	if not lanes.lane_slots[9].is_melee_locked:
		_fail("Entering an opponent's lane did not form melee lock.")
		return

	# The AI must retain the pre-contact facing. Equal lane indices must not make
	# it disengage through the player to the opposite side of the battlefield.
	if enemy_ai._direction_toward_target() != -1:
		_fail("Enemy lost its facing direction when melee lock began.")
		return
	if lanes.move_entity(enemy, 9, 8):
		_fail("Ordinary movement escaped a melee lock without DISENGAGE.")
		return

	seed(20260619)
	var disengaged := false
	for _attempt in range(24):
		if lanes.attempt_disengage(enemy, 9, 10):
			disengaged = true
			break
	if not disengaged:
		_fail("Could not exercise a successful AI disengage for the position test.")
		return
	if lanes._find_entity_lane(enemy) != 10 or lanes._find_entity_lane(player) != 9:
		_fail("Enemy disengaged onto the player's side instead of its own side.")
		return
	if lanes.move_entity(enemy, 10, 8):
		_fail("A later movement crossed back through the player.")
		return

	# PUSH / FOLLOW and PULL / FOLLOW relocate the pair together; neither
	# action is allowed to leave one combatant on the far side of the other.
	lanes.remove_entity(player)
	lanes.remove_entity(enemy)
	lanes.force_spawn_entity(player, 6)
	lanes.force_spawn_entity(enemy, 6)
	lanes.resolve_displacement(player, enemy, 1, true, "PUSH")
	if lanes._find_entity_lane(player) != 7 or lanes._find_entity_lane(enemy) != 7:
		_fail("PUSH / FOLLOW did not keep both combatants together.")
		return
	lanes.resolve_displacement(player, enemy, -1, true, "PULL")
	if lanes._find_entity_lane(player) != 6 or lanes._find_entity_lane(enemy) != 6:
		_fail("PULL / FOLLOW did not keep both combatants together.")
		return

	arena.turn_manager.halt_loop()
	arena.queue_free()
	await process_frame
	print("[TEST PASS] Combat lane movement preserves facing and never crosses opponents.")
	quit(0)

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
