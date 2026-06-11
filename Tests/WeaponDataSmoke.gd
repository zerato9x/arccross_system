extends SceneTree

const FIREARM_PATHS := [
	"res://ItemCore/Items/carbon_pistol.tres",
	"res://ItemCore/Items/service_pistol.tres",
	"res://ItemCore/Items/revolver.tres",
	"res://ItemCore/Items/carbon_rifle.tres",
	"res://ItemCore/Items/ak47.tres",
	"res://ItemCore/Items/service_rifle.tres",
	"res://ItemCore/Items/shotgun.tres",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _verify_authored_roster():
		return

	var holder := Node.new()
	root.add_child(holder)
	var duel_scene := load(
		"res://CombatCore/MainDuelScene.tscn"
	) as PackedScene
	if not duel_scene:
		_fail("Could not load the combat scene.")
		return
	var arena = duel_scene.instantiate()
	holder.add_child(arena)
	await process_frame

	var base_definition := load(
		"res://BiologicalCore/player_def.tres"
	) as EntityDefinition
	var test_definition := base_definition.duplicate(true) as EntityDefinition
	test_definition.loadout = null
	test_definition.fortitude = 12

	var shooter: HumanoidCore = arena._fabricate_humanoid(
		"Weapon_Shooter",
		test_definition,
		false
	)
	var target: HumanoidCore = arena._fabricate_humanoid(
		"Weapon_Target",
		test_definition,
		false
	)
	await process_frame
	_clear_inventory(target)

	if not _verify_ballistic_limb_damage(arena, target):
		return
	if not _verify_service_pistol_reload(arena, shooter):
		return
	if not _verify_revolver_reload(arena, shooter):
		return
	if not _verify_runtime_round_trip():
		return

	holder.queue_free()
	await process_frame
	print(
		"[TEST PASS] Weapon data, exact ammunition feeds, ballistic limb trauma, "
		+ "manual loading, and firearm runtime state obey the authored rules."
	)
	quit(0)

func _verify_authored_roster() -> bool:
	for path in FIREARM_PATHS:
		var weapon := load(path) as ItemData
		if weapon == null:
			return _fail("Could not load firearm: " + path)
		if (
			not weapon.is_ranged()
			or weapon.damage_type != GameEnums.DamageType.BALLISTIC
			or not is_zero_approx(weapon.stance_damage)
			or weapon.flesh_damage < 7.0
			or weapon.ammunition_id.is_empty()
		):
			return _fail("Firearm has invalid ballistic data: " + weapon.id)

	var carbon_pistol := load(
		"res://ItemCore/Items/carbon_pistol.tres"
	) as ItemData
	var service_pistol := load(
		"res://ItemCore/Items/service_pistol.tres"
	) as ItemData
	if (
		carbon_pistol.max_magazine != 16
		or service_pistol.max_magazine != 8
		or carbon_pistol.effective_range != 6
		or service_pistol.effective_range != 6
		or carbon_pistol.accuracy_rating
			<= service_pistol.accuracy_rating
	):
		return _fail("Carbon and service pistol distinctions are incorrect.")

	var shotgun := load(
		"res://ItemCore/Items/shotgun.tres"
	) as ItemData
	if (
		not is_equal_approx(shotgun.damage_multiplier_at_distance(2), 1.0)
		or shotgun.damage_multiplier_at_distance(3) >= 1.0
		or not is_equal_approx(
			shotgun.damage_multiplier_at_distance(4),
			0.35
		)
		or shotgun.effective_range != 4
	):
		return _fail("Shotgun range damage falloff is incorrect.")

	var scope := load(
		"res://ItemCore/Items/service_rifle_scope.tres"
	) as ItemData
	if (
		not scope.grants_snipe
		or scope.macro_snipe_range != 2
		or not scope.compatible_weapon_ids.has("service_rifle")
	):
		return _fail("Service rifle scope metadata is incorrect.")
	return true

func _verify_ballistic_limb_damage(
	arena: Node,
	target: HumanoidCore
) -> bool:
	var pistol := load(
		"res://ItemCore/Items/service_pistol.tres"
	) as ItemData
	target.reset_stance()
	var stance_before := target.stance_points
	var limb := GameEnums.LimbRegion.LEFT_ARM
	var hp_before: float = target.body.limb_hp[limb]
	arena.resolution_engine._resolve_damage(target, pistol, limb)
	var hp_lost := hp_before - float(target.body.limb_hp[limb])
	if target.stance_points != stance_before:
		return _fail("A ballistic hit changed Stance.")
	if not is_equal_approx(hp_lost, pistol.flesh_damage):
		return _fail("A pistol round did not apply its authored limb damage.")
	return true

func _verify_service_pistol_reload(
	arena: Node,
	shooter: HumanoidCore
) -> bool:
	_clear_hands(shooter)
	var pistol := (
		load("res://ItemCore/Items/service_pistol.tres") as ItemData
	).create_runtime_instance()
	shooter.inventory.equip_item(pistol, GameEnums.EquipmentSlot.HANDS)
	pistol.current_magazine = 0
	_add_item_copies(shooter, "pistol_round", 8)

	if arena.resolution_engine.execute_reload(shooter):
		return _fail("Service pistol reloaded without its magazine.")
	shooter.inventory.add_to_backpack(
		load("res://ItemCore/Items/carbon_pistol_magazine.tres")
	)
	if arena.resolution_engine.execute_reload(shooter):
		return _fail("Service pistol accepted a carbon pistol magazine.")
	shooter.inventory.add_to_backpack(
		load("res://ItemCore/Items/service_pistol_magazine.tres")
	)
	if not arena.resolution_engine.execute_reload(shooter):
		return _fail("Service pistol rejected its correct magazine and rounds.")
	if pistol.current_magazine != 8:
		return _fail("Service pistol did not load its 7+1 capacity.")
	return true

func _verify_revolver_reload(
	arena: Node,
	shooter: HumanoidCore
) -> bool:
	_clear_hands(shooter)
	var revolver := (
		load("res://ItemCore/Items/revolver.tres") as ItemData
	).create_runtime_instance()
	shooter.inventory.equip_item(revolver, GameEnums.EquipmentSlot.HANDS)
	revolver.current_magazine = 0
	_add_item_copies(shooter, "pistol_round", 6)

	if arena.resolution_engine.execute_reload(shooter):
		return _fail("Revolver used fast RELOAD without a speedloader.")
	if not arena.resolution_engine.execute_cycle(shooter):
		return _fail("Revolver could not hand-load a round through CYCLE.")
	if revolver.current_magazine != 1:
		return _fail("Revolver CYCLE loaded more than one round.")

	shooter.inventory.add_to_backpack(
		load("res://ItemCore/Items/revolver_speedloader.tres")
	)
	if not arena.resolution_engine.execute_reload(shooter):
		return _fail("Revolver rejected its speedloader.")
	if revolver.current_magazine != 6:
		return _fail("Revolver speedloader did not fill all six chambers.")
	return true

func _verify_runtime_round_trip() -> bool:
	var definition := load(
		"res://ItemCore/Items/service_rifle.tres"
	) as ItemData
	var runtime := definition.create_runtime_instance()
	runtime.current_magazine = 3
	runtime.needs_cycling = true
	var restored := ItemData.from_runtime_state(runtime.to_runtime_state())
	if (
		restored.current_magazine != 3
		or not restored.needs_cycling
		or restored.ammunition_id != "rifle_round"
		or restored.reload_aid_id != "service_rifle_clip"
		or restored.effective_range != 11
	):
		return _fail("Expanded firearm data failed its runtime round trip.")
	return true

func _add_item_copies(
	entity: HumanoidCore,
	item_id: String,
	count: int
) -> void:
	var definition := load(
		"res://ItemCore/Items/%s.tres" % item_id
	) as ItemData
	for _item_index in range(count):
		entity.inventory.add_to_backpack(definition)

func _clear_hands(entity: HumanoidCore) -> void:
	var held: ItemData = entity.inventory.paper_doll.get(
		GameEnums.EquipmentSlot.HANDS
	)
	if held:
		entity.inventory.remove_item_by_instance_id(held.instance_id)

func _clear_inventory(entity: HumanoidCore) -> void:
	entity.inventory.backpack_array.clear()
	for slot in entity.inventory.paper_doll.keys():
		entity.inventory.paper_doll[slot] = null
	entity.inventory._recalculate_bounds()

func _fail(message: String) -> bool:
	push_error("[TEST FAIL] " + message)
	quit(1)
	return false
