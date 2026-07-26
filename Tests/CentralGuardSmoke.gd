extends SceneTree

## Smoke: Central Guard pair contract, ambush denial, Central re-entry refuse.

const SEED := "CENTRAL_GUARD_SMOKE"
const MobSpawnerScript := preload("res://SystemCore/MobSpawner.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _verify_loadouts_and_def():
		return
	if not _verify_ambush_denial():
		return
	if not _verify_central_reentry_lock():
		return
	if not _verify_spawner_pair_records():
		return
	if not _verify_token_visual_ids():
		return
	print("CentralGuardSmoke PASSED")
	quit(0)


func _fail(message: String) -> bool:
	push_error("CentralGuardSmoke FAILED: " + message)
	print("CentralGuardSmoke FAILED: " + message)
	quit(1)
	return false


func _make_spawner() -> Node:
	var spawner: Node = MobSpawnerScript.new()
	root.add_child(spawner)
	return spawner


func _verify_loadouts_and_def() -> bool:
	var def := load("res://BiologicalCore/central_guard_def.tres") as EntityDefinition
	if def == null:
		return _fail("Missing central_guard_def.tres")
	if not def.blocks_ambush or not def.blocks_central_reentry:
		return _fail("Guard def must block ambush and Central re-entry.")
	if def.template_id != "central_guard":
		return _fail("Guard template_id mismatch.")
	var ak := load("res://ItemCore/Loadouts/central_guard_ak_loadout.tres") as SpawnLoadout
	var kar := load("res://ItemCore/Loadouts/central_guard_kar98_loadout.tres") as SpawnLoadout
	if ak == null or kar == null:
		return _fail("Missing Central Guard loadouts.")
	if ak.weapon == null or ak.weapon.id != "ak47":
		return _fail("AK guard loadout weapon must be ak47.")
	if kar.weapon == null or kar.weapon.id != "service_rifle":
		return _fail("Kar98 guard loadout weapon must be service_rifle.")
	if kar.weapon.display_name != "Kar98k":
		return _fail("service_rifle display_name must be Kar98k.")
	for piece in [ak.inner_torso, ak.outer_torso, ak.legs, ak.feet, ak.head]:
		if piece == null:
			return _fail("AK loadout missing a service gear slot.")
	return true


func _verify_ambush_denial() -> bool:
	var spawner := _make_spawner()
	var record: EntityRecord = spawner.generate_central_guard_record(
		Vector2i(3, 0),
		false,
		"squad_test",
		"smoke:ak"
	)
	var opponent := MacroEntityCollisionResolver.build_opponent_summary(record)
	if not bool(opponent.get("blocks_ambush", false)):
		return _fail("Opponent summary missing blocks_ambush.")
	var deny := MacroEntityCollisionResolver.ambush_denied_result(record)
	if str(deny.get("title", "")) != "AMBUSH DENIED":
		return _fail("Ambush deny result title wrong.")
	if str(deny.get("body", "")).is_empty():
		return _fail("Ambush deny body empty.")
	if str(deny.get("resume", "")) != MacroEntityCollisionResolver.MODE_ROOT:
		return _fail("Ambush deny must resume to collision root.")
	spawner.queue_free()
	return true


func _verify_central_reentry_lock() -> bool:
	var world_state := RuntimeStateStore.new()
	world_state.name = "CentralGuardLockState"
	root.add_child(world_state)
	world_state.begin_new_world(SEED)

	var meta: Node = root.get_node_or_null("MetaProgression")
	var created_meta := false
	var prior_lock := true
	if meta == null:
		meta = MetaProgressionStore.new()
		meta.name = "MetaProgression"
		root.add_child(meta)
		created_meta = true
	if meta.has_method("is_central_locked"):
		prior_lock = bool(meta.is_central_locked())
	if meta.has_method("set_central_locked"):
		meta.set_central_locked(true, false)
	else:
		meta.set("central_locked", true)

	var progress := MacroProgressController.new()
	progress.configure(world_state)
	progress.begin_campaign(SEED)
	if not progress.enter_node(MacroGraphGenerator.CENTRAL_ID):
		return _fail("Initial Central entry should still work from empty active.")
	if not progress.enter_node(
		"north_random_1",
		GameEnums.MacroTravelDirection.NORTH
	):
		return _fail("Could not enter north_random_1 from Central.")
	if progress.can_enter_node(
		MacroGraphGenerator.CENTRAL_ID,
		GameEnums.MacroTravelDirection.SOUTH
	):
		return _fail("Central re-entry must be refused while central_locked.")
	var south_dests := progress.get_directional_destinations(
		GameEnums.MacroTravelDirection.SOUTH
	)
	if south_dests.has(MacroGraphGenerator.CENTRAL_ID):
		return _fail("Central must not appear in locked directional destinations.")
	if MacroEntityCollisionResolver.central_reentry_refused_line().is_empty():
		return _fail("Missing Central re-entry refuse line.")
	if meta.has_method("set_central_locked"):
		meta.set_central_locked(prior_lock, false)
	if created_meta:
		meta.queue_free()
	world_state.queue_free()
	return true


func _verify_spawner_pair_records() -> bool:
	var spawner := _make_spawner()
	var a: EntityRecord = spawner.generate_central_guard_record(
		Vector2i(0, 12),
		false,
		"pair_n1",
		"smoke:pair:0"
	)
	var b: EntityRecord = spawner.generate_central_guard_record(
		Vector2i(1, 11),
		true,
		"pair_n1",
		"smoke:pair:1"
	)
	if str(a.runtime.get("squad_id", "")) != "pair_n1":
		return _fail("Squad id not stamped on guard A.")
	if str(b.runtime.get("squad_id", "")) != "pair_n1":
		return _fail("Squad id not stamped on guard B.")
	if str(a.definition.get("template_id", "")) != "central_guard":
		return _fail("template_id missing on definition state.")
	var weapon_a := str(
		(a.definition.get("loadout", {}) as Dictionary).get("weapon", "")
	)
	var weapon_b := str(
		(b.definition.get("loadout", {}) as Dictionary).get("weapon", "")
	)
	if not weapon_a.ends_with("ak47.tres"):
		return _fail("First guard should carry AK loadout path.")
	if not weapon_b.ends_with("service_rifle.tres"):
		return _fail("Second guard should carry Kar98 loadout path.")
	spawner.queue_free()
	return true


func _verify_token_visual_ids() -> bool:
	var required := [
		"ak47",
		"service_rifle",
		"armor_service",
		"helmet_service",
		"shirt_service",
		"pants_service",
		"boot_service",
	]
	for item_id in required:
		if not HumanoidVisualCatalog.ITEM_VISUAL_DIRECTORIES.has(item_id):
			return _fail("HumanoidVisualCatalog missing token map for %s." % item_id)
	return true
