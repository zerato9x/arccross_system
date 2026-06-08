extends Node
class_name CombatAIEvaluator

@export var ai_core: HumanoidCore
@export var lane_manager: CombatLaneManager
@export var turn_manager: CombatTurnManager
@export var resolution_engine: CombatResolutionEngine

var target_core: HumanoidCore

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

func _evaluate_tactics() -> int:
	if not target_core or target_core.is_dead:
		return -1

	var scores = {
		GameEnums.ActionType.STRIKE: _score_melee(),
		GameEnums.ActionType.SHOOT: _score_ranged(),
		GameEnums.ActionType.AIMED_SHOT: _score_aimed_shot(),
		GameEnums.ActionType.RELOAD: _score_reload(),
		GameEnums.ActionType.CYCLE: _score_cycle(),
		GameEnums.ActionType.MOVE_FORWARD: _score_advance(),
		GameEnums.ActionType.MOVE_BACKWARD: _score_retreat(),
		GameEnums.ActionType.DISENGAGE: _score_disengage(),
		GameEnums.ActionType.EXECUTE: _score_execute(),
		GameEnums.ActionType.GRAPPLE: _score_grapple(),
		GameEnums.ActionType.TAKE_COVER: _score_take_cover(),
		-1: 0.1 # Baseline. If everything else scores worse than 0.1, just give up.
	}
	
	var is_survival_crisis = _is_in_survival_crisis()
	var my_tactic = ai_core.definition.combat_tactic
	var tactic_multipliers = GameEnums.TACTIC_MULTIPLIERS.get(my_tactic, {})
	
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
			multiplier = GameEnums.SURVIVAL_MULTIPLIERS.get(action, 1.0)
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
	
	if ai_core.body.blood_level < 0.5:
		return true
	if ai_core.current_stance == GameEnums.StanceState.STUMBLING or ai_core.current_stance == GameEnums.StanceState.FELLED:
		return true
		
	# Severe limb damage to core
	var upper_torso = ai_core.body.limb_hp[GameEnums.LimbRegion.UPPER_TORSO]
	var max_upper = ai_core.body.BASE_LIMB_MAX[GameEnums.LimbRegion.UPPER_TORSO] * (ai_core.definition.fortitude / 6.0)
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
	if my_idx == target_idx:
		return 0.80
	return 0.0

func _score_ranged() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.SHOOT): return 0.0
	var weapon = ai_core.inventory.get_active_weapon(false) # Ranged context
	if weapon == null: return 0.0
	if weapon.weapon_type == GameEnums.WeaponClass.PISTOL and weapon.current_magazine <= 0: return 0.0
	if weapon.weapon_type == GameEnums.WeaponClass.RIFLE:
		if weapon.needs_cycling: return 0.0
		# Ensure they actually have loose ammo
		var has_ammo = false
		for item in ai_core.inventory.backpack_array:
			if item.id == "ammo_round" or item.id.begins_with("ammo_"):
				has_ammo = true
				break
		if not has_ammo: return 0.0
	
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	if my_idx == target_idx: return 0.2
	var distance = abs(my_idx - target_idx)
	return 0.7 + (distance * 0.02)

func _score_aimed_shot() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.AIMED_SHOT): return 0.0
	var weapon = ai_core.inventory.get_active_weapon(false) # Ranged context
	if weapon == null: return 0.0
	if weapon.weapon_type == GameEnums.WeaponClass.PISTOL and weapon.current_magazine <= 0: return 0.0
	if weapon.weapon_type == GameEnums.WeaponClass.RIFLE:
		if weapon.needs_cycling: return 0.0
		# Ensure they actually have loose ammo
		var has_ammo = false
		for item in ai_core.inventory.backpack_array:
			if item.id == "ammo_round" or item.id.begins_with("ammo_"):
				has_ammo = true
				break
		if not has_ammo: return 0.0
	
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	if my_idx == target_idx: return 0.1
	var distance = abs(my_idx - target_idx)
	return 0.85 + (distance * 0.01)

func _score_reload() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.RELOAD): return 0.0
	var weapon = ai_core.inventory.get_active_weapon(false) # Ranged context
	if weapon != null and weapon.weapon_type == GameEnums.WeaponClass.PISTOL and weapon.current_magazine <= 0:
		# AI must verify it actually has loose ammo or a magazine to avoid reload loops
		var has_ammo = false
		for item in ai_core.inventory.backpack_array:
			if item.id.ends_with("_magazine") or item.id == "magazine" or item.id.begins_with("ammo_"):
				has_ammo = true
				break
		if has_ammo:
			return 0.95
	return 0.0

func _score_cycle() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.CYCLE): return 0.0
	var weapon = ai_core.inventory.get_active_weapon(false) # Ranged context
	if weapon != null and weapon.weapon_type == GameEnums.WeaponClass.RIFLE and weapon.needs_cycling:
		return 0.95
	return 0.0

func _score_advance() -> float:
	var ap_cost = turn_manager.get_action_cost(ai_core, GameEnums.ActionType.MOVE_FORWARD)
	if turn_manager.current_ap_pool < ap_cost:
		return 0.0
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	var distance = abs(my_idx - target_idx)
	if distance <= 0:
		return 0.0 
	var weapon = ai_core.inventory.get_active_weapon(true) # Melee context
	if weapon != null:
		return 0.85
	return 0.4

func _score_retreat() -> float:
	if ai_core.is_mindless_hive_thrall: return 0.0 
	
	var my_idx = _get_lane_idx(ai_core)
	if my_idx >= 0 and lane_manager.lane_slots[my_idx].is_melee_locked:
		if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.DISENGAGE): return 0.0
	else:
		if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.MOVE_BACKWARD): return 0.0
		
	if ai_core.is_fleeing: return 10.0 
	if ai_core.current_stance == GameEnums.StanceState.STUMBLING: return 0.7
	return 0.1

func _score_execute() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.EXECUTE): return 0.0
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	if my_idx != target_idx: return 0.0
	if target_core.current_stance != GameEnums.StanceState.FELLED: return 0.0
	return 15.0

func _score_disengage() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.DISENGAGE): return 0.0
	var my_idx = _get_lane_idx(ai_core)
	if my_idx < 0 or not lane_manager.lane_slots[my_idx].is_melee_locked: return 0.0
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
	
	var grapple_cost = turn_manager.get_action_cost(ai_core, GameEnums.ActionType.GRAPPLE)
	var execute_cost = turn_manager.get_action_cost(ai_core, GameEnums.ActionType.EXECUTE)
	# If I have execute AP ready and can afford grapple
	if turn_manager.current_ap_pool >= (grapple_cost + execute_cost):
		return 0.85
	return 0.3

func _score_take_cover() -> float:
	if turn_manager.current_ap_pool < turn_manager.get_action_cost(ai_core, GameEnums.ActionType.TAKE_COVER): return 0.0
	var my_idx = _get_lane_idx(ai_core)
	if my_idx < 0: return 0.0
	var slot = lane_manager.lane_slots[my_idx]
	if slot.current_cover != GameEnums.TileObject.NONE and ai_core.current_stance == GameEnums.StanceState.PLANTED:
		return 0.6
	return 0.1

# ---------------------------------------------------------
# EXECUTION ROUTER (Active Turn)
# ---------------------------------------------------------

func _execute_action(action: int) -> void:
	match action:
		GameEnums.ActionType.STRIKE:
			if turn_manager.request_action(ai_core, GameEnums.ActionType.STRIKE):
				resolution_engine.execute_melee_strike(ai_core, target_core, GameEnums.LimbRegion.UPPER_TORSO)

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
			var target_idx = _get_lane_idx(target_core)
			var forward_dir = sign(target_idx - my_idx)
			if forward_dir == 0: forward_dir = 1
			
			if turn_manager.request_action(ai_core, GameEnums.ActionType.MOVE_FORWARD):
				if lane_manager.move_entity(ai_core, my_idx, my_idx + forward_dir):
					resolution_engine.check_hazard_trip(ai_core, lane_manager.lane_slots[my_idx + forward_dir], false)

		GameEnums.ActionType.MOVE_BACKWARD:
			var my_idx = _get_lane_idx(ai_core)
			var current_slot = lane_manager.lane_slots[my_idx]
			if current_slot.object_name == "Escape Zone":
				if turn_manager.request_action(ai_core, GameEnums.ActionType.MOVE_BACKWARD):
					print(ai_core.name, " hunkers down in the Escape Zone! (Must survive 1 turn to flee)")
					ai_core.is_escaping = true
					turn_manager.pass_turn(ai_core)
					return
			var target_idx = _get_lane_idx(target_core)
			var forward_dir = sign(target_idx - my_idx)
			if forward_dir == 0: forward_dir = 1
			
			if current_slot.is_melee_locked:
				if turn_manager.request_action(ai_core, GameEnums.ActionType.DISENGAGE):
					lane_manager.attempt_disengage(ai_core, my_idx, my_idx - forward_dir)
			else:
				if turn_manager.request_action(ai_core, GameEnums.ActionType.MOVE_BACKWARD):
					if lane_manager.move_entity(ai_core, my_idx, my_idx - forward_dir):
						resolution_engine.check_hazard_trip(ai_core, lane_manager.lane_slots[my_idx - forward_dir], false)

		GameEnums.ActionType.GRAPPLE:
			if turn_manager.request_action(ai_core, GameEnums.ActionType.GRAPPLE):
				resolution_engine.execute_grapple(ai_core, target_core)
				
		GameEnums.ActionType.EXECUTE:
			if turn_manager.request_action(ai_core, GameEnums.ActionType.EXECUTE):
				resolution_engine.execute_execute(ai_core, target_core)
				
		GameEnums.ActionType.TAKE_COVER:
			if turn_manager.request_action(ai_core, GameEnums.ActionType.TAKE_COVER):
				resolution_engine.execute_take_cover(ai_core)

	call_deferred("_process_action_loop")

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
	var tactic_multipliers = GameEnums.TACTIC_MULTIPLIERS.get(my_tactic, {})
	
	var best_reaction = -1
	var highest_score = 0.0
	
	for reaction in available_reactions:
		var base = 1.0 # Baseline validity
		var mult = 1.0
		
		if is_survival_crisis:
			mult = GameEnums.SURVIVAL_MULTIPLIERS.get(reaction, 1.0)
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
	var weapon = ai_core.inventory.get_active_weapon(true) # Check if we have melee
	var chose_follow: bool = false
	if weapon != null:
		chose_follow = true
		
	turn_manager.resolve_displacement_choice(ai_core, chose_follow)

func _get_lane_idx(entity: HumanoidCore) -> int:
	for i in range(lane_manager.lane_slots.size()):
		if lane_manager.lane_slots[i].occupants.has(entity): return i
	return -1
