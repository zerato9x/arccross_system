extends SceneTree

const WEAPON_CARD_SCENE := preload(
	"res://CombatCore/Realtime/RealtimeWeaponCard.tscn"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if GameSettingsStore.DEFAULT_COMBAT_MODE != GameSettingsStore.COMBAT_TURN_BASED:
		return _fail("Turn-based combat is not the official default.")
	if not _verify_turn_balance_profiles():
		return
	if not await _verify_action_transaction():
		return
	if not await _verify_turn_weapon_card():
		return
	print("[TURN_BASED_COMBAT_OVERHAUL] PASS")
	quit(0)


func _verify_turn_balance_profiles() -> bool:
	var shoot := TurnBasedCombatBalance.presentation_profile(
		GameEnums.ActionType.SHOOT
	)
	var aimed := TurnBasedCombatBalance.presentation_profile(
		GameEnums.ActionType.AIMED_SHOT
	)
	if (
		float(shoot.duration) <= 0.0
		or float(shoot.cue_fraction) <= 0.0
		or float(shoot.cue_fraction) >= 1.0
	):
		return _fail("SHOOT has no usable windup/impact profile.")
	if float(aimed.duration) <= float(shoot.duration):
		return _fail("AIMED SHOT is not paced independently from SHOOT.")
	return true


func _verify_action_transaction() -> bool:
	var manager := CombatTurnManager.new()
	root.add_child(manager)
	var actor := HumanoidCore.new()
	manager.combatants = [actor]
	manager.active_entity_index = 0
	manager.current_ap_pool = manager.get_action_cost(
		actor,
		GameEnums.ActionType.SHOOT
	)
	var ended := [0]
	manager.turn_ended.connect(func(_entity): ended[0] += 1)
	if not manager.begin_action_resolution(actor):
		manager.queue_free()
		return _fail("Could not begin an action transaction.")
	if not manager.request_action(actor, GameEnums.ActionType.SHOOT):
		manager.queue_free()
		return _fail("Transactional action request was rejected.")
	await process_frame
	await process_frame
	if ended[0] != 0 or not manager.is_action_resolving():
		manager.queue_free()
		return _fail("Turn advanced before action resolution completed.")
	if manager.request_action(actor, GameEnums.ActionType.SHOOT):
		manager.queue_free()
		return _fail("A second action entered an active transaction.")
	manager.end_action_resolution(actor)
	await process_frame
	await process_frame
	if ended[0] != 1 or manager.is_action_resolving():
		manager.queue_free()
		return _fail("Turn did not advance after the transaction released.")
	manager.queue_free()
	actor.free()
	await process_frame
	return true


func _verify_turn_weapon_card() -> bool:
	var card := WEAPON_CARD_SCENE.instantiate() as RealtimeWeaponCard
	root.add_child(card)
	await process_frame
	card.show_descriptor({
		"id": "revolver",
		"display_name": "Civilian Revolver",
		"current_magazine": 6,
		"max_magazine": 6,
		"current_condition": 12.0,
		"effective_range": 6,
		"readiness": {"reason": "ready"},
	}, true)
	var duration := TurnBasedCombatBalance.duration(GameEnums.ActionType.SHOOT)
	card.play_turn_action(GameEnums.ActionType.SHOOT, duration)
	await process_frame
	var state := card.get_animation_debug_state()
	if (
		not bool(state.playing)
		or int(state.base_frames) <= 1
		or not is_equal_approx(float(state.duration), duration)
	):
		card.queue_free()
		return _fail("Turn firearm card did not enter timed sheet playback.")
	if int(state.base_columns) > 1:
		card._apply_base_frame(1)
		if not is_zero_approx(card._base_atlas.region.position.y):
			card.queue_free()
			return _fail("Weapon card sampled a fractional atlas row.")
	card.queue_free()
	await process_frame
	return true


func _fail(message: String) -> bool:
	push_error("[TURN_BASED_COMBAT_OVERHAUL] " + message)
	quit(1)
	return false
