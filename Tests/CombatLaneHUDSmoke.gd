extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var holder := Node.new()
	root.add_child(holder)

	var duel_scene := load("res://CombatCore/MainDuelScene.tscn") as PackedScene
	if not duel_scene:
		_fail("Could not load the combat scene.")
		return
	var arena = duel_scene.instantiate()
	holder.add_child(arena)
	await process_frame

	if arena.get_node_or_null("DebugUI") != null:
		_fail("The retired combat DebugUI still exists.")
		return

	var player_definition := load(
		"res://BiologicalCore/player_def.tres"
	) as EntityDefinition
	var enemy_definition := load(
		"res://BiologicalCore/scavenger_def.tres"
	) as EntityDefinition
	var player: HumanoidCore = arena._fabricate_humanoid(
		"HUD_Player",
		player_definition,
		false
	)
	player.stance_points = 0
	player._evaluate_stance_state()
	player.is_escaping = true
	arena.setup_duel(
		player,
		{
			"entity_id": "hud_smoke_enemy",
			"definition": enemy_definition.to_state(),
			"runtime": {},
		}
	)
	await process_frame

	if (
		player.current_stance != GameEnums.StanceState.PLANTED
		or player.stance_points != int(GameEnums.SCALE_MAX)
		or player.is_escaping
	):
		_fail("Encounter setup did not clear tactical state from prior combat.")
		return

	var snapshot: Dictionary = arena.command_adapter.get_snapshot()
	var lane_slots: Array = snapshot.get("lane_slots", [])
	if lane_slots.size() != 12:
		_fail("Combat snapshot did not expose exactly twelve lane slots.")
		return
	if not _slot_has_side(lane_slots[2], "player"):
		_fail("Neutral deployment did not project the player in slot 2.")
		return
	if not _slot_has_side(lane_slots[9], "enemy"):
		_fail("Neutral deployment did not project the enemy in slot 9.")
		return

	var hud_snapshot: Dictionary = arena.lane_hud.get_snapshot()
	if hud_snapshot.get("lane_slots", []).size() != 12:
		_fail("CombatLaneHUD did not receive the twelve-slot snapshot.")
		return
	if hud_snapshot.get("player", {}).get("limbs", []).size() != 7:
		_fail("CombatLaneHUD did not receive all seven Limb Regions.")
		return
	if not arena.lane_hud._player_label.text.contains("CORE HD"):
		_fail("CombatLaneHUD did not render the limb structure readout.")
		return
	if arena.lane_hud.is_showing_melee_lock():
		_fail("The lane HUD entered lock mode before combatants shared a slot.")
		return

	var enemy_lane: int = arena.lane_manager._find_entity_lane(arena.enemy_core)
	arena.lane_manager.remove_entity(player)
	arena.lane_manager.force_spawn_entity(player, enemy_lane)
	await process_frame

	if not arena.lane_hud.is_showing_melee_lock():
		_fail("The lane HUD did not switch to the melee-lock overlay.")
		return
	var lock_snapshot: Dictionary = arena.lane_hud.get_snapshot()
	var lock_slot: Dictionary = lock_snapshot.get("lane_slots", [])[enemy_lane]
	if (
		not lock_slot.get("is_melee_locked", false)
		or lock_slot.get("occupants", []).size() != 2
	):
		_fail("The melee-lock projection did not preserve shared occupancy.")
		return

	snapshot = arena.command_adapter.get_snapshot()
	var strike_descriptor := _find_action(
		snapshot,
		GameEnums.ActionType.STRIKE
	)
	if strike_descriptor.is_empty():
		_fail("STRIKE was unavailable in a valid Melee Lock.")
		return
	if not strike_descriptor.get("target_limbs", []).is_empty():
		_fail("STRIKE still exposed manual limb targeting.")
		return
	if not _snapshot_has_action(snapshot, GameEnums.ActionType.PULL_FOLLOW):
		_fail("PULL / FOLLOW was unavailable in a valid Melee Lock.")
		return

	for _sample in range(120):
		var hit_region: GameEnums.LimbRegion = (
			arena.resolution_engine.roll_melee_target()
		)
		if hit_region == GameEnums.LimbRegion.HEAD:
			_fail("Random melee targeting selected the Head.")
			return

	player.definition.brawn = 6
	player.definition.finesse = 6
	arena.enemy_core.definition.brawn = 6
	arena.enemy_core.definition.finesse = 6
	player.reset_stance()
	arena.enemy_core.reset_stance()
	var losing_grapple: bool = arena.resolution_engine.execute_grapple(
		player,
		arena.enemy_core,
		1,
		12
	)
	if losing_grapple:
		_fail("A clearly losing opposed Grapple check succeeded.")
		return
	if arena.enemy_core.current_stance == GameEnums.StanceState.FELLED:
		_fail("A failed Grapple felled the defender.")
		return

	player.reset_stance()
	arena.enemy_core.reset_stance()
	var winning_grapple: bool = arena.resolution_engine.execute_grapple(
		player,
		arena.enemy_core,
		12,
		1
	)
	if not winning_grapple:
		_fail("A clearly winning opposed Grapple check failed.")
		return
	if (
		arena.enemy_core.current_stance != GameEnums.StanceState.FELLED
		or player.current_stance == GameEnums.StanceState.FELLED
	):
		_fail("Grapple success did not fell only the defender.")
		return

	arena.command_adapter.refresh_snapshot()
	snapshot = arena.command_adapter.get_snapshot()
	if _snapshot_has_action(snapshot, GameEnums.ActionType.EXECUTE):
		_fail("The disabled EXECUTE action appeared after a Grapple.")
		return
	var ap_before: int = arena.turn_manager.current_ap_pool
	if arena.turn_manager.request_action(player, GameEnums.ActionType.EXECUTE):
		_fail("The turn manager accepted disabled EXECUTE.")
		return
	if arena.turn_manager.current_ap_pool != ap_before:
		_fail("Rejected EXECUTE still consumed AP.")
		return

	player.reset_stance()
	arena.enemy_core.reset_stance()
	var pull_succeeded: bool = (
		arena.resolution_engine.execute_leverage_check(
			player,
			arena.enemy_core,
			false,
			12,
			1
		)
	)
	if not pull_succeeded:
		_fail("The deterministic Pull leverage check failed.")
		return
	arena.lane_manager.resolve_displacement(
		player,
		arena.enemy_core,
		-1,
		true,
		"PULL"
	)
	if (
		arena.lane_manager._find_entity_lane(player) != enemy_lane - 1
		or arena.lane_manager._find_entity_lane(arena.enemy_core)
		!= enemy_lane - 1
	):
		_fail("PULL / FOLLOW did not move both locked combatants rearward.")
		return

	arena.turn_manager.halt_loop()
	holder.queue_free()
	await process_frame
	print(
		"[TEST PASS] Combat HUD, encounter transients, melee targeting, "
		+ "Grapple, Execute gating, and Pull / Follow obey the demo rules."
	)
	quit(0)

func _slot_has_side(slot: Dictionary, side: String) -> bool:
	for occupant in slot.get("occupants", []):
		if occupant.get("side", "") == side:
			return true
	return false

func _snapshot_has_action(snapshot: Dictionary, action: int) -> bool:
	return not _find_action(snapshot, action).is_empty()

func _find_action(snapshot: Dictionary, action: int) -> Dictionary:
	for descriptor in snapshot.get("actions", []):
		if descriptor.get("action", -1) == action:
			return descriptor
	return {}

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
