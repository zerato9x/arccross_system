extends Node
class_name CombatLaneManager

signal lane_changed

var lane_slots: Array[CombatLaneSlot] = []

@export var turn_manager: CombatTurnManager

func _ready() -> void:
	_initialize_lane()

func _initialize_lane() -> void:
	for i in range(12):
		var slot = CombatLaneSlot.new(i)
		
		# Define the geography of the lane
		if i == 0 or i == 11:
			slot.object_name = "Escape Zone"
		elif i == 5 or i == 6:
			slot.is_spawnable = false
			
		lane_slots.append(slot)

# --- MOVEMENT MATTERS ---

func move_entity(entity: HumanoidCore, from_idx: int, to_idx: int, is_charge: bool = false) -> bool:
	if to_idx < 0 or to_idx > 11:
		return false
		
	var origin_slot: CombatLaneSlot = lane_slots[from_idx]
	var target_slot: CombatLaneSlot = lane_slots[to_idx]
	
	if origin_slot.is_melee_locked:
		print("Movement denied. You must explicitly 'Disengage' from the Melee Lock.")
		return false
	
	# Check if the path is obstructed by a trap/obstacle or if it's a hazard that trips them
	# We assume the resolution engine handles the actual Trip check right after this succeeds,
	# but we can return true indicating the movement occurred (even if they fell).
		
	if target_slot.enter_slot(entity):
		origin_slot.exit_slot(entity)
		
		# THE GRAPPLE INTERCEPT: Check if a CHARGE ended directly adjacent to an enemy
		if is_charge and turn_manager:
			_check_charge_intercept(entity, to_idx)
		
		lane_changed.emit()
		return true
		
	return false

func _check_charge_intercept(charger: HumanoidCore, charger_idx: int) -> void:
	# Check cells directly adjacent (distance = 1)
	var adjacent_indices = [charger_idx - 1, charger_idx + 1]
	for adj_idx in adjacent_indices:
		if adj_idx >= 0 and adj_idx <= 11:
			var slot = lane_slots[adj_idx]
			if slot.occupants.size() > 0:
				for occupant in slot.occupants:
					if occupant != charger and occupant.definition.faction != charger.definition.faction:
						print("\n[CHARGE INTERCEPT OPPORTUNITY] ", charger.name, " charged and ended adjacent to ", occupant.name, "!")
						# Check if the defender wants to spend 6 AP to intercept
						if turn_manager.request_grapple_intercept(occupant, charger):
							# Force the charger into the defender's slot to initiate the lock
							lane_slots[charger_idx].exit_slot(charger)
							slot.enter_slot(charger)
							
							# Charge interception is a special momentum takedown.
							print("[INTERCEPT SUCCESS] ", occupant.name, " tackles ", charger.name, " mid-sprint!")
							charger.stance_points = 0
							charger._evaluate_stance_state()
							occupant.apply_stance_damage(3.0)
						return

# --- DISPLACEMENT: STAY / FOLLOW / SHOVE CUSHION ---

func resolve_displacement(
	initiator: HumanoidCore,
	target: HumanoidCore,
	displacement_direction: int,
	chose_follow: bool,
	action_name: String = "PUSH"
) -> void:
	var init_idx = _find_entity_lane(initiator)
	var target_idx = _find_entity_lane(target)
	
	if init_idx != target_idx or init_idx == -1:
		return
	
	var destination_idx = target_idx + displacement_direction
	
	# Bounds check
	if destination_idx < 0 or destination_idx > 11:
		print("[DISPLACEMENT] ", target.name, " has nowhere to go.")
		return
	
	# BRACED STATE CHECK (The Shove Cushion)
	# Check if an ally of the target is directly behind them
	var braced_ally = _get_braced_ally(target, destination_idx)
	if braced_ally != null:
		print("\n[SHOVE CUSHION] ", braced_ally.name, " braces ", target.name, "! Displacement stopped.")
		
		# Both friendly units take minor blunt collision trauma
		target.body.apply_targeted_hit(GameEnums.LimbRegion.UPPER_TORSO, 0.5, 0.0)
		braced_ally.body.apply_targeted_hit(GameEnums.LimbRegion.UPPER_TORSO, 0.5, 0.0)
		
		# Lock is maintained because target didn't move
		return
		
	# Move the target
	var movement_verb := "dragged" if action_name == "PULL" else "shoved"
	print("\n[", action_name, "] ", target.name, " is ", movement_verb, " into Lane Slot ", destination_idx)
	lane_slots[init_idx].exit_slot(target)
	lane_slots[destination_idx].enter_slot(target)
	
	if chose_follow:
		# Check if target has a Backup Braced ally that disables FOLLOW
		var disabled_by_backup = false
		var backup_idx = destination_idx + displacement_direction
		if backup_idx >= 0 and backup_idx <= 11:
			var deep_backup_ally = _get_braced_ally(target, backup_idx)
			if deep_backup_ally != null:
				disabled_by_backup = true
				print("[BACKUP PASSIVE] ", deep_backup_ally.name, " is maintaining rear support. FOLLOW denied.")
		
		if not disabled_by_backup:
			print("[FOLLOW] ", initiator.name, " follows to maintain the Melee Lock.")
			lane_slots[init_idx].exit_slot(initiator)
			lane_slots[destination_idx].enter_slot(initiator)
		else:
			print("[FOLLOW FAILED] The Lock shatters.")
			_break_lock_and_reset_stance(initiator, target)
	else:
		print("[STAY] ", initiator.name, " drops anchor. The Melee Lock shatters.")
		_break_lock_and_reset_stance(initiator, target)
	
	lane_changed.emit()

func _get_braced_ally(front_entity: HumanoidCore, backup_idx: int) -> HumanoidCore:
	if backup_idx < 0 or backup_idx > 11:
		return null
	var slot = lane_slots[backup_idx]
	for occupant in slot.occupants:
		if occupant.definition.faction == front_entity.definition.faction:
			return occupant
	return null

func _break_lock_and_reset_stance(initiator: HumanoidCore, target: HumanoidCore) -> void:
	initiator.reset_stance()
	target.reset_stance()
	print("[LOCK BROKEN] Spatial separation achieved. Stances restored to 12.")

# --- THE MELEE HOTEL EXIT CLAUSE ---

func attempt_disengage(entity: HumanoidCore, current_idx: int, retreat_idx: int) -> bool:
	var slot: CombatLaneSlot = lane_slots[current_idx]
	
	if not slot.is_melee_locked:
		return move_entity(entity, current_idx, retreat_idx)
		
	# Find the opponent in the mud with you
	var opponent: HumanoidCore = null
	for occ in slot.occupants:
		if occ != entity:
			opponent = occ
			break
			
	# The Math: Your physical condition vs their Stance
	var escape_roll: float = randf() * entity.current_max_ap
	var upper_torso_max := opponent.body.get_limb_max(
		GameEnums.LimbRegion.UPPER_TORSO
	)
	var enemy_grip: float = (
		opponent.body.limb_hp[GameEnums.LimbRegion.UPPER_TORSO]
		/ upper_torso_max
	) * 5.0
	
	if escape_roll > enemy_grip:
		print("Disengage successful! Kicked away from the grapple.")
		slot.exit_slot(entity)
		lane_slots[retreat_idx].enter_slot(entity)
		_break_lock_and_reset_stance(entity, opponent)
		lane_changed.emit()
		return true
	else:
		print("Disengage failed! Slipped in the mud. Reaction Strike window opened.")
		# Note: deduct AP and trigger enemy counter-attack here later
		return false

# --- SPAWN LOGIC ---

func force_spawn_entity(entity: HumanoidCore, target_idx: int) -> void:
	if target_idx < 0 or target_idx > 11:
		push_error("Spawn index out of bounds.")
		return
		
	var target_slot: CombatLaneSlot = lane_slots[target_idx]
	if target_slot.enter_slot(entity):
		print(entity.name, " materialized in Lane Slot ", target_idx)
		lane_changed.emit()
	else:
		push_error("Failed to spawn " + entity.name + " into slot " + str(target_idx))

func remove_entity(entity: HumanoidCore) -> void:
	for slot in lane_slots:
		if slot.occupants.has(entity):
			slot.exit_slot(entity)
			lane_changed.emit()
			return

func _find_entity_lane(entity: HumanoidCore) -> int:
	for i in range(lane_slots.size()):
		if lane_slots[i].occupants.has(entity): return i
	return -1
