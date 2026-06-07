extends Node
class_name CombatTurnManager

# ---------------------------------------------------------
# SIGNALS: Broadcasting the flow of time
# ---------------------------------------------------------
signal round_started(round_number: int)
signal turn_started(active_entity: HumanoidCore)
signal ap_spent(entity: HumanoidCore, remaining_ap: int)
signal turn_ended(entity: HumanoidCore)

# Hardcoded Action Costs (You can move this to GameEnums later)
const COST = {
	"MOVE": 2,
	"MELEE_STRIKE": 4,
	"FIRE_WEAPON": 5,
	"DISENGAGE": 6, # Expensive because it's a desperate escape
	"RELOAD": 3,
	"USE_ITEM": 3
}

var combatants: Array[HumanoidCore] = []
var current_round: int = 0
var active_entity_index: int = 0

var current_ap_pool: int = 0

# ---------------------------------------------------------
# INITIALIZATION & ROUND LOOP
# ---------------------------------------------------------

func initialize_duel(combatant_array: Array[HumanoidCore], initiator: HumanoidCore = null) -> void:
	combatants = combatant_array
	
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
	print("========== ROUND ", current_round, " START ==========")
	
	# Force everyone to check their bleeding wounds and recalculate their AP limits
	for entity in combatants:
		# Note: We emit the signal in HumanoidCore to update this implicitly, 
		# but you can explicitly trigger a refresh here if needed.
		pass 
		
	active_entity_index = 0
	_start_turn()

func _start_turn() -> void:
	var active_entity: HumanoidCore = combatants[active_entity_index]
	
	# If they are dead, skipping their turn is usually the polite thing to do
	if active_entity.is_dead or active_entity.current_max_ap <= 0:
		print(active_entity.name, " is incapacitated. Skipping turn.")
		_end_turn()
		return
		
	# Fill their pockets with time
	current_ap_pool = active_entity.current_max_ap
	print("\n>>> ", active_entity.name, "'s turn begins with ", current_ap_pool, " AP.")
	turn_started.emit(active_entity)

# ---------------------------------------------------------
# THE GATEKEEPER
# ---------------------------------------------------------

## The overarching Game Loop must call this BEFORE executing any physical logic
func request_action(entity: HumanoidCore, action_name: String) -> bool:
	if entity != combatants[active_entity_index]:
		print("DENIED: It is not ", entity.name, "'s turn. Wait patiently.")
		return false
		
	if not COST.has(action_name):
		push_error("The action [" + action_name + "] does not exist in the timekeeper's ledger.")
		return false
		
	var ap_cost: int = COST[action_name]
	
	if current_ap_pool < ap_cost:
		print("DENIED: Insufficient AP for [", action_name, "]. Needs: ", ap_cost, " | Has: ", current_ap_pool)
		return false
		
	# Transaction Approved
	current_ap_pool -= ap_cost
	print("APPROVED: ", entity.name, " performed [", action_name, "]. Remaining AP: ", current_ap_pool)
	ap_spent.emit(entity, current_ap_pool)
	
	# Force an end if they are bankrupt
	if current_ap_pool <= 0:
		_end_turn()
		
	return true

## Can be manually triggered by a "Pass Turn" UI Button
func pass_turn(entity: HumanoidCore) -> void:
	if entity == combatants[active_entity_index]:
		print(entity.name, " intentionally passed their turn.")
		_end_turn()

func _end_turn() -> void:
	var active_entity: HumanoidCore = combatants[active_entity_index]
	print("<<< ", active_entity.name, "'s turn ended.")
	turn_ended.emit(active_entity)
	
	active_entity_index += 1
	
	# If everyone has gone, loop back around
	if active_entity_index >= combatants.size():
		start_new_round()
	else:
		_start_turn()
