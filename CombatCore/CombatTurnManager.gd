extends Node
class_name CombatTurnManager

# ---------------------------------------------------------
# SIGNALS: Broadcasting the flow of time
# ---------------------------------------------------------
signal round_started(round_number: int)
signal turn_started(active_entity: HumanoidCore)
signal ap_spent(entity: HumanoidCore, remaining_ap: int)
signal turn_ended(entity: HumanoidCore)
signal entity_escaped(entity: HumanoidCore)

## Reaction Window Signals — clean hooks for animation systems.
## Emitted when a reaction window opens. The UI/animation layer listens to present choices.
signal reaction_window_opened(defender: HumanoidCore, attacker: HumanoidCore, trigger_action: GameEnums.ActionType, available_reactions: Array)
## Emitted when a reaction is resolved (defender chose an option or window expired).
signal reaction_resolved(defender: HumanoidCore, chosen_reaction: GameEnums.ActionType, success: bool)
## Emitted specifically for displacement follow-up choices (STAY/FOLLOW).
signal displacement_choice_opened(initiator: HumanoidCore, displaced_entity: HumanoidCore)
signal displacement_choice_resolved(initiator: HumanoidCore, chose_follow: bool)

# ---------------------------------------------------------
# AP COST LEDGER (Spec-Accurate)
# ---------------------------------------------------------
# GET_UP and TRIP are marked -1 to flag "ALL remaining AP" consumption.
const COST_ALL_AP: int = -1

const ACTION_CATEGORIES = {
	# --- Non-Duel (Approach Phase) ---
	GameEnums.ActionType.MOVE_FORWARD: GameEnums.ActionCategory.MINOR,
	GameEnums.ActionType.MOVE_BACKWARD: GameEnums.ActionCategory.MINOR,
	GameEnums.ActionType.CHARGE: GameEnums.ActionCategory.HEAVY,
	GameEnums.ActionType.SHOOT: GameEnums.ActionCategory.MAJOR,
	GameEnums.ActionType.AIMED_SHOT: GameEnums.ActionCategory.HEAVY,
	GameEnums.ActionType.CYCLE: GameEnums.ActionCategory.QUICK,
	GameEnums.ActionType.RELOAD: GameEnums.ActionCategory.MINOR,
	GameEnums.ActionType.OBJ_INTERACT: GameEnums.ActionCategory.MAJOR,
	GameEnums.ActionType.USE_ITEM: GameEnums.ActionCategory.MINOR,
	GameEnums.ActionType.TAKE_COVER: GameEnums.ActionCategory.MAJOR,
	# --- Duel-Locked (Melee Lock) ---
	GameEnums.ActionType.STRIKE: GameEnums.ActionCategory.MAJOR,
	GameEnums.ActionType.GRAPPLE: GameEnums.ActionCategory.HEAVY,
	GameEnums.ActionType.PUSH_STAY: GameEnums.ActionCategory.MAJOR,
	GameEnums.ActionType.PUSH_FOLLOW: GameEnums.ActionCategory.MAJOR,
	GameEnums.ActionType.PULL_FOLLOW: GameEnums.ActionCategory.MAJOR,
	GameEnums.ActionType.PULL_STAY: GameEnums.ActionCategory.MAJOR,
	GameEnums.ActionType.BREAK: GameEnums.ActionCategory.MAJOR,
	GameEnums.ActionType.DISENGAGE: GameEnums.ActionCategory.HEAVY,
	# --- Prone Window ---
	GameEnums.ActionType.TRIP: GameEnums.ActionCategory.ALL_AP,
	GameEnums.ActionType.GET_UP: GameEnums.ActionCategory.ALL_AP,
	GameEnums.ActionType.EXECUTE: GameEnums.ActionCategory.MINOR,
	# --- Reactions (Off-Turn, consume leftover AP) ---
	GameEnums.ActionType.BLOCK: GameEnums.ActionCategory.MINOR,
	GameEnums.ActionType.DODGE: GameEnums.ActionCategory.MINOR,
	GameEnums.ActionType.STAY: GameEnums.ActionCategory.FREE,
	GameEnums.ActionType.FOLLOW: GameEnums.ActionCategory.FREE,
}

func get_action_cost(entity: HumanoidCore, action: GameEnums.ActionType) -> int:
	if not ACTION_CATEGORIES.has(action): return 0
	
	var category = ACTION_CATEGORIES[action]
	var tier = entity.kinetic_tier
	
	match category:
		GameEnums.ActionCategory.QUICK:
			if tier == GameEnums.KineticTier.FLUID: return 1
			if tier == GameEnums.KineticTier.LABORED: return 2
			return 3
		GameEnums.ActionCategory.MINOR:
			if tier == GameEnums.KineticTier.FLUID: return 2
			if tier == GameEnums.KineticTier.LABORED: return 3
			return 4
		GameEnums.ActionCategory.MAJOR:
			if tier == GameEnums.KineticTier.FLUID: return 3
			if tier == GameEnums.KineticTier.LABORED: return 4
			return 6
		GameEnums.ActionCategory.HEAVY:
			if tier == GameEnums.KineticTier.FLUID: return 4
			if tier == GameEnums.KineticTier.LABORED: return 6
			return 12
		GameEnums.ActionCategory.FREE:
			return 0
		GameEnums.ActionCategory.ALL_AP:
			return COST_ALL_AP
			
	return 0

# ---------------------------------------------------------
# STATE TRACKING
# ---------------------------------------------------------
var combatants: Array[HumanoidCore] = []
var current_round: int = 0
var active_entity_index: int = 0

var current_ap_pool: int = 0

## Leftover AP from each entity's last active turn. Used for off-turn reactions.
## Key = HumanoidCore, Value = int (unspent AP carried forward for defensive reactions).
var reserved_ap: Dictionary = {}

## Tracks whether a reaction window is currently active (blocks further actions until resolved).
var _reaction_pending: bool = false

## Stops the turn cycle from continuing (used when waiting for next mob spawn or duel resolution).
var is_halted: bool = false

## Prevents double-deferrals of _end_turn if an action hits 0 AP and triggers a pass simultaneously.
var _is_turn_ending: bool = false

# Lane reference for ActionGroup validation
var lane_manager: CombatLaneManager

# ---------------------------------------------------------
# INITIALIZATION & ROUND LOOP
# ---------------------------------------------------------

func initialize_duel(combatant_array: Array[HumanoidCore], initiator: HumanoidCore = null) -> void:
	combatants = combatant_array
	
	# Initialize reserved AP pools
	for entity in combatants:
		reserved_ap[entity] = 0
	
	if initiator and combatants.has(initiator):
		# Force the initiator to be index 0
		active_entity_index = combatants.find(initiator)
		print("INITIATIVE OVERRIDE: ", initiator.name, " dictates the engagement!")
	else:
		# Standard fallback: You would roll Dexterity + Weight penalty here
		active_entity_index = 0 
		print("NEUTRAL INITIATIVE: Standard combat order applied.")
		
	start_new_round()

func start_new_round() -> void:
	current_round += 1
	
	# --- FAILSAFE: Prevent infinite loop crashes ---
	if current_round > 1000:
		print("\n[CRITICAL ERROR] Combat exceeded 1000 rounds! Halting engine to prevent PC crash.")
		push_error("Infinite loop detected in CombatTurnManager. Forcing engine pause.")
		get_tree().paused = true
		halt_loop()
		return
		
	print("========== ROUND ", current_round, " START ==========")
	
	active_entity_index = 0
	_start_turn()

func _start_turn() -> void:
	if is_halted: return
	
	_is_turn_ending = false
	
	if combatants.size() == 0: return
	
	var active_entity: HumanoidCore = combatants[active_entity_index]
	
	if active_entity.is_escaping:
		var my_idx = _find_entity_lane(active_entity)
		if my_idx >= 0 and lane_manager.lane_slots[my_idx].object_name == "Escape Zone":
			print("\n[ESCAPE SUCCESS] ", active_entity.name, " has survived the wait and vanished from the battlefield!")
			lane_manager.lane_slots[my_idx].exit_slot(active_entity)
			escape_combat(active_entity)
			return
		else:
			print("\n[ESCAPE INTERRUPTED] ", active_entity.name, " was displaced from the Escape Zone! They must fight!")
			active_entity.is_escaping = false
	
	# If they are dead or comatose, skipping their turn is usually the polite thing to do
	if active_entity.is_dead or active_entity.current_max_ap <= 0 or active_entity.is_comatose:
		print(active_entity.name, " is incapacitated/comatose. Skipping turn.")
		if _is_everyone_incapacitated():
			await get_tree().create_timer(0.1).timeout
		_trigger_end_turn()
		return
		
	# Enforce the mandatory Felled stun lock penalty
	# At the start of its skipped turn, it passively recovers 6 Stance Points (→ STUMBLING) and ends.
	if active_entity.current_stance == GameEnums.StanceState.FELLED:
		print("\n[STUNNED] ", active_entity.name, " is face-down in the mud. Skipping turn and recovering equilibrium.")
		active_entity.recover_stance(6, true) # Force bypass the FELLED guard
		reserved_ap[active_entity] = 0 # No leftover AP when you're face down
		if _is_everyone_incapacitated():
			await get_tree().create_timer(0.1).timeout
		_trigger_end_turn()
		return
		
	# Fill their pockets with time
	current_ap_pool = active_entity.current_max_ap
	print("\n>>> ", active_entity.name, "'s turn begins with ", current_ap_pool, " AP.")
	turn_started.emit(active_entity)

# ---------------------------------------------------------
# THE GATEKEEPER (Active Turn Actions)
# ---------------------------------------------------------

## The overarching Game Loop must call this BEFORE executing any physical logic
func request_action(entity: HumanoidCore, action: GameEnums.ActionType) -> bool:
	if _reaction_pending:
		print("DENIED: A reaction window is active. Resolve it first.")
		return false
	
	if entity != combatants[active_entity_index]:
		print("DENIED: It is not ", entity.name, "'s turn. Wait patiently.")
		return false
		
	if not ACTION_CATEGORIES.has(action):
		push_error("The action [" + str(action) + "] does not exist in the timekeeper's ledger.")
		return false
	
	# Reactions cannot be used during your own active turn via request_action
	if GameEnums.ACTION_GROUPS.has(action) and GameEnums.ACTION_GROUPS[action] == GameEnums.ActionGroup.REACTION:
		print("DENIED: [", action, "] is a reaction. It can only be triggered during an opponent's turn.")
		return false
	
	# ActionGroup enforcement: validate the action is legal for the entity's current spatial context
	if lane_manager and GameEnums.ACTION_GROUPS.has(action):
		var required_group: GameEnums.ActionGroup = GameEnums.ACTION_GROUPS[action]
		var entity_lane_idx: int = _find_entity_lane(entity)
		var is_locked: bool = entity_lane_idx >= 0 and lane_manager.lane_slots[entity_lane_idx].is_melee_locked
		
		# Prone Window: must be FELLED to use these (except EXECUTE which targets FELLED opponents)
		if required_group == GameEnums.ActionGroup.PRONE_WINDOW:
			if action == GameEnums.ActionType.GET_UP or action == GameEnums.ActionType.TRIP:
				if entity.current_stance != GameEnums.StanceState.FELLED:
					print("DENIED: [", action, "] requires the entity to be FELLED.")
					return false
			elif action == GameEnums.ActionType.EXECUTE:
				# EXECUTE requires the EXECUTIONER to be standing/stumbling and target to be FELLED in same slot
				pass # Validation handled by resolution engine
		
		if required_group == GameEnums.ActionGroup.DUEL_LOCKED and not is_locked:
			print("DENIED: [", action, "] requires a Melee Lock. ", entity.name, " is not engaged.")
			return false
		if required_group == GameEnums.ActionGroup.NON_DUEL and is_locked:
			# Movement is blocked while locked; you must DISENGAGE first
			# SHOOT and CYCLE are explicitly blocked in Duel Lock per spec
			if action != GameEnums.ActionType.USE_ITEM:
				print("DENIED: [", action, "] is not available during a Melee Lock. Disengage first.")
				return false
		
	var ap_cost: int = get_action_cost(entity, action)
	
	# Handle ALL AP cost actions (GET_UP, TRIP)
	if ap_cost == COST_ALL_AP:
		if current_ap_pool <= 0:
			print("DENIED: [", action, "] requires AP but the pool is empty.")
			return false
		ap_cost = current_ap_pool # Consume everything
	
	if current_ap_pool < ap_cost:
		print("DENIED: Insufficient AP for [", action, "]. Needs: ", ap_cost, " | Has: ", current_ap_pool)
		return false
		
	# Transaction Approved
	current_ap_pool -= ap_cost
	print("APPROVED: ", entity.name, " performed [", action, "]. Remaining AP: ", current_ap_pool)
	ap_spent.emit(entity, current_ap_pool)
	
	# Force an end if they are bankrupt
	if current_ap_pool <= 0:
		_trigger_end_turn()
		
	return true

# ---------------------------------------------------------
# REACTION WINDOW SYSTEM (Off-Turn Defensive Actions)
# ---------------------------------------------------------
# Reactions consume from the defender's LEFTOVER AP (reserved_ap).
# If they spent all 12 AP on their turn, they cannot react at all.

## Opens a reaction window for a defending entity. Returns available reaction types.
## The UI/animation system should listen to reaction_window_opened and present choices.
func open_reaction_window(defender: HumanoidCore, attacker: HumanoidCore, trigger_action: GameEnums.ActionType) -> Array:
	var available: Array = []
	var defender_ap: int = reserved_ap.get(defender, 0)
	
	if defender.is_dead or defender.current_stance == GameEnums.StanceState.FELLED:
		return available
	
	# BLOCK: Only against STRIKE, requires shield or functional arms
	if trigger_action == GameEnums.ActionType.STRIKE:
		if defender_ap >= get_action_cost(defender, GameEnums.ActionType.BLOCK):
			if defender.body.has_functional_arms():
				available.append(GameEnums.ActionType.BLOCK)
	
	# DODGE: Against both ranged (SHOOT) and melee (STRIKE) attacks
	# Disabled if either leg is destroyed (The Cripple Clause)
	if trigger_action == GameEnums.ActionType.STRIKE or trigger_action == GameEnums.ActionType.SHOOT:
		if defender_ap >= get_action_cost(defender, GameEnums.ActionType.DODGE):
			var left_leg_ok: bool = defender.body.limb_hp[GameEnums.LimbRegion.LEFT_LEG] > 0
			var right_leg_ok: bool = defender.body.limb_hp[GameEnums.LimbRegion.RIGHT_LEG] > 0
			if left_leg_ok and right_leg_ok:
				available.append(GameEnums.ActionType.DODGE)
	
	if available.size() > 0:
		_reaction_pending = true
		print("\n[REACTION WINDOW] ", defender.name, " can react! Available: ", available, " | Reserved AP: ", defender_ap)
		reaction_window_opened.emit(defender, attacker, trigger_action, available)
	
	return available

## Called by the UI/AI when a reaction choice is made.
func resolve_reaction(defender: HumanoidCore, chosen_reaction: GameEnums.ActionType) -> bool:
	_reaction_pending = false
	
	if chosen_reaction == GameEnums.ActionType.BLOCK or chosen_reaction == GameEnums.ActionType.DODGE:
		var cost: int = get_action_cost(defender, chosen_reaction)
		var defender_ap: int = reserved_ap.get(defender, 0)
		
		if defender_ap < cost:
			print("[REACTION] ", defender.name, " cannot afford [", chosen_reaction, "]. AP: ", defender_ap)
			reaction_resolved.emit(defender, chosen_reaction, false)
			return false
		
		reserved_ap[defender] -= cost
		print("[REACTION] ", defender.name, " spent ", cost, " reserved AP on [", chosen_reaction, "]. Remaining reserved: ", reserved_ap[defender])
		reaction_resolved.emit(defender, chosen_reaction, true)
		return true
	
	# STAY/FOLLOW are free (0 AP) — always succeed
	if chosen_reaction == GameEnums.ActionType.STAY or chosen_reaction == GameEnums.ActionType.FOLLOW:
		print("[REACTION] ", defender.name, " chose [", chosen_reaction, "] (free action).")
		reaction_resolved.emit(defender, chosen_reaction, true)
		return true
	
	reaction_resolved.emit(defender, chosen_reaction, false)
	return false

## Called when the defender declines to react or the window times out.
func skip_reaction(defender: HumanoidCore) -> void:
	_reaction_pending = false
	print("[REACTION] ", defender.name, " declined to react.")
	reaction_resolved.emit(defender, -1, false)

## Opens a displacement follow-up choice window (STAY or FOLLOW) for the initiator.
func open_displacement_choice(initiator: HumanoidCore, displaced_entity: HumanoidCore) -> void:
	_reaction_pending = true
	print("\n[DISPLACEMENT] ", initiator.name, " must choose: STAY (break lock) or FOLLOW (maintain lock).")
	displacement_choice_opened.emit(initiator, displaced_entity)

## Resolves a STAY/FOLLOW choice after a successful push/pull.
func resolve_displacement_choice(initiator: HumanoidCore, chose_follow: bool) -> void:
	_reaction_pending = false
	displacement_choice_resolved.emit(initiator, chose_follow)

## Request a Grapple Intercept reaction (HEAVY AP) triggered when CHARGE ends adjacent.
func request_grapple_intercept(defender: HumanoidCore, charger: HumanoidCore) -> bool:
	var defender_ap: int = reserved_ap.get(defender, 0)
	var cost = get_action_cost(defender, GameEnums.ActionType.GRAPPLE)
	if defender_ap < cost:
		print("[INTERCEPT] ", defender.name, " cannot afford GRAPPLE intercept (needs ", cost, ", has ", defender_ap, ").")
		return false
	
	reserved_ap[defender] -= cost
	print("[INTERCEPT] ", defender.name, " spends ", cost, " reserved AP to GRAPPLE intercept ", charger.name, "!")
	return true



# ---------------------------------------------------------
# TURN LIFECYCLE
# ---------------------------------------------------------

## Can be manually triggered by a "Pass Turn" UI Button
func pass_turn(entity: HumanoidCore) -> void:
	if entity == combatants[active_entity_index]:
		print(entity.name, " intentionally passed their turn.")
		_trigger_end_turn()

func _trigger_end_turn() -> void:
	if _is_turn_ending: return
	_is_turn_ending = true
	call_deferred("_end_turn")

func _end_turn() -> void:
	var active_entity: HumanoidCore = combatants[active_entity_index]
	
	# Bank leftover AP for reaction use during opponents' turns
	reserved_ap[active_entity] = current_ap_pool
	if current_ap_pool > 0:
		print("[RESERVED] ", active_entity.name, " banks ", current_ap_pool, " AP for defensive reactions.")
	
	print("<<< ", active_entity.name, "'s turn ended.")
	turn_ended.emit(active_entity)
	
	active_entity_index += 1
	
	# If everyone has gone, loop back around
	if active_entity_index >= combatants.size():
		call_deferred("start_new_round")
	else:
		call_deferred("_start_turn")

func escape_combat(entity: HumanoidCore) -> void:
	if combatants.has(entity):
		var idx = combatants.find(entity)
		combatants.erase(entity)
		print("[TURN MANAGER] ", entity.name, " has been removed from the turn order.")
		entity_escaped.emit(entity)
		
		if combatants.size() <= 1:
			pass # Duel is over, MainDuelScene will handle it.
		elif active_entity_index > idx:
			active_entity_index -= 1 # Shift index to prevent skipping

func halt_loop() -> void:
	is_halted = true

func resume_loop() -> void:
	is_halted = false
	call_deferred("_start_turn")

# ---------------------------------------------------------
# UTILITY
# ---------------------------------------------------------

func _find_entity_lane(entity: HumanoidCore) -> int:
	if not lane_manager: return -1
	for i in range(lane_manager.lane_slots.size()):
		if lane_manager.lane_slots[i].occupants.has(entity): return i
	return -1

## Get the active entity for this turn.
func get_active_entity() -> HumanoidCore:
	if active_entity_index < combatants.size():
		return combatants[active_entity_index]
	return null

func _is_everyone_incapacitated() -> bool:
	if combatants.size() == 0:
		return true
	for entity in combatants:
		if not entity.is_dead and entity.current_max_ap > 0 and not entity.is_comatose and entity.current_stance != GameEnums.StanceState.FELLED:
			return false
	return true
