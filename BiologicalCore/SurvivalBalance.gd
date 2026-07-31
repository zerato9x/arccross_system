extends Resource
class_name SurvivalBalance

## Data-only tuning for macro survival. Mods may replace the default resource
## without changing HumanoidBody or WorldCore orchestration.

@export_group("Reserve Drain Per 15 Minutes")
@export_range(0.0, 12.0, 0.01) var hunger_drain: float = 0.12
@export_range(0.0, 12.0, 0.01) var thirst_drain: float = 0.36
@export_range(0.0, 12.0, 0.01) var fatigue_gain: float = 0.24

@export_group("Zero Hunger Crisis")
@export_range(0, 1440, 15) var hunger_grace_minutes: int = 360
@export_range(15, 2880, 15) var hunger_fatal_minutes: int = 1440
@export_range(0.0, 12.0, 0.01) var hunger_blood_loss_per_hour: float = 0.5
@export_range(0.0, 12.0, 0.01) var hunger_fatigue_per_hour: float = 0.25

@export_group("Zero Thirst Crisis")
@export_range(0, 720, 15) var thirst_grace_minutes: int = 60
@export_range(15, 1440, 15) var thirst_fatal_minutes: int = 360
@export_range(0.0, 12.0, 0.01) var thirst_blood_loss_per_hour: float = 2.0
@export_range(0.0, 12.0, 0.01) var thirst_fatigue_per_hour: float = 1.0


func validate() -> bool:
	return (
		hunger_fatal_minutes > hunger_grace_minutes
		and thirst_fatal_minutes > thirst_grace_minutes
		and hunger_drain >= 0.0
		and thirst_drain >= 0.0
		and fatigue_gain >= 0.0
	)
