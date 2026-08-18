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
	var actor_current := CombatActorState.new().to_dict()
	if not CombatActorState.compatibility_error(actor_current).is_empty():
		_fail("The current combat actor schema was rejected.")
		return
	var actor_old := actor_current.duplicate(true)
	actor_old["schema_version"] = CombatActorState.SCHEMA_VERSION - 1
	var actor_error := CombatActorState.compatibility_error(actor_old)
	if "incompatible" not in actor_error or "start a new combat encounter" not in actor_error:
		_fail("Old combat actor schema rejection was not explicit: %s" % actor_error)
		return
	var actor_retired := actor_current.duplicate(true)
	actor_retired["reserved_ap"] = 2
	if CombatActorState.compatibility_error(actor_retired).is_empty():
		_fail("A combat actor snapshot with retired reserved_ap was silently accepted.")
		return
	var actor_missing := actor_current.duplicate(true)
	actor_missing.erase("schema_version")
	if CombatActorState.compatibility_error(actor_missing).is_empty():
		_fail("A versionless combat actor snapshot was silently accepted.")
		return
	print("COMBAT_SCHEMA_REJECTION_SMOKE: PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("COMBAT_SCHEMA_REJECTION_SMOKE: " + message)
	quit(1)
