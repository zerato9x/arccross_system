extends RefCounted
class_name CombatHardStateClassifier

const _Result := preload("res://CombatCore/Tactical/CombatHardStateResult.gd")

const PRIORITY := [
	_Result.INACTIVE,
	_Result.BROKEN,
	_Result.ENGAGED,
	_Result.CRITICAL,
	_Result.WEAPON_DISABLED,
	_Result.OUT_OF_AMMO,
	_Result.THREATENED,
	_Result.OUTNUMBERED,
	_Result.EXPOSED,
	_Result.TRAPPED,
	_Result.STABLE,
]


static func classify(snapshot):
	var result = _Result.new()
	if snapshot == null:
		result.tags = [_Result.INACTIVE]
		result.dominant_tag = _Result.INACTIVE
		result.terminal = true
		return result
	result.snapshot_revision = snapshot.revision
	var source: Dictionary = snapshot.hard_facts.duplicate(true)
	var source_tags: Array = source.get("tags", [])
	for raw_tag in source_tags:
		var tag := str(raw_tag)
		if tag not in result.tags:
			result.tags.append(tag)
	if result.tags.is_empty():
		result.tags.append(_Result.STABLE)
	for tag in PRIORITY:
		if tag in result.tags:
			result.dominant_tag = tag
			break
	result.terminal = _Result.INACTIVE in result.tags or _Result.BROKEN in result.tags
	result.reason_tags = result.tags.duplicate()
	return result
