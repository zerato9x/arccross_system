extends Resource
class_name EntityDefinition

@export_group("Identity & Faction")
@export var archetype_name: String = "Baseline Human"
@export var faction: GameEnums.Faction = GameEnums.Faction.UNALIGNED
@export var agenda: GameEnums.Agenda = GameEnums.Agenda.SURVIVALIST
# --- THE 12-POINT PILLARS ---
@export_group("Core Attributes")
@export_range(1, 12) var brawn: int = 6     # 6 = Average
@export_range(1, 12) var finesse: int = 6   
@export_range(1, 12) var fortitude: int = 6 
@export_range(1, 12) var will: int = 6      

@export_group("Combat Behavior")
## Determines the scoring multipliers and priorities in a firefight.
@export var combat_tactic: GameEnums.CombatTactic = GameEnums.CombatTactic.BRUTE

@export_group("Arc Manifestation")
@export var arc_tier: GameEnums.ArcbornTier = GameEnums.ArcbornTier.NONE
@export var max_arc_energy: float = 0.0
@export var red_mist_resistance: float = 0.0

@export_group("Spawn Loadout")
## The starting gear this entity spawns with. Drag a SpawnLoadout .tres here.
@export var loadout: SpawnLoadout

func to_state() -> Dictionary:
	return {
		"archetype_name": archetype_name,
		"faction": faction,
		"agenda": agenda,
		"brawn": brawn,
		"finesse": finesse,
		"fortitude": fortitude,
		"will": will,
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
	definition.brawn = state.get("brawn", 6)
	definition.finesse = state.get("finesse", 6)
	definition.fortitude = state.get("fortitude", 6)
	definition.will = state.get("will", 6)
	definition.combat_tactic = state.get("combat_tactic", GameEnums.CombatTactic.BRUTE)
	definition.arc_tier = state.get("arc_tier", GameEnums.ArcbornTier.NONE)
	definition.max_arc_energy = state.get("max_arc_energy", 0.0)
	definition.red_mist_resistance = state.get("red_mist_resistance", 0.0)

	var loadout_state: Dictionary = state.get("loadout", {})
	if not loadout_state.is_empty():
		definition.loadout = SpawnLoadout.from_state(loadout_state)

	return definition
