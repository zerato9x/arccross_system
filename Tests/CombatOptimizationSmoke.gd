extends SceneTree

const DUEL_SCENE := preload("res://CombatCore/MainDuelScene.tscn")
const PLAYER_DEFINITION := preload("res://BiologicalCore/player_def.tres")

const BATTLES_PER_MATCHUP := 6
const MAX_ROUNDS := 16
const REPORT_PATH := "res://Tests/combat_optimization_report.json"

const STRATEGIES := [
	{
		"id": "current_pack_aimed",
		"loadout": "current",
		"policy": "aimed",
		"reserve_ap": 0,
	},
	{
		"id": "service_light_aimed",
		"weapon": "service_pistol",
		"armor": ["coat_leather", "pants_cargo"],
		"policy": "aimed",
		"reserve_ap": 0,
	},
	{
		"id": "carbon_light_aimed",
		"weapon": "carbon_pistol",
		"armor": ["coat_leather", "pants_cargo"],
		"policy": "aimed",
		"reserve_ap": 0,
	},
	{
		"id": "carbon_light_guard",
		"weapon": "carbon_pistol",
		"armor": ["coat_leather", "pants_cargo"],
		"policy": "aimed",
		"reserve_ap": 4,
	},
	{
		"id": "carbon_hybrid_aimed",
		"weapon": "carbon_pistol",
		"secondary_weapon": "knife_service",
		"armor": ["coat_leather", "pants_cargo"],
		"policy": "aimed",
		"reserve_ap": 0,
	},
	{
		"id": "carbon_hybrid_guard",
		"weapon": "carbon_pistol",
		"secondary_weapon": "knife_service",
		"armor": ["coat_leather", "pants_cargo"],
		"policy": "aimed",
		"reserve_ap": 4,
	},
	{
		"id": "carbon_light_body",
		"weapon": "carbon_pistol",
		"armor": ["coat_leather", "pants_cargo"],
		"policy": "shoot",
		"reserve_ap": 0,
	},
	{
		"id": "carbon_rifle_aimed",
		"weapon": "carbon_rifle",
		"secondary_weapon": "knife_service",
		"armor": [],
		"policy": "aimed",
		"reserve_ap": 0,
	},
	{
		"id": "ak47_aimed",
		"weapon": "ak47",
		"armor": [],
		"policy": "aimed",
		"reserve_ap": 0,
	},
	{
		"id": "shotgun_aimed",
		"weapon": "shotgun",
		"secondary_weapon": "knife_service",
		"armor": [],
		"policy": "aimed",
		"reserve_ap": 0,
	},
	{
		"id": "knife_light",
		"weapon": "knife_service",
		"armor": ["coat_leather", "pants_carbon"],
		"policy": "melee",
		"reserve_ap": 0,
	},
	{
		"id": "placeholder_railgun_tank",
		"weapon": "unique_railgun",
		"secondary_weapon": "knife_service",
		"armor": ["armor_arcborn"],
		"policy": "aimed",
		"reserve_ap": 0,
	},
]

const MATCHUPS := [
	{
		"id": "scavenger_gunner",
		"faction": GameEnums.Faction.SCAVENGER_CELL,
		"agenda": GameEnums.Agenda.SURVIVALIST,
		"tactic": GameEnums.CombatTactic.MARKSMAN,
		"brawn": 5,
		"finesse": 9,
		"fortitude": 4,
		"will": 3,
		"weapon": "service_pistol",
		"armor": ["coat_leather", "boot_service"],
		"context": GameEnums.EncounterContext.PLAYER_AMBUSH,
		"ambush_position": GameEnums.AmbushPosition.FAR,
		"initiator_id": "player",
	},
	{
		"id": "arcborn_gunner",
		"faction": GameEnums.Faction.ARCBORN_RESISTANCE,
		"agenda": GameEnums.Agenda.BELLIGERENT,
		"tactic": GameEnums.CombatTactic.MARKSMAN,
		"brawn": 8,
		"finesse": 8,
		"fortitude": 8,
		"will": 8,
		"weapon": "carbon_pistol",
		"armor": [
			"shirt_thermo",
			"armor_arcborn",
			"pants_carbon",
			"boot_service",
			"backpack_service_big",
		],
		"context": GameEnums.EncounterContext.PLAYER_AMBUSH,
		"ambush_position": GameEnums.AmbushPosition.FAR,
		"initiator_id": "player",
	},
	{
		"id": "craven_rush",
		"faction": GameEnums.Faction.CRAVEN_HIVE,
		"agenda": GameEnums.Agenda.MINDLESS,
		"tactic": GameEnums.CombatTactic.BRUTE,
		"brawn": 9,
		"finesse": 3,
		"fortitude": 10,
		"will": 1,
		"weapon": "",
		"armor": [],
		"context": GameEnums.EncounterContext.ENEMY_AMBUSH,
		"ambush_position": GameEnums.AmbushPosition.CLOSE,
		"initiator_id": "enemy",
	},
]

var _battle_serial: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var strategy_filter := ""
	var matchup_filter := ""
	var battle_count := BATTLES_PER_MATCHUP
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("strategy="):
			strategy_filter = argument.trim_prefix("strategy=")
		elif argument.begins_with("matchup="):
			matchup_filter = argument.trim_prefix("matchup=")
		elif argument.begins_with("battles="):
			battle_count = maxi(
				1,
				int(argument.trim_prefix("battles="))
			)

	var summaries: Array[Dictionary] = []
	for strategy in STRATEGIES:
		if (
			not strategy_filter.is_empty()
			and strategy.id != strategy_filter
		):
			continue
		var strategy_summary := _new_summary(strategy)
		for matchup in MATCHUPS:
			if (
				not matchup_filter.is_empty()
				and matchup.id != matchup_filter
			):
				continue
			var matchup_summary := _new_matchup_summary(matchup)
			for battle_index in range(battle_count):
				var battle_seed := 71000 + battle_index
				var result := await _run_battle(
					strategy,
					matchup,
					battle_seed
				)
				_accumulate_result(
					strategy_summary,
					matchup_summary,
					result
				)
			strategy_summary.matchups.append(matchup_summary)
			print(
				"[OPTIMIZATION_PROGRESS] strategy=%s enemy=%s"
				% [strategy.id, matchup.id]
			)
		summaries.append(strategy_summary)

	var report := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if report:
		report.store_string(JSON.stringify(summaries, "\t"))
		_print_report(summaries, battle_count)
		quit(0)
	else:
		push_error("Could not write optimization report to " + REPORT_PATH)
	_print_report(summaries, battle_count)
	quit(0)

func _run_battle(
	strategy: Dictionary,
	matchup: Dictionary,
	battle_seed: int
) -> Dictionary:
	seed(battle_seed)
	_battle_serial += 1

	var arena = DUEL_SCENE.instantiate()
	root.add_child(arena)
	await process_frame

	var player_definition := PLAYER_DEFINITION.duplicate(true) as EntityDefinition
	player_definition.loadout = _build_player_loadout(strategy)
	var player: HumanoidCore = arena._fabricate_humanoid(
		"Optimization_Player",
		player_definition,
		false
	)
	var secondary_weapon := _load_item(
		strategy.get("secondary_weapon", "")
	)
	if secondary_weapon:
		player.inventory.equip_item(
			secondary_weapon,
			GameEnums.EquipmentSlot.OFFHAND
		)
	var result := {
		"outcome": GameEnums.CombatOutcome.DRAW,
		"rounds": MAX_ROUNDS,
		"damage_taken": 0.0,
		"shots_fired": 0,
		"burden": player.total_burden,
		"tier": player.kinetic_tier,
		"weight": player.inventory.get_total_weight(),
		"bulk": player.inventory.get_total_bulk(),
		"threat": player.inventory.get_total_threat(),
	}
	var initial_rounds := _weapon_rounds(player)
	var battle_state := {"finished": false}
	var battle_id := _battle_serial

	arena.turn_manager.turn_started.connect(
		func(entity: HumanoidCore) -> void:
			if (
				entity == player
				and not battle_state.finished
				and battle_id == _battle_serial
			):
				call_deferred(
					"_drive_player_turn",
					arena,
					strategy,
					battle_id
				)
	)
	arena.turn_manager.reaction_window_opened.connect(
		func(
			defender: HumanoidCore,
			_attacker: HumanoidCore,
			_trigger: GameEnums.ActionType,
			reactions: Array
		) -> void:
			if defender != player or battle_state.finished:
				return
			if reactions.has(GameEnums.ActionType.DODGE):
				arena.turn_manager.resolve_reaction(
					player,
					GameEnums.ActionType.DODGE
				)
			elif reactions.has(GameEnums.ActionType.BLOCK):
				arena.turn_manager.resolve_reaction(
					player,
					GameEnums.ActionType.BLOCK
				)
			else:
				arena.turn_manager.skip_reaction(player)
	)
	arena.duel_finished.connect(
		func(
			outcome: GameEnums.CombatOutcome,
			_enemy_id: String,
			_enemy_runtime: Dictionary,
			_dropped_items: Array
		) -> void:
			battle_state.finished = true
			result.outcome = outcome
			result.rounds = arena.turn_manager.current_round
	)

	var enemy_definition := _build_enemy_definition(matchup)
	arena.setup_duel(
		player,
		{
			"entity_id": "optimization_enemy_%d" % battle_id,
			"definition": enemy_definition.to_state(),
			"runtime": {},
		},
		{
			"context": matchup.context,
			"ambush_position": matchup.ambush_position,
			"initiator_id": matchup.initiator_id,
		}
	)

	for _frame in range(90):
		if battle_state.finished:
			break
		if arena.turn_manager.current_round > MAX_ROUNDS:
			arena.turn_manager.halt_loop()
			battle_state.finished = true
			break
		await process_frame

	result.damage_taken = _total_damage(player)
	result.shots_fired = maxi(
		0,
		initial_rounds - _weapon_rounds(player)
	)

	arena.queue_free()
	await process_frame
	await process_frame
	return result

func _drive_player_turn(
	arena: Node,
	strategy: Dictionary,
	battle_id: int
) -> void:
	if battle_id != _battle_serial or not is_instance_valid(arena):
		return
	var player: HumanoidCore = arena.player_core
	var enemy: HumanoidCore = arena.enemy_core
	var manager: CombatTurnManager = arena.turn_manager
	var lane: CombatLaneManager = arena.lane_manager
	var resolver: CombatResolutionEngine = arena.resolution_engine
	var reserve_ap: int = strategy.reserve_ap
	var safety := 0

	while (
		is_instance_valid(player)
		and is_instance_valid(enemy)
		and not player.is_dead
		and not enemy.is_dead
		and manager.get_active_entity() == player
		and manager.current_ap_pool > 0
		and not manager._reaction_pending
		and safety < 12
	):
		safety += 1
		if player.current_stance == GameEnums.StanceState.FELLED:
			if manager.request_action(player, GameEnums.ActionType.GET_UP):
				resolver.execute_get_up(player)
			return

		var player_lane := lane._find_entity_lane(player)
		var enemy_lane := lane._find_entity_lane(enemy)
		if player_lane < 0 or enemy_lane < 0:
			return
		var locked := lane.lane_slots[player_lane].is_melee_locked

		if locked:
			var melee_weapon := player.inventory.get_active_weapon(true)
			if melee_weapon != null:
				if not _can_spend(
					manager,
					player,
					GameEnums.ActionType.STRIKE,
					reserve_ap
				):
					break
				if manager.request_action(player, GameEnums.ActionType.STRIKE):
					await resolver.execute_melee_strike(player, enemy)
				continue

			if not _can_spend(
				manager,
				player,
				GameEnums.ActionType.DISENGAGE,
				reserve_ap
			):
				break
			if manager.request_action(player, GameEnums.ActionType.DISENGAGE):
				lane.attempt_disengage(
					player,
					player_lane,
					player_lane - sign(enemy_lane - player_lane)
				)
			continue

		if strategy.policy == "melee":
			if not _can_spend(
				manager,
				player,
				GameEnums.ActionType.CHARGE,
				reserve_ap
			):
				break
			var direction: int = signi(enemy_lane - player_lane)
			var distance := absi(enemy_lane - player_lane)
			var destination: int = (
				player_lane + direction * mini(2, distance)
			)
			if manager.request_action(player, GameEnums.ActionType.CHARGE):
				if lane.move_entity(player, player_lane, destination, true):
					resolver.check_hazard_trip(
						player,
						lane.lane_slots[destination],
						true
					)
			continue

		var weapon := player.inventory.get_active_weapon(false)
		if weapon == null:
			break
		if weapon.needs_cycling:
			if not _can_spend(
				manager,
				player,
				GameEnums.ActionType.CYCLE,
				reserve_ap
			):
				break
			if manager.request_action(player, GameEnums.ActionType.CYCLE):
				resolver.execute_cycle(player)
			continue
		if weapon.current_magazine <= 0:
			if not _can_spend(
				manager,
				player,
				GameEnums.ActionType.RELOAD,
				reserve_ap
			):
				break
			if manager.request_action(player, GameEnums.ActionType.RELOAD):
				if not resolver.execute_reload(player):
					break
			continue

		var distance := absi(enemy_lane - player_lane)
		if distance > weapon.effective_range:
			if not _can_spend(
				manager,
				player,
				GameEnums.ActionType.MOVE_FORWARD,
				reserve_ap
			):
				break
			var direction: int = signi(enemy_lane - player_lane)
			var destination: int = player_lane + direction
			if manager.request_action(player, GameEnums.ActionType.MOVE_FORWARD):
				if lane.move_entity(player, player_lane, destination):
					resolver.check_hazard_trip(
						player,
						lane.lane_slots[destination],
						false
					)
			continue

		var action := (
			GameEnums.ActionType.AIMED_SHOT
			if strategy.policy == "aimed"
			else GameEnums.ActionType.SHOOT
		)
		if not _can_spend(manager, player, action, reserve_ap):
			break
		if not manager.request_action(player, action):
			break
		if action == GameEnums.ActionType.AIMED_SHOT:
			await resolver.execute_aimed_shot(
				player,
				enemy_lane,
				GameEnums.LimbRegion.HEAD
			)
		else:
			await resolver.execute_ranged_strike(player, enemy_lane)

	if (
		is_instance_valid(player)
		and manager.get_active_entity() == player
		and not manager._reaction_pending
	):
		manager.pass_turn(player)

func _can_spend(
	manager: CombatTurnManager,
	entity: HumanoidCore,
	action: GameEnums.ActionType,
	reserve_ap: int
) -> bool:
	var cost := manager.get_action_cost(entity, action)
	if cost == CombatTurnManager.COST_ALL_AP:
		return manager.current_ap_pool > reserve_ap
	return manager.current_ap_pool - cost >= reserve_ap

func _build_player_loadout(strategy: Dictionary) -> SpawnLoadout:
	if strategy.get("loadout", "") == "current":
		return PLAYER_DEFINITION.loadout
	return _build_loadout(
		strategy.get("weapon", ""),
		strategy.get("armor", []),
		true
	)

func _build_enemy_definition(matchup: Dictionary) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.archetype_name = matchup.id
	definition.faction = matchup.faction
	definition.agenda = matchup.agenda
	definition.combat_tactic = matchup.tactic
	definition.brawn = matchup.brawn
	definition.finesse = matchup.finesse
	definition.fortitude = matchup.fortitude
	definition.will = matchup.will
	definition.loadout = _build_loadout(
		matchup.weapon,
		matchup.armor,
		true
	)
	return definition

func _build_loadout(
	weapon_id: String,
	armor_ids: Array,
	add_ammunition: bool
) -> SpawnLoadout:
	var loadout := SpawnLoadout.new()
	var weapon := _load_item(weapon_id)
	if weapon:
		loadout.weapon = weapon
		if add_ammunition and weapon.is_ranged():
			for support_id in [weapon.magazine_id, weapon.reload_aid_id]:
				var support := _load_item(support_id)
				if support:
					loadout.starting_items.append(support)
			var ammunition := _load_item(weapon.ammunition_id)
			if ammunition:
				for _round_index in range(weapon.max_magazine):
					loadout.starting_items.append(ammunition)

	for armor_id in armor_ids:
		var armor := _load_item(armor_id)
		if armor == null:
			continue
		match armor.target_slot:
			GameEnums.EquipmentSlot.INNER_TORSO:
				loadout.inner_torso = armor
			GameEnums.EquipmentSlot.OUTER_TORSO:
				loadout.outer_torso = armor
			GameEnums.EquipmentSlot.LEGS:
				loadout.legs = armor
			GameEnums.EquipmentSlot.FEET:
				loadout.feet = armor
			GameEnums.EquipmentSlot.BACKPACK:
				loadout.backpack_gear = armor
	return loadout

func _load_item(item_id: String) -> ItemData:
	if item_id.is_empty():
		return null
	return load("res://ItemCore/Items/%s.tres" % item_id) as ItemData

func _weapon_rounds(entity: HumanoidCore) -> int:
	var weapon := entity.inventory.get_active_weapon(false)
	return weapon.current_magazine if weapon else 0

func _total_damage(entity: HumanoidCore) -> float:
	var total := 0.0
	for limb in entity.body.limb_hp.keys():
		total += (
			entity.body.get_limb_max(limb)
			- float(entity.body.limb_hp[limb])
		)
	return total

func _new_summary(strategy: Dictionary) -> Dictionary:
	return {
		"id": strategy.id,
		"wins": 0,
		"survivals": 0,
		"enemy_escapes": 0,
		"losses": 0,
		"draws": 0,
		"rounds": 0,
		"damage": 0.0,
		"shots": 0,
		"battles": 0,
		"burden": -1,
		"tier": -1,
		"weight": 0.0,
		"bulk": 0.0,
		"threat": 0.0,
		"matchups": [],
	}

func _new_matchup_summary(matchup: Dictionary) -> Dictionary:
	return {
		"id": matchup.id,
		"wins": 0,
		"survivals": 0,
		"enemy_escapes": 0,
		"losses": 0,
		"draws": 0,
		"rounds": 0,
		"damage": 0.0,
		"shots": 0,
		"battles": 0,
	}

func _accumulate_result(
	summary: Dictionary,
	matchup_summary: Dictionary,
	result: Dictionary
) -> void:
	for target in [summary, matchup_summary]:
		target.battles += 1
		target.rounds += result.rounds
		target.damage += result.damage_taken
		target.shots += result.shots_fired
		match result.outcome:
			GameEnums.CombatOutcome.PLAYER_VICTORY:
				target.wins += 1
				target.survivals += 1
			GameEnums.CombatOutcome.ENEMY_ESCAPED:
				target.enemy_escapes += 1
				target.survivals += 1
			GameEnums.CombatOutcome.PLAYER_DEFEAT:
				target.losses += 1
			_:
				target.draws += 1

	if summary.burden < 0:
		summary.burden = result.burden
		summary.tier = result.tier
		summary.weight = result.weight
		summary.bulk = result.bulk
		summary.threat = result.threat

func _print_report(
	summaries: Array[Dictionary],
	battle_count: int
) -> void:
	print("[OPTIMIZATION] battles_per_matchup=%d" % battle_count)
	for summary in summaries:
		var battles: float = float(summary.battles)
		print(
			"[OPTIMIZATION] strategy=%s tier=%s burden=%d weight=%.1f "
			% [
				summary.id,
				GameEnums.KineticTier.keys()[summary.tier],
				summary.burden,
				summary.weight,
			]
			+ "bulk=%.1f threat=%.1f win=%.1f%% survive=%.1f%% "
			% [
				summary.bulk,
				summary.threat,
				float(summary.wins) / battles * 100.0,
				float(summary.survivals) / battles * 100.0,
			]
			+ "avg_rounds=%.2f avg_damage=%.2f avg_shots=%.2f"
			% [
				float(summary.rounds) / battles,
				summary.damage / battles,
				float(summary.shots) / battles,
			]
		)
		for matchup in summary.matchups:
			var matchup_battles: float = float(matchup.battles)
			print(
				"[OPTIMIZATION_MATCHUP] strategy=%s enemy=%s "
				% [summary.id, matchup.id]
				+ "win=%.1f%% survive=%.1f%% escape=%.1f%% loss=%.1f%% "
				% [
					float(matchup.wins) / matchup_battles * 100.0,
					float(matchup.survivals) / matchup_battles * 100.0,
					float(matchup.enemy_escapes) / matchup_battles * 100.0,
					float(matchup.losses) / matchup_battles * 100.0,
				]
				+ "avg_rounds=%.2f avg_damage=%.2f"
				% [
					float(matchup.rounds) / matchup_battles,
					matchup.damage / matchup_battles,
				]
			)
