extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var meta := MetaProgressionStore.new()
	for core_id in ["north_core", "east_core", "south_core"]:
		meta.set_core_state(core_id, {"restored": true}, false)
	if not meta.is_central_locked():
		return _fail("Central unlocked before all four regional Cores were restored.")
	meta.set_core_state("west_core", {"restored": true}, false)
	if meta.is_central_locked():
		return _fail("Central remained locked after all four Cores were restored.")
	if not meta.is_event_completed("central_reentry_unlocked"):
		return _fail("Central milestone event was not recorded.")
	print("CentralMilestoneSmoke PASSED")
	quit(0)


func _fail(message: String) -> void:
	push_error("CentralMilestoneSmoke: " + message)
	quit(1)
