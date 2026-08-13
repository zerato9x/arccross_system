@tool
extends Resource
class_name CombatEncounterAssemblyProfile

## Data contract for macro-to-tactical participant selection.

@export var profile_id: String = "default"
@export_range(0, 8) var axial_radius: int = 2
@export_range(2, 6) var participant_cap: int = 6
@export_range(0.0, 1.0, 0.05) var aware_same_squad_threshold: float = 0.5
@export var late_reinforcements_enabled: bool = false
@export var default_return_policy: String = "origin"
