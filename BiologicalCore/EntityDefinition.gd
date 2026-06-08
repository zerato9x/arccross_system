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

@export_group("Arc Manifestation")
@export var arc_tier: GameEnums.ArcbornTier = GameEnums.ArcbornTier.NONE
@export var max_arc_energy: float = 0.0
@export var red_mist_resistance: float = 0.0

@export_group("Spawn Loadout")
## The starting gear this entity spawns with. Drag a SpawnLoadout .tres here.
@export var loadout: SpawnLoadout
