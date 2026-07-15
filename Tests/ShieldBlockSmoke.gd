extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var duel_scene := load("res://CombatCore/MainDuelScene.tscn") as PackedScene
	if duel_scene == null:
		_fail("Could not load the duel scene.")
		return
	var arena := duel_scene.instantiate()
	root.add_child(arena)
	await process_frame

	var player_definition := load("res://BiologicalCore/player_def.tres")
	var enemy_definition := load("res://BiologicalCore/scavenger_def.tres")
	arena.setup_duel_from_records(
		{
			"entity_id": "shield_test_player",
			"definition": player_definition.to_state(),
			"runtime": {},
		},
		{
			"entity_id": "shield_test_enemy",
			"definition": enemy_definition.to_state(),
			"runtime": {},
		}
	)
	await process_frame

	var defender: HumanoidCore = arena.player_core
	var attacker: HumanoidCore = arena.enemy_core
	var ballistic_shield := (
		load("res://ItemCore/Items/shield_ballistic.tres") as ItemData
	).create_runtime_instance()
	var makeshift_shield := (
		load("res://ItemCore/Items/makeshift_shield.tres") as ItemData
	).create_runtime_instance()
	var firearm := ItemData.new()
	firearm.id = "shield_test_firearm"
	firearm.item_type = GameEnums.ItemType.WEAPON
	firearm.weapon_type = GameEnums.WeaponClass.PISTOL
	firearm.damage_type = GameEnums.DamageType.BALLISTIC
	firearm.flesh_damage = 10.0
	firearm.stance_damage = 8.0
	attacker.inventory.paper_doll[GameEnums.EquipmentSlot.HAND] = firearm
	attacker.inventory.paper_doll[GameEnums.EquipmentSlot.OFFHAND] = null

	defender.inventory.paper_doll[GameEnums.EquipmentSlot.HAND] = ballistic_shield
	defender.inventory.paper_doll[GameEnums.EquipmentSlot.OFFHAND] = null
	arena.turn_manager.reserved_ap[defender] = 12
	var reactions: Array = arena.turn_manager.open_reaction_window(
		defender,
		attacker,
		GameEnums.ActionType.AIMED_SHOT
	)
	if not reactions.has(GameEnums.ActionType.BLOCK):
		_fail("A ballistic shield did not expose BLOCK against AIMED SHOT.")
		return
	if not reactions.has(GameEnums.ActionType.DODGE):
		_fail("AIMED SHOT still bypasses the ordinary DODGE reaction window.")
		return
	arena.turn_manager._reaction_pending = false

	var arm := GameEnums.LimbRegion.LEFT_ARM
	var arm_before := float(defender.body.limb_hp[arm])
	var stance_before := defender.stance_points
	if not arena.resolution_engine.resolve_block(
		defender,
		attacker,
		firearm,
		GameEnums.LimbRegion.UPPER_TORSO
	):
		_fail("The ballistic shield rejected a covered torso shot.")
		return
	var arm_damage := arm_before - float(defender.body.limb_hp[arm])
	if not is_equal_approx(arm_damage, 1.0):
		_fail("Ballistic shield flesh bleed-through ignored its authored multiplier.")
		return
	if defender.stance_points != stance_before:
		_fail("Ballistic BLOCK applied Stance damage from a ballistic weapon.")
		return

	arm_before = float(defender.body.limb_hp[arm])
	if arena.resolution_engine.resolve_block(
		defender,
		attacker,
		firearm,
		GameEnums.LimbRegion.LEFT_LEG
	):
		_fail("The ballistic shield covered a leg outside its authored coverage.")
		return
	if not is_equal_approx(arm_before, float(defender.body.limb_hp[arm])):
		_fail("A missed shield coverage check still applied damage.")
		return

	defender.inventory.paper_doll[GameEnums.EquipmentSlot.HAND] = makeshift_shield
	arena.turn_manager.reserved_ap[defender] = 12
	reactions = arena.turn_manager.open_reaction_window(
		defender,
		attacker,
		GameEnums.ActionType.SHOOT
	)
	if reactions.has(GameEnums.ActionType.BLOCK):
		_fail("The makeshift shield falsely advertised ballistic coverage.")
		return
	arena.turn_manager._reaction_pending = false

	var blade := ItemData.new()
	blade.damage_type = GameEnums.DamageType.SHARP
	blade.flesh_damage = 10.0
	blade.stance_damage = 4.0
	arm_before = float(defender.body.limb_hp[arm])
	if not arena.resolution_engine.resolve_block(
		defender,
		attacker,
		blade,
		GameEnums.LimbRegion.UPPER_TORSO
	):
		_fail("The makeshift shield rejected a covered sharp strike.")
		return
	arm_damage = arm_before - float(defender.body.limb_hp[arm])
	if not is_equal_approx(arm_damage, 3.5):
		_fail("Makeshift shield mitigation ignored its authored multiplier.")
		return

	var restored := ItemData.from_runtime_state(ballistic_shield.to_runtime_state())
	if (
		restored.block_coverage != ballistic_shield.block_coverage
		or restored.block_damage_types != ballistic_shield.block_damage_types
		or not is_equal_approx(
			restored.block_flesh_multiplier,
			ballistic_shield.block_flesh_multiplier
		)
	):
		_fail("Shield BLOCK authoring fields did not survive runtime serialization.")
		return

	print(
		"[TEST PASS] Shield-authored damage coverage, mitigation, ranged BLOCK, "
		+ "AIMED SHOT reactions, and runtime serialization work."
	)
	quit(0)

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
