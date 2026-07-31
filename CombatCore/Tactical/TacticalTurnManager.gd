extends Node
class_name TacticalTurnManager

signal round_started(round_number: int)
signal turn_started(active_actor: HumanoidCore)
signal ap_spent(actor: HumanoidCore, remaining_ap: int)
signal turn_ended(actor: HumanoidCore)
signal combat_bleed_tick(actor: HumanoidCore, event: Dictionary)
signal reaction_window_opened(defender: HumanoidCore, attacker: HumanoidCore, trigger_action, available_reactions: Array)
signal reaction_resolved(defender: HumanoidCore, chosen_reaction, success: bool)
signal action_denied(denial: Dictionary)

var combatants: Array[HumanoidCore] = []
var current_round := 0
var active_actor_index := 0
var current_ap_pool := 0
var reserved_ap: Dictionary = {}
var is_halted := true
var _reaction_pending := false
var _reaction_defender: HumanoidCore
var _available_reactions: Array = []
var _action_resolution_owner: HumanoidCore
var _action_resolving := false
var _action_cost_committed := false
var _end_turn_requested := false


func initialize(combatant_array: Array[HumanoidCore], initiator: HumanoidCore = null) -> void:
	var initiative: Dictionary = {}
	for actor in combatant_array:
		initiative[actor] = actor.get_initiative_roll() + (3.0 if actor == initiator else 0.0)
	combatants = combatant_array.duplicate()
	combatants.sort_custom(func(left: HumanoidCore, right: HumanoidCore) -> bool:
		return float(initiative[left]) > float(initiative[right])
	)
	reserved_ap.clear()
	for actor in combatants:
		reserved_ap[actor] = 0
	current_round = 0
	active_actor_index = 0
	is_halted = false
	_start_round()


func get_active_entity() -> HumanoidCore:
	if combatants.is_empty() or active_actor_index < 0 or active_actor_index >= combatants.size():
		return null
	return combatants[active_actor_index]


func halt_loop() -> void:
	is_halted = true


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
		if actor != null and not actor.is_dead and not actor.is_comatose and actor.current_max_ap > 0:
			reserved_ap[actor] = 0
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
	reserved_ap[actor] = maxi(0, current_ap_pool)
	current_ap_pool = 0
	if _action_resolving:
		_end_turn_requested = true
		return
	_finish_turn()


func begin_action_resolution(actor: HumanoidCore) -> bool:
	if actor == null or actor != get_active_entity() or is_halted or _action_resolving or _reaction_pending:
		return false
	_action_resolving = true
	_action_resolution_owner = actor
	_action_cost_committed = false
	return true


func end_action_resolution(actor: HumanoidCore) -> void:
	if not _action_resolving or (_action_resolution_owner != null and actor != _action_resolution_owner):
		return
	_action_resolving = false
	_action_resolution_owner = null
	_action_cost_committed = false
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
		and (not _action_resolving or (_action_resolution_owner == actor and not _action_cost_committed))
	)


func commit_action_cost(actor: HumanoidCore, action_id: String, cost: int) -> bool:
	if not can_commit_action_cost(actor, cost):
		action_denied.emit({"code": "transaction_denied", "action_id": action_id, "cost": cost})
		return false
	current_ap_pool -= cost
	_action_cost_committed = _action_resolving
	ap_spent.emit(actor, current_ap_pool)
	if current_ap_pool <= 0:
		_end_turn_requested = true
	return true


func open_reaction_window(defender: HumanoidCore, attacker: HumanoidCore, trigger_action) -> Array:
	if defender == null or defender.is_dead or defender.is_comatose or _reaction_pending:
		return []
	var available_ap := int(reserved_ap.get(defender, 0))
	var available: Array = []
	var is_melee := str(trigger_action) in ["strike", "power_strike", "aimed_strike", "opportunity_strike"]
	if is_melee and available_ap >= reaction_cost(defender, "block") and defender.body.has_functional_arms():
		available.append("block")
	if available_ap >= reaction_cost(defender, "dodge") and not defender.body.are_both_legs_disabled():
		available.append("dodge")
	if available.is_empty():
		return []
	_reaction_pending = true
	_reaction_defender = defender
	_available_reactions = available
	reaction_window_opened.emit(defender, attacker, trigger_action, available.duplicate())
	return available


func resolve_reaction(defender: HumanoidCore, chosen_reaction) -> bool:
	if not _reaction_pending or defender != _reaction_defender or chosen_reaction not in _available_reactions:
		return false
	var action_id := str(chosen_reaction)
	var cost := reaction_cost(defender, action_id)
	if not try_spend_reserved_ap(defender, cost):
		return false
	_reaction_pending = false
	_reaction_defender = null
	_available_reactions.clear()
	reaction_resolved.emit(defender, chosen_reaction, true)
	return true


func decline_reaction(defender: HumanoidCore) -> void:
	if not _reaction_pending or defender != _reaction_defender:
		return
	_reaction_pending = false
	_reaction_defender = null
	_available_reactions.clear()
	reaction_resolved.emit(defender, -1, false)


func try_spend_reserved_ap(actor: HumanoidCore, amount: int) -> bool:
	var available := int(reserved_ap.get(actor, 0))
	if amount < 0 or available < amount:
		return false
	reserved_ap[actor] = available - amount
	return true


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
		if actor != null and not actor.is_dead and not actor.is_comatose and actor.current_max_ap > 0:
			return false
	return true
