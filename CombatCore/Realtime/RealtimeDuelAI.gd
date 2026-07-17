extends Node
class_name RealtimeDuelAI

@export var think_interval := 0.8
@export var opening_grace_seconds := 2.0

var ai_core: HumanoidCore
var opponent: HumanoidCore
var runtime: RealtimeDuelRuntime
var lane_manager: CombatLaneManager
var _think_accumulator := 0.0
var _aiming := false
var _next_decision_time := 0.0

func configure(
	entity: HumanoidCore,
	target: HumanoidCore,
	duel_runtime: RealtimeDuelRuntime,
	lanes: CombatLaneManager
) -> void:
	ai_core = entity
	opponent = target
	runtime = duel_runtime
	lane_manager = lanes
	_think_accumulator = 0.0
	_next_decision_time = opening_grace_seconds
	set_physics_process(true)

func _ready() -> void:
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	if (
		ai_core == null
		or opponent == null
		or runtime == null
		or not runtime.running
		or ai_core.is_dead
		or opponent.is_dead
	):
		return
	_think_accumulator += delta
	if _think_accumulator < think_interval:
		return
	_think_accumulator = 0.0
	_think()

func _think() -> void:
	if runtime.elapsed_time < _next_decision_time:
		return
	var state := runtime.get_action_state(ai_core)
	if int(state.get("action", GameEnums.DuelActionType.NONE)) != GameEnums.DuelActionType.NONE:
		return
	if ai_core.current_stance == GameEnums.StanceState.FELLED:
		return

	if _should_guard():
		if runtime.request_intent(ai_core, GameEnums.DuelIntent.GUARD):
			_next_decision_time = runtime.elapsed_time + 1.0
		return

	var my_lane := lane_manager._find_entity_lane(ai_core)
	var target_lane := lane_manager._find_entity_lane(opponent)
	if my_lane < 0 or target_lane < 0:
		return
	var distance := absi(my_lane - target_lane)
	var firearm := ai_core.inventory.get_active_weapon(false)
	var melee := ai_core.inventory.get_active_weapon(true)

	if lane_manager.is_entity_melee_locked(ai_core):
		_aiming = false
		var acted := false
		if firearm != null and firearm.is_ready_to_fire() and runtime.get_ap(ai_core) >= 8.0 and randf() < 0.2:
			acted = runtime.request_intent(ai_core, GameEnums.DuelIntent.MOVE_TOWARD)
		elif runtime.get_ap(ai_core) >= 5.0 and randf() < 0.38:
			acted = runtime.request_intent(ai_core, GameEnums.DuelIntent.HEAVY_ATTACK)
		else:
			acted = runtime.request_intent(ai_core, GameEnums.DuelIntent.LIGHT_ATTACK)
		if acted:
			_next_decision_time = runtime.elapsed_time + 1.2
		return

	if firearm != null and firearm.is_ready_to_fire() and distance <= firearm.effective_range:
		if _aiming:
			if float(state.get("aim_progress", 0.0)) >= _desired_aim_progress():
				runtime.request_intent(ai_core, GameEnums.DuelIntent.FIRE)
				_aiming = false
			return
		if runtime.get_ap(ai_core) >= 6.0 and randf() < _aim_preference():
			_aiming = runtime.request_intent(ai_core, GameEnums.DuelIntent.AIM_START)
		else:
			runtime.request_intent(ai_core, GameEnums.DuelIntent.FIRE)
		return

	if firearm != null and (firearm.needs_cycling or firearm.current_magazine <= 0):
		if runtime.request_intent(ai_core, GameEnums.DuelIntent.RELOAD_OR_CYCLE):
			return

	if melee != null or firearm == null:
		runtime.request_intent(ai_core, GameEnums.DuelIntent.MOVE_TOWARD)

func _should_guard() -> bool:
	var opponent_state := runtime.get_action_state(opponent)
	var action := int(opponent_state.get("action", GameEnums.DuelActionType.NONE))
	if action not in [
		GameEnums.DuelActionType.LIGHT_STRIKE,
		GameEnums.DuelActionType.HEAVY_STRIKE,
		GameEnums.DuelActionType.COMBO_FINISHER,
	]:
		return false
	var until_impact := (
		float(opponent_state.get("impact_time", 0.0))
		- float(opponent_state.get("elapsed", 0.0))
	)
	var parry_window := runtime.get_parry_response_window()
	if until_impact < parry_window.x or until_impact > parry_window.y:
		return false
	var finesse_ratio := clampf(float(ai_core.definition.finesse) / GameEnums.SCALE_MAX, 0.0, 1.0)
	return runtime.get_ap(ai_core) >= 3.0 and randf() < lerpf(0.28, 0.72, finesse_ratio)

func _aim_preference() -> float:
	match ai_core.definition.combat_tactic:
		GameEnums.CombatTactic.MARKSMAN:
			return 0.82
		GameEnums.CombatTactic.BRUTE:
			return 0.16
	return 0.48

func _desired_aim_progress() -> float:
	return 0.82 if ai_core.definition.combat_tactic == GameEnums.CombatTactic.MARKSMAN else 0.55
