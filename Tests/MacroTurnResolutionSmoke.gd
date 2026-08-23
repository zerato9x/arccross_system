extends SceneTree

const _TurnResolutionState := preload(
	"res://WorldCore/MacroTurnResolutionState.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := _TurnResolutionState.new()
	var first_id := state.begin(
		"travel",
		Vector2i(0, 0),
		Vector2i(2, 0),
		2,
		true
	)
	if first_id <= 0 or not state.is_active():
		_fail("A fresh turn did not enter the active resolution state.")
		return
	if str(state.data.get("phase", "")) != "walking":
		_fail("A fresh turn did not begin in WALKING.")
		return
	if state.begin("travel", Vector2i.ZERO, Vector2i.ONE, 1, true) != 0:
		_fail("The resolver accepted a second turn while the first was active.")
		return

	state.set_phase(
		"resolving",
		"TURN RESOLVE // ARRIVAL COMMIT..."
	)
	state.mark_step_committed(Vector2i(1, 0), 2)
	if str(state.data.get("phase", "")) != "resolving":
		_fail("Arrival phase was not retained across the commit boundary.")
		return
	if int(state.data.get("completed_steps", 0)) != 1:
		_fail("The committed step was not recorded.")
		return

	state.set_phase("world_turn", "TURN RESOLVE // NPC WORLD TURN...")
	state.set_phase("presentation", "TURN RESOLVE // PRESENTATION...")
	if str(state.data.get("phase", "")) != "presentation":
		_fail("The resolver did not expose the presentation phase.")
		return
	state.finish("ARRIVED", "idle")
	if state.is_active() or str(state.data.get("phase", "")) != "idle":
		_fail("The resolver did not release its input lock at completion.")
		return

	var second_id := state.begin(
		"retreat",
		Vector2i(2, 0),
		Vector2i(1, 0),
		1,
		false
	)
	if second_id <= first_id or not state.is_active():
		_fail("A completed turn did not release the resolver for the next turn.")
		return

	print("MACRO_TURN_RESOLUTION_SMOKE: PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("[MACRO_TURN_RESOLUTION_SMOKE] FAIL // " + message)
	quit(1)
