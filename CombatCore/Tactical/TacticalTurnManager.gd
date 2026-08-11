extends Node
class_name TacticalTurnManager

const _CombatActorState := preload("res://SystemCore/CombatActorState.gd")
const _CombatBalanceProfile := preload("res://SystemCore/CombatBalanceProfile.gd")

signal round_started(round_number: int)
signal turn_started(active_actor: HumanoidCore)
signal ap_spent(actor: HumanoidCore, remaining_ap: int)
signal turn_ended(actor: HumanoidCore)
signal combat_bleed_tick(actor: HumanoidCore, event: Dictionary)
signal reaction_window_opened(defender: HumanoidCore, attacker: HumanoidCore, trigger_action, available_reactions: Array)
signal reaction_resolved(defender: HumanoidCore, chosen_reaction, success: bool)
signal action_denied(denial: Dictionary)
signal action_resolution_finished(actor: HumanoidCore)

var combatants: Array[HumanoidCore] = []
var current_round := 0
var active_actor_index := 0
var current_ap_pool := 0
## Deprecated compatibility projection. AP is never reserved between turns in
## the unified system; this remains empty so older snapshot consumers do not
## crash while they migrate.
var reserved_ap: Dictionary = {}
var is_halted := true
var _reaction_pending := false
var _reaction_defender: HumanoidCore
var _available_reactions: Array = []
var _action_resolution_owner: HumanoidCore
var _action_resolving := false
var _action_cost_committed := false
var _action_reserved_ap := 0
var _end_turn_requested := false
var _initiative_rng := RandomNumberGenerator.new()
var balance_profile: CombatBalanceProfile


func initialize(combatant_array: Array[HumanoidCore], initiator: HumanoidCore = null, encounter_seed: int = 1) -> void:
	_initiative_rng.seed = encounter_seed
	var initiative: Dictionary = {}
	for actor in combatant_array:
		initiative[actor] = actor.get_initiative_roll(_initiative_rng) + (3.0 if actor == initiator else 0.0)
	combatants = combatant_array.duplicate()
	combatants.sort_custom(func(left: HumanoidCore, right: HumanoidCore) -> bool:
		return float(initiative[left]) > float(initiative[right])
	)
	reserved_ap.clear()
	current_round = 0
	active_actor_index = 0
	is_halted = false
	_action_resolving = false
	_action_resolution_owner = null
	_action_cost_committed = false
	_action_reserved_ap = 0
	_start_round()


func get_active_entity() -> HumanoidCore:
	if combatants.is_empty() or active_actor_index < 0 or active_actor_index >= combatants.size():
		return null
	return combatants[active_actor_index]


func halt_loop() -> void:
	is_halted = true


func remove_combatant(actor: HumanoidCore) -> bool:
	## Terminal actors no longer participate in initiative. Their biological
	## node and body/inventory remain owned by the encounter handoff.
	var index := combatants.find(actor)
	if index < 0:
		return false
	combatants.remove_at(index)
	reserved_ap.erase(actor)
	if combatants.is_empty():
		active_actor_index = 0
		is_halted = true
		return true
	if index < active_actor_index:
		active_actor_index -= 1
	active_actor_index = clampi(active_actor_index, 0, combatants.size() - 1)
	return true


func resume_loop() -> void:
	if combatants.is_empty():
		return
	is_halted = false
	if current_round == 0:
		_start_round()


func _start_round() -> void:
	if is_halted:
		return
	current_round += 1
	active_actor_index = 0
	round_started.emit(current_round)
	_start_turn()


func _start_turn() -> void:
	if is_halted or combatants.is_empty():
		return
	var scanned := 0
	while scanned < combatants.size():
		var actor := get_active_entity()
		if actor != null:
			# Hydrate old records before initiative checks. A zero-blood actor must
			# never come back as an immortal target after a combat handoff.
			actor.reconcile_terminal_state()
		var state := _combat_state(actor)
		if state != null and state.surrendered:
			active_actor_index = (active_actor_index + 1) % combatants.size()
			scanned += 1
			continue
		if state != null and state.broken and not state.incapacitated:
			# Broken actors lose their next activation, then recover to a low but
			# usable stance. This is a state transition, not a player verb.
			state.activation_lost = true
			state.stance = balance_profile.recovery_stance(state.max_stance) if balance_profile != null else maxf(1.0, minf(state.max_stance, state.max_stance * 0.25))
			state.reconcile()
			actor.set_meta("combat_actor_state", state)
			current_ap_pool = 0
			active_actor_index = (active_actor_index + 1) % combatants.size()
			scanned += 1
			continue
		if actor != null and not actor.is_dead and not actor.is_comatose and actor.current_max_ap > 0:
			reserved_ap.erase(actor)
			var bleed := actor.body.process_combat_bleeding_tick()
			if not bleed.is_empty():
				combat_bleed_tick.emit(actor, bleed)
			if not actor.is_dead and not actor.is_comatose:
				current_ap_pool = actor.current_max_ap
				turn_started.emit(actor)
				return
		active_actor_index = (active_actor_index + 1) % combatants.size()
		scanned += 1
	if _everyone_unable_to_act():
		is_halted = true


func pass_turn(actor: HumanoidCore) -> void:
	if actor == null or actor != get_active_entity() or is_halted:
		return
	# End Turn discards every remaining AP. There is no reaction reserve.
	reserved_ap.erase(actor)
	current_ap_pool = 0
	if _action_resolving:
		_end_turn_requested = true
		return
	_finish_turn()


func begin_action_resolution(actor: HumanoidCore, required_ap: int = 0) -> bool:
	if actor == null or actor != get_active_entity() or is_halted or _action_resolving:
		return false
	if required_ap < 0 or current_ap_pool < required_ap:
		return false
	_action_resolving = true
	_action_resolution_owner = actor
	_action_cost_committed = false
	_action_reserved_ap = required_ap
	return true


func end_action_resolution(actor: HumanoidCore) -> void:
	if not _action_resolving or (_action_resolution_owner != null and actor != _action_resolution_owner):
		return
	_action_resolving = false
	_action_resolution_owner = null
	_action_cost_committed = false
	_action_reserved_ap = 0
	action_resolution_finished.emit(actor)
	if _end_turn_requested or current_ap_pool <= 0:
		_end_turn_requested = false
		_finish_turn()


func can_commit_action_cost(actor: HumanoidCore, cost: int) -> bool:
	return (
		actor != null
		and actor == get_active_entity()
		and not is_halted
		and not _reaction_pending
		and cost >= 0
		and current_ap_pool >= cost
		and (
			not _action_resolving
			or (
				_action_resolution_owner == actor
				and not _action_cost_committed
				and cost <= _action_reserved_ap
			)
		)
	)


func action_reserved_ap() -> int:
	return _action_reserved_ap


func commit_action_cost(actor: HumanoidCore, action_id: String, cost: int) -> bool:
	if not can_commit_action_cost(actor, cost):
		action_denied.emit({"code": "transaction_denied", "action_id": action_id, "cost": cost})
		return false
	current_ap_pool -= cost
	_action_cost_committed = _action_resolving
	_action_reserved_ap = 0
	ap_spent.emit(actor, current_ap_pool)
	if current_ap_pool <= 0:
		_end_turn_requested = true
	return true


func open_reaction_window(defender: HumanoidCore, attacker: HumanoidCore, trigger_action) -> Array:
	# Reactions were a second, hidden action economy. Defense is now resolved in
	# the authoritative attack quote, so an attack never opens another input
	# window or waits for a reserved AP response.
	return []


func resolve_reaction(defender: HumanoidCore, chosen_reaction) -> bool:
	return false


func decline_reaction(defender: HumanoidCore) -> void:
	return


func try_spend_reserved_ap(actor: HumanoidCore, amount: int) -> bool:
	return false


func reaction_cost(actor: HumanoidCore, _action_id: String) -> int:
	match actor.kinetic_tier:
		GameEnums.KineticTier.LABORED:
			return 3
		GameEnums.KineticTier.AGONIZING:
			return 4
	return 2


func _finish_turn() -> void:
	if is_halted or combatants.is_empty():
		return
	var actor := get_active_entity()
	turn_ended.emit(actor)
	active_actor_index += 1
	if active_actor_index >= combatants.size():
		_start_round()
	else:
		_start_turn()


func _everyone_unable_to_act() -> bool:
	for actor in combatants:
		var state := _combat_state(actor)
		if actor != null and not actor.is_dead and not actor.is_comatose and (state == null or not state.surrendered) and actor.current_max_ap > 0:
			return false
	return true


func is_actor_active(actor: HumanoidCore) -> bool:
	if actor == null or actor.is_dead or actor.is_comatose or actor.current_max_ap <= 0:
		return false
	var state := _combat_state(actor)
	return state == null or (not state.incapacitated and not state.surrendered)


func _combat_state(actor: HumanoidCore) -> CombatActorState:
	if actor == null:
		return null
	var existing: Variant = actor.get_meta("combat_actor_state") if actor.has_meta("combat_actor_state") else null
	if existing is _CombatActorState:
		(existing as _CombatActorState).reconcile()
		return existing as _CombatActorState
	if existing is Dictionary:
		var hydrated := _CombatActorState.from_runtime(existing)
		actor.set_meta("combat_actor_state", hydrated)
		return hydrated
	return null
