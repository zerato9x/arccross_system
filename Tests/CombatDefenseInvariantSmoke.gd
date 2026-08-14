extends SceneTree

var _failures: Array[String] = []
var _injury_events: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var attacker := _actor("defense_attacker", GameEnums.Faction.ARCBORN_RESISTANCE)
	var defender := _actor("defense_defender", GameEnums.Faction.CRAVEN_HIVE)
	root.add_child(attacker)
	root.add_child(defender)
	await process_frame

	_verify_wounds(defender)
	_verify_equipment(defender)
	await _verify_stance_and_cover(attacker, defender)
	_verify_range_and_conditions()

	if _failures.is_empty():
		print("COMBAT_DEFENSE_INVARIANT_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _verify_wounds(defender: HumanoidCore) -> void:
	var bus := root.get_node_or_null("GameEventBus")
	if bus != null and not bus.humanoid_injured.is_connected(_on_humanoid_injured):
		bus.humanoid_injured.connect(_on_humanoid_injured)
	var before := defender.body.get_total_wound_count()
	var identity := {
		"encounter_id": "defense_invariant",
		"action_event_id": "defense_invariant:1:strike",
		"action_id": "strike",
		"attacker_id": "defense_attacker",
		"victim_id": "defense_defender",
		"source_item_instance_id": "test_blade_instance",
	}
	defender.body.apply_targeted_hit(
		GameEnums.LimbRegion.UPPER_TORSO,
		2.0,
		0.5,
		GameEnums.DamageType.SHARP,
		identity
	)
	if defender.body.get_total_wound_count() != before + 1:
		_failures.append("A positive targeted hit did not create exactly one wound.")
	if _injury_events.size() != 1:
		_failures.append("Wound creation did not emit exactly one HumanInjured event.")
	elif str(_injury_events[0].get("action_event_id", "")) != "defense_invariant:1:strike":
		_failures.append("The wound event lost its action identity.")


func _verify_equipment(defender: HumanoidCore) -> void:
	var armor_definition := load("res://ItemCore/Items/armor_arcborn.tres") as ItemData
	var armor := armor_definition.create_runtime_instance() if armor_definition != null else null
	if armor == null or not defender.inventory.equip_item(armor, GameEnums.EquipmentSlot.OUTER_TORSO):
		_failures.append("Authored torso armor could not be equipped for the defense invariant.")
		return
	var protected := defender.inventory.preview_protection(
		GameEnums.DamageType.BALLISTIC,
		GameEnums.LimbRegion.UPPER_TORSO
	)
	var uncovered := defender.inventory.preview_protection(
		GameEnums.DamageType.BALLISTIC,
		GameEnums.LimbRegion.HEAD
	)
	if protected <= uncovered or protected <= 0.0:
		_failures.append("Equipment coverage did not produce region-specific protection.")


func _verify_stance_and_cover(attacker: HumanoidCore, defender: HumanoidCore) -> void:
	var board := CombatBoard.new()
	root.add_child(board)
	await process_frame
	var stance_before := board.stance(defender)
	var stance_event := board.apply_stance_damage(defender, 2.0, false, "defense_invariant")
	if float(stance_event.get("amount", 0.0)) != 2.0 or board.stance(defender) >= stance_before:
		_failures.append("Stance damage did not change the typed combat-state pool.")

	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.encounter_id = "defense_invariant"
	encounter.world_seed = "DEFENSE_INVARIANT"
	encounter.center_hex = HexRecord.new()
	encounter.center_hex.zone_id = "defense_invariant"
	encounter.center_hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	board.configure_from_encounter(encounter)
	var defender_index := board.arena_state.index_for(Vector2i(2, 2))
	var attacker_index := board.arena_state.index_for(Vector2i(4, 2))
	if not board.force_spawn_actor(defender, defender_index, "enemy"):
		_failures.append("Could not place the defender for the cover invariant.")
	if not board.force_spawn_actor(attacker, attacker_index, "player"):
		_failures.append("Could not place the attacker for the cover invariant.")
	var sector = board.sectors[defender_index]
	sector.record.cover_edges = {"east": 0.8}
	sector.configure(sector.record)
	if not board.take_cover(defender, attacker_index):
		_failures.append("Geometry-authored east cover could not be taken against an eastern threat.")
	elif not is_equal_approx(board.cover_against(defender_index, attacker_index), 0.8):
		_failures.append("Cover defense was not derived from the threatened sector edge.")


func _verify_range_and_conditions() -> void:
	var catalog := load("res://CombatCore/Tactical/default_combat_action_catalog.tres") as CombatActionCatalog
	var rules_state := RefCounted.new()
	var defender := {
		"sector": Vector2i(2, 0),
		"armor_protection": {},
	}
	var melee_attacker := {
		"combat_accuracy_melee": 0.6,
		"right_arm_function": GameEnums.SCALE_MAX,
		"off_balance": false,
		"melee_weapon": {
			"flesh_damage": 2.0,
			"damage_type": GameEnums.DamageType.BLUNT,
			"armor_penetration": 0.0,
		},
	}
	var quote := CombatActionQuote.new()
	quote.projected_origin = Vector2i(2, 0)
	var normal := CombatForecastService.build(
		CombatActionRequest.new(), catalog.definition("strike"), melee_attacker, defender, rules_state, quote
	)
	melee_attacker["off_balance"] = true
	var conditioned := CombatForecastService.build(
		CombatActionRequest.new(), catalog.definition("strike"), melee_attacker, defender, rules_state, quote
	)
	if conditioned.hit_probability >= normal.hit_probability:
		_failures.append("Off-balance did not reduce melee defense resolution accuracy.")

	var ranged_attacker := {
		"combat_accuracy_ranged": 0.65,
		"right_arm_function": GameEnums.SCALE_MAX,
		"ranged_weapon": {
			"flesh_damage": 3.0,
			"damage_type": GameEnums.DamageType.BALLISTIC,
			"armor_penetration": 1.0,
			"optimal_range_cells": Vector2i(1, 3),
			"range_falloff": 0.10,
		},
	}
	var near_quote := CombatActionQuote.new()
	near_quote.projected_origin = Vector2i(0, 0)
	var near_defender := defender.duplicate(true)
	near_defender["sector"] = Vector2i(2, 0)
	var far_defender := defender.duplicate(true)
	far_defender["sector"] = Vector2i(9, 0)
	var near_forecast := CombatForecastService.build(
		CombatActionRequest.new(), catalog.definition("fire"), ranged_attacker, near_defender, rules_state, near_quote
	)
	var far_forecast := CombatForecastService.build(
		CombatActionRequest.new(), catalog.definition("fire"), ranged_attacker, far_defender, rules_state, near_quote
	)
	if far_forecast.hit_probability >= near_forecast.hit_probability:
		_failures.append("Range pressure did not reduce ranged hit probability outside the weapon band.")


func _actor(actor_id: String, faction: int) -> HumanoidCore:
	var actor := HumanoidCore.new()
	actor.name = actor_id
	actor.set_meta("actor_id", actor_id)
	var definition := EntityDefinition.new()
	definition.archetype_name = actor_id
	definition.faction = faction as GameEnums.Faction
	definition.brawn = 6
	definition.fortitude = 6
	definition.will = 6
	actor.definition = definition
	var body := HumanoidBody.new()
	body.name = "HumanoidBody"
	actor.add_child(body)
	var inventory := InventorySystem.new()
	inventory.name = "InventorySystem"
	actor.add_child(inventory)
	return actor


func _on_humanoid_injured(_entity: Node, _wound_type: int, context: Dictionary) -> void:
	_injury_events.append(context.duplicate(true))
