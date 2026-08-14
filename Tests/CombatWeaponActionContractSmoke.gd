extends SceneTree

const CATALOG_PATH := "res://CombatCore/Tactical/default_combat_action_catalog.tres"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := load(CATALOG_PATH) as CombatActionCatalog
	if catalog == null:
		_fail("The authored combat action catalog failed to load.")
		return
	var blade := ItemData.new()
	blade.id = "contract_blade"
	blade.display_name = "Contract Blade"
	blade.item_type = GameEnums.ItemType.WEAPON
	blade.weapon_type = GameEnums.WeaponClass.BLADE
	blade.specialized_action_ids = PackedStringArray(["strike", "strike"])
	if Array(blade.combat_action_ids()) != ["strike"]:
		_fail("Melee default and duplicate specialized IDs were not normalized deterministically.")
		return
	var blade_actions := catalog.weapon_action_definitions(blade)
	if blade_actions.size() != 1 or blade_actions[0].action_id != "strike" or not blade_actions[0].is_melee_weapon_action():
		_fail("The blade did not project the canonical typed Strike definition.")
		return

	var rifle := ItemData.new()
	rifle.id = "contract_rifle"
	rifle.display_name = "Contract Rifle"
	rifle.item_type = GameEnums.ItemType.WEAPON
	rifle.weapon_type = GameEnums.WeaponClass.RIFLE
	if Array(rifle.combat_action_ids()) != ["fire"]:
		_fail("The ranged default did not derive Fire.")
		return
	var hydrated := ItemData.from_runtime_state(rifle.create_runtime_instance().to_runtime_state())
	if Array(hydrated.combat_action_ids()) != ["fire"]:
		_fail("Weapon action authoring did not survive runtime serialization.")
		return

	var specialized_fire := catalog.definition("fire").duplicate(true) as CombatActionDefinition
	specialized_fire.action_id = "specialized_fire"
	specialized_fire.label = "Specialized Fire"
	catalog.definitions.append(specialized_fire)
	rifle.specialized_action_ids = PackedStringArray(["specialized_fire"])
	if not catalog.weapon_action_validation_error(rifle).is_empty():
		_fail("A catalog-authored specialized ranged action failed weapon validation.")
		return
	if Array(rifle.combat_action_ids()) != ["fire", "specialized_fire"]:
		_fail("The canonical ranged default was not ordered before its specialized action.")
		return
	var canonical_resolver := specialized_fire.resolver_id
	specialized_fire.resolver_id = "legacy_weapon_resolver"
	if catalog.weapon_action_validation_error(rifle).is_empty():
		_fail("A specialized action with a non-canonical weapon resolver passed validation.")
		specialized_fire.resolver_id = canonical_resolver
		return
	specialized_fire.resolver_id = canonical_resolver
	if not _specialized_quote_contract(specialized_fire):
		return

	rifle.specialized_action_ids = PackedStringArray(["burst_shot"])
	var validation_error := catalog.weapon_action_validation_error(rifle)
	if "Contract Rifle" not in validation_error or "contract_rifle" not in validation_error or "burst_shot" not in validation_error:
		_fail("Unknown weapon-action validation did not name the weapon and action: %s" % validation_error)
		return
	for maintenance_id in ["reload", "cycle", "ready"]:
		if maintenance_id in rifle.combat_action_ids():
			_fail("Maintenance action leaked into the authored weapon-action projection: %s" % maintenance_id)
			return
	print("COMBAT_WEAPON_ACTION_CONTRACT_SMOKE: PASS")
	quit(0)


func _specialized_quote_contract(definition: CombatActionDefinition) -> bool:
	var rules := CombatRulesState.new()
	rules.current_ap_pool = 12
	rules.active_actor_id = "shooter"
	rules.action_definitions = {definition.action_id: definition}
	rules.actor_facts = {
		"shooter": {
			"actor_id": "shooter",
			"sector_index": 0,
			"sector": Vector2i.ZERO,
			"right_arm_function": GameEnums.SCALE_MAX,
			"left_arm_function": GameEnums.SCALE_MAX,
			"combat_accuracy_ranged": 0.6,
			"ranged_weapon": {
				"id": "contract_rifle",
				"ranged": true,
				"combat_action_ids": ["fire", "specialized_fire"],
				"jammed": true,
				"condition": 12.0,
				"current_magazine": 5,
				"maximum_range_cells": 12,
				"optimal_range_cells": Vector2i(1, 6),
				"range_falloff": 0.05,
				"flesh_damage": 3.0,
				"damage_type": GameEnums.DamageType.BALLISTIC,
			},
		},
		"target": {
			"actor_id": "target",
			"sector_index": 1,
			"sector": Vector2i(1, 0),
			"armor_protection": {},
		},
	}
	rules.sector_facts = {
		0: {"coords": Vector2i.ZERO, "blocked": false, "opaque": false, "cover_edges": {}},
		1: {"coords": Vector2i(1, 0), "blocked": false, "opaque": false, "cover_edges": {}},
	}
	rules.occupancy = {0: ["shooter"], 1: ["target"]}
	rules.coordinates_by_index = {0: Vector2i.ZERO, 1: Vector2i(1, 0)}
	rules.indices_by_coordinate = {"0,0": 0, "1,0": 1}
	rules.neighbors = {0: [1], 1: [0]}
	rules.relationships = {CombatRelationshipLedger.pair_key("shooter", "target"): CombatRelationshipLedger.Relation.HOSTILE}
	var request := CombatActionRequest.new()
	request.actor_id = "shooter"
	request.target_actor_id = "target"
	request.action_id = definition.action_id
	var jammed_quote := CombatActionQuoteService.quote(request, rules)
	if jammed_quote.legal or jammed_quote.denial_code != "weapon_not_ready":
		_fail("Specialized ranged action bypassed shared jam/readiness legality.")
		return false
	var shooter: Dictionary = rules.actor_facts["shooter"]
	var weapon: Dictionary = shooter["ranged_weapon"]
	weapon["jammed"] = false
	shooter["ranged_weapon"] = weapon
	rules.actor_facts["shooter"] = shooter
	var ready_quote := CombatActionQuoteService.quote(request, rules)
	if not ready_quote.legal or ready_quote.forecast == null:
		_fail("Ready specialized ranged action did not reuse generic quote/forecast behavior.")
		return false
	return true


func _fail(message: String) -> void:
	push_error("COMBAT_WEAPON_ACTION_CONTRACT_SMOKE: " + message)
	quit(1)
