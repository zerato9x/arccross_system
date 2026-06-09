extends Node
class_name CombatCommandAdapter

signal snapshot_changed(snapshot: Dictionary)
signal reaction_requested(prompt: Dictionary)
signal command_feedback(message: String)

var player_core: HumanoidCore
var enemy_core: HumanoidCore
var lane_manager: CombatLaneManager
var turn_manager: CombatTurnManager
var resolution_engine: CombatResolutionEngine

var _action_in_progress: bool = false
var _available_reactions: Array = []
var _player_forward_direction: int = 1

const STRIKE_LIMBS := [
	GameEnums.LimbRegion.UPPER_TORSO,
	GameEnums.LimbRegion.LOWER_TORSO,
	GameEnums.LimbRegion.LEFT_ARM,
	GameEnums.LimbRegion.RIGHT_ARM,
	GameEnums.LimbRegion.LEFT_LEG,
	GameEnums.LimbRegion.RIGHT_LEG,
]

const AIMED_LIMBS := [
	GameEnums.LimbRegion.HEAD,
	GameEnums.LimbRegion.UPPER_TORSO,
	GameEnums.LimbRegion.LOWER_TORSO,
	GameEnums.LimbRegion.LEFT_ARM,
	GameEnums.LimbRegion.RIGHT_ARM,
	GameEnums.LimbRegion.LEFT_LEG,
	GameEnums.LimbRegion.RIGHT_LEG,
]

func configure(
	player: HumanoidCore,
	enemy: HumanoidCore,
	lanes: CombatLaneManager,
	turns: CombatTurnManager,
	resolver: CombatResolutionEngine
) -> void:
	player_core = player
	enemy_core = enemy
	lane_manager = lanes
	turn_manager = turns
	resolution_engine = resolver

	if not turn_manager.turn_started.is_connected(_on_combat_state_changed):
		turn_manager.turn_started.connect(_on_combat_state_changed)
	if not turn_manager.ap_spent.is_connected(_on_ap_spent):
		turn_manager.ap_spent.connect(_on_ap_spent)
	if not turn_manager.turn_ended.is_connected(_on_combat_state_changed):
		turn_manager.turn_ended.connect(_on_combat_state_changed)
	if not turn_manager.reaction_window_opened.is_connected(
		_on_reaction_window_opened
	):
		turn_manager.reaction_window_opened.connect(
			_on_reaction_window_opened
		)
	if not turn_manager.reaction_resolved.is_connected(_on_reaction_resolved):
		turn_manager.reaction_resolved.connect(_on_reaction_resolved)

func refresh_snapshot() -> void:
	if not player_core or not enemy_core or not turn_manager or not lane_manager:
		return
	var player_lane := lane_manager._find_entity_lane(player_core)
	var enemy_lane := lane_manager._find_entity_lane(enemy_core)
	if player_lane >= 0 and enemy_lane >= 0 and player_lane != enemy_lane:
		_player_forward_direction = signi(enemy_lane - player_lane)
	snapshot_changed.emit(get_snapshot())

func get_snapshot() -> Dictionary:
	if not player_core or not enemy_core or not turn_manager or not lane_manager:
		return {}
	var active := turn_manager.get_active_entity()
	return {
		"round": turn_manager.current_round,
		"ap": turn_manager.current_ap_pool,
		"is_player_turn": active == player_core,
		"active_name": active.name if active else "",
		"busy": _action_in_progress,
		"reaction_pending": turn_manager._reaction_pending,
		"player": _combatant_snapshot(player_core),
		"enemy": _combatant_snapshot(enemy_core),
		"actions": _build_legal_actions(),
		"can_pass": (
			active == player_core
			and not _action_in_progress
			and not turn_manager._reaction_pending
		),
	}

func request_player_action(
	action: int,
	target_limb: int = GameEnums.LimbRegion.UPPER_TORSO,
	item_instance_id: String = ""
) -> void:
	if _action_in_progress:
		command_feedback.emit("Another action is still resolving.")
		return
	if not _has_legal_command(action, item_instance_id):
		command_feedback.emit("That action is not currently legal.")
		refresh_snapshot()
		return

	_action_in_progress = true
	refresh_snapshot()
	var succeeded := await _execute_player_action(
		action,
		target_limb,
		item_instance_id
	)
	_action_in_progress = false
	if not succeeded:
		command_feedback.emit("The action could not be completed.")
	refresh_snapshot()

func pass_player_turn() -> void:
	if (
		not turn_manager
		or turn_manager.get_active_entity() != player_core
		or _action_in_progress
		or turn_manager._reaction_pending
	):
		return
	turn_manager.pass_turn(player_core)
	refresh_snapshot()

func resolve_player_reaction(reaction: int) -> void:
	if not turn_manager or not turn_manager._reaction_pending:
		return
	if reaction == -1:
		turn_manager.skip_reaction(player_core)
	elif _available_reactions.has(reaction):
		turn_manager.resolve_reaction(player_core, reaction)
	else:
		return
	_available_reactions.clear()
	refresh_snapshot()

func _execute_player_action(
	action: int,
	target_limb: int,
	item_instance_id: String
) -> bool:
	var player_lane := lane_manager._find_entity_lane(player_core)
	var enemy_lane := lane_manager._find_entity_lane(enemy_core)
	var direction := _direction_toward_enemy(player_lane, enemy_lane)

	match action:
		GameEnums.ActionType.MOVE_FORWARD:
			if not turn_manager.request_action(player_core, action):
				return false
			var destination := player_lane + direction
			if lane_manager.move_entity(
				player_core,
				player_lane,
				destination
			):
				resolution_engine.check_hazard_trip(
					player_core,
					lane_manager.lane_slots[destination],
					false
				)
				return true
		GameEnums.ActionType.MOVE_BACKWARD:
			if not turn_manager.request_action(player_core, action):
				return false
			if lane_manager.lane_slots[player_lane].object_name == "Escape Zone":
				player_core.is_escaping = true
				turn_manager.pass_turn(player_core)
				return true
			var retreat := player_lane - direction
			if lane_manager.move_entity(player_core, player_lane, retreat):
				resolution_engine.check_hazard_trip(
					player_core,
					lane_manager.lane_slots[retreat],
					false
				)
				return true
		GameEnums.ActionType.CHARGE:
			if not turn_manager.request_action(player_core, action):
				return false
			var charge_distance := mini(2, abs(enemy_lane - player_lane))
			var charge_destination := player_lane + (direction * charge_distance)
			if lane_manager.move_entity(
				player_core,
				player_lane,
				charge_destination,
				true
			):
				resolution_engine.check_hazard_trip(
					player_core,
					lane_manager.lane_slots[charge_destination],
					true
				)
				return true
		GameEnums.ActionType.SHOOT:
			if not turn_manager.request_action(player_core, action):
				return false
			await resolution_engine.execute_ranged_strike(
				player_core,
				enemy_lane
			)
			return true
		GameEnums.ActionType.AIMED_SHOT:
			if not turn_manager.request_action(player_core, action):
				return false
			var aimed_limb := (
				target_limb
				if AIMED_LIMBS.has(target_limb)
				else GameEnums.LimbRegion.UPPER_TORSO
			)
			await resolution_engine.execute_aimed_shot(
				player_core,
				enemy_lane,
				aimed_limb
			)
			return true
		GameEnums.ActionType.RELOAD:
			if not turn_manager.request_action(player_core, action):
				return false
			return resolution_engine.execute_reload(player_core)
		GameEnums.ActionType.CYCLE:
			if not turn_manager.request_action(player_core, action):
				return false
			return resolution_engine.execute_cycle(player_core)
		GameEnums.ActionType.USE_ITEM:
			var item := player_core.inventory.find_item_by_instance_id(
				item_instance_id
			)
			if item == null or not turn_manager.request_action(player_core, action):
				return false
			return player_core.use_consumable_item(item)
		GameEnums.ActionType.TAKE_COVER:
			if not turn_manager.request_action(player_core, action):
				return false
			resolution_engine.execute_take_cover(player_core)
			return true
		GameEnums.ActionType.STRIKE:
			if not turn_manager.request_action(player_core, action):
				return false
			var strike_limb := (
				target_limb
				if STRIKE_LIMBS.has(target_limb)
				else GameEnums.LimbRegion.UPPER_TORSO
			)
			await resolution_engine.execute_melee_strike(
				player_core,
				enemy_core,
				strike_limb
			)
			return true
		GameEnums.ActionType.GRAPPLE:
			if not turn_manager.request_action(player_core, action):
				return false
			resolution_engine.execute_grapple(player_core, enemy_core)
			return true
		GameEnums.ActionType.BREAK:
			if not turn_manager.request_action(player_core, action):
				return false
			resolution_engine.execute_break(player_core, enemy_core)
			return true
		GameEnums.ActionType.PUSH_STAY, GameEnums.ActionType.PUSH_FOLLOW:
			if not turn_manager.request_action(player_core, action):
				return false
			if resolution_engine.execute_leverage_check(
				player_core,
				enemy_core,
				true
			):
				lane_manager.resolve_displacement(
					player_core,
					enemy_core,
					_player_forward_direction,
					action == GameEnums.ActionType.PUSH_FOLLOW
				)
			return true
		GameEnums.ActionType.DISENGAGE:
			if not turn_manager.request_action(player_core, action):
				return false
			return lane_manager.attempt_disengage(
				player_core,
				player_lane,
				player_lane - _player_forward_direction
			)
		GameEnums.ActionType.EXECUTE:
			if not turn_manager.request_action(player_core, action):
				return false
			resolution_engine.execute_execute(player_core, enemy_core)
			return true
	return false

func _build_legal_actions() -> Array:
	var actions: Array = []
	if (
		not player_core
		or not enemy_core
		or turn_manager.get_active_entity() != player_core
		or _action_in_progress
		or turn_manager._reaction_pending
		or player_core.is_dead
		or enemy_core.is_dead
	):
		return actions

	var player_lane := lane_manager._find_entity_lane(player_core)
	var enemy_lane := lane_manager._find_entity_lane(enemy_core)
	if player_lane < 0 or enemy_lane < 0:
		return actions
	var slot := lane_manager.lane_slots[player_lane]
	var locked := slot.is_melee_locked
	var direction := _direction_toward_enemy(player_lane, enemy_lane)

	if not locked:
		if _can_move_to(player_lane + direction):
			_add_action(actions, GameEnums.ActionType.MOVE_FORWARD, "ADVANCE")
		if (
			slot.object_name == "Escape Zone"
			or _can_move_to(player_lane - direction)
		):
			_add_action(
				actions,
				GameEnums.ActionType.MOVE_BACKWARD,
				"BEGIN ESCAPE" if slot.object_name == "Escape Zone" else "RETREAT"
			)
		if (
			abs(enemy_lane - player_lane) >= 2
			and _can_move_to(
				player_lane
				+ direction * mini(2, abs(enemy_lane - player_lane))
			)
		):
			_add_action(actions, GameEnums.ActionType.CHARGE, "CHARGE")

		var ranged := player_core.inventory.get_active_weapon(false)
		if ranged and _ranged_weapon_ready(ranged):
			_add_action(actions, GameEnums.ActionType.SHOOT, "SHOOT")
			_add_action(
				actions,
				GameEnums.ActionType.AIMED_SHOT,
				"AIMED SHOT",
				AIMED_LIMBS
			)
		if ranged and _can_reload(ranged):
			_add_action(actions, GameEnums.ActionType.RELOAD, "RELOAD")
		if (
			ranged
			and ranged.weapon_type == GameEnums.WeaponClass.RIFLE
			and ranged.needs_cycling
		):
			_add_action(actions, GameEnums.ActionType.CYCLE, "CYCLE")
		if slot.current_cover != CombatRules.TileObject.NONE:
			_add_action(actions, GameEnums.ActionType.TAKE_COVER, "TAKE COVER")
	else:
		_add_action(
			actions,
			GameEnums.ActionType.STRIKE,
			"STRIKE",
			STRIKE_LIMBS
		)
		_add_action(actions, GameEnums.ActionType.GRAPPLE, "GRAPPLE")
		_add_action(actions, GameEnums.ActionType.BREAK, "BREAK STANCE")
		_add_action(actions, GameEnums.ActionType.PUSH_STAY, "PUSH / STAY")
		_add_action(actions, GameEnums.ActionType.PUSH_FOLLOW, "PUSH / FOLLOW")
		if _can_move_to(player_lane - _player_forward_direction):
			_add_action(actions, GameEnums.ActionType.DISENGAGE, "DISENGAGE")
		if enemy_core.current_stance == GameEnums.StanceState.FELLED:
			_add_action(actions, GameEnums.ActionType.EXECUTE, "EXECUTE")

	for item in player_core.inventory.backpack_array:
		if item.item_type == GameEnums.ItemType.CONSUMABLE:
			_add_action(
				actions,
				GameEnums.ActionType.USE_ITEM,
				"USE " + item.display_name.to_upper(),
				[],
				item.instance_id
			)
	return actions

func _add_action(
	actions: Array,
	action: int,
	label: String,
	target_limbs: Array = [],
	item_instance_id: String = ""
) -> void:
	if not _can_afford(action):
		return
	actions.append({
		"action": action,
		"label": label,
		"cost": _display_action_cost(action),
		"target_limbs": target_limbs.duplicate(),
		"item_instance_id": item_instance_id,
	})

func _has_legal_command(action: int, item_instance_id: String) -> bool:
	for descriptor in _build_legal_actions():
		if (
			descriptor.get("action", -1) == action
			and descriptor.get("item_instance_id", "") == item_instance_id
		):
			return true
	return false

func _combatant_snapshot(entity: HumanoidCore) -> Dictionary:
	var weapon_name := "Unarmed"
	var weapon: ItemData = entity.inventory.paper_doll.get(
		GameEnums.EquipmentSlot.HANDS
	)
	if weapon:
		weapon_name = weapon.display_name
	return {
		"name": entity.name,
		"archetype": entity.definition.archetype_name,
		"lane": lane_manager._find_entity_lane(entity),
		"blood": entity.body.blood_level,
		"morale": entity.current_morale,
		"stance": entity.stance_points,
		"stance_state": GameEnums.StanceState.keys()[entity.current_stance],
		"kinetic_tier": GameEnums.KineticTier.keys()[entity.kinetic_tier],
		"weapon": weapon_name,
		"is_escaping": entity.is_escaping,
	}

func _can_afford(action: int) -> bool:
	var cost := turn_manager.get_action_cost(player_core, action)
	if cost == CombatTurnManager.COST_ALL_AP:
		return turn_manager.current_ap_pool > 0
	return turn_manager.current_ap_pool >= cost

func _display_action_cost(action: int) -> int:
	var cost := turn_manager.get_action_cost(player_core, action)
	return turn_manager.current_ap_pool if cost == CombatTurnManager.COST_ALL_AP else cost

func _can_move_to(lane_index: int) -> bool:
	if lane_index < 0 or lane_index >= lane_manager.lane_slots.size():
		return false
	return lane_manager.lane_slots[lane_index].occupants.size() < 2

func _direction_toward_enemy(player_lane: int, enemy_lane: int) -> int:
	if player_lane == enemy_lane:
		return _player_forward_direction
	return signi(enemy_lane - player_lane)

func _ranged_weapon_ready(weapon: ItemData) -> bool:
	if weapon.weapon_type == GameEnums.WeaponClass.PISTOL:
		return weapon.current_magazine > 0
	if weapon.weapon_type == GameEnums.WeaponClass.RIFLE:
		return not weapon.needs_cycling and _has_ammunition()
	return false

func _can_reload(weapon: ItemData) -> bool:
	return (
		weapon.weapon_type == GameEnums.WeaponClass.PISTOL
		and weapon.current_magazine < weapon.max_magazine
		and _has_ammunition()
	)

func _has_ammunition() -> bool:
	for item in player_core.inventory.backpack_array:
		if (
			item.id == "magazine"
			or item.id.ends_with("_magazine")
			or item.id.begins_with("ammo_")
		):
			return true
	return false

func _on_combat_state_changed(_entity: HumanoidCore) -> void:
	refresh_snapshot()

func _on_ap_spent(_entity: HumanoidCore, _remaining_ap: int) -> void:
	refresh_snapshot()

func _on_reaction_window_opened(
	defender: HumanoidCore,
	_attacker: HumanoidCore,
	trigger_action: int,
	available_reactions: Array
) -> void:
	if defender != player_core:
		return
	_available_reactions = available_reactions.duplicate()
	var reaction_descriptors: Array = []
	for reaction in _available_reactions:
		reaction_descriptors.append({
			"action": reaction,
			"label": GameEnums.ActionType.keys()[reaction].replace("_", " "),
			"cost": turn_manager.get_action_cost(player_core, reaction),
		})
	reaction_requested.emit({
		"trigger": GameEnums.ActionType.keys()[trigger_action].replace("_", " "),
		"reactions": reaction_descriptors,
	})
	refresh_snapshot()

func _on_reaction_resolved(
	defender: HumanoidCore,
	_chosen_reaction: int,
	_success: bool
) -> void:
	if defender == player_core:
		_available_reactions.clear()
	refresh_snapshot()
