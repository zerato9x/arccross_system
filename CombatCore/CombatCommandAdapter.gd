extends Node
class_name CombatCommandAdapter

signal snapshot_changed(snapshot: Dictionary)
signal reaction_requested(prompt: Dictionary)
signal command_feedback(message: String)
signal presentation_event(event: Dictionary)

var player_core: HumanoidCore
var enemy_core: HumanoidCore
var lane_manager: CombatLaneManager
var turn_manager: CombatTurnManager
var resolution_engine: CombatResolutionEngine

var _action_in_progress: bool = false
var _available_reactions: Array = []
var _player_forward_direction: int = 1

const AIMED_LIMBS := [
	GameEnums.LimbRegion.HEAD,
	GameEnums.LimbRegion.UPPER_TORSO,
	GameEnums.LimbRegion.LOWER_TORSO,
	GameEnums.LimbRegion.LEFT_ARM,
	GameEnums.LimbRegion.RIGHT_ARM,
	GameEnums.LimbRegion.LEFT_LEG,
	GameEnums.LimbRegion.RIGHT_LEG,
]
const ACTION_GROUP_FIREARM := "firearm"
const ACTION_GROUP_MOVEMENT := "movement"
const ACTION_GROUP_MELEE := "melee"
const ACTION_GROUP_FIELD := "field"
const ACTION_GROUP_ITEMS := "items"

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
	if not turn_manager.combat_bleed_tick.is_connected(_on_combat_bleed_tick):
		turn_manager.combat_bleed_tick.connect(_on_combat_bleed_tick)
	if not turn_manager.reaction_window_opened.is_connected(
		_on_reaction_window_opened
	):
		turn_manager.reaction_window_opened.connect(
			_on_reaction_window_opened
		)
	if not turn_manager.reaction_resolved.is_connected(_on_reaction_resolved):
		turn_manager.reaction_resolved.connect(_on_reaction_resolved)
	if not lane_manager.lane_changed.is_connected(_on_lane_changed):
		lane_manager.lane_changed.connect(_on_lane_changed)
	if not lane_manager.disengage_failed.is_connected(_on_disengage_failed):
		lane_manager.disengage_failed.connect(_on_disengage_failed)
	if not resolution_engine.action_started.is_connected(
		_on_resolution_action_started
	):
		resolution_engine.action_started.connect(
			_on_resolution_action_started
		)
	if not resolution_engine.damage_applied.is_connected(
		_on_resolution_damage_applied
	):
		resolution_engine.damage_applied.connect(
			_on_resolution_damage_applied
		)
	if not resolution_engine.damage_resolved.is_connected(
		_on_resolution_damage_resolved
	):
		resolution_engine.damage_resolved.connect(
			_on_resolution_damage_resolved
		)
	for entity in [player_core, enemy_core]:
		var death_callback := _on_entity_died.bind(entity)
		if not entity.died.is_connected(death_callback):
			entity.died.connect(death_callback)
	for inventory in [player_core.inventory, enemy_core.inventory]:
		if not inventory.equipment_changed.is_connected(
			_on_equipment_changed
		):
			inventory.equipment_changed.connect(_on_equipment_changed)

func refresh_snapshot() -> void:
	if not player_core or not enemy_core or not turn_manager or not lane_manager:
		return
	var player_lane := lane_manager._find_entity_lane(player_core)
	var enemy_lane := lane_manager._find_entity_lane(enemy_core)
	if player_lane >= 0 and enemy_lane >= 0 and player_lane != enemy_lane:
		_player_forward_direction = signi(enemy_lane - player_lane)
	snapshot_changed.emit(get_snapshot())

func _on_disengage_failed(
	entity: HumanoidCore,
	opponent: HumanoidCore
) -> void:
	if entity.is_dead or opponent.is_dead:
		return
	resolution_engine.execute_fumble_strike(opponent, entity)

func get_snapshot() -> Dictionary:
	if not player_core or not enemy_core or not turn_manager or not lane_manager:
		return {}
	var active := turn_manager.get_active_entity()
	return {
		"round": turn_manager.current_round,
		"ap": turn_manager.current_ap_pool,
		"is_player_turn": active == player_core,
		"active_name": active.name if active != null else "",
		"active_side": _entity_side(active),
		"busy": _action_in_progress,
		"reaction_pending": turn_manager._reaction_pending,
		"player": _combatant_snapshot(player_core),
		"enemy": _combatant_snapshot(enemy_core),
		"lane_slots": _lane_snapshot(),
		"actions": _build_legal_actions(),
		"can_pass": (
			active == player_core
			and not _action_in_progress
			and not turn_manager._reaction_pending
			and player_core.current_stance != GameEnums.StanceState.FELLED
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
		GameEnums.ActionType.GET_UP:
			if not turn_manager.request_action(player_core, action):
				return false
			return resolution_engine.execute_get_up(player_core)
		GameEnums.ActionType.MOVE_FORWARD:
			var destination := player_lane + direction
			if not lane_manager.can_move_entity_to(player_core, player_lane, destination):
				return false
			if not turn_manager.request_action(player_core, action):
				return false
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
			if lane_manager.lane_slots[player_lane].object_name == "Escape Zone":
				if not turn_manager.request_action(player_core, action):
					return false
				player_core.is_escaping = true
				turn_manager.pass_turn(player_core)
				return true
			var retreat := player_lane - direction
			if not lane_manager.can_move_entity_to(player_core, player_lane, retreat):
				return false
			if not turn_manager.request_action(player_core, action):
				return false
			if lane_manager.move_entity(player_core, player_lane, retreat):
				resolution_engine.check_hazard_trip(
					player_core,
					lane_manager.lane_slots[retreat],
					false
				)
				return true
		GameEnums.ActionType.CHARGE:
			var charge_distance := mini(2, abs(enemy_lane - player_lane))
			var charge_destination := player_lane + (direction * charge_distance)
			if not lane_manager.can_move_entity_to(
				player_core,
				player_lane,
				charge_destination
			):
				return false
			if not turn_manager.request_action(player_core, action):
				return false
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
			var used: bool = player_core.use_consumable_item(item, true)
			if used:
				_emit_presentation_action(player_core, action)
			return used
		GameEnums.ActionType.TAKE_COVER:
			if not turn_manager.request_action(player_core, action):
				return false
			resolution_engine.execute_take_cover(player_core)
			return true
		GameEnums.ActionType.STRIKE:
			if not turn_manager.request_action(player_core, action):
				return false
			await resolution_engine.execute_melee_strike(
				player_core,
				enemy_core
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
		GameEnums.ActionType.PUSH_STAY:
			if not turn_manager.request_action(player_core, action):
				return false
			_emit_presentation_action(player_core, action)
			if resolution_engine.execute_leverage_check(
				player_core,
				enemy_core,
				true
			):
				lane_manager.resolve_displacement(
					player_core,
					enemy_core,
					_player_forward_direction,
					false,
					"PUSH"
				)
			return true
		GameEnums.ActionType.PULL_FOLLOW:
			if not turn_manager.request_action(player_core, action):
				return false
			_emit_presentation_action(player_core, action)
			if resolution_engine.execute_leverage_check(
				player_core,
				enemy_core,
				false
			):
				lane_manager.resolve_displacement(
					player_core,
					enemy_core,
					-_player_forward_direction,
					true,
					"PULL"
				)
			return true
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
	var locked := lane_manager.is_entity_melee_locked(player_core)
	var direction := _direction_toward_enemy(player_lane, enemy_lane)

	if player_core.current_stance == GameEnums.StanceState.FELLED:
		_add_action(actions, GameEnums.ActionType.GET_UP, "GET UP")
		return actions

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

		var ranged: ItemData = player_core.inventory.get_active_weapon(false)
		var ranged_distance: int = absi(enemy_lane - player_lane)
		if ranged and _ranged_weapon_ready(ranged, ranged_distance):
			_add_action(actions, GameEnums.ActionType.SHOOT, "SHOOT")
			_add_action(
				actions,
				GameEnums.ActionType.AIMED_SHOT,
				"AIMED SHOT",
				AIMED_LIMBS
			)
		if ranged and _can_reload(ranged):
			_add_action(actions, GameEnums.ActionType.RELOAD, "RELOAD")
		if ranged and _can_cycle(ranged):
			_add_action(actions, GameEnums.ActionType.CYCLE, "CYCLE")
		if slot.current_cover != CombatRules.TileObject.NONE:
			_add_action(actions, GameEnums.ActionType.TAKE_COVER, "TAKE COVER")
	else:
		_add_action(actions, GameEnums.ActionType.STRIKE, "STRIKE")
		_add_action(actions, GameEnums.ActionType.GRAPPLE, "GRAPPLE")
		_add_action(actions, GameEnums.ActionType.BREAK, "BREAK STANCE")
		_add_action(actions, GameEnums.ActionType.PUSH_STAY, "PUSH")
		_add_action(actions, GameEnums.ActionType.PULL_FOLLOW, "PULL")
		if (
			CombatRules.EXECUTE_ENABLED
			and enemy_core.current_stance == GameEnums.StanceState.FELLED
		):
			_add_action(actions, GameEnums.ActionType.EXECUTE, "EXECUTE")

	for item in player_core.inventory.backpack_array:
		if (
			item.item_type == GameEnums.ItemType.CONSUMABLE
			and player_core.inventory.is_combat_accessible(item)
		):
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
		"group": _action_group_for(action, item_instance_id),
	})

func _action_group_for(action: int, item_instance_id: String) -> String:
	if action == GameEnums.ActionType.USE_ITEM or not item_instance_id.is_empty():
		return ACTION_GROUP_ITEMS
	match action:
		GameEnums.ActionType.SHOOT, GameEnums.ActionType.AIMED_SHOT:
			return ACTION_GROUP_FIREARM
		GameEnums.ActionType.RELOAD, GameEnums.ActionType.CYCLE:
			return ACTION_GROUP_FIREARM
		GameEnums.ActionType.GET_UP, GameEnums.ActionType.MOVE_FORWARD:
			return ACTION_GROUP_MOVEMENT
		GameEnums.ActionType.MOVE_BACKWARD, GameEnums.ActionType.CHARGE:
			return ACTION_GROUP_MOVEMENT
		GameEnums.ActionType.STRIKE, GameEnums.ActionType.GRAPPLE:
			return ACTION_GROUP_MELEE
		GameEnums.ActionType.BREAK, GameEnums.ActionType.PUSH_STAY:
			return ACTION_GROUP_MELEE
		GameEnums.ActionType.PULL_FOLLOW:
			return ACTION_GROUP_MELEE
		GameEnums.ActionType.EXECUTE:
			return ACTION_GROUP_MELEE
	return ACTION_GROUP_FIELD

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
	var weapon_detail := ""
	var weapon_descriptor := {}
	var weapon_state := "UNARMED"
	var weapon_sprite_path := ""
	var ranged_weapon := _weapon_slot_snapshot(entity, false)
	var melee_weapon := _weapon_slot_snapshot(entity, true)
	var weapon: ItemData = entity.inventory.get_active_weapon(false)
	if weapon == null:
		weapon = entity.inventory.get_active_weapon(true)
	if weapon:
		weapon_name = weapon.display_name
		weapon_sprite_path = weapon.get_inventory_sprite_path()
		weapon_state = _weapon_state_label(weapon)
		weapon_descriptor = weapon.to_definition_state()
		weapon_descriptor["instance_id"] = weapon.instance_id
		weapon_descriptor["current_magazine"] = weapon.current_magazine
		weapon_descriptor["loaded_rounds"] = weapon.loaded_rounds
		weapon_descriptor["needs_cycling"] = weapon.needs_cycling
		weapon_descriptor["sprite_path"] = weapon_sprite_path
		if weapon.is_ranged():
			weapon_detail = " %02d/%02d R%02d%s" % [
				weapon.current_magazine,
				weapon.max_magazine,
				weapon.effective_range,
				" CYCLE" if weapon.needs_cycling else "",
			]
	return {
		"name": entity.name,
		"archetype": entity.definition.archetype_name,
		"lane": lane_manager._find_entity_lane(entity),
		"blood": entity.body.blood_level,
		"limbs": _limb_snapshot(entity),
		"morale": entity.current_morale,
		"stance": entity.stance_points,
		"stance_state": GameEnums.StanceState.keys()[entity.current_stance],
		"stance_recovery_guard": entity.has_stance_recovery_guard,
		"kinetic_tier": GameEnums.KineticTier.keys()[entity.kinetic_tier],
		"weapon": weapon_name,
		"weapon_detail": weapon_detail,
		"has_firearm": weapon != null and weapon.is_ranged(),
		"weapon_id": weapon.id if weapon else "",
		"weapon_sprite_path": weapon_sprite_path,
		"weapon_state": weapon_state,
		"active_weapon": weapon_descriptor,
		"ranged_weapon": ranged_weapon,
		"melee_weapon": melee_weapon,
		"equipment": _equipment_snapshot(entity),
		"both_legs_broken": entity.body.are_both_legs_disabled(),
		"appearance": HumanoidVisualCatalog.appearance_from_inventory(
			entity.inventory
		),
		"is_dead": entity.is_dead,
		"is_escaping": entity.is_escaping,
		"reserved_ap": turn_manager.reserved_ap.get(entity, 0),
		"is_active": turn_manager.get_active_entity() == entity,
	}

func _weapon_slot_snapshot(entity: HumanoidCore, melee: bool) -> Dictionary:
	var weapon: ItemData = entity.inventory.get_active_weapon(melee)
	if weapon == null:
		return {}
	var descriptor := weapon.to_definition_state()
	descriptor["instance_id"] = weapon.instance_id
	descriptor["current_magazine"] = weapon.current_magazine
	descriptor["loaded_rounds"] = weapon.loaded_rounds
	descriptor["needs_cycling"] = weapon.needs_cycling
	descriptor["sprite_path"] = weapon.get_inventory_sprite_path()
	descriptor["state"] = _weapon_state_label(weapon)
	descriptor["slot_label"] = "MELEE" if melee else "RANGED"
	return descriptor

func _weapon_state_label(weapon: ItemData) -> String:
	if weapon == null:
		return "UNARMED"
	if not weapon.is_ranged():
		return "READY"
	if weapon.current_magazine <= 0:
		return "EMPTY"
	if weapon.needs_cycling:
		return "CYCLE"
	return "READY"

func _limb_snapshot(entity: HumanoidCore) -> Array:
	var limbs: Array = []
	var ordered_regions := [
		GameEnums.LimbRegion.HEAD,
		GameEnums.LimbRegion.UPPER_TORSO,
		GameEnums.LimbRegion.LOWER_TORSO,
		GameEnums.LimbRegion.LEFT_ARM,
		GameEnums.LimbRegion.RIGHT_ARM,
		GameEnums.LimbRegion.LEFT_LEG,
		GameEnums.LimbRegion.RIGHT_LEG,
	]
	var codes := ["HD", "UT", "LT", "LA", "RA", "LL", "RL"]
	for index in range(ordered_regions.size()):
		var region: GameEnums.LimbRegion = ordered_regions[index]
		limbs.append({
			"region": region,
			"code": codes[index],
			"current": float(entity.body.limb_hp.get(region, 0.0)),
			"maximum": entity.body.get_limb_max(region),
			"trauma": GameEnums.TraumaType.keys()[
				int(entity.body.limb_trauma.get(region, GameEnums.TraumaType.NONE))
			],
		})
	return limbs

func _equipment_snapshot(entity: HumanoidCore) -> Array:
	var equipment: Array = []
	for slot_key in entity.inventory.paper_doll.keys():
		var item: ItemData = entity.inventory.paper_doll[slot_key]
		if item == null:
			continue
		var descriptor := item.to_definition_state()
		descriptor["instance_id"] = item.instance_id
		descriptor["equipment_slot"] = int(slot_key)
		descriptor["current_magazine"] = item.current_magazine
		descriptor["loaded_rounds"] = item.loaded_rounds
		descriptor["needs_cycling"] = item.needs_cycling
		equipment.append(descriptor)
	return equipment

func _lane_snapshot() -> Array:
	var slots: Array = []
	for slot in lane_manager.lane_slots:
		var presentation := slot.get_presentation_descriptor()
		var occupants: Array = []
		for occupant in slot.occupants:
			occupants.append({
				"side": _entity_side(occupant),
				"name": occupant.name,
				"archetype": occupant.definition.archetype_name,
				"is_active": turn_manager.get_active_entity() == occupant,
				"stance": occupant.stance_points,
				"stance_state": GameEnums.StanceState.keys()[
					occupant.current_stance
				],
			})
		slots.append({
			"index": slot.lane_index,
			"is_escape": slot.object_name == "Escape Zone",
			"is_spawnable": slot.is_spawnable,
			"background": CombatRules.TileBackground.keys()[slot.background],
			"background_label": presentation.get("background_label", "PLAINS"),
			"ground_asset": presentation.get("ground_asset", ""),
			"surface_label": presentation.get("surface_label", "GRASS"),
			"surface_asset": presentation.get("surface_asset", ""),
			"terrain_modifiers": presentation.get("terrain_modifiers", []),
			"cover": CombatRules.TileObject.keys()[slot.current_cover],
			"object_name": presentation.get("object_name", "NONE"),
			"object_asset": presentation.get("object_asset", ""),
			"object_interactions": presentation.get("object_interactions", []),
			"cover_durability": slot.object_durability,
			"is_melee_locked": lane_manager.is_lane_melee_locked(slot.lane_index),
			"occupants": occupants,
		})
	return slots

func _entity_side(entity: HumanoidCore) -> String:
	if entity == player_core:
		return "player"
	if entity == enemy_core:
		return "enemy"
	return "other"

func _can_afford(action: int) -> bool:
	var cost := turn_manager.get_action_cost(player_core, action)
	if cost == CombatTurnManager.COST_ALL_AP:
		return turn_manager.current_ap_pool > 0
	return turn_manager.current_ap_pool >= cost

func _display_action_cost(action: int) -> int:
	var cost := turn_manager.get_action_cost(player_core, action)
	return turn_manager.current_ap_pool if cost == CombatTurnManager.COST_ALL_AP else cost

func _can_move_to(
	lane_index: int,
	allow_break_from_melee_lock: bool = false
) -> bool:
	var player_lane := lane_manager._find_entity_lane(player_core)
	return lane_manager.can_move_entity_to(
		player_core,
		player_lane,
		lane_index,
		allow_break_from_melee_lock
	)

func _direction_toward_enemy(player_lane: int, enemy_lane: int) -> int:
	if player_lane == enemy_lane:
		return _player_forward_direction
	return signi(enemy_lane - player_lane)

func _ranged_weapon_ready(weapon: ItemData, distance: int) -> bool:
	return (
		weapon.is_ready_to_fire()
		and distance <= weapon.effective_range
	)

func _can_reload(weapon: ItemData) -> bool:
	if weapon.current_magazine >= weapon.max_magazine:
		return false
	var feed_id := (
		weapon.magazine_id
		if not weapon.magazine_id.is_empty()
		else weapon.reload_aid_id
	)
	if not feed_id.is_empty():
		return player_core.inventory.find_filled_magazine(feed_id) != null
	if (
		weapon.magazine_id.is_empty()
		and weapon.reload_aid_id.is_empty()
		and weapon.cycle_loads_one_round
	):
		return false
	return _has_ammunition(weapon.ammunition_id)

func _can_cycle(weapon: ItemData) -> bool:
	if weapon.needs_cycling:
		return true
	return (
		weapon.cycle_loads_one_round
		and weapon.current_magazine < weapon.max_magazine
		and _has_ammunition(weapon.ammunition_id)
	)

func _has_inventory_item(item_id: String) -> bool:
	if item_id.is_empty():
		return true
	return player_core.inventory.has_combat_item(item_id)

func _has_ammunition(ammunition_id: String) -> bool:
	var resolved_id := ammunition_id if not ammunition_id.is_empty() else "ammo_round"
	return _has_inventory_item(resolved_id)

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

func _on_lane_changed() -> void:
	refresh_snapshot()

func _on_equipment_changed(
	_slot: GameEnums.EquipmentSlot,
	_item: ItemData
) -> void:
	refresh_snapshot()

func _on_combat_bleed_tick(entity: HumanoidCore, event: Dictionary) -> void:
	var presentation := event.duplicate(true)
	presentation["side"] = _entity_side(entity)
	presentation["victim_name"] = entity.name
	presentation["type"] = "bleed"
	presentation_event.emit(presentation)
	call_deferred("refresh_snapshot")

func _on_resolution_action_started(
	entity: HumanoidCore,
	action: int
) -> void:
	_emit_presentation_action(entity, action)

func _on_resolution_damage_applied(_entity: HumanoidCore) -> void:
	call_deferred("refresh_snapshot")

func _on_resolution_damage_resolved(event: Dictionary) -> void:
	var victim := event.get("victim") as HumanoidCore
	var attacker := event.get("attacker") as HumanoidCore
	var presentation := event.duplicate(true)
	presentation["type"] = "damage"
	presentation["side"] = _entity_side(victim)
	presentation["attacker_side"] = _entity_side(attacker)
	presentation_event.emit(presentation)
	call_deferred("refresh_snapshot")

func _on_entity_died(cause: String, entity: HumanoidCore) -> void:
	presentation_event.emit({
		"side": _entity_side(entity),
		"type": "death",
		"cause": cause,
	})
	call_deferred("refresh_snapshot")

func _emit_presentation_action(
	entity: HumanoidCore,
	action: int
) -> void:
	presentation_event.emit({
		"side": _entity_side(entity),
		"type": "action",
		"action": action,
	})
