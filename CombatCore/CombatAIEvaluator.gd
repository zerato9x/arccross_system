extends Node
class_name CombatAIEvaluator

@export var ai_core: HumanoidCore
@export var lane_manager: CombatLaneManager
@export var turn_manager: CombatTurnManager

var target_core: HumanoidCore

func _ready() -> void:
	# Wake the AI up when the clock says it's their turn
	turn_manager.turn_started.connect(_on_turn_started)

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
# THE COGNITIVE LOOP
# ---------------------------------------------------------

func _process_action_loop() -> void:
	# The AI keeps thinking and acting until it runs out of AP or ends its turn
	if ai_core.is_dead or turn_manager.current_ap_pool <= 0:
		return
		
	var best_action: int = _evaluate_tactics()
	
	if best_action == -1:
		turn_manager.pass_turn(ai_core)
		return
		
	# Attempt to execute the highest scoring idea
	_execute_action(best_action)

func _evaluate_tactics() -> String:
	var scores = {
		GameEnums.ActionType.STRIKE: _score_melee(),
		GameEnums.ActionType.SHOOT: _score_ranged(),
		GameEnums.ActionType.MOVE_FORWARD: _score_advance(),
		GameEnums.ActionType.MOVE_BACKWARD: _score_retreat(),
		GameEnums.ActionType.DISENGAGE: _score_disengage(),
		GameEnums.ActionType.EXECUTE: _score_execute(),
		-1: 0.1 # Baseline. If everything else scores worse than 0.1, just give up.
	}
	
	var best_action = -1
	var highest_score = 0.0
	
	for action in scores.keys():
		if scores[action] > highest_score:
			highest_score = scores[action]
			best_action = action
			
	print("[AI THINKING] Selected: ", best_action, " | Confidence: ", highest_score)
	return best_action

# ---------------------------------------------------------
# THE SCORING ALGORITHMS (0.0 to 1.0)
# ---------------------------------------------------------

func _score_melee() -> float:
	if turn_manager.current_ap_pool < turn_manager.COST[GameEnums.ActionType.STRIKE]: return 0.0
	
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	
	# If we share a grid (Melee Lock), stabbing them is a fantastic idea.
	if my_idx == target_idx:
		return 0.95
	return 0.0

func _score_ranged() -> float:
	if turn_manager.current_ap_pool < turn_manager.COST[GameEnums.ActionType.SHOOT]: return 0.0
	
	var weapon = ai_core.inventory.paper_doll[GameEnums.EquipmentSlot.HANDS]
	if weapon == null or not weapon.is_ranged(): return 0.0
	
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	
	# Don't shoot if trapped in a grapple, collateral is too risky unless desperate
	if my_idx == target_idx: return 0.2
	
	# If we have a gun and they are far away, shoot them.
	var distance = abs(my_idx - target_idx)
	return 0.8 + (distance * 0.02) # Higher score the further away they are

func _score_advance() -> float:
	if turn_manager.current_ap_pool < turn_manager.COST[GameEnums.ActionType.MOVE_FORWARD]: return 0.0
	
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	var distance = abs(my_idx - target_idx)
	
	if distance <= 1: return 0.0 # Already close enough
	
	# If AI has a melee weapon, it desperately wants to close the gap
	var weapon = ai_core.inventory.paper_doll[GameEnums.EquipmentSlot.HANDS]
	if weapon != null and weapon.is_melee():
		return 0.85
		
	return 0.4 # Default roaming curiosity

func _score_retreat() -> float:
	if ai_core.is_mindless_hive_thrall: 
		return 0.0 # Zombies don't retreat.
		
	if ai_core.is_fleeing:
		return 10.0 # Absolute priority override. Break the scale. Run.
	
	# STUMBLING entities are desperate to disengage and regroup
	if ai_core.current_stance == GameEnums.StanceState.STUMBLING:
		return 0.7
		
	return 0.0

func _score_execute() -> float:
	# Can only EXECUTE a FELLED target in the same grid
	if turn_manager.current_ap_pool < turn_manager.COST.get(GameEnums.ActionType.STRIKE, 4): return 0.0
	
	var my_idx = _get_lane_idx(ai_core)
	var target_idx = _get_lane_idx(target_core)
	
	if my_idx != target_idx: return 0.0
	if target_core.current_stance != GameEnums.StanceState.FELLED: return 0.0
	
	# If the target is face-down, this is the highest priority action in the game
	return 15.0
func _score_disengage() -> float:
	if turn_manager.current_ap_pool < turn_manager.COST[GameEnums.ActionType.DISENGAGE]: return 0.0
	
	var my_idx = _get_lane_idx(ai_core)
	if not lane_manager.lane_slots[my_idx].is_melee_locked: return 0.0
	
	# If I am a sniper trapped in a Melee Lock, I need to get out immediately.
	var weapon = ai_core.inventory.paper_doll[GameEnums.EquipmentSlot.HANDS]
	if weapon != null and weapon.is_ranged():
		return 0.90
		
	return 0.0

# ---------------------------------------------------------
# EXECUTION ROUTER
# ---------------------------------------------------------

func _execute_action(action: int) -> void:
	match action:
		# ... [Advance, Strike, Disengage logic stays the same] ...
		
		GameEnums.ActionType.MOVE_BACKWARD:
			var my_idx = _get_lane_idx(ai_core)
			var current_slot = lane_manager.lane_slots[my_idx]
			
			# 1. Am I already in the Escape Zone?
			if current_slot.object_name == "Escape Zone":
				if turn_manager.request_action(ai_core, GameEnums.ActionType.MOVE_BACKWARD): # Spend AP to physically flee the map
					print("\n>>> ", ai_core.name, " HAS SUCCESSFULLY ESCAPED THE BATTLEFIELD! <<<")
					current_slot.exit_slot(ai_core)
					turn_manager.current_ap_pool = 0 # Force turn end
					# NOTE: You would emit a signal here to tell the Macro Map to cache this entity and close the scene.
				return
				
			# 2. I need to run toward the closest Escape Zone
			var target_escape_idx = 0 if my_idx < 6 else 11
			var step = -1 if target_escape_idx < my_idx else 1
			
			# If locked in Melee, they MUST disengage first before running
			if current_slot.is_melee_locked:
				print(ai_core.name, " is panicking and violently trying to tear away from the Melee Lock!")
				if turn_manager.request_action(ai_core, GameEnums.ActionType.DISENGAGE):
					lane_manager.attempt_disengage(ai_core, my_idx, my_idx + step)
			else:
				if turn_manager.request_action(ai_core, GameEnums.ActionType.MOVE_BACKWARD):
					lane_manager.move_entity(ai_core, my_idx, my_idx + step)

	call_deferred("_process_action_loop")

func _get_lane_idx(entity: HumanoidCore) -> int:
	for i in range(lane_manager.lane_slots.size()):
		if lane_manager.lane_slots[i].occupants.has(entity): return i
	return -1
