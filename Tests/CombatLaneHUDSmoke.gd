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
	if not arena.lane_hud._player_label.text.contains("08/08 R06"):
		_fail("CombatLaneHUD did not render firearm rounds and range.")
		return
	if arena.lane_hud.is_showing_melee_lock():
		_fail("The lane HUD entered lock mode before combatants shared a slot.")
		return

	player.stance_points = 4
	player._evaluate_stance_state()
	var turn_probe := CombatTurnManager.new()
	holder.add_child(turn_probe)
	turn_probe.combatants = [player]
	turn_probe.active_entity_index = 0
	var turn_events: Array = []
	turn_probe.turn_started.connect(
		func(entity: HumanoidCore) -> void:
			turn_events.append(entity)
	)
	turn_probe._start_turn()
	if (
		turn_events.size() != 1
		or turn_events[0] != player
		or turn_probe.current_ap_pool != player.current_max_ap
		or player.current_stance != GameEnums.StanceState.STUMBLING
		or player.stance_points != 6
	):
		_fail("STUMBLING did not receive a normal AP turn with passive recovery.")
		return
	arena.command_adapter.refresh_snapshot()
	snapshot = arena.command_adapter.get_snapshot()
	if snapshot.get("actions", []).is_empty():
		_fail("A STUMBLING player received no legal combat actions.")
		return
	turn_probe.halt_loop()
	turn_probe.queue_free()

	player.reset_stance()
	player.apply_stance_damage(GameEnums.SCALE_MAX)
	if (
		player.current_stance != GameEnums.StanceState.STUMBLING
		or player.stance_points != 1
	):
		_fail("Ordinary stance damage directly FELLED a combatant.")
		return

	arena.resolution_engine.execute_break(arena.enemy_core, player)
	if player.current_stance != GameEnums.StanceState.FELLED:
		_fail("BREAK could not finish a combatant who was already STUMBLING.")
		return

	var ai_get_up_probe := CombatAIEvaluator.new()
	ai_get_up_probe.ai_core = player
	var ai_get_up_action: int = ai_get_up_probe._evaluate_tactics()
	ai_get_up_probe.free()
	if ai_get_up_action != GameEnums.ActionType.GET_UP:
		_fail("AI did not prioritize GET UP while FELLED.")
		return

	arena.command_adapter.refresh_snapshot()
	snapshot = arena.command_adapter.get_snapshot()
	var felled_actions: Array = snapshot.get("actions", [])
	if (
		felled_actions.size() != 1
		or not _snapshot_has_action(snapshot, GameEnums.ActionType.GET_UP)
		or snapshot.get("can_pass", true)
	):
		_fail("A FELLED player was not restricted to GET UP.")
		return

	var get_up_probe := CombatTurnManager.new()
	holder.add_child(get_up_probe)
	get_up_probe.combatants = [player]
	get_up_probe.active_entity_index = 0
	var get_up_turn_events: Array = []
	get_up_probe.turn_started.connect(
		func(entity: HumanoidCore) -> void:
			get_up_turn_events.append(entity)
	)
	get_up_probe._start_turn()
	if (
		get_up_turn_events.size() != 1
		or get_up_probe.current_ap_pool != player.current_max_ap
		or player.current_stance != GameEnums.StanceState.FELLED
	):
		_fail("A FELLED combatant did not receive an actionable GET UP turn.")
		return
	if not get_up_probe.request_action(player, GameEnums.ActionType.GET_UP):
		_fail("The turn manager rejected GET UP for a FELLED combatant.")
		return
	if not arena.resolution_engine.execute_get_up(player):
		_fail("GET UP did not restore the FELLED combatant.")
		return
	if (
		player.current_stance != GameEnums.StanceState.STUMBLING
		or player.stance_points != CombatRules.FELLED_RECOVERY_POINTS
		or not player.has_stance_recovery_guard
	):
		_fail("GET UP restored an invalid stance state.")
		return
	get_up_probe.halt_loop()
	get_up_probe.queue_free()

	player.expire_stance_recovery_guard()
	player.try_fell()
	player.begin_felled_recovery(CombatRules.FELLED_RECOVERY_POINTS)
	for _hit in range(4):
		player.apply_stance_damage(GameEnums.SCALE_MAX)
	if (
		player.current_stance != GameEnums.StanceState.STUMBLING
		or player.stance_points != 1
		or not player.has_stance_recovery_guard
	):
		_fail("Repeated pressure bypassed the post-Felled Recovery Guard.")
		return
	if player.try_fell():
		_fail("A forced knockdown bypassed the post-Felled Recovery Guard.")
		return
	arena.command_adapter.refresh_snapshot()
	snapshot = arena.command_adapter.get_snapshot()
	if not snapshot.get("player", {}).get(
		"stance_recovery_guard",
		false
	):
		_fail("The combat snapshot did not expose the Recovery Guard.")
		return
	player.recover_stance(CombatRules.STUMBLING_TURN_RECOVERY)
	player.expire_stance_recovery_guard()
	player.apply_stance_damage(GameEnums.SCALE_MAX)
	if (
		player.current_stance != GameEnums.StanceState.STUMBLING
		or player.stance_points != 1
	):
		_fail("Ordinary pressure bypassed the Stumbling floor.")
		return
	player.apply_stance_damage(GameEnums.SCALE_MAX, true)
	if player.current_stance != GameEnums.StanceState.FELLED:
		_fail("An explicit takedown could not reach FELLED.")
		return
	player.reset_stance()
	player.stance_points = 4
	player._evaluate_stance_state()
	arena.resolution_engine.execute_take_cover(player)
	if player.stance_points != 6:
		_fail("TAKE COVER did not brace and recover Stance.")
		return
	player.reset_stance()

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
		"[TEST PASS] Combat HUD, Stance recovery safeguards, melee targeting, "
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
