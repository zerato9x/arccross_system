extends Resource
class_name CombatMapComposition

@export var schema_version: int = 1
@export var variant_id: String = ""
@export var seed: int = 0
@export var base_ground_path: String = ""
@export var road_cells: Array[Vector2i] = []
@export var water_cells: Array[Vector2i] = []
@export var dominant_landmark: Dictionary = {}
@export var props: Array[Dictionary] = []
@export var sector_facts: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"variant_id": variant_id,
		"seed": seed,
		"base_ground_path": base_ground_path,
		"road_cells": road_cells.duplicate(),
		"water_cells": water_cells.duplicate(),
		"dominant_landmark": dominant_landmark.duplicate(true),
		"props": props.duplicate(true),
		"sector_facts": sector_facts.duplicate(true),
	}


static func from_dict(data: Dictionary):
	var result = (load("res://CombatCore/Tactical/CombatMapComposition.gd") as Script).new()
	result.schema_version = int(data.get("schema_version", 1))
	result.variant_id = str(data.get("variant_id", ""))
	result.seed = int(data.get("seed", 0))
	result.base_ground_path = str(data.get("base_ground_path", ""))
	result.road_cells.assign(data.get("road_cells", []))
	result.water_cells.assign(data.get("water_cells", []))
	result.dominant_landmark = data.get("dominant_landmark", {}).duplicate(true)
	result.props.assign(data.get("props", []))
	result.sector_facts = data.get("sector_facts", {}).duplicate(true)
	return result
