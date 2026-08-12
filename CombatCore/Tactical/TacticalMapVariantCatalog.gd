extends Resource
class_name TacticalMapVariantCatalog

## Family -> weighted variant dictionaries. Content packs can replace this
## resource without changing generation or rendering code.
@export var variants: Dictionary = {}


func choose(family: String, seed_value: int) -> Dictionary:
	var candidates: Array = variants.get(family, variants.get("default", []))
	if candidates.is_empty():
		return {"id": "%s_%02d" % [family, posmod(seed_value, 3)], "weight": 1.0}
	var total := 0.0
	for candidate in candidates:
		total += maxf(0.0, float(candidate.get("weight", 1.0)))
	if total <= 0.0:
		return (candidates[0] as Dictionary).duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var roll := rng.randf() * total
	for candidate in candidates:
		roll -= maxf(0.0, float(candidate.get("weight", 1.0)))
		if roll <= 0.0:
			return (candidate as Dictionary).duplicate(true)
	return (candidates.back() as Dictionary).duplicate(true)
