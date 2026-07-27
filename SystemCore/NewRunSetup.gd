extends Resource
class_name NewRunSetup

@export var world_seed: String = "DEMO_WASTELAND_01"
@export var base_definition_path: String = "res://BiologicalCore/player_def.tres"
@export var occupation_id: String = ""
@export var trait_ids: PackedStringArray = []
@export var flaw_ids: PackedStringArray = []
@export var start_node_id: String = ""
@export var arrival_direction: int = GameEnums.MacroTravelDirection.SOUTH
@export var intro_version: int = 1


func validate(allowed_start_node_ids: PackedStringArray = []) -> PackedStringArray:
	var failures := IdentityCatalog.validate_selection(occupation_id, trait_ids, flaw_ids)
	if world_seed.is_empty():
		failures.append("World seed is required.")
	if not ResourceLoader.exists(base_definition_path):
		failures.append("Player definition is missing: %s" % base_definition_path)
	if start_node_id.is_empty():
		failures.append("A starting node is required.")
	elif not allowed_start_node_ids.is_empty() and not allowed_start_node_ids.has(start_node_id):
		failures.append("Invalid starting node: %s" % start_node_id)
	elif (
		not allowed_start_node_ids.is_empty()
		and arrival_direction != MacroGraphGenerator.arrival_direction_for_start(start_node_id)
	):
		failures.append("Arrival direction does not match starting node: %s" % start_node_id)
	return failures


func build_definition_state() -> Dictionary:
	var base := load(base_definition_path) as EntityDefinition
	if base == null:
		return {}
	var definition := base.duplicate(true) as EntityDefinition
	definition.occupation_id = occupation_id
	definition.trait_ids = trait_ids.duplicate()
	definition.flaw_ids = flaw_ids.duplicate()
	if definition.loadout != null:
		definition.loadout = definition.loadout.duplicate(true) as SpawnLoadout
	var occupation := IdentityCatalog.occupation_definition(occupation_id)
	if occupation != null:
		if definition.loadout == null:
			definition.loadout = SpawnLoadout.new()
		for item in occupation.starting_items:
			if item != null:
				definition.loadout.starting_items.append(item)
	return definition.to_state()


func to_state() -> Dictionary:
	return {
		"world_seed": world_seed,
		"base_definition_path": base_definition_path,
		"occupation_id": occupation_id,
		"trait_ids": Array(trait_ids),
		"flaw_ids": Array(flaw_ids),
		"start_node_id": start_node_id,
		"arrival_direction": arrival_direction,
		"intro_version": intro_version,
		"definition": build_definition_state(),
	}


static func from_state(state: Dictionary) -> NewRunSetup:
	var setup := NewRunSetup.new()
	setup.world_seed = str(state.get("world_seed", setup.world_seed))
	setup.base_definition_path = str(state.get("base_definition_path", setup.base_definition_path))
	setup.occupation_id = str(state.get("occupation_id", ""))
	setup.trait_ids = EntityDefinition._string_array(state.get("trait_ids", []))
	setup.flaw_ids = EntityDefinition._string_array(state.get("flaw_ids", []))
	setup.start_node_id = str(state.get("start_node_id", ""))
	setup.arrival_direction = int(state.get("arrival_direction", GameEnums.MacroTravelDirection.SOUTH))
	setup.intro_version = int(state.get("intro_version", 1))
	return setup
