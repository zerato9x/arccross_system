extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var armored_damage := CombatRules.get_unarmed_damage(6, 2.0, 2.0)
	var exposed_damage := CombatRules.get_unarmed_damage(8, 0.0, 0.0)
	if float(exposed_damage.get("flesh", 0.0)) <= float(armored_damage.get("flesh", 0.0)):
		_fail("Exposed target did not take more fist trauma than armored target.")
		return
	if float(exposed_damage.get("balance_impact", 0.0)) <= float(armored_damage.get("balance_impact", 0.0)):
		_fail("The stronger unarmed strike did not produce more balance impact.")
		return

	var spawner := root.get_node_or_null("MobSpawner") as MobSpawner
	if spawner == null:
		_fail("MobSpawner autoload is unavailable.")
		return
	var craven := spawner.generate_mob(
		GameEnums.Faction.CRAVEN_HIVE,
		0,
		RandomNumberGenerator.new()
	)
	var core := EntityFactory.record_to_humanoid_core(
		{
			"entity_id": "craven_balance_probe",
			"definition": craven.to_state(),
			"runtime": {},
		},
		root,
		"CravenBalanceProbe"
	)
	await process_frame
	if core.current_max_ap != HumanoidCore.MINDLESS_BASE_AP:
		_fail("Mindless Craven retained the full human AP budget.")
		return
	if core.definition.fortitude > 4:
		_fail("Wave-one Craven rolled outside the intended frail Fortitude band.")
		return

	print(
		"[COMBAT_UNARMED_BALANCE_SMOKE] PASS // exposed=",
		exposed_damage,
		" armored=",
		armored_damage,
		" craven_ap=",
		core.current_max_ap,
		" craven_fort=",
		core.definition.fortitude
	)
	quit(0)

func _fail(message: String) -> void:
	push_error("[COMBAT_UNARMED_BALANCE_SMOKE] " + message)
	quit(1)
