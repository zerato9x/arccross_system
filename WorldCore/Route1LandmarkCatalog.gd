extends Resource
class_name Route1LandmarkCatalog

const DEFAULT_PATH := "res://WorldCore/route1_landmarks.tres"

@export var landmarks: Array[Route1LandmarkDefinition] = []


func for_arm(arm_id: String) -> Route1LandmarkDefinition:
	for landmark in landmarks:
		if landmark != null and landmark.arm_id == arm_id:
			return landmark
	return null


func for_poi(poi_id: String) -> Route1LandmarkDefinition:
	for landmark in landmarks:
		if landmark != null and landmark.poi_id == poi_id:
			return landmark
	return null


static func data() -> Route1LandmarkCatalog:
	return load(DEFAULT_PATH) as Route1LandmarkCatalog
