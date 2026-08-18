extends Resource
class_name CombatMapComposition

@export var schema_version: int = 2
@export var variant_id: String = ""
@export var map_seed: int = 0
@export var base_ground_path: String = ""
@export var base_ground_modulation: Color = Color.WHITE
@export var palette: Dictionary = {}
@export var source_provenance: Dictionary = {}
@export var layer_metadata: Array = []
@export var variant_overrides: Dictionary = {}
@export var road_cells: Array[Vector2i] = []
@export var water_cells: Array[Vector2i] = []
@export var dominant_landmark: Dictionary = {}
@export var props: Array[Dictionary] = []
@export var landmark_instances: Array = []
@export var prop_instances: Array = []
@export var sector_facts: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"variant_id": variant_id,
		"seed": map_seed,
		"base_ground_path": base_ground_path,
		"base_ground_modulation": base_ground_modulation,
		"palette": palette.duplicate(true),
		"source_provenance": source_provenance.duplicate(true),
		"layer_metadata": layer_metadata.duplicate(true),
		"variant_overrides": variant_overrides.duplicate(true),
		"road_cells": road_cells.duplicate(),
		"water_cells": water_cells.duplicate(),
		"dominant_landmark": dominant_landmark.duplicate(true),
		"props": props.duplicate(true),
		"landmark_instances": landmark_instances.duplicate(true),
		"prop_instances": prop_instances.duplicate(true),
		"sector_facts": sector_facts.duplicate(true),
	}


static func from_dict(data: Dictionary):
	var result = (load("res://CombatCore/Tactical/CombatMapComposition.gd") as Script).new()
	result.schema_version = int(data.get("schema_version", 1))
	result.variant_id = str(data.get("variant_id", ""))
	result.map_seed = int(data.get("seed", 0))
	result.base_ground_path = str(data.get("base_ground_path", ""))
	result.base_ground_modulation = data.get("base_ground_modulation", Color.WHITE)
	result.palette = data.get("palette", {}).duplicate(true)
	result.source_provenance = data.get("source_provenance", {}).duplicate(true)
	result.layer_metadata.assign(data.get("layer_metadata", []))
	result.variant_overrides = data.get("variant_overrides", {}).duplicate(true)
	result.road_cells.assign(data.get("road_cells", []))
	result.water_cells.assign(data.get("water_cells", []))
	result.dominant_landmark = data.get("dominant_landmark", {}).duplicate(true)
	result.props.assign(data.get("props", []))
	result.landmark_instances.assign(data.get("landmark_instances", []))
	result.prop_instances.assign(data.get("prop_instances", []))
	result.sector_facts = data.get("sector_facts", {}).duplicate(true)
	return result
