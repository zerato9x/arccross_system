extends Resource
class_name DuelWeaponProfile

@export var profile_id: String = "default"

@export_group("Melee")
@export var light_cost: float = 3.0
@export var light_duration: float = 2.2
@export var light_impact_time: float = 1.35
@export var light_flesh_multiplier: float = 0.85
@export var light_stance_multiplier: float = 0.8
@export var heavy_cost: float = 5.0
@export var heavy_duration: float = 3.4
@export var heavy_impact_time: float = 2.15
@export var heavy_commit_time: float = 1.15
@export var heavy_flesh_multiplier: float = 1.3
@export var heavy_stance_multiplier: float = 1.5
@export var finisher_cost: float = 6.0
@export var finisher_duration: float = 4.2
@export var finisher_impact_time: float = 2.65
@export var finisher_flesh_multiplier: float = 1.75
@export var finisher_stance_multiplier: float = 2.0
@export var combo_window: float = 1.25
@export var combo_sequence: Array[int] = [
	GameEnums.DuelIntent.LIGHT_ATTACK,
	GameEnums.DuelIntent.LIGHT_ATTACK,
	GameEnums.DuelIntent.HEAVY_ATTACK,
]

@export_group("Ranged")
@export var blind_cost: float = 4.0
@export var blind_duration: float = 1.9
@export var blind_impact_time: float = 1.15
@export var aim_setup_cost: float = 1.0
@export var aimed_fire_cost: float = 5.0
@export var base_aim_time: float = 2.4
@export var full_aim_accuracy_bonus: float = 0.24
@export_range(0.0, 1.0) var full_aim_head_weight: float = 0.35

@export_group("Presentation")
@export var light_animation: String = "Attack3"
@export var second_light_animation: String = "Attack4"
@export var heavy_animation: String = "Attack2"
@export var finisher_animation: String = "Attack1"
@export var firearm_animation: String = "Attack1"
