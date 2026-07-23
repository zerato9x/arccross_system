extends SceneTree

const DUEL_SCENE := preload("res://CombatCore/TurnBased/TurnBasedDuelScene.tscn")
const PLAYER_DEFINITION := preload("res://BiologicalCore/player_def.tres")
const ENEMY_DEFINITION := preload("res://BiologicalCore/scavenger_def.tres")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var arena := DUEL_SCENE.instantiate()
	root.add_child(arena)
	await process_frame

	var player: HumanoidCore = arena._fabricate_humanoid(
		"Fumble_Player",
		PLAYER_DEFINITION,
		false
	)
	arena.setup_duel(player, {
		"entity_id": "fumble_enemy",
		"definition": ENEMY_DEFINITION.to_state(),
		"runtime": {},
	})
	arena.turn_manager.halt_loop()

	var lanes: CombatLaneManager = arena.lane_manager
	var enemy: HumanoidCore = arena.enemy_core
	lanes.remove_entity(player)
	lanes.remove_entity(enemy)
	lanes.force_spawn_entity(player, 6)
	lanes.force_spawn_entity(enemy, 6)

	# A blown Grapple is the new risky lock commitment; Break Away is gone.
	player.definition.brawn = 3
	player.definition.finesse = 3
	enemy.definition.brawn = 9
	enemy.definition.finesse = 9
	var stance_before := player.stance_points
	if arena.resolution_engine.execute_grapple(player, enemy, 1, 12):
		_fail("Forced failed Grapple unexpectedly succeeded.")
		return
	if player.stance_points >= stance_before:
		_fail("Failed Grapple did not trigger a Fumble Strike payoff.")
		return

	arena.queue_free()
	await process_frame
	print("[TEST PASS] Failed Grapple triggers one Fumble Strike.")
	quit(0)

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
