extends Resource
class_name TacticalTerrainCatalog

## Data-owned mapping from macro layers to tactical sector behavior. Content
## packs can replace this Resource without changing arena-generation code.

@export var terrain_profiles: Dictionary = {}
@export var flora_profiles: Dictionary = {}
@export var rock_profiles: Dictionary = {}
@export var water_profiles: Dictionary = {}
@export var structure_profiles: Dictionary = {}


func terrain(value: int) -> Dictionary:
	return _profile(terrain_profiles, value)


func flora(value: int) -> Dictionary:
	return _profile(flora_profiles, value)


func rock(value: int) -> Dictionary:
	return _profile(rock_profiles, value)


func water(value: int) -> Dictionary:
	return _profile(water_profiles, value)


func structure(value: int) -> Dictionary:
	return _profile(structure_profiles, value)


func _profile(source: Dictionary, value: int) -> Dictionary:
	var profile: Variant = source.get(value, source.get(str(value), {}))
	return profile.duplicate(true) if profile is Dictionary else {}
