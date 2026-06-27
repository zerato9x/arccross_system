extends Node
class_name CombatAIEvaluator

@export var ai_core: HumanoidCore
@export var lane_manager: CombatLaneManager
@export var turn_manager: CombatTurnManager
@export var resolution_engine: CombatResolutionEngine

var target_core: HumanoidCore
var _forward_direction: int = -1

func _ready() -> void:
	# Wake the AI up when the clock says it's their turn
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.reaction_window_opened.connect(_on_reaction_window_opened)
	turn_manager.displacement_choice_opened.connect(_on_displacement_choice_opened)
	turn_manager.reaction_resolved.connect(_on_reaction_resolved)
	turn_manager.displacement_choice_resolved.connect(_on_displacement_choice_resolved)

func _on_turn_started(entity: HumanoidCore) -> void:
	if entity != ai_core:
		return # Not my turn. Back to sleep.
		
	# Find the player (Prototype logic: just grab the other guy in the array)
	for combatant in turn_manager.combatants:
		if combatant != ai_core:
			target_core = combatant
			break
			
	print("\n[SYSTEM] ", ai_core.name, " is calculating optimal violence...")
	
	# THE THREAT CHECK: First thing the AI does is size up the player
	if not ai_core.is_fleeing and target_core:
		var player_threat: float = target_core.get_effective_threat()
		ai_core._evaluate_flight_response(player_threat)
		if ai_core.is_fleeing:
			print("[AI] ", ai_core.name, " decided this fight isn't worth dying for.")
	
	_process_action_loop()

# ---------------------------------------------------------
# THE COGNITIVE LOOP (Active Turn)
# ---------------------------------------------------------

func _process_action_loop() -> void:
	# The AI keeps thinking and acting until it runs out of AP or ends its turn
	if ai_core.is_dead or turn_manager.current_ap_pool <= 0:
		return
		
	if turn_manager.get_active_entity() != ai_core:
		return
		
	if turn_manager._reaction_pending:
		return # Wait for reaction window to close
		
	var best_action: int = _evaluate_tactics()
	
	if best_action == -1:
		turn_manager.pass_turn(ai_core)
		return
		
	var initial_ap = turn_manager.current_ap_pool
		
	# Attempt to execute the highest scoring idea
	_execute_action(best_action)
	
	if initial_ap == turn_manager.current_ap_pool and not turn_manager._reaction_pending:
		print("[AI] Failsafe: Action ", best_action, " failed to consume AP. Passing turn.")
		turn_manager.pass_turn(ai_core)
	else:
		if turn_manager.current_ap_pool > 0 and not turn_manager._reaction_pending and turn_manager.get_active_entity() == ai_core:
			await get_tree().create_timer(1.2).timeout
			# Double check state hasn't changed during the wait
			if turn_manager.current_ap_pool > 0 and not turn_manager._reaction_pending and turn_manager.get_active_entity() == ai_core:
				_process_action_loop()

func _evaluate_tactics() -> int:
	if ai_core.current_stance == GameEnums.StanceState.FELLED:
		return GameEnums.ActionType.GET_UP
	if not target_core or target_core.is_dead:
		return -1

	var scores = {
		GameEnums.ActionType.STRIKE: _score_melee(),
		GameEnums.ActionType.SHOOT: _score_ranged(),
		GameEnums.ActionType.AIMED_SHOT: _score_aimed_shot(),
		GameEnums.ActionType.RELOAD: _score_reload(),
		GameEnums.ActionType.CYCLE: _score_cycle(),
		GameEnums.ActionType.MOVE_FORWARD: _score_advance(),
		GameEnums.ActionType.CHARGE: _score_charge(),
		GameEnums.ActionType.MOVE_BACKWARD: _score_retreat(),
		GameEnums.ActionType.DISENGAGE: _score_disengage(),
		GameEnums.ActionType.GRAPPLE: _score_grapple(),
		GameEnums.ActionType.TAKE_COVER: _score_take_cover(),
		-1: 0.1 # Baseline. If everything else scores worse than 0.1, just give up.
	}
	
	var is_survival_crisis = _is_in_survival_crisis()
	var my_tactic = ai_core.definition.combat_tactic
	var tactic_multipliers = CombatRules.TACTIC_MULTIPLIERS.get(my_tactic, {})
	
	if is_survival_crisis:
		print("[AI] ", ai_core.name, " is in a SURVIVAL CRISIS! Overriding tactics with survival bias.")
	
	var best_action = -1
	var highest_score = 0.0
	
	for action in scores.keys():
		if action == -1:
			continue
			
		var base_score = scores[action]
		var multiplier = 1.0
		
		if is_survival_crisis:
			multiplier = CombatRules.SURVIVAL_MULTIPLIERS.get(action, 1.0)
		else:
			multiplier = tactic_multipliers.get(action, 1.0)
			
		var final_score = base_score * multiplier
		
		if final_score > highest_score:
			highest_score = final_score
			best_action = action
			
	# Check baseline
	if highest_score < 0.1:
		best_action = -1
		highest_score = 0.1
			
	print("[AI THINKING] Selected: ", best_action, " | Confidence: ", highest_score)
	return best_action

func _is_in_survival_crisis() -> bool:
	if ai_core.is_mindless_hive_thrall:
		return false
	
	if ai_core.body.blood_level < GameEnums.SCALE_MIDPOINT:
		return true
	if ai_core.current_stance == GameEnums.StanceState.STUMBLING or ai_core.current_stance == GameEnums.StanceState.FELLED:
		return true
		
	# Severe limb damage to core
	var upper_torso = ai_core.body.limb_hp[GameEnums.LimbRegion.UPPER_TORSO]
	var max_upper = ai_core.body.get_limb_max(GameEnums.LimbRegion.UPPER_TORSO)
	if upper_torso < max_upper * 0.3:
		return true
		
	return false

# ---------------------------------------------------------
# THE SCORING ALGORITHMS (0.0 to 1.0+)
# ---------------------------------------------------------

func _score_melee() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.STRIKE): return 0.0
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	if my_idx != target_idx:
		return 0.0
	# COMBO PAYOFF: an off-balance foe cannot meaningfully react, and a FELLED
	# foe eats a guaranteed 1.5x grounded head strike. Prioritize cashing in the
	# knockdown we (or a hazard) just set up instead of re-grappling thin air.
	if target_core.current_stance == GameEnums.StanceState.FELLED:
		print("[Combat] ", ai_core.name, " sets up GROUNDED STRIKE combo on FELLED ", target_core.name, ".")
		return 1.6
	if target_core.current_stance == GameEnums.StanceState.STUMBLING:
		print("[Combat] ", ai_core.name, " presses advantage on STUMBLING ", target_core.name, ".")
		return 1.0
	return 0.80

func _score_ranged() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.SHOOT): return 0.0
	# SHOOT is a NON_DUEL action and is rejected while Melee Locked; scoring it
	# above zero here would let the AI burn its whole turn on a denied request.
	if _is_self_locked(): return 0.0
	var weapon = ai_core.inventory.get_active_weapon(false) # Ranged context
	if weapon == null: return 0.0
	
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	var distance = abs(my_idx - target_idx)
	if not weapon.is_ready_to_fire() or distance > weapon.effective_range:
		return 0.0
	if my_idx == target_idx: return 0.2
	return 0.8 - (distance * 0.02)

func _score_aimed_shot() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.AIMED_SHOT): return 0.0
	if _is_self_locked(): return 0.0
	var weapon = ai_core.inventory.get_active_weapon(false) # Ranged context
	if weapon == null: return 0.0
	
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	var distance = abs(my_idx - target_idx)
	if not weapon.is_ready_to_fire() or distance > weapon.effective_range:
		return 0.0
	if my_idx == target_idx: return 0.1
	return 0.9 - (distance * 0.015)

func _score_reload() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.RELOAD): return 0.0
	if _is_self_locked(): return 0.0
	var weapon = ai_core.inventory.get_active_weapon(false) # Ranged context
	if weapon != null and weapon.current_magazine <= 0 and _can_reload_weapon(weapon):
		return 0.98
	return 0.0

func _score_cycle() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.CYCLE): return 0.0
	if _is_self_locked(): return 0.0
	var weapon = ai_core.inventory.get_active_weapon(false) # Ranged context
	if weapon != null and _can_cycle_weapon(weapon):
		return 1.0 if weapon.needs_cycling else 0.95
	return 0.0

func _score_advance() -> float:
	var ap_cost = turn_manager.get_action_cost(ai_core, GameEnums.ActionType.MOVE_FORWARD)
	if turn_manager.current_ap_pool < ap_cost:
		return 0.0
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	var distance = abs(my_idx - target_idx)
	if (
		distance <= 0
		or _is_self_locked()
		or not lane_manager.can_move_entity_to(
			ai_core,
			my_idx,
			my_idx + _direction_toward_target()
		)
	):
		return 0.0 
	var weapon = ai_core.inventory.get_active_weapon(true) # Melee context
	if weapon != null:
		return 0.85
	return 0.4

func _score_charge() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.CHARGE):
		return 0.0
	# CHARGE is NON_DUEL: it cannot start from inside a Melee Lock.
	if _is_self_locked():
		return 0.0
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	if my_idx < 0 or target_idx < 0:
		return 0.0
	# Short gaps are handled by MOVE_FORWARD; CHARGE is for closing real ground.
	var distance = abs(my_idx - target_idx)
	if distance < 2:
		return 0.0
	var step = mini(2, distance)
	var destination = my_idx + _direction_toward_target() * step
	if not lane_manager.can_move_entity_to(ai_core, my_idx, destination):
		return 0.0
	# Charging into a Melee Lock only pays off with something to swing.
	var weapon = ai_core.inventory.get_active_weapon(true) # Melee context
	if weapon != null:
		return 0.88
	return 0.45

func _score_retreat() -> float:
	if ai_core.is_mindless_hive_thrall: return 0.0 
	
	var my_idx = _get_lane_idx(ai_core)
	# THE ESCAPE HATCH: while standing on an Escape Zone tile, MOVE_BACKWARD
	# commits to the hunker-down escape rather than stepping to a tile behind
	# (there is none at the lane edge). Only a fleeing combatant should take it,
	# otherwise the AID would accidentally surrender the fight.
	if (
		my_idx >= 0
		and lane_manager.lane_slots[my_idx].object_name == "Escape Zone"
		and not _is_self_locked()
	):
		if not ai_core.is_fleeing:
			return 0.0
		if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.MOVE_BACKWARD):
			return 0.0
		return 10.0
	if my_idx >= 0 and _is_self_locked():
		if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.DISENGAGE): return 0.0
		if not lane_manager.can_move_entity_to(ai_core, my_idx, my_idx - _direction_toward_target(), true): return 0.0
	else:
		if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.MOVE_BACKWARD): return 0.0
		if not lane_manager.can_move_entity_to(ai_core, my_idx, my_idx - _direction_toward_target()): return 0.0
		
	if ai_core.is_fleeing: return 10.0 
	if ai_core.current_stance == GameEnums.StanceState.STUMBLING: return 0.7
	return 0.1

func _score_disengage() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.DISENGAGE): return 0.0
	var my_idx = _get_lane_idx(ai_core)
	if my_idx < 0 or not _is_self_locked(): return 0.0
	if not lane_manager.can_move_entity_to(ai_core, my_idx, my_idx - _direction_toward_target(), true): return 0.0
	var weapon = ai_core.inventory.get_active_weapon(false) # Ranged context implies they want to shoot
	if weapon != null:
		return 0.90
	if ai_core.is_fleeing: return 10.0
	return 0.1

func _score_grapple() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.GRAPPLE): return 0.0
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	if my_idx != target_idx: return 0.0
	if target_core.current_stance == GameEnums.StanceState.FELLED: return 0.0
	
	var strength_edge := (
		ai_core.get_grapple_strength()
		- maxf(
			target_core.get_grapple_strength(),
			float(target_core.definition.finesse)
		)
	)
	return clampf(0.45 + strength_edge * 0.05, 0.15, 0.75)

func _score_take_cover() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.TAKE_COVER): return 0.0
	if _is_self_locked(): return 0.0
	var my_idx = _get_lane_idx(ai_core)
	if my_idx < 0: return 0.0
	var slot = lane_manager.lane_slots[my_idx]
	if (
		slot.current_cover != CombatRules.TileObject.NONE
		and ai_core.current_stance == GameEnums.StanceState.PLANTED
	):
		return 0.6
	return 0.1

# ---------------------------------------------------------
# EXECUTION ROUTER (Active Turn)
# ---------------------------------------------------------

func _execute_action(action: int) -> void:
	var action_label: String = (
		GameEnums.ActionType.keys()[action]
		if action >= 0 and action < GameEnums.ActionType.keys().size()
		else "PASS"
	)
	print(
		"[Combat] ", ai_core.name, " executes ", action_label,
		" (AP left ", turn_manager.current_ap_pool, ")."
	)
	match action:
		GameEnums.ActionType.GET_UP:
			if turn_manager.request_action(ai_core, GameEnums.ActionType.GET_UP):
				resolution_engine.execute_get_up(ai_core)

		GameEnums.ActionType.STRIKE:
			if turn_manager.request_action(ai_core, GameEnums.ActionType.STRIKE):
				resolution_engine.execute_melee_strike(ai_core, target_core)

		GameEnums.ActionType.SHOOT:
			if turn_manager.request_action(ai_core, GameEnums.ActionType.SHOOT):
				var target_idx = _get_lane_idx(target_core)
				resolution_engine.execute_ranged_strike(ai_core, target_idx)
				
		GameEnums.ActionType.AIMED_SHOT:
			if turn_manager.request_action(ai_core, GameEnums.ActionType.AIMED_SHOT):
				var target_idx = _get_lane_idx(target_core)
				resolution_engine.execute_aimed_shot(ai_core, target_idx, GameEnums.LimbRegion.HEAD)
				
		GameEnums.ActionType.RELOAD:
			if turn_manager.request_action(ai_core, GameEnums.ActionType.RELOAD):
				resolution_engine.execute_reload(ai_core)
				
		GameEnums.ActionType.CYCLE:
			if turn_manager.request_action(ai_core, GameEnums.ActionType.CYCLE):
				resolution_engine.execute_cycle(ai_core)

		GameEnums.ActionType.MOVE_FORWARD:
			var my_idx = _get_lane_idx(ai_core)
			var forward_dir = _direction_toward_target()
			
			if (
				not _is_self_locked()
				and lane_manager.can_move_entity_to(ai_core, my_idx, my_idx + forward_dir)
				and turn_manager.request_action(ai_core, GameEnums.ActionType.MOVE_FORWARD)
			):
				if lane_manager.move_entity(ai_core, my_idx, my_idx + forward_dir):
					resolution_engine.check_hazard_trip(ai_core, lane_manager.lane_slots[my_idx + forward_dir], false)

		GameEnums.ActionType.CHARGE:
			var my_idx = _get_lane_idx(ai_core)
			var target_idx = _get_lane_idx(target_core)
			var forward_dir = _direction_toward_target()
			var step = mini(2, abs(target_idx - my_idx))
			var destination = my_idx + forward_dir * step
			# Validate the relocation before paying AP, mirroring the player path.
			if lane_manager.can_move_entity_to(ai_core, my_idx, destination) and turn_manager.request_action(ai_core, GameEnums.ActionType.CHARGE):
				if lane_manager.move_entity(ai_core, my_idx, destination, true):
					resolution_engine.check_hazard_trip(ai_core, lane_manager.lane_slots[destination], true)

		GameEnums.ActionType.MOVE_BACKWARD:
			var my_idx = _get_lane_idx(ai_core)
			var current_slot = lane_manager.lane_slots[my_idx]
			if current_slot.object_name == "Escape Zone":
				if turn_manager.request_action(ai_core, GameEnums.ActionType.MOVE_BACKWARD):
					print(ai_core.name, " hunkers down in the Escape Zone! (Must survive 1 turn to flee)")
					ai_core.is_escaping = true
					turn_manager.pass_turn(ai_core)
					return
			var forward_dir = _direction_toward_target()
			
			if _is_self_locked():
				if lane_manager.can_move_entity_to(ai_core, my_idx, my_idx - forward_dir, true) and turn_manager.request_action(ai_core, GameEnums.ActionType.DISENGAGE):
					lane_manager.attempt_disengage(ai_core, my_idx, my_idx - forward_dir)
			else:
				if lane_manager.can_move_entity_to(ai_core, my_idx, my_idx - forward_dir) and turn_manager.request_action(ai_core, GameEnums.ActionType.MOVE_BACKWARD):
					if lane_manager.move_entity(ai_core, my_idx, my_idx - forward_dir):
						resolution_engine.check_hazard_trip(ai_core, lane_manager.lane_slots[my_idx - forward_dir], false)

		GameEnums.ActionType.DISENGAGE:
			var disengage_idx = _get_lane_idx(ai_core)
			var disengage_direction = _direction_toward_target()
			if lane_manager.can_move_entity_to(ai_core, disengage_idx, disengage_idx - disengage_direction, true) and turn_manager.request_action(ai_core, GameEnums.ActionType.DISENGAGE):
				lane_manager.attempt_disengage(ai_core, disengage_idx, disengage_idx - disengage_direction)

		GameEnums.ActionType.GRAPPLE:
			if turn_manager.request_action(ai_core, GameEnums.ActionType.GRAPPLE):
				resolution_engine.execute_grapple(ai_core, target_core)
				
		GameEnums.ActionType.TAKE_COVER:
			if turn_manager.request_action(ai_core, GameEnums.ActionType.TAKE_COVER):
				resolution_engine.execute_take_cover(ai_core)


# ---------------------------------------------------------
# REACTION HANDLERS (Off-Turn)
# ---------------------------------------------------------

func _on_reaction_resolved(defender: HumanoidCore, chosen_reaction: int, success: bool) -> void:
	if turn_manager.get_active_entity() == ai_core:
		call_deferred("_process_action_loop")

func _on_displacement_choice_resolved(initiator: HumanoidCore, chose_follow: bool) -> void:
	if turn_manager.get_active_entity() == ai_core:
		call_deferred("_process_action_loop")

func _on_reaction_window_opened(defender: HumanoidCore, attacker: HumanoidCore, trigger_action: GameEnums.ActionType, available_reactions: Array) -> void:
	if defender != ai_core:
		return
		
	var is_survival_crisis = _is_in_survival_crisis()
	var my_tactic = ai_core.definition.combat_tactic
	var tactic_multipliers = CombatRules.TACTIC_MULTIPLIERS.get(my_tactic, {})
	
	var best_reaction = -1
	var highest_score = 0.0
	
	for reaction in available_reactions:
		var base = 1.0 # Baseline validity
		var mult = 1.0
		
		if is_survival_crisis:
			mult = CombatRules.SURVIVAL_MULTIPLIERS.get(reaction, 1.0)
		else:
			mult = tactic_multipliers.get(reaction, 1.0)
			
		var final_score = base * mult
		if final_score > highest_score:
			highest_score = final_score
			best_reaction = reaction
			
	if best_reaction != -1:
		print("[AI REACTION] ", ai_core.name, " decides to ", GameEnums.ActionType.keys()[best_reaction], "!")
		turn_manager.resolve_reaction(ai_core, best_reaction)
		return
		
	turn_manager.skip_reaction(ai_core)

func _on_displacement_choice_opened(initiator: HumanoidCore, displaced_entity: HumanoidCore) -> void:
	if initiator != ai_core:
		return
		
	# AI logic: if it has a melee weapon, it wants to FOLLOW to keep the lock.
	# If it has a gun, it wants to STAY to break the lock.
	# A fleeing combatant always STAYS so the shattered lock frees it to run.
	var weapon = ai_core.inventory.get_active_weapon(true) # Check if we have melee
	var chose_follow: bool = false
	if weapon != null and not ai_core.is_fleeing:
		chose_follow = true
		
	turn_manager.resolve_displacement_choice(ai_core, chose_follow)

func _get_lane_idx(entity: HumanoidCore) -> int:
	for i in range(lane_manager.lane_slots.size()):
		if lane_manager.lane_slots[i].occupants.has(entity): return i
	return -1

## True when the AI shares a Melee Locked slot, which forbids NON_DUEL actions
## (shooting, reloading, cycling, charging, taking cover) until it DISENGAGEs.
func _is_self_locked() -> bool:
	return lane_manager != null and lane_manager.is_entity_melee_locked(ai_core)

func _direction_toward_target() -> int:
	if target_core:
		var my_idx := _get_lane_idx(ai_core)
		var target_idx := _get_lane_idx(target_core)
		if my_idx >= 0 and target_idx >= 0 and my_idx != target_idx:
			_forward_direction = signi(target_idx - my_idx)
	return _forward_direction

func _can_reload_weapon(weapon: ItemData) -> bool:
	if weapon.current_magazine >= weapon.max_magazine:
		return false
	var feed_id := (
		weapon.magazine_id
		if not weapon.magazine_id.is_empty()
		else weapon.reload_aid_id
	)
	if not feed_id.is_empty():
		return ai_core.inventory.find_filled_magazine(feed_id) != null
	if (
		weapon.magazine_id.is_empty()
		and weapon.reload_aid_id.is_empty()
		and weapon.cycle_loads_one_round
	):
		return false
	return _has_inventory_item(
		weapon.ammunition_id
			if not weapon.ammunition_id.is_empty()
			else "ammo_round"
	)

func _can_cycle_weapon(weapon: ItemData) -> bool:
	if weapon.needs_cycling:
		return true
	return (
		weapon.cycle_loads_one_round
		and weapon.current_magazine < weapon.max_magazine
		and _has_inventory_item(
			weapon.ammunition_id
				if not weapon.ammunition_id.is_empty()
				else "ammo_round"
		)
	)

func _has_inventory_item(item_id: String) -> bool:
	return ai_core.inventory.has_combat_item(item_id)
