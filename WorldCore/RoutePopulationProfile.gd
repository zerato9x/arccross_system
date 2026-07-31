extends Resource
class_name RoutePopulationProfile

@export var node_id: String = ""
@export var spawn_entries: Array[Dictionary] = []


func entries() -> Array[Dictionary]:
	return spawn_entries.duplicate(true)
