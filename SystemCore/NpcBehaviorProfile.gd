@tool
extends Resource
class_name NpcBehaviorProfile

## Neutral authored decision weights. WorldCore and CombatCore consume their
## own projections; neither domain imports the other.

@export var profile_id: String = "default"
@export var role_id: String = ""
@export var hunger_threshold: float = 3.0
@export var thirst_threshold: float = 3.0
@export var pursuit_radius: int = 3
@export var work_weights: Dictionary = {}
@export var combat_weights: Dictionary = {}
@export var exploration_weights: Dictionary = {}
@export var combat_tag_weights: Dictionary = {}
## Fine-grained score coefficients stay authored beside the role/tag weights;
## tactical code supplies only safe fallbacks for older profile resources.
@export var combat_score_weights: Dictionary = {}
## Combat intent and plan policy are authored data, not evaluator constants.
@export var motive_weights: Dictionary = {}
@export var utility_weights: Dictionary = {}
## Optional authored transforms for observable utility facts. Kept beside the
## existing weights so roles can tune missing signals without a second profile
## type or evaluator-owned constants.
@export var utility_inputs: Dictionary = {}
@export var tactical_problem_weights: Dictionary = {}
@export var allowed_plan_templates: Array[String] = []
@export var intent_presentation_id: String = "default"
@export_range(0.0, 1.0, 0.01) var motive_switch_margin: float = 0.15
@export_range(0.0, 1.0, 0.01) var motive_inertia: float = 0.15
@export var preferred_range_cells := Vector2i(1, 2)
@export_range(0.0, 12.0, 0.1) var retreat_pressure: float = 9.0
@export var cover_weight: float = 1.0
@export var flank_weight: float = 1.0
@export var hazard_weight: float = 1.0
@export var tags: Array[String] = []


func weight_for_combat_tag(tag: String) -> float:
	return float(combat_tag_weights.get(tag, 0.0))


func score_weight(key: String, fallback: float = 0.0) -> float:
	return float(combat_score_weights.get(key, fallback))


func exploration_projection() -> Dictionary:
	var weights := exploration_weights.duplicate(true)
	if weights.is_empty():
		weights = work_weights.duplicate(true)
	return {
		"profile_id": profile_id,
		"goal_weights": weights,
		"retreat_pressure": retreat_pressure,
		"tags": tags.duplicate(),
	}


func combat_projection() -> Dictionary:
	return {
		"profile_id": profile_id,
		"combat_weights": combat_weights.duplicate(true),
		"tag_weights": combat_tag_weights.duplicate(true),
		"score_weights": combat_score_weights.duplicate(true),
		"motive_weights": motive_weights.duplicate(true),
		"utility_weights": utility_weights.duplicate(true),
		"utility_inputs": utility_inputs.duplicate(true),
		"tactical_problem_weights": tactical_problem_weights.duplicate(true),
		"allowed_plan_templates": allowed_plan_templates.duplicate(),
		"intent_presentation_id": intent_presentation_id,
		"motive_switch_margin": motive_switch_margin,
		"motive_inertia": motive_inertia,
		"preferred_range_cells": preferred_range_cells,
		"retreat_pressure": retreat_pressure,
		"cover_weight": cover_weight,
		"flank_weight": flank_weight,
		"hazard_weight": hazard_weight,
		"tags": tags.duplicate(),
	}
