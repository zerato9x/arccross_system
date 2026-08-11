extends SceneTree

const _Snapshot := preload("res://CombatCore/Tactical/CombatPerceptionSnapshot.gd")
const _Classifier := preload("res://CombatCore/Tactical/CombatHardStateClassifier.gd")
const _Result := preload("res://CombatCore/Tactical/CombatHardStateResult.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot = _Snapshot.new()
	snapshot.revision = 9
	snapshot.hard_facts = {"tags": [_Result.ENGAGED, _Result.THREATENED, _Result.EXPOSED]}
	var first = _Classifier.classify(snapshot)
	var second = _Classifier.classify(snapshot)
	if first.dominant_tag != _Result.ENGAGED or first.tags.size() != 3:
		return _fail("Hard-state classifier lost coexisting engaged/threat tags.")
	if first.to_dict() != second.to_dict():
		return _fail("Identical hard-state inputs were not stable.")
	snapshot.hard_facts = {"tags": [_Result.INACTIVE, _Result.BROKEN, _Result.CRITICAL]}
	var terminal = _Classifier.classify(snapshot)
	if not terminal.terminal or terminal.dominant_tag != _Result.INACTIVE:
		return _fail("Inactive/broken hard state did not short-circuit normal planning.")
	print("COMBAT_AI_HARD_STATE_SMOKE: PASS")
	quit(0)


func _fail(message: String) -> bool:
	push_error("[COMBAT_AI_HARD_STATE] " + message)
	quit(1)
	return false
