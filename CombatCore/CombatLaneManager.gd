extends Node
class_name CombatLaneManager

signal disengage_failed(entity: HumanoidCore, opponent: HumanoidCore)

signal lane_changed

var lane_slots: Array[CombatLaneSlot] = []

@export var turn_manager: CombatTurnManager

func _ready() -> void:
	_initialize_lane()

func _initialize_lane() -> void:
	lane_slots.clear()
	for i in range(12):
		var slot = CombatLaneSlot.new(i)
		_configure_lane_slot(slot)
		lane_slots.append(slot)

func _configure_lane_slot(slot: CombatLaneSlot) -> void:
	match slot.lane_index:
		0, 11:
			slot.object_name = "Escape Zone"
			slot.configure_surface(
				"DIRT ROAD",
				CombatLaneSlot.DIRT_ROAD_ASSET,
				"ROAD: 0 trip modifier, clear retreat route"
			)
		1, 10:
			slot.configure_surface(
				"DIRT ROAD",
				CombatLaneSlot.DIRT_ROAD_ASSET,
				"ROAD: 0 trip modifier, fast visual route"
			)
		4:
			slot.current_cover = CombatRules.TileObject.COVER
			slot.object_name = "Supply Crates"
			slot.object_durability = 70.0
		5, 6:
			slot.background = CombatRules.TileBackground.MUD
			slot.is_spawnable = false
			slot.surface_note = "CENTER GRID: deployment blocked"
		7:
			slot.current_cover = CombatRules.TileObject.COVER
			slot.object_name = "Barricade"
			slot.object_durability = 120.0
		8:
			slot.current_cover = CombatRules.TileObject.OBSTACLE
			slot.object_name = "Rock Outcrop"
			slot.object_durability = 160.0

# --- MOVEMENT MATTERS ---

## The lane is an engagement line, not a transit tunnel. A combatant may enter
## an opponent's lane to start a Melee Lock, but cannot move from one side of
## an opponent to the other in a single relocation.
func can_move_entity_to(
	entity: HumanoidCore,
	from_idx: int,
	to_idx: int,
	allow_break_from_melee_lock: bool = false
) -> bool:
	refresh_lock_states()
	if entity == null or from_idx < 0 or from_idx >= lane_slots.size():
		return false
	if to_idx < 0 or to_idx >= lane_slots.size() or from_idx == to_idx:
		return false
	if _find_entity_lane(entity) != from_idx:
		return false

	var target_slot: CombatLaneSlot = lane_slots[to_idx]
	if is_entity_melee_locked(entity) and not allow_break_from_melee_lock:
		return false
	if target_slot.occupants.size() >= 2:
		return false
	if _would_cross_an_opponent(entity, from_idx, to_idx):
		return false
	return true

func move_entity(entity: HumanoidCore, from_idx: int, to_idx: int, is_charge: bool = false) -> bool:
	if not can_move_entity_to(entity, from_idx, to_idx):
		if is_entity_melee_locked(entity):
			print("Movement denied. Use PUSH to create space from the Melee Lock.")
		elif _would_cross_an_opponent(entity, from_idx, to_idx):
			print("Movement denied. Combatants cannot pass through one another.")
		return false

	if not _relocate_entity(entity, from_idx, to_idx):
		return false

	# THE GRAPPLE INTERCEPT: Check if a CHARGE ended directly adjacent to an enemy
	if is_charge and turn_manager:
		_check_charge_intercept(entity, to_idx)

	lane_changed.emit()
	return true

func _relocate_entity(
	entity: HumanoidCore,
	from_idx: int,
	to_idx: int,
	allow_break_from_melee_lock: bool = false
) -> bool:
	if not can_move_entity_to(
		entity,
		from_idx,
		to_idx,
		allow_break_from_melee_lock
	):
		print("Movement denied. Use PUSH to create space from the Melee Lock.")
		return false

	var origin_slot: CombatLaneSlot = lane_slots[from_idx]
	var target_slot: CombatLaneSlot = lane_slots[to_idx]
	if not target_slot.enter_slot(entity):
		return false
	origin_slot.exit_slot(entity)
	refresh_lock_states()
	return true

func refresh_lock_states() -> void:
	for slot in lane_slots:
		var locked := _slot_contains_hostile_pair(slot)
		slot.is_melee_locked = locked
		if not locked:
			slot.grapple_stance_scale = 12

func is_entity_melee_locked(entity: HumanoidCore) -> bool:
	var lane_idx := _find_entity_lane(entity)
	if lane_idx < 0:
		return false
	return _slot_contains_hostile_pair(lane_slots[lane_idx], entity)

func is_lane_melee_locked(lane_idx: int) -> bool:
	if lane_idx < 0 or lane_idx >= lane_slots.size():
		return false
	return _slot_contains_hostile_pair(lane_slots[lane_idx])

func _slot_contains_hostile_pair(
	slot: CombatLaneSlot,
	focus_entity: HumanoidCore = null
) -> bool:
	if slot == null or slot.occupants.size() < 2:
		return false
	var has_focus := focus_entity == null
	for occupant in slot.occupants:
		if occupant == focus_entity:
			has_focus = true
			break
	if not has_focus:
		return false

	for left_index in range(slot.occupants.size()):
		var left: HumanoidCore = slot.occupants[left_index]
		if left == null:
			continue
		for right_index in range(left_index + 1, slot.occupants.size()):
			var right: HumanoidCore = slot.occupants[right_index]
			if right == null:
				continue
			if left.definition.faction != right.definition.faction:
				return true
	return false

func _would_cross_an_opponent(
	entity: HumanoidCore,
	from_idx: int,
	to_idx: int
) -> bool:
	for slot in lane_slots:
		for occupant in slot.occupants:
			if occupant == entity or occupant.definition.faction == entity.definition.faction:
				continue
			var opponent_idx := slot.lane_index
			# Entering an opponent's lane starts a Melee Lock. Leaving a shared
			# lane is controlled by explicit displacement actions such as PUSH.
			if opponent_idx == from_idx or opponent_idx == to_idx:
				continue
			if (
				(from_idx < opponent_idx and to_idx > opponent_idx)
				or (from_idx > opponent_idx and to_idx < opponent_idx)
			):
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
							# Force the charger into the defender's slot to initiate the lock.
							if not move_entity(charger, charger_idx, adj_idx):
								return
							
							# Charge interception is a special momentum takedown.
							print("[INTERCEPT SUCCESS] ", occupant.name, " tackles ", charger.name, " mid-sprint!")
							charger.try_fell()
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
	if not _relocate_entity(target, init_idx, destination_idx, true):
		print("[DISPLACEMENT] ", target.name, " cannot be moved through an opponent.")
		return
	
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
			if not _relocate_entity(initiator, init_idx, destination_idx):
				print("[FOLLOW FAILED] The destination is no longer valid.")
				_break_lock_and_reset_stance(initiator, target)
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

# --- LEGACY LOCK EXIT CLAUSE ---

func attempt_disengage(entity: HumanoidCore, current_idx: int, retreat_idx: int) -> bool:
	if not can_move_entity_to(entity, current_idx, retreat_idx, true):
		return false

	var slot: CombatLaneSlot = lane_slots[current_idx]
	
	if not is_entity_melee_locked(entity):
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
		print("Legacy disengage successful. Kicked away from the grapple.")
		if not _relocate_entity(entity, current_idx, retreat_idx, true):
			return false
		_break_lock_and_reset_stance(entity, opponent)
		lane_changed.emit()
		return true
	else:
		print("Legacy disengage failed. Slipped in the mud.")
		if opponent:
			disengage_failed.emit(entity, opponent)
		return false

# --- SPAWN LOGIC ---

func force_spawn_entity(entity: HumanoidCore, target_idx: int) -> void:
	if target_idx < 0 or target_idx > 11:
		push_error("Spawn index out of bounds.")
		return
		
	var target_slot: CombatLaneSlot = lane_slots[target_idx]
	if target_slot.enter_slot(entity):
		refresh_lock_states()
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
