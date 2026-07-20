extends Resource
class_name EntityDefinition

@export_group("Identity & Faction")
@export var archetype_name: String = "Baseline Human"
@export var faction: GameEnums.Faction = GameEnums.Faction.UNALIGNED
@export var agenda: GameEnums.Agenda = GameEnums.Agenda.SURVIVALIST
## Optional authored dialogue profile id for unique NPC Ask trees.
@export var dialogue_id: String = ""
## When false, Ceasefire Trade stays locked.
@export var allows_trade: bool = true
# --- THE 12-POINT PILLARS ---
@export_group("Core Attributes")
@export_range(1, 12) var brawn: int = 6     # 6 = Average
@export_range(1, 12) var finesse: int = 6   
@export_range(1, 12) var fortitude: int = 6 
@export_range(1, 12) var will: int = 6

@export_group("Background")
@export var occupation_id: String = ""
@export var trait_ids: PackedStringArray = []
@export var flaw_ids: PackedStringArray = []

@export_group("Combat Behavior")
## Determines the scoring multipliers and priorities in a firefight.
@export var combat_tactic: GameEnums.CombatTactic = GameEnums.CombatTactic.BRUTE

@export_group("Arc Manifestation")
@export var arc_tier: GameEnums.ArcbornTier = GameEnums.ArcbornTier.NONE
@export_range(0.0, 12.0) var max_arc_energy: float = 0.0
@export_range(0.0, 12.0) var red_mist_resistance: float = 0.0

@export_group("Spawn Loadout")
## The starting gear this entity spawns with. Drag a SpawnLoadout .tres here.
@export var loadout: SpawnLoadout

func to_state() -> Dictionary:
	return {
		"archetype_name": archetype_name,
		"faction": faction,
		"agenda": agenda,
		"dialogue_id": dialogue_id,
		"allows_trade": allows_trade,
		"brawn": brawn,
		"finesse": finesse,
		"fortitude": fortitude,
		"will": will,
		"occupation_id": occupation_id,
		"trait_ids": Array(trait_ids),
		"flaw_ids": Array(flaw_ids),
		"combat_tactic": combat_tactic,
		"arc_tier": arc_tier,
		"max_arc_energy": max_arc_energy,
		"red_mist_resistance": red_mist_resistance,
		"loadout": loadout.to_state() if loadout else {},
	}

static func from_state(state: Dictionary) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.archetype_name = state.get("archetype_name", "Baseline Human")
	definition.faction = state.get("faction", GameEnums.Faction.UNALIGNED)
	definition.agenda = state.get("agenda", GameEnums.Agenda.SURVIVALIST)
	definition.dialogue_id = str(state.get("dialogue_id", ""))
	definition.allows_trade = bool(state.get("allows_trade", true))
	definition.brawn = clampi(state.get("brawn", 6), 1, 12)
	definition.finesse = clampi(state.get("finesse", 6), 1, 12)
	definition.fortitude = clampi(state.get("fortitude", 6), 1, 12)
	definition.will = clampi(state.get("will", 6), 1, 12)
	definition.occupation_id = str(state.get("occupation_id", ""))
	definition.trait_ids = _string_array(state.get("trait_ids", []))
	definition.flaw_ids = _string_array(state.get("flaw_ids", []))
	definition.combat_tactic = state.get("combat_tactic", GameEnums.CombatTactic.BRUTE)
	definition.arc_tier = state.get("arc_tier", GameEnums.ArcbornTier.NONE)
	definition.max_arc_energy = clampf(
		float(state.get("max_arc_energy", 0.0)),
		0.0,
		GameEnums.SCALE_MAX
	)
	definition.red_mist_resistance = clampf(
		float(state.get("red_mist_resistance", 0.0)),
		0.0,
		GameEnums.SCALE_MAX
	)

	var loadout_state: Dictionary = state.get("loadout", {})
	if not loadout_state.is_empty():
		definition.loadout = SpawnLoadout.from_state(loadout_state)

	return definition


static func _string_array(values: Variant) -> PackedStringArray:
	var result: PackedStringArray = []
	if values is PackedStringArray:
		return values
	if values is Array:
		for value in values:
			var text := str(value)
			if not text.is_empty():
				result.append(text)
	return result
