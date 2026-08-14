extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var current := {
		"schema_version": CombatArenaState.SCHEMA_VERSION,
		"width": 1,
		"height": 1,
		"sectors": [],
	}
	if not CombatArenaState.compatibility_error(current).is_empty():
		_fail("The current combat arena schema was rejected.")
		return
	var old := current.duplicate(true)
	old["schema_version"] = CombatArenaState.SCHEMA_VERSION - 1
	var error := CombatArenaState.compatibility_error(old)
	if "incompatible" not in error or "start a new combat encounter" not in error:
		_fail("Old combat schema rejection was not explicit: %s" % error)
		return
	var missing := current.duplicate(true)
	missing.erase("schema_version")
	if CombatArenaState.compatibility_error(missing).is_empty():
		_fail("A versionless combat snapshot was silently accepted.")
		return
	print("COMBAT_SCHEMA_REJECTION_SMOKE: PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("COMBAT_SCHEMA_REJECTION_SMOKE: " + message)
	quit(1)
