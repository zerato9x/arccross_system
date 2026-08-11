extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cp_record := CombatEncounterRecord.new()
	cp_record.communication_points = 4
	var cp_payload := cp_record.to_dict()
	if int(cp_payload.get("communication_points", -1)) != 4:
		_fail("Encounter serialization did not emit canonical Communication Points.")
	var migrated_record := CombatEncounterRecord.from_dict({"squad_points": 3})
	if migrated_record.resolved_communication_points() != 3:
		_fail("Legacy squad-point records did not migrate into Communication Points.")
	var scene := load("res://CombatCore/WaveMode.tscn") as PackedScene
	if scene == null:
		_fail("Combat Lab scene did not load.")
		return
	var lab := scene.instantiate() as WaveMode
	root.add_child(lab)
	await process_frame
	await process_frame

	if lab.get_current_arena() != null:
		_fail("Combat Lab spawned combat before a roster was started.")
	if lab.get_lab_actor_count() != 2:
		_fail("The default Lab roster must expose one player and one autonomous actor.")

	var mixed_result := lab.set_lab_roster_preset("mixed_squad")
	if not bool(mixed_result.get("ok", false)):
		_fail("The authored mixed squad preset could not be selected: %s" % mixed_result)
	var roster: Array = lab.get_lab_roster()
	if roster.size() != 6:
		_fail("The mixed squad preset must materialize six actors, got %d." % roster.size())
	var roles := {}
	for entry in roster:
		var role := str(entry.get("role", ""))
		roles[role] = int(roles.get(role, 0)) + 1
	if int(roles.get("player", 0)) != 1:
		_fail("The squad roster lost its direct player actor.")
	if int(roles.get("ally", 0)) < 1 or int(roles.get("neutral", 0)) < 1:
		_fail("The squad roster must include authored ally and neutral actors.")
	if int(roles.get("hostile", 0)) < 3:
		_fail("The squad roster must include three independently acting hostiles.")

	var at_capacity := lab.add_lab_actor()
	if bool(at_capacity.get("ok", true)):
		_fail("The Lab allowed an actor beyond the six-actor encounter cap.")
	var remove_player := lab.remove_lab_actor("player")
	if bool(remove_player.get("ok", true)):
		_fail("The Lab allowed removal of the direct player actor.")
	var remove_result := lab.remove_lab_actor("lab_enemy_03")
	if not bool(remove_result.get("ok", false)) or lab.get_lab_actor_count() != 5:
		_fail("A non-player Lab actor could not be removed cleanly.")
	var add_result := lab.add_lab_actor("lab_enemy_03")
	if not bool(add_result.get("ok", false)) or lab.get_lab_actor_count() != 6:
		_fail("A removed authored actor could not be added back to the roster.")

	var validation := lab.get_staging_validation()
	if int(validation.get("actor_count", 0)) != 6:
		_fail("Staging validation did not report the complete squad roster.")
	if not validation.get("roster", []) is Array:
		_fail("Staging validation did not expose the roster projection.")

	if failures.is_empty():
		print("COMBAT_LAB_SQUAD_SMOKE: PASS // actors=", lab.get_lab_actor_count())
		quit(0)
		return
	for failure in failures:
		push_error("[COMBAT_LAB_SQUAD] " + failure)
	quit(1)


func _fail(message: String) -> void:
	failures.append(message)
