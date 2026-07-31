extends Resource
class_name RoutePopulationCatalog

const DEFAULT_PATH := "res://WorldCore/route1_populations.tres"

@export var profiles: Array[RoutePopulationProfile] = []


func for_node(node_id: String) -> RoutePopulationProfile:
	for profile in profiles:
		if profile != null and profile.node_id == node_id:
			return profile
	return null


static func data() -> RoutePopulationCatalog:
	return load(DEFAULT_PATH) as RoutePopulationCatalog
