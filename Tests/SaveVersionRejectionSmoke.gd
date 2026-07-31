extends SceneTree

const FIXTURE_PATH := "res://.save_version_rejection_smoke.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
	if fixture == null:
		_fail("Could not create the obsolete-save fixture.")
		return
	fixture.store_string(JSON.stringify({"version": RuntimeStateStore.SAVE_VERSION - 1}))
	fixture.close()
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	var accepted := world_state.load_from_disk(FIXTURE_PATH)
	var message := world_state.get_last_persistence_error()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_PATH))
	if accepted:
		_fail("A pre-overhaul save was accepted.")
		return
	if "new run is required" not in message or "pre-combat-overhaul" not in message:
		_fail("Obsolete-save rejection did not explain the required new run: %s" % message)
		return
	print("[SAVE_VERSION_REJECTION] PASS")
	quit(0)


func _fail(message: String) -> void:
	if FileAccess.file_exists(FIXTURE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_PATH))
	push_error("[SAVE_VERSION_REJECTION] " + message)
	quit(1)
