extends SceneTree

const NpcSimulator := preload("res://WorldCore/MacroNpcSimulator.gd")
const PlotDirector := preload("res://WorldCore/NpcPlotDirector.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var record := EntityRecord.new()
	record.entity_id = "npc_role_smoke"
	record.kind = GameEnums.RuntimeEntityKind.NPC
	record.life_state = GameEnums.EntityLifeState.ALIVE
	record.world_status = GameEnums.EntityWorldStatus.CEASEFIRE
	record.coords = Vector2i(4, -2)
	record.definition = {
		"archetype_name": "Test Salvager",
		"faction": GameEnums.Faction.UNALIGNED,
		"npc_role_id": "salvager",
	}
	record.runtime = {}
	var role: Dictionary = NpcSimulator.role_descriptor(record)
	if str(role.get("role_id", "")) != "salvager":
		_fail("NPC role catalog did not resolve the authored role.")
		return
	var goal: String = NpcSimulator.select_goal(record, Vector2i.ZERO, "NPC_ROLE_SMOKE", 4)
	if goal.is_empty() or not record.runtime.has("macro_ai"):
		_fail("NPC goal selection did not persist AI state.")
		return
	for index in range(12):
		NpcSimulator.remember_player_event(
			record,
			"event_%d" % index,
			index,
			Vector2i(index, -index),
			0.25,
			0.5
		)
	var memory: Dictionary = record.runtime.get("macro_ai", {}).get("memory", {})
	if memory.get("events", []).size() != 8:
		_fail("NPC memory did not retain its bounded recent history.")
		return
	if float(memory.get("player_trust", 0.0)) <= 0.0:
		_fail("NPC relationship memory did not accumulate outcomes.")
		return

	var director: Variant = PlotDirector.data()
	var deployment: Variant = director.eligible_deployment(
		["east_handle_registry"],
		"east_random_1",
		{}
	) if director != null else null
	if deployment == null or deployment.role_id != "plot_agent":
		_fail("Side-arm intel did not qualify the emergent plot actor.")
		return
	var blocked: Variant = director.eligible_deployment(
		["east_handle_registry"],
		"east_random_1",
		{deployment.run_once_key: true}
	)
	if blocked != null:
		_fail("Run-once plot deployment could repeat.")
		return
	var dialogue := DialogueCatalog.data()
	if dialogue == null or dialogue.resolve("route1_signal_courier").is_empty():
		_fail("Emergent plot actor dialogue is not data-driven.")
		return
	print("[TEST PASS] NPC roles, goals, bounded memory, and plot deployment data are valid.")
	quit(0)


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
