extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://CombatCore/MainDuelScene.tscn") as PackedScene
	if scene == null:
		return _fail("Real-time duel scene does not load.")
	var arena := scene.instantiate()
	root.add_child(arena)
	await process_frame

	var player_definition := load("res://BiologicalCore/player_def.tres") as EntityDefinition
	var enemy_definition := load("res://BiologicalCore/scavenger_def.tres") as EntityDefinition
	arena.setup_duel_from_records(
		{"entity_id": "rt_player", "definition": player_definition.to_state(), "runtime": {}},
		{"entity_id": "rt_enemy", "definition": enemy_definition.to_state(), "runtime": {}}
	)
	await process_frame
	await process_frame

	var runtime: RealtimeDuelRuntime = arena.duel_runtime
	var player: HumanoidCore = arena.player_core
	var enemy: HumanoidCore = arena.enemy_core
	arena._enemy_ai.set_physics_process(false)
	if runtime.running:
		return _fail("Real-time simulation started before the pre-combat briefing was dismissed.")
	if not arena.combat_briefing.visible:
		return _fail("Pre-combat briefing did not cover the loaded real-time encounter.")
	arena.combat_briefing.visible = false
	arena.combat_briefing.combat_begin_requested.emit()
	await process_frame
	if not runtime.running:
		return _fail("Real-time simulation did not start after the combat-ready gate cleared.")
	if runtime.get_snapshot().get("mode", "") != "realtime_duel":
		return _fail("MainDuelScene did not cut over to the real-time runtime.")
	if not arena.lane_hud.visible:
		return _fail("Minimal real-time duel HUD did not open.")
	var default_profile := DuelWeaponProfileCatalog.profile_for(null)
	if default_profile.light_duration < 2.0 or default_profile.heavy_duration < 3.2:
		return _fail("Authored real-time action profiles are still too short for readable animation.")
	if arena.lane_hud.readability_effects == null:
		return _fail("Duel readability effect system was not present in the live HUD.")
	if arena.lane_hud.player_panel == null or arena.lane_hud.enemy_panel == null:
		return _fail("Realtime HUD is missing its actor paper-doll panels.")
	if arena.lane_hud.player_panel.limb_bars.size() != 7:
		return _fail("Realtime HUD did not restore all seven per-limb health bars.")
	if arena.lane_hud.player_weapon_card == null:
		return _fail("Realtime HUD is missing the preserved gun animation card.")
	if (runtime.get_snapshot().get("player", {}) as Dictionary).get("limbs", []).size() != 7:
		return _fail("Realtime snapshot did not preserve seven-region wound data.")
	var enemy_display_name := str(runtime.get_snapshot().get("enemy", {}).get("display_name", "")).to_upper()
	if enemy_display_name.is_empty() or enemy_display_name not in arena.lane_hud.enemy_panel.title_label.text:
		return _fail("Realtime HUD leaked a scene-node name instead of the encounter identity.")
	if arena.lane_hud.timeline_bar.value != 0.0 or arena.lane_hud.impact_marker.visible:
		return _fail("Ready timeline still looked like an active attack.")
	var timeline_rect: Rect2 = arena.lane_hud.get_node("UILayer/UIRoot/DuelTimeline").get_global_rect()
	var player_panel_rect: Rect2 = arena.lane_hud.player_panel.get_global_rect()
	if timeline_rect.intersects(player_panel_rect):
		return _fail("Responsive duel timeline overlaps the player paper-doll panel: %s vs %s." % [timeline_rect, player_panel_rect])

	var player_state: Dictionary = runtime._states[player]
	player_state["ap"] = 0.0
	var rejection_events: Array[Dictionary] = []
	runtime.intent_rejected.connect(
		func(side: String, code: String, message: String) -> void:
			rejection_events.append({"side": side, "code": code, "message": message})
	)
	if runtime.request_intent(player, GameEnums.DuelIntent.GUARD):
		return _fail("Zero-AP guard was accepted.")
	if rejection_events.is_empty() or rejection_events.back().get("code", "") != "NOT_ENOUGH_AP":
		return _fail("Rejected AP spend did not emit a structured reason.")
	player_state["ap"] = 12.0
	if runtime.request_intent(player, GameEnums.DuelIntent.LIGHT_ATTACK):
		return _fail("Out-of-range melee strike was accepted.")
	if rejection_events.back().get("code", "") != "OUT_OF_RANGE":
		return _fail("Out-of-range melee rejection did not identify the range problem.")
	player_state["ap"] = 0.0
	player.kinetic_tier = GameEnums.KineticTier.FLUID
	player.current_stance = GameEnums.StanceState.PLANTED
	runtime._regenerate_ap_tick()
	if not is_equal_approx(runtime.get_ap(player), 1.0):
		return _fail("FLUID/PLANTED did not regenerate 1 AP per tick.")
	player_state["ap"] = 0.0
	player.kinetic_tier = GameEnums.KineticTier.AGONIZING
	player.current_stance = GameEnums.StanceState.STUMBLING
	runtime._regenerate_ap_tick()
	if not is_equal_approx(runtime.get_ap(player), 0.325):
		return _fail("Burden and Stance regeneration multipliers did not compose.")

	player.kinetic_tier = GameEnums.KineticTier.FLUID
	player.current_stance = GameEnums.StanceState.PLANTED
	player.stance_points = 12
	player_state["ap"] = 12.0
	var lane_before: int = arena.lane_manager._find_entity_lane(player)
	if not runtime.request_intent(player, GameEnums.DuelIntent.MOVE_TOWARD):
		return _fail("D movement intent was rejected with AP and open ground.")
	if runtime.request_intent(player, GameEnums.DuelIntent.GUARD):
		return _fail("A second action was accepted during movement recovery.")
	if rejection_events.back().get("code", "") != "BUSY":
		return _fail("Busy action rejection did not emit its structured reason.")
	if not is_equal_approx(runtime.get_ap(player), 10.0):
		return _fail("Movement did not keep its fixed 2 AP cost.")
	await create_timer(1.65).timeout
	var lane_after: int = arena.lane_manager._find_entity_lane(player)
	if lane_after != lane_before + 1:
		return _fail("Real-time movement did not commit one discrete lane step.")
	runtime._finish_action(player, player_state)

	var enemy_lane: int = arena.lane_manager._find_entity_lane(enemy)
	arena.lane_manager.lane_slots[enemy_lane].exit_slot(enemy)
	arena.lane_manager.lane_slots[lane_after].enter_slot(enemy)
	arena.lane_manager.refresh_lock_states()
	runtime.refresh_snapshot()
	await process_frame
	if arena.lane_hud.lane_view.get_duel_focus_slot() != lane_after:
		return _fail("Melee Lock did not focus the shared grid.")
	for slot in arena.lane_hud.lane_view._slot_nodes:
		var expected_alpha := 1.0 if slot.slot_index == lane_after else 0.26
		if not is_equal_approx(slot.get_duel_focus_alpha(), expected_alpha):
			return _fail("Melee Lock did not dim unrelated grids consistently.")
	player_state["ap"] = 12.0
	var enemy_state: Dictionary = runtime._states[enemy]
	enemy_state["ap"] = 12.0
	if not runtime.request_intent(enemy, GameEnums.DuelIntent.HEAVY_ATTACK):
		return _fail("Enemy heavy attack could not begin for telegraph coverage.")
	if "HEAVY WIND-UP" not in arena.lane_hud.intent_label.text:
		return _fail("Enemy heavy attack did not produce the marked duel timeline warning.")
	if arena.lane_hud.readability_effects.get_active_telegraph_text() != "HEAVY WIND-UP":
		return _fail("Enemy timeline was discarded before reaching the readability layer.")
	if arena.lane_hud.readability_effects.threat_panel.visible:
		return _fail("Obsolete overlapping threat card became visible over the main timeline.")
	if not arena.lane_hud.parry_window.visible:
		return _fail("Incoming melee timeline did not expose the parry window.")
	if not is_equal_approx(
		arena.lane_hud.readability_effects.threat_bar.max_value,
		float(enemy_state.get("impact_time", 0.0))
	):
		return _fail("Telegraph timing drifted away from the resolver impact time.")
	var lock_zoom_before: Vector2 = arena.lane_hud.lock_camera.zoom
	arena.lane_hud.show_presentation_event({"type": "block", "side": "player"})
	if arena.lane_hud.lock_camera.zoom != lock_zoom_before:
		return _fail("An ordinary combat event changed the lock-camera zoom.")
	if arena.lane_hud.readability_effects.get_last_popup_side() != "player":
		return _fail("Block popup was not anchored to the defending combatant.")
	if runtime.request_intent(player, GameEnums.DuelIntent.AIM_START):
		return _fail("Aiming was accepted inside Melee Lock.")
	if rejection_events.back().get("code", "") != "MELEE_LOCK":
		return _fail("Melee-lock rejection did not explain why aiming was unavailable.")
	runtime._finish_action(enemy, enemy_state)
	arena.lane_hud.readability_effects.clear_telegraph()
	runtime.presentation_event.emit({
		"type": "action_timeline",
		"side": "enemy",
		"opponent_side": "player",
		"action": GameEnums.DuelActionType.AIMED_FIRE,
		"duration": 2.4,
		"impact_time": 1.6,
	})
	if arena.lane_hud.readability_effects.get_active_telegraph_text() != "AIMED SHOT":
		return _fail("Ranged hostile actions did not receive the shared telegraph treatment.")
	if not is_equal_approx(arena.lane_hud.readability_effects.threat_bar.max_value, 1.6):
		return _fail("Ranged telegraph did not retain resolver-authored impact timing.")
	arena.lane_hud.readability_effects.clear_telegraph()
	var enemy_stance_before := enemy.stance_points
	if not runtime.request_intent(player, GameEnums.DuelIntent.LIGHT_ATTACK):
		return _fail("Melee Lock did not accept left-click/light intent.")
	await create_timer(1.5).timeout
	if enemy.stance_points >= enemy_stance_before:
		return _fail("Animation-timed light impact did not resolve Stance damage.")
	if int(runtime._states[player].get("combo_step", 0)) != 1:
		return _fail("Successful light strike did not advance the weapon combo.")
	await create_timer(0.8).timeout

	player_state["ap"] = 12.0
	if not runtime.request_intent(player, GameEnums.DuelIntent.HEAVY_ATTACK):
		return _fail("Heavy strike did not start.")
	if not runtime.request_intent(player, GameEnums.DuelIntent.GUARD):
		return _fail("Early heavy windup could not cancel into timed guard.")
	if int(runtime._states[player].get("action", 0)) != GameEnums.DuelActionType.GUARD:
		return _fail("Heavy cancellation did not replace the timeline with guard.")
	await create_timer(0.8).timeout
	runtime._finish_action(player, player_state)

	var shared: int = arena.lane_manager._find_entity_lane(player)
	arena.lane_manager.lane_slots[shared].exit_slot(enemy)
	arena.lane_manager.lane_slots[shared + 2].enter_slot(enemy)
	arena.lane_manager.refresh_lock_states()
	runtime.refresh_snapshot()
	await process_frame
	for slot in arena.lane_hud.lane_view._slot_nodes:
		if not is_equal_approx(slot.get_duel_focus_alpha(), 1.0):
			return _fail("Lane presentation did not restore after Melee Lock ended.")
	var firearm := player.inventory.get_active_weapon(false)
	if firearm == null:
		var pistol := (load("res://ItemCore/Items/service_pistol.tres") as ItemData).create_runtime_instance()
		player.inventory.equip_item(pistol, GameEnums.EquipmentSlot.HAND)
		firearm = player.inventory.get_active_weapon(false)
	if firearm == null:
		return _fail("Could not equip a firearm for real-time aim coverage.")
	var ready_rounds: int = maxi(1, firearm.current_magazine)
	firearm.current_magazine = 0
	if runtime.request_intent(player, GameEnums.DuelIntent.FIRE):
		return _fail("An unloaded firearm was allowed to fire.")
	if rejection_events.back().get("code", "") != "UNLOADED":
		return _fail("Unloaded firearm rejection did not identify the empty weapon.")
	firearm.current_magazine = ready_rounds
	firearm.needs_cycling = true
	if runtime.request_intent(player, GameEnums.DuelIntent.FIRE):
		return _fail("A firearm requiring cycling was allowed to fire.")
	if rejection_events.back().get("code", "") != "NEED_CYCLE":
		return _fail("Cycle-required rejection did not tell the player to service the weapon.")
	firearm.needs_cycling = false
	if runtime.request_intent(player, GameEnums.DuelIntent.FOLLOW):
		return _fail("FOLLOW was accepted without an active displacement window.")
	if rejection_events.back().get("code", "") != "FOLLOW_UNAVAILABLE":
		return _fail("Unavailable FOLLOW did not emit its structured reason.")
	player_state["ap"] = 12.0
	if not runtime.request_intent(player, GameEnums.DuelIntent.AIM_START):
		return _fail("Right-click aim did not start outside Melee Lock.")
	await create_timer(0.2).timeout
	if float(runtime._states[player].get("aim_progress", 0.0)) <= 0.0:
		return _fail("Held aim did not accumulate accuracy progress.")
	if not runtime.request_intent(player, GameEnums.DuelIntent.FIRE):
		return _fail("Left-click did not fire while right-click aim was held.")

	var trap_lane: int = shared + 1
	var trap_slot: CombatLaneSlot = arena.lane_manager.lane_slots[trap_lane]
	arena.lane_manager.place_trap(trap_lane, "trap_makeshift", 1.0, "player")
	arena.lane_manager._try_trigger_trap(trap_slot, player)
	if not trap_slot.trap_armed:
		return _fail("Friendly entry incorrectly triggered an owned trap.")
	arena.lane_manager._try_trigger_trap(trap_slot, enemy)
	if trap_slot.trap_armed:
		return _fail("Hostile entry did not trigger the pre-combat trap.")

	await create_timer(0.45).timeout
	runtime._finish_action(player, player_state)
	runtime._finish_action(enemy, enemy_state)
	arena.lane_manager.remove_entity(player)
	arena.lane_manager.remove_entity(enemy)
	arena.lane_manager.force_spawn_entity(player, 4)
	arena.lane_manager.force_spawn_entity(enemy, 4)
	player_state["ap"] = 12.0
	if not runtime.request_intent(player, GameEnums.DuelIntent.MOVE_TOWARD):
		return _fail("D did not become PUSH inside Melee Lock.")
	runtime._advance_action(player, player_state, 1.8)
	if arena.lane_manager._find_entity_lane(enemy) != 5:
		return _fail("PUSH did not displace the enemy one lane.")
	if float(player_state.get("follow_deadline", 0.0)) <= runtime.elapsed_time:
		return _fail("PUSH did not open the follow-or-shoot window.")
	runtime._finish_action(player, player_state)
	if not runtime.request_intent(player, GameEnums.DuelIntent.MOVE_TOWARD):
		return _fail("D did not FOLLOW during the displacement window.")
	runtime._advance_action(player, player_state, 1.7)
	if not arena.lane_manager.is_entity_melee_locked(player):
		return _fail("FOLLOW did not restore Melee Lock.")

	runtime._finish_action(player, player_state)
	player.stance_points = 0
	player.current_stance = GameEnums.StanceState.FELLED
	player_state["ap"] = RealtimeDuelRuntime.GET_UP_COST
	if runtime.request_intent(player, GameEnums.DuelIntent.GUARD):
		return _fail("Felled combatant was allowed to guard before recovery.")
	if rejection_events.back().get("code", "") != "FELLED":
		return _fail("Felled-state rejection did not explain the recovery requirement.")
	runtime._process_actor(player, 0.01)
	if int(player_state.get("action", 0)) != GameEnums.DuelActionType.GET_UP:
		return _fail("Felled combatant did not begin automatic AP-funded recovery.")
	runtime._advance_action(player, player_state, 2.5)
	if player.stance_points != RealtimeDuelRuntime.GET_UP_STANCE or not player.has_stance_recovery_guard:
		return _fail("Automatic get-up did not restore Stance and Recovery Guard.")

	arena.lane_hud.show_resolve_screen({
		"title": "VICTORY",
		"result": "OPPONENT NEUTRALIZED",
		"dead_side": "enemy",
		"cause": "Realtime smoke resolve coverage.",
		"loot_count": 0,
	})
	await process_frame
	if not arena.lane_hud.is_resolve_screen_visible():
		return _fail("Realtime end-combat damage report did not become visible.")
	if arena.lane_hud.get_resolve_focus_side() != "enemy":
		return _fail("Realtime end-combat screen did not retain its defeated-side focus.")
	arena.lane_hud.request_resolve_continue()
	await process_frame
	if arena.lane_hud.is_resolve_screen_visible():
		return _fail("Realtime end-combat report did not close after acknowledgement.")

	runtime.stop()
	arena.queue_free()
	await process_frame

	var turn_scene := load(
		"res://CombatCore/TurnBased/TurnBasedDuelScene.tscn"
	) as PackedScene
	if turn_scene == null:
		return _fail("Separate turn-based comparison scene does not load.")
	var turn_arena := turn_scene.instantiate()
	root.add_child(turn_arena)
	await process_frame
	if not (turn_arena.turn_manager is CombatTurnManager):
		return _fail("Turn-based comparison scene does not retain CombatTurnManager authority.")
	if not turn_arena.has_node("CombatBriefingOverlay"):
		return _fail("Turn-based combat is missing the shared pre-combat briefing screen.")
	if turn_arena.get_node_or_null("RealtimeDuelRuntime") != null:
		return _fail("Turn-based comparison scene secretly contains the real-time runtime.")
	turn_arena.queue_free()
	await process_frame

	if load("res://CombatCore/CombatModeComparison.tscn") == null:
		return _fail("Combat mode comparison launcher does not load.")
	var settings := root.get_node_or_null("GameSettings")
	if settings == null:
		return _fail("Expanded persistent GameSettings autoload is unavailable.")
	if (
		PresentationSceneRegistry.REALTIME_DUEL_SCENE
		== PresentationSceneRegistry.TURN_BASED_DUEL_SCENE
	):
		return _fail("Combat settings route both choices to the same scene.")
	print("[REALTIME_DUEL_SMOKE] PASS // pacing, telegraphs, AP, grid, melee, aim, traps, and separate turn mode")
	quit(0)

func _fail(message: String) -> void:
	push_error("[REALTIME_DUEL_SMOKE] " + message)
	quit(1)
