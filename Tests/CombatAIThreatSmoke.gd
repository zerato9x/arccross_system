extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var spawner := root.get_node_or_null("MobSpawner") as MobSpawner
	if spawner == null:
		_fail("MobSpawner autoload is unavailable.")
		return

	var definition := spawner.generate_mob(
		GameEnums.Faction.SCAVENGER_CELL,
		0,
		RandomNumberGenerator.new()
	)
	definition.agenda = GameEnums.Agenda.SURVIVALIST
	definition.will = 3
	var core := EntityFactory.record_to_humanoid_core(
		{
			"entity_id": "threat_probe",
			"definition": definition.to_state(),
			"runtime": {},
		},
		root,
		"ThreatProbe"
	)
	await process_frame

	var own_threat := core.get_effective_threat()
	var tolerance := float(core.definition.will) + own_threat
	core._evaluate_flight_response(tolerance)
	if core.is_fleeing:
		_fail("An equally threatening armed scavenger fled at its tolerance boundary.")
		return

	core._evaluate_flight_response(tolerance + 1.0)
	if not core.is_fleeing:
		_fail("A survivalist did not flee when opponent threat exceeded tolerance.")
		return

	print(
		"[COMBAT_AI_THREAT_SMOKE] PASS // own_threat=",
		own_threat,
		" tolerance=",
		tolerance
	)
	quit(0)

func _fail(message: String) -> void:
	push_error("[COMBAT_AI_THREAT_SMOKE] " + message)
	quit(1)
