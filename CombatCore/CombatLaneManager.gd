extends Node
class_name CombatLaneManager

var lane_slots: Array[CombatLaneSlot] = []

func _ready() -> void:
	_initialize_lane()

func _initialize_lane() -> void:
	for i in range(12):
		var slot = CombatLaneSlot.new(i)
		
		# Define the geography of the lane
		if i == 0 or i == 11:
			slot.object_name = "Escape Zone"
		elif i == 5 or i == 6:
			slot.object_name = "No Man's Void"
			slot.is_spawnable = false
			
		lane_slots.append(slot)

# --- MOVEMENT MATTERS ---

func move_entity(entity: HumanoidCore, from_idx: int, to_idx: int) -> bool:
	if to_idx < 0 or to_idx > 11:
		return false
		
	var origin_slot: CombatLaneSlot = lane_slots[from_idx]
	var target_slot: CombatLaneSlot = lane_slots[to_idx]
	
	# THE FIX: If you are in a Melee Lock, you can't just walk away.
	if origin_slot.is_melee_locked:
		print("Movement denied. You must explicitly 'Disengage' from the Melee Lock.")
		return false
		
	if target_slot.enter_slot(entity):
		origin_slot.exit_slot(entity)
		return true
		
	return false

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
	# A bleeding guy with 2 AP shouldn't easily push off a healthy Raider
	var escape_roll: float = randf() * entity.current_max_ap
	var enemy_grip: float = (opponent.body.limb_hp[GameEnums.Limb.TORSO] / 100.0) * 5.0
	
	if escape_roll > enemy_grip:
		print("Disengage successful! Kicked away from the grapple.")
		slot.exit_slot(entity)
		lane_slots[retreat_idx].enter_slot(entity)
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
	else:
		push_error("Failed to spawn " + entity.name + " into slot " + str(target_idx))
