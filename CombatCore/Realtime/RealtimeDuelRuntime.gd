extends Node
class_name RealtimeDuelRuntime

signal snapshot_changed(snapshot: Dictionary)
signal presentation_event(event: Dictionary)
signal feedback(message: String)
signal intent_rejected(side: String, code: String, message: String)
signal entity_escaped(entity: HumanoidCore)

const AP_MAX := 12.0
const AP_TICK_SECONDS := 0.5
const MOVE_COST := 2.0
const MOVE_DURATION := 1.8
const MOVE_IMPACT_TIME := 1.55
const PUSH_COST := 4.0
const PUSH_DURATION := 2.6
const PUSH_IMPACT_TIME := 1.65
const FOLLOW_COST := 2.0
const FOLLOW_WINDOW := 1.8
const GUARD_COST := 3.0
const GUARD_DURATION := 1.45
const PARRY_OPEN := 0.1
const PARRY_CLOSE := 0.42
const GET_UP_COST := 4.0
const GET_UP_DURATION := 2.4
const GET_UP_STANCE := 6
const REFELL_GUARD_SECONDS := 0.75
const HEAVY_CANCEL_FEE := 1.0
const HEAVY_CANCEL_RECOVERY := 0.55
const BLEED_TICK_SECONDS := 1.0
const STANCE_RECOVERY_DELAY := 1.5
const STANCE_RECOVERY_PER_SECOND := 1.0

const COMMITTED_REGEN_MULTIPLIER := 0.25
const AIMING_REGEN_MULTIPLIER := 0.4

## Compatibility surface for scenes built during the prototype. Action
## profiles now own their real presentation durations; this is intentionally
## neutral so animation playback cannot drift away from resolver timing.
@export var duel_pace_scale := 1.0

@export var lane_manager: CombatLaneManager
@export var realtime_lane: RealtimeLaneController
@export var damage_resolver: RealtimeDamageResolver

var player_core: HumanoidCore
var enemy_core: HumanoidCore
var running := false
var elapsed_time := 0.0

var _states: Dictionary = {}
var _ap_tick_accumulator := 0.0
var _bleed_tick_accumulator := 0.0
var _timeline_serial := 0

## Transitional read aliases for callers that only halt or escape an arena.
## Turn scheduling and reaction APIs are intentionally not emulated.
var combatants: Array[HumanoidCore] = []
var current_round: int = 0
var reserved_ap: Dictionary = {}
var current_ap_pool: float:
	get:
		return get_ap(player_core) if player_core != null else 0.0

func _ready() -> void:
	set_physics_process(false)

func configure(player: HumanoidCore, enemy: HumanoidCore) -> void:
	player_core = player
	enemy_core = enemy
	combatants = [player_core, enemy_core]
	_states.clear()
	for entity in [player_core, enemy_core]:
		_states[entity] = _new_actor_state(entity)
		entity.set_meta("duel_side", _side(entity))
	elapsed_time = 0.0
	_ap_tick_accumulator = 0.0
	_bleed_tick_accumulator = 0.0
	running = false
	set_physics_process(false)
	_emit_snapshot()


func begin_duel() -> void:
	if player_core == null or enemy_core == null or running:
		return
	running = true
	set_physics_process(true)
	_emit_snapshot()

func stop() -> void:
	running = false
	set_physics_process(false)

func halt_loop() -> void:
	stop()

func resume_loop() -> void:
	begin_duel()

func escape_combat(entity: HumanoidCore) -> void:
	if entity == null:
		return
	lane_manager.remove_entity(entity)
	entity_escaped.emit(entity)

func refresh_snapshot() -> void:
	_emit_snapshot()

## Narrow migration bridge for macro/vertical-slice callers that issued one old
## command directly. Menu descriptors, turns, and reactions are not recreated.
func request_player_action(
	action: int,
	_target_limb: int = GameEnums.LimbRegion.UPPER_TORSO,
	_item_instance_id: String = ""
) -> void:
	match action:
		GameEnums.ActionType.MOVE_FORWARD:
			request_intent(player_core, GameEnums.DuelIntent.MOVE_TOWARD)
		GameEnums.ActionType.MOVE_BACKWARD:
			request_intent(player_core, GameEnums.DuelIntent.MOVE_AWAY)
		GameEnums.ActionType.STRIKE:
			request_intent(player_core, GameEnums.DuelIntent.LIGHT_ATTACK)
		GameEnums.ActionType.PUSH_STAY:
			request_intent(player_core, GameEnums.DuelIntent.MOVE_TOWARD)
		GameEnums.ActionType.SHOOT:
			request_intent(player_core, GameEnums.DuelIntent.FIRE)
		GameEnums.ActionType.AIMED_SHOT:
			if request_intent(player_core, GameEnums.DuelIntent.AIM_START):
				var state: Dictionary = _states[player_core]
				state["aim_progress"] = 1.0
				request_intent(player_core, GameEnums.DuelIntent.FIRE)
		GameEnums.ActionType.RELOAD, GameEnums.ActionType.CYCLE:
			request_intent(player_core, GameEnums.DuelIntent.RELOAD_OR_CYCLE)

func _physics_process(delta: float) -> void:
	if not running or player_core == null or enemy_core == null:
		return
	elapsed_time += delta
	_ap_tick_accumulator += delta
	_bleed_tick_accumulator += delta
	while _ap_tick_accumulator >= AP_TICK_SECONDS:
		_ap_tick_accumulator -= AP_TICK_SECONDS
		_regenerate_ap_tick()
	while _bleed_tick_accumulator >= BLEED_TICK_SECONDS:
		_bleed_tick_accumulator -= BLEED_TICK_SECONDS
		_process_bleeding()
	for entity in [player_core, enemy_core]:
		_process_actor(entity, delta)
	_emit_snapshot()

func request_intent(entity: HumanoidCore, intent: int) -> bool:
	if not running or not _states.has(entity) or entity.is_dead:
		return _reject(entity, "NOT_AVAILABLE", "The duel is not accepting commands.")
	var state: Dictionary = _states[entity]
	var opponent := _opponent(entity)

	if intent in [GameEnums.DuelIntent.MOVE_AWAY, GameEnums.DuelIntent.MOVE_TOWARD, GameEnums.DuelIntent.GUARD]:
		if _try_cancel_heavy(entity, state):
			if intent == GameEnums.DuelIntent.GUARD:
				return _start_guard(entity, state)
			return _start_movement_intent(entity, intent, state)

	if state.get("aiming", false):
		match intent:
			GameEnums.DuelIntent.FIRE:
				return _start_shot(entity, state, true)
			GameEnums.DuelIntent.AIM_CANCEL:
				_cancel_aim(state)
				return true
			GameEnums.DuelIntent.GUARD, GameEnums.DuelIntent.MOVE_AWAY, GameEnums.DuelIntent.MOVE_TOWARD:
				_cancel_aim(state)
			_:
				return _reject(entity, "BUSY", "Release or cancel the current aim first.")

	if _is_busy(state):
		return _reject(entity, "BUSY", "Finish the current action first.")
	if entity.current_stance == GameEnums.StanceState.FELLED:
		return _reject(entity, "FELLED", "Recover your stance before acting.")

	match intent:
		GameEnums.DuelIntent.MOVE_AWAY, GameEnums.DuelIntent.MOVE_TOWARD:
			return _start_movement_intent(entity, intent, state)
		GameEnums.DuelIntent.LIGHT_ATTACK:
			return _start_melee(entity, opponent, state, false)
		GameEnums.DuelIntent.HEAVY_ATTACK:
			return _start_melee(entity, opponent, state, true)
		GameEnums.DuelIntent.FIRE:
			if _is_melee_locked(entity):
				return _start_melee(entity, opponent, state, false)
			return _start_shot(entity, state, false)
		GameEnums.DuelIntent.AIM_START:
			return _start_aim(entity, state)
		GameEnums.DuelIntent.GUARD:
			return _start_guard(entity, state)
		GameEnums.DuelIntent.RELOAD_OR_CYCLE:
			return _start_reload_or_cycle(entity, state)
		GameEnums.DuelIntent.FOLLOW:
			return _start_follow(entity, state)
	return _reject(entity, "INVALID_ACTION", "That command is unavailable here.")

func request_escape(entity: HumanoidCore) -> bool:
	if not _states.has(entity):
		return false
	var state: Dictionary = _states[entity]
	if _is_busy(state) or _is_melee_locked(entity):
		return false
	var lane := lane_manager._find_entity_lane(entity)
	var valid_edge := lane == 0 if entity == player_core else lane == 11
	if not valid_edge or not _spend_ap(state, MOVE_COST):
		return false
	_start_action(entity, state, {
		"action": GameEnums.DuelActionType.ESCAPE,
		"duration": 1.2,
		"impact_time": 1.2,
		"animation": "RunBackwards",
	})
	return true

func get_snapshot() -> Dictionary:
	if player_core == null or enemy_core == null:
		return {}
	return {
		"mode": "realtime_duel",
		"elapsed": elapsed_time,
		"running": running,
		"player": _combatant_snapshot(player_core),
		"enemy": _combatant_snapshot(enemy_core),
		"lane_slots": _lane_snapshot(),
		"is_melee_locked": _is_melee_locked(player_core),
	}

func get_ap(entity: HumanoidCore) -> float:
	return float(_states.get(entity, {}).get("ap", 0.0))

func get_action_state(entity: HumanoidCore) -> Dictionary:
	return (_states.get(entity, {}) as Dictionary).duplicate(true)

func get_pace_scale() -> float:
	return duel_pace_scale

func get_parry_response_window() -> Vector2:
	return Vector2(PARRY_OPEN, PARRY_CLOSE)

func _new_actor_state(entity: HumanoidCore) -> Dictionary:
	return {
		"side": _side(entity),
		"ap": minf(AP_MAX, float(entity.current_max_ap)),
		"action": GameEnums.DuelActionType.NONE,
		"elapsed": 0.0,
		"duration": 0.0,
		"impact_time": 0.0,
		"impact_done": false,
		"action_data": {},
		"aiming": false,
		"aim_progress": 0.0,
		"aim_time": 1.0,
		"combo_step": 0,
		"combo_deadline": 0.0,
		"follow_deadline": 0.0,
		"follow_lane": -1,
		"stance_idle": 0.0,
		"stance_recovery_accumulator": 0.0,
		"refell_guard": 0.0,
	}

func _process_actor(entity: HumanoidCore, delta: float) -> void:
	if entity == null or entity.is_dead or not _states.has(entity):
		return
	var state: Dictionary = _states[entity]
	state["refell_guard"] = maxf(0.0, float(state.get("refell_guard", 0.0)) - delta)
	entity.has_stance_recovery_guard = float(state["refell_guard"]) > 0.0
	if elapsed_time > float(state.get("combo_deadline", 0.0)):
		state["combo_step"] = 0
	if elapsed_time > float(state.get("follow_deadline", 0.0)):
		state["follow_lane"] = -1

	if state.get("aiming", false):
		state["aim_progress"] = clampf(
			float(state.get("aim_progress", 0.0))
			+ delta / maxf(0.05, float(state.get("aim_time", 1.0))),
			0.0,
			1.0
		)

	if _is_busy(state):
		state["stance_idle"] = 0.0
		_advance_action(entity, state, delta)
	elif state.get("aiming", false):
		state["stance_idle"] = 0.0
	else:
		state["stance_idle"] = float(state.get("stance_idle", 0.0)) + delta
		_process_stance_recovery(entity, state, delta)
		if (
			entity.current_stance == GameEnums.StanceState.FELLED
			and get_ap(entity) >= GET_UP_COST
		):
			_start_get_up(entity, state)

func _advance_action(entity: HumanoidCore, state: Dictionary, delta: float) -> void:
	state["elapsed"] = float(state.get("elapsed", 0.0)) + delta
	if (
		not state.get("impact_done", false)
		and float(state["elapsed"]) >= float(state.get("impact_time", 0.0))
	):
		state["impact_done"] = true
		_resolve_action_impact(entity, state)
	if float(state["elapsed"]) >= float(state.get("duration", 0.0)):
		_finish_action(entity, state)

func _resolve_action_impact(entity: HumanoidCore, state: Dictionary) -> void:
	var data: Dictionary = state.get("action_data", {})
	match int(state.get("action", GameEnums.DuelActionType.NONE)):
		GameEnums.DuelActionType.MOVE:
			var from_lane := int(data.get("from_lane", -1))
			var to_lane := int(data.get("to_lane", -1))
			if realtime_lane == null or not realtime_lane.commit_move(entity, from_lane, to_lane):
				feedback.emit("Movement was blocked before arrival.")
				_refund_ap(state, MOVE_COST)
			else:
				_resolve_movement_hazard(entity, lane_manager.lane_slots[to_lane])
		GameEnums.DuelActionType.LIGHT_STRIKE, GameEnums.DuelActionType.HEAVY_STRIKE, GameEnums.DuelActionType.COMBO_FINISHER:
			_resolve_melee_impact(entity, state, data)
		GameEnums.DuelActionType.PUSH:
			_resolve_push(entity, state)
		GameEnums.DuelActionType.FOLLOW:
			_resolve_follow(entity, state)
		GameEnums.DuelActionType.BLIND_FIRE, GameEnums.DuelActionType.AIMED_FIRE:
			_resolve_shot_impact(entity, state, data)
		GameEnums.DuelActionType.RELOAD, GameEnums.DuelActionType.CYCLE:
			_resolve_firearm_service(
				entity,
				int(state.get("action", GameEnums.DuelActionType.NONE)),
				data.get("weapon") as ItemData
			)
		GameEnums.DuelActionType.GET_UP:
			if entity.current_stance == GameEnums.StanceState.FELLED:
				entity.begin_felled_recovery(GET_UP_STANCE)
				state["refell_guard"] = REFELL_GUARD_SECONDS
		GameEnums.DuelActionType.ESCAPE:
			lane_manager.remove_entity(entity)
			entity_escaped.emit(entity)

func _finish_action(_entity: HumanoidCore, state: Dictionary) -> void:
	state["action"] = GameEnums.DuelActionType.NONE
	state["elapsed"] = 0.0
	state["duration"] = 0.0
	state["impact_time"] = 0.0
	state["impact_done"] = false
	state["action_data"] = {}

func _start_movement_intent(entity: HumanoidCore, intent: int, state: Dictionary) -> bool:
	if _is_melee_locked(entity):
		if intent == GameEnums.DuelIntent.MOVE_TOWARD:
			return _start_push(entity, state)
		return _reject(entity, "MELEE_LOCK", "You cannot retreat while locked; push to create space.")
	if intent == GameEnums.DuelIntent.MOVE_TOWARD and _follow_available(state):
		return _start_follow(entity, state)
	var from_lane := lane_manager._find_entity_lane(entity)
	var toward := 1 if entity == player_core else -1
	var direction := toward if intent == GameEnums.DuelIntent.MOVE_TOWARD else -toward
	var to_lane := from_lane + direction
	if to_lane < 0 or to_lane >= lane_manager.lane_slots.size():
		return request_escape(entity)
	if not lane_manager.can_move_entity_to(entity, from_lane, to_lane):
		return _reject(entity, "BLOCKED_MOVEMENT", "The next grid cannot be entered.")
	if not _spend_ap(state, MOVE_COST):
		return false
	_start_action(entity, state, {
		"action": GameEnums.DuelActionType.MOVE,
		"duration": MOVE_DURATION,
		"impact_time": MOVE_IMPACT_TIME,
		"animation": "Run" if direction == toward else "RunBackwards",
		"from_lane": from_lane,
		"to_lane": to_lane,
	})
	return true

func _start_melee(
	entity: HumanoidCore,
	opponent: HumanoidCore,
	state: Dictionary,
	heavy: bool
) -> bool:
	if not _is_melee_locked(entity) or opponent == null or opponent.is_dead:
		return _reject(entity, "OUT_OF_RANGE", "Close into melee lock before striking.")
	var weapon := entity.inventory.get_active_weapon(true)
	var profile := DuelWeaponProfileCatalog.profile_for(weapon)
	var combo_step := int(state.get("combo_step", 0))
	var finisher := heavy and combo_step == 2 and elapsed_time <= float(state.get("combo_deadline", 0.0))
	var action := GameEnums.DuelActionType.LIGHT_STRIKE
	var cost := profile.light_cost
	var duration := profile.light_duration
	var impact := profile.light_impact_time
	var animation := profile.light_animation if combo_step != 1 else profile.second_light_animation
	var flesh_multiplier := profile.light_flesh_multiplier
	var stance_multiplier := profile.light_stance_multiplier
	var commit_time := 0.0
	if heavy:
		action = GameEnums.DuelActionType.COMBO_FINISHER if finisher else GameEnums.DuelActionType.HEAVY_STRIKE
		cost = profile.finisher_cost if finisher else profile.heavy_cost
		duration = profile.finisher_duration if finisher else profile.heavy_duration
		impact = profile.finisher_impact_time if finisher else profile.heavy_impact_time
		animation = profile.finisher_animation if finisher else profile.heavy_animation
		flesh_multiplier = profile.finisher_flesh_multiplier if finisher else profile.heavy_flesh_multiplier
		stance_multiplier = profile.finisher_stance_multiplier if finisher else profile.heavy_stance_multiplier
		commit_time = profile.heavy_commit_time
	if not _spend_ap(state, cost):
		return false
	_start_action(entity, state, {
		"action": action,
		"duration": duration,
		"impact_time": impact,
		"commit_time": commit_time,
		"animation": animation,
		"cost": cost,
		"weapon": weapon,
		"flesh_multiplier": flesh_multiplier,
		"stance_multiplier": stance_multiplier,
		"source": "combo_finisher" if finisher else ("heavy" if heavy else "light"),
	})
	return true

func _start_push(entity: HumanoidCore, state: Dictionary) -> bool:
	if not _is_melee_locked(entity) or not _spend_ap(state, PUSH_COST):
		return false
	_start_action(entity, state, {
		"action": GameEnums.DuelActionType.PUSH,
		"duration": PUSH_DURATION,
		"impact_time": PUSH_IMPACT_TIME,
		"animation": "Attack2",
	})
	return true

func _start_follow(entity: HumanoidCore, state: Dictionary) -> bool:
	if not _follow_available(state):
		return _reject(entity, "FOLLOW_UNAVAILABLE", "The follow window has closed.")
	if not _spend_ap(state, FOLLOW_COST):
		return false
	_start_action(entity, state, {
		"action": GameEnums.DuelActionType.FOLLOW,
		"duration": MOVE_DURATION,
		"impact_time": MOVE_IMPACT_TIME,
		"animation": "Run",
		"to_lane": int(state.get("follow_lane", -1)),
	})
	state["follow_deadline"] = 0.0
	return true

func _start_guard(entity: HumanoidCore, state: Dictionary) -> bool:
	if not _spend_ap(state, GUARD_COST):
		return false
	_start_action(entity, state, {
		"action": GameEnums.DuelActionType.GUARD,
		"duration": GUARD_DURATION,
		"impact_time": GUARD_DURATION,
		"animation": "StrafeLeft" if entity == player_core else "StrafeRight",
		"guard_started": elapsed_time,
	})
	return true

func _start_aim(entity: HumanoidCore, state: Dictionary) -> bool:
	var weapon := entity.inventory.get_active_weapon(false)
	if _is_melee_locked(entity):
		return _reject(entity, "MELEE_LOCK", "Create distance before aiming the firearm.")
	if not _validate_ready_firearm(entity, weapon):
		return false
	var profile := DuelWeaponProfileCatalog.profile_for(weapon)
	if not _spend_ap(state, profile.aim_setup_cost):
		return false
	var finesse_ratio := clampf(float(entity.definition.finesse) / GameEnums.SCALE_MAX, 0.0, 1.0)
	state["aiming"] = true
	state["aim_progress"] = 0.001
	state["aim_time"] = (
		profile.base_aim_time
		* lerpf(1.25, 0.75, finesse_ratio)
	)
	presentation_event.emit({
		"type": "aim_started",
		"side": _side(entity),
		"duration": state["aim_time"],
	})
	return true

func _start_shot(entity: HumanoidCore, state: Dictionary, aimed: bool) -> bool:
	var weapon := entity.inventory.get_active_weapon(false)
	if _is_melee_locked(entity):
		return _reject(entity, "MELEE_LOCK", "Use a melee strike or push to create distance.")
	if not _validate_ready_firearm(entity, weapon):
		return false
	var target := _opponent(entity)
	var distance := absi(lane_manager._find_entity_lane(entity) - lane_manager._find_entity_lane(target))
	if distance > weapon.effective_range:
		return _reject(entity, "OUT_OF_RANGE", "Target is outside %s effective range." % weapon.display_name)
	var profile := DuelWeaponProfileCatalog.profile_for(weapon)
	var cost := profile.aimed_fire_cost if aimed else profile.blind_cost
	if not _spend_ap(state, cost):
		return false
	var aim_progress := float(state.get("aim_progress", 0.0)) if aimed else 0.0
	_cancel_aim(state)
	weapon.current_magazine -= 1
	weapon.needs_cycling = weapon.requires_cycle_after_shot
	_start_action(entity, state, {
		"action": GameEnums.DuelActionType.AIMED_FIRE if aimed else GameEnums.DuelActionType.BLIND_FIRE,
		"duration": profile.blind_duration,
		"impact_time": profile.blind_impact_time,
		"animation": profile.firearm_animation,
		"weapon": weapon,
		"aim_progress": aim_progress,
	})
	return true

func _start_reload_or_cycle(entity: HumanoidCore, state: Dictionary) -> bool:
	var weapon := entity.inventory.get_active_weapon(false)
	if weapon == null:
		return _reject(entity, "NO_FIREARM", "No firearm is equipped.")
	if weapon.needs_cycling or weapon.cycle_loads_one_round:
		if not _can_cycle(entity, weapon):
			return _reject(entity, "NEED_CYCLE", "The weapon cannot cycle without ammunition.")
		if not _spend_ap(state, 1.0):
			return false
		_start_action(entity, state, {
			"action": GameEnums.DuelActionType.CYCLE,
			"duration": 1.85,
			"impact_time": 1.25,
			"animation": "Taunt",
			"weapon": weapon,
		})
		return true
	if not _can_reload(entity, weapon):
		return _reject(entity, "UNLOADED", "No compatible ammunition is available.")
	if not _spend_ap(state, 2.0):
		return false
	_start_action(entity, state, {
		"action": GameEnums.DuelActionType.RELOAD,
		"duration": 2.8,
		"impact_time": 2.1,
		"animation": "Taunt",
		"weapon": weapon,
	})
	return true

func _start_get_up(entity: HumanoidCore, state: Dictionary) -> void:
	if not _spend_ap(state, GET_UP_COST):
		return
	_start_action(entity, state, {
		"action": GameEnums.DuelActionType.GET_UP,
		"duration": GET_UP_DURATION,
		"impact_time": GET_UP_DURATION,
		"animation": "Taunt",
	})

func _start_action(entity: HumanoidCore, state: Dictionary, data: Dictionary) -> void:
	_timeline_serial += 1
	var paced_data := data.duplicate()
	var duration := maxf(0.05, float(data.get("duration", 0.0)))
	var impact_time := clampf(
		float(data.get("impact_time", duration)),
		0.0,
		duration
	)
	paced_data["duration"] = duration
	paced_data["impact_time"] = impact_time
	paced_data["telegraph_time"] = impact_time
	paced_data["recovery_time"] = maxf(0.0, duration - impact_time)
	state["action"] = int(data.get("action", GameEnums.DuelActionType.NONE))
	state["elapsed"] = 0.0
	state["duration"] = float(paced_data.get("duration", 0.0))
	state["impact_time"] = float(paced_data.get("impact_time", 0.0))
	state["impact_done"] = false
	state["action_data"] = paced_data
	state["stance_idle"] = 0.0
	var event := paced_data.duplicate()
	event["type"] = "action_timeline"
	event["timeline_id"] = _timeline_serial
	event["side"] = _side(entity)
	event["opponent_side"] = _side(_opponent(entity))
	presentation_event.emit(event)

func _resolve_melee_impact(entity: HumanoidCore, state: Dictionary, data: Dictionary) -> void:
	var defender := _opponent(entity)
	if defender == null or defender.is_dead or not _is_melee_locked(entity):
		_break_combo(state)
		return
	var defense := _melee_defense(defender, entity)
	if defense == "parry":
		entity.apply_stance_damage(3.0, true)
		_stagger(entity, state, 0.7)
		_break_combo(state)
		presentation_event.emit({"type": "parry", "side": _side(defender), "target_side": _side(entity)})
		return
	if defense == "block":
		damage_resolver.resolve_block(entity, defender, data.get("weapon") as ItemData)
		_advance_combo(state, int(state.get("action", 0)))
		presentation_event.emit({"type": "block", "side": _side(defender), "target_side": _side(entity)})
		return
	var event := damage_resolver.resolve_melee(
		entity,
		defender,
		data.get("weapon") as ItemData,
		float(data.get("flesh_multiplier", 1.0)),
		float(data.get("stance_multiplier", 1.0)),
		str(data.get("source", "melee"))
	)
	_advance_combo(state, int(state.get("action", 0)))
	_emit_damage_presentation(event)

func _resolve_push(entity: HumanoidCore, state: Dictionary) -> void:
	var target := _opponent(entity)
	var shared_lane := lane_manager._find_entity_lane(entity)
	if target == null or shared_lane < 0 or lane_manager._find_entity_lane(target) != shared_lane:
		return
	var direction := 1 if entity == player_core else -1
	var destination := realtime_lane.push(entity, target, direction) if realtime_lane != null else -1
	if destination >= 0:
		state["follow_deadline"] = elapsed_time + FOLLOW_WINDOW * duel_pace_scale
		state["follow_lane"] = destination
		target.apply_stance_damage(2.0)
		presentation_event.emit({
			"type": "push",
			"side": _side(entity),
			"target_side": _side(target),
			"from_lane": shared_lane,
			"to_lane": destination,
			"follow_deadline": state["follow_deadline"],
			"move_duration": maxf(0.35, PUSH_DURATION - PUSH_IMPACT_TIME),
		})

func _resolve_follow(entity: HumanoidCore, state: Dictionary) -> void:
	var to_lane := int(state.get("action_data", {}).get("to_lane", -1))
	if to_lane >= 0 and realtime_lane != null:
		realtime_lane.follow(entity, to_lane)

func _resolve_shot_impact(entity: HumanoidCore, _state: Dictionary, data: Dictionary) -> void:
	var defender := _opponent(entity)
	if defender == null or defender.is_dead:
		return
	var attacker_lane := lane_manager._find_entity_lane(entity)
	var defender_lane := lane_manager._find_entity_lane(defender)
	if attacker_lane < 0 or defender_lane < 0:
		return
	var defender_state: Dictionary = _states[defender]
	var guard_active := int(defender_state.get("action", 0)) == GameEnums.DuelActionType.GUARD
	var event := damage_resolver.resolve_shot(
		entity,
		defender,
		data.get("weapon") as ItemData,
		absi(attacker_lane - defender_lane),
		lane_manager.lane_slots[defender_lane],
		float(data.get("aim_progress", 0.0)),
		guard_active
	)
	event["type"] = "shot"
	event["side"] = _side(entity)
	event["target_side"] = _side(defender)
	event["origin_lane"] = attacker_lane
	event["target_lane"] = defender_lane
	presentation_event.emit(event)
	if event.get("hit", false):
		_emit_damage_presentation(event)

func _melee_defense(defender: HumanoidCore, _attacker: HumanoidCore) -> String:
	var state: Dictionary = _states.get(defender, {})
	if int(state.get("action", 0)) != GameEnums.DuelActionType.GUARD:
		return ""
	var guard_started := float(state.get("action_data", {}).get("guard_started", -99.0))
	var age := elapsed_time - guard_started
	if age >= PARRY_OPEN and age <= PARRY_CLOSE:
		return "parry"
	if age >= 0.0 and age <= GUARD_DURATION:
		return "block"
	return ""

func _stagger(entity: HumanoidCore, state: Dictionary, duration: float) -> void:
	state["action"] = GameEnums.DuelActionType.STAGGER
	state["elapsed"] = 0.0
	state["duration"] = duration
	state["impact_time"] = duration
	state["impact_done"] = true
	state["action_data"] = {"animation": "TakeDamage"}

func _try_cancel_heavy(entity: HumanoidCore, state: Dictionary) -> bool:
	var action := int(state.get("action", 0))
	if action not in [GameEnums.DuelActionType.HEAVY_STRIKE, GameEnums.DuelActionType.COMBO_FINISHER]:
		return false
	var data: Dictionary = state.get("action_data", {})
	if float(state.get("elapsed", 0.0)) >= float(data.get("commit_time", 0.0)):
		return false
	var cost := float(data.get("cost", 0.0))
	_refund_ap(state, maxf(0.0, cost - HEAVY_CANCEL_FEE))
	_break_combo(state)
	_stagger(entity, state, HEAVY_CANCEL_RECOVERY)
	presentation_event.emit({"type": "heavy_cancel", "side": _side(entity)})
	return true

func _advance_combo(state: Dictionary, action: int) -> void:
	if action == GameEnums.DuelActionType.LIGHT_STRIKE:
		state["combo_step"] = mini(2, int(state.get("combo_step", 0)) + 1)
		state["combo_deadline"] = (
			elapsed_time
			+ DuelWeaponProfileCatalog.profile_for(null).combo_window
		)
	else:
		_break_combo(state)

func _break_combo(state: Dictionary) -> void:
	state["combo_step"] = 0
	state["combo_deadline"] = 0.0

func _cancel_aim(state: Dictionary) -> void:
	state["aiming"] = false
	state["aim_progress"] = 0.0

func _follow_available(state: Dictionary) -> bool:
	return (
		int(state.get("follow_lane", -1)) >= 0
		and elapsed_time <= float(state.get("follow_deadline", 0.0))
	)

func _regenerate_ap_tick() -> void:
	for entity in [player_core, enemy_core]:
		if entity == null or entity.is_dead or not _states.has(entity):
			continue
		var state: Dictionary = _states[entity]
		var base := 1.0
		match entity.kinetic_tier:
			GameEnums.KineticTier.LABORED:
				base = 0.75
			GameEnums.KineticTier.AGONIZING:
				base = 0.5
		var stance_multiplier := 1.0
		match entity.current_stance:
			GameEnums.StanceState.STUMBLING:
				stance_multiplier = 0.65
			GameEnums.StanceState.FELLED:
				stance_multiplier = 0.35
		var activity_multiplier := 1.0
		if _is_busy(state):
			activity_multiplier = COMMITTED_REGEN_MULTIPLIER
		elif state.get("aiming", false):
			activity_multiplier = AIMING_REGEN_MULTIPLIER
		state["ap"] = minf(
			AP_MAX,
			float(state.get("ap", 0.0))
			+ base * stance_multiplier * activity_multiplier
		)

func _process_bleeding() -> void:
	for entity in [player_core, enemy_core]:
		if entity != null and not entity.is_dead and entity.body != null:
			entity.body.process_combat_bleeding_tick()

func _resolve_movement_hazard(entity: HumanoidCore, slot: CombatLaneSlot) -> void:
	if slot == null or slot.background != CombatRules.TileBackground.MUD:
		return
	var chance := maxf(
		CombatRules.MUD_MIN_TRIP_CHANCE,
		CombatRules.MUD_MOVE_TRIP_CHANCE
		- float(entity.definition.finesse) * CombatRules.MUD_MOVE_FINESSE_REDUCTION
	)
	if randf() < chance:
		entity.try_fell()
		presentation_event.emit({
			"type": "hazard_trip",
			"side": _side(entity),
			"lane": slot.lane_index,
		})

func _process_stance_recovery(entity: HumanoidCore, state: Dictionary, delta: float) -> void:
	if (
		entity.current_stance == GameEnums.StanceState.FELLED
		or float(state.get("stance_idle", 0.0)) < STANCE_RECOVERY_DELAY
		or entity.stance_points >= int(GameEnums.SCALE_MAX)
	):
		return
	var rate := STANCE_RECOVERY_PER_SECOND
	var lane := lane_manager._find_entity_lane(entity)
	if lane >= 0 and lane_manager.lane_slots[lane].current_cover == CombatRules.TileObject.COVER:
		rate = 1.5
	state["stance_recovery_accumulator"] = float(state.get("stance_recovery_accumulator", 0.0)) + delta * rate
	while float(state["stance_recovery_accumulator"]) >= 1.0:
		state["stance_recovery_accumulator"] = float(state["stance_recovery_accumulator"]) - 1.0
		entity.recover_stance(1)

func _can_reload(entity: HumanoidCore, weapon: ItemData) -> bool:
	if weapon.current_magazine >= weapon.max_magazine:
		return false
	var feed_id := weapon.magazine_id if not weapon.magazine_id.is_empty() else weapon.reload_aid_id
	if not feed_id.is_empty():
		return entity.inventory.find_filled_magazine(feed_id) != null
	if weapon.cycle_loads_one_round:
		return false
	return entity.inventory.find_combat_item(weapon.ammunition_id) != null

func _can_cycle(entity: HumanoidCore, weapon: ItemData) -> bool:
	if weapon.needs_cycling:
		return true
	return (
		weapon.cycle_loads_one_round
		and weapon.current_magazine < weapon.max_magazine
		and entity.inventory.find_combat_item(weapon.ammunition_id) != null
	)

func _resolve_firearm_service(entity: HumanoidCore, action: int, weapon: ItemData) -> bool:
	if action == GameEnums.DuelActionType.CYCLE:
		if weapon.needs_cycling:
			weapon.needs_cycling = false
			return true
		if weapon.cycle_loads_one_round:
			var loaded := entity.inventory.consume_ammunition(weapon.ammunition_id, 1, true)
			weapon.current_magazine += loaded
			return loaded > 0
		return false
	var feed_id := weapon.magazine_id if not weapon.magazine_id.is_empty() else weapon.reload_aid_id
	if not feed_id.is_empty():
		var magazine := entity.inventory.consume_filled_magazine(feed_id)
		if magazine == null:
			return false
		weapon.current_magazine = mini(weapon.max_magazine, magazine.loaded_rounds)
		weapon.needs_cycling = false
		return true
	var needed := weapon.max_magazine - weapon.current_magazine
	var rounds := entity.inventory.consume_ammunition(weapon.ammunition_id, needed, true)
	weapon.current_magazine += rounds
	weapon.needs_cycling = false
	return rounds > 0

func _spend_ap(state: Dictionary, amount: float) -> bool:
	if float(state.get("ap", 0.0)) + 0.0001 < amount:
		_reject_state(state, "NOT_ENOUGH_AP", "Wait for AP regeneration.")
		return false
	state["ap"] = maxf(0.0, float(state["ap"]) - amount)
	return true

func _refund_ap(state: Dictionary, amount: float) -> void:
	state["ap"] = minf(AP_MAX, float(state.get("ap", 0.0)) + amount)

func _is_busy(state: Dictionary) -> bool:
	return int(state.get("action", GameEnums.DuelActionType.NONE)) != GameEnums.DuelActionType.NONE

func _validate_ready_firearm(entity: HumanoidCore, weapon: ItemData) -> bool:
	if weapon == null:
		return _reject(entity, "NO_FIREARM", "No firearm is equipped.")
	if weapon.needs_cycling:
		return _reject(entity, "NEED_CYCLE", "Press R to cycle the weapon.")
	if weapon.current_magazine <= 0:
		return _reject(entity, "UNLOADED", "Press R to reload the weapon.")
	if not weapon.is_ready_to_fire():
		return _reject(entity, "WEAPON_UNAVAILABLE", "The firearm is not ready.")
	return true

func _reject(entity: HumanoidCore, code: String, message: String) -> bool:
	var side := _side(entity) if entity != null else "unknown"
	intent_rejected.emit(side, code, message)
	return false

func _reject_state(state: Dictionary, code: String, message: String) -> bool:
	intent_rejected.emit(str(state.get("side", "unknown")), code, message)
	return false

func _is_melee_locked(entity: HumanoidCore) -> bool:
	return lane_manager != null and lane_manager.is_entity_melee_locked(entity)

func _opponent(entity: HumanoidCore) -> HumanoidCore:
	return enemy_core if entity == player_core else player_core

func _side(entity: HumanoidCore) -> String:
	return "player" if entity == player_core else "enemy"

func _emit_snapshot() -> void:
	snapshot_changed.emit(get_snapshot())

func _emit_damage_presentation(event: Dictionary) -> void:
	var defender: HumanoidCore = event.get("defender") as HumanoidCore
	if defender != null and _states.has(defender):
		var defender_state: Dictionary = _states[defender]
		defender_state["stance_idle"] = 0.0
		if int(defender_state.get("action", 0)) == GameEnums.DuelActionType.GET_UP:
			_stagger(defender, defender_state, 0.2 * duel_pace_scale)
			feedback.emit("Get-up interrupted by impact.")
	var presentation := event.duplicate()
	presentation["type"] = "damage"
	presentation["side"] = _side(defender)
	presentation_event.emit(presentation)

func _combatant_snapshot(entity: HumanoidCore) -> Dictionary:
	var state: Dictionary = _states.get(entity, {})
	var ranged := entity.inventory.get_active_weapon(false)
	var melee := entity.inventory.get_active_weapon(true)
	var equipment: Array = []
	for slot_key in entity.inventory.paper_doll.keys():
		var item: ItemData = entity.inventory.paper_doll[slot_key]
		if item == null:
			continue
		var descriptor := item.to_definition_state()
		descriptor["instance_id"] = item.instance_id
		descriptor["equipment_slot"] = int(slot_key)
		descriptor["current_magazine"] = item.current_magazine
		descriptor["loaded_rounds"] = item.loaded_rounds
		descriptor["needs_cycling"] = item.needs_cycling
		equipment.append(descriptor)
	return {
		"name": entity.name,
		"archetype": entity.definition.archetype_name,
		"display_name": (
			entity.definition.archetype_name
			if not entity.definition.archetype_name.strip_edges().is_empty()
			else entity.name
		),
		"lane": lane_manager._find_entity_lane(entity),
		"ap": float(state.get("ap", 0.0)),
		"ap_max": AP_MAX,
		"ap_regen": _effective_regen_per_second(entity),
		"action": int(state.get("action", GameEnums.DuelActionType.NONE)),
		"action_elapsed": float(state.get("elapsed", 0.0)),
		"action_duration": float(state.get("duration", 0.0)),
		"action_impact_time": float(state.get("impact_time", 0.0)),
		"aiming": state.get("aiming", false),
		"aim_progress": float(state.get("aim_progress", 0.0)),
		"combo_step": int(state.get("combo_step", 0)),
		"follow_window": maxf(0.0, float(state.get("follow_deadline", 0.0)) - elapsed_time),
		"blood": entity.body.blood_level,
		"blood_max": GameEnums.SCALE_MAX,
		"limbs": _limb_snapshot(entity),
		"stance": entity.stance_points,
		"stance_state": GameEnums.StanceState.keys()[entity.current_stance],
		"kinetic_tier": GameEnums.KineticTier.keys()[entity.kinetic_tier],
		"is_dead": entity.is_dead,
		"both_legs_broken": entity.body.are_both_legs_disabled(),
		"has_firearm": ranged != null,
		"ranged_weapon": _weapon_snapshot(ranged),
		"melee_weapon": _weapon_snapshot(melee),
		"equipment": equipment,
		"appearance": HumanoidVisualCatalog.appearance_from_equipment_snapshot(equipment),
	}

func _weapon_snapshot(weapon: ItemData) -> Dictionary:
	if weapon == null:
		return {}
	var data := weapon.to_definition_state()
	data["instance_id"] = weapon.instance_id
	data["current_magazine"] = weapon.current_magazine
	data["needs_cycling"] = weapon.needs_cycling
	data["sprite_path"] = weapon.get_inventory_sprite_path()
	return data

func _limb_snapshot(entity: HumanoidCore) -> Array:
	var limbs: Array = []
	var ordered_regions := [
		GameEnums.LimbRegion.HEAD,
		GameEnums.LimbRegion.UPPER_TORSO,
		GameEnums.LimbRegion.LOWER_TORSO,
		GameEnums.LimbRegion.LEFT_ARM,
		GameEnums.LimbRegion.RIGHT_ARM,
		GameEnums.LimbRegion.LEFT_LEG,
		GameEnums.LimbRegion.RIGHT_LEG,
	]
	var codes := ["HD", "UT", "LT", "LA", "RA", "LL", "RL"]
	for index in range(ordered_regions.size()):
		var region: GameEnums.LimbRegion = ordered_regions[index]
		var damage_type := int(entity.body.limb_damage_types.get(region, -1))
		var damage_type_name := ""
		if damage_type >= 0 and damage_type < GameEnums.DamageType.keys().size():
			damage_type_name = str(GameEnums.DamageType.keys()[damage_type])
		limbs.append({
			"region": region,
			"code": codes[index],
			"current": float(entity.body.limb_hp.get(region, 0.0)),
			"maximum": entity.body.get_limb_max(region),
			"trauma": GameEnums.TraumaType.keys()[
				int(entity.body.limb_trauma.get(region, GameEnums.TraumaType.NONE))
			],
			"damage_type": damage_type_name,
			"damage_type_index": damage_type,
		})
	return limbs

func _lane_snapshot() -> Array:
	var slots: Array = []
	for slot in lane_manager.lane_slots:
		var presentation := slot.get_presentation_descriptor()
		var occupants: Array = []
		for occupant in slot.occupants:
			occupants.append({
				"side": _side(occupant),
				"name": occupant.name,
				"stance": occupant.stance_points,
			})
		slots.append({
			"index": slot.lane_index,
			"is_escape": slot.object_name == "Escape Zone",
			"is_spawnable": slot.is_spawnable,
			"background": CombatRules.TileBackground.keys()[slot.background],
			"background_label": presentation.get("background_label", "PLAINS"),
			"ground_asset": presentation.get("ground_asset", ""),
			"surface_label": presentation.get("surface_label", "GRASS"),
			"surface_asset": presentation.get("surface_asset", ""),
			"terrain_modifiers": presentation.get("terrain_modifiers", []),
			"cover": CombatRules.TileObject.keys()[slot.current_cover],
			"object_name": presentation.get("object_name", "NONE"),
			"object_asset": presentation.get("object_asset", ""),
			"object_interactions": presentation.get("object_interactions", []),
			"cover_durability": slot.object_durability,
			"is_melee_locked": lane_manager.is_lane_melee_locked(slot.lane_index),
			"territory_side": slot.territory_side,
			"trap_owner_side": slot.trap_owner_side,
			"occupants": occupants,
		})
	return slots

func _effective_regen_per_second(entity: HumanoidCore) -> float:
	var base := 1.0 / AP_TICK_SECONDS
	if entity.kinetic_tier == GameEnums.KineticTier.LABORED:
		base *= 0.75
	elif entity.kinetic_tier == GameEnums.KineticTier.AGONIZING:
		base *= 0.5
	if entity.current_stance == GameEnums.StanceState.STUMBLING:
		base *= 0.65
	elif entity.current_stance == GameEnums.StanceState.FELLED:
		base *= 0.35
	var state: Dictionary = _states.get(entity, {})
	if _is_busy(state):
		base *= COMMITTED_REGEN_MULTIPLIER
	elif state.get("aiming", false):
		base *= AIMING_REGEN_MULTIPLIER
	return base
