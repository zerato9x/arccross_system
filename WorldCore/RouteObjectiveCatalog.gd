extends Resource
class_name RouteObjectiveCatalog

const DEFAULT_PATH := "res://WorldCore/route_objectives.tres"

@export var objectives: Array[RouteObjectiveDefinition] = []


func get_objective(objective_id: String) -> RouteObjectiveDefinition:
	for objective in objectives:
		if objective != null and objective.objective_id == objective_id:
			return objective
	return null


func for_poi(poi_id: String) -> RouteObjectiveDefinition:
	for objective in objectives:
		if objective != null and objective.turn_in_poi_id == poi_id:
			return objective
	return null


static func data() -> RouteObjectiveCatalog:
	return load(DEFAULT_PATH) as RouteObjectiveCatalog
