extends SceneTree

const ARENA_SCRIPT := preload("res://CombatCore/Tactical/TacticalArenaView.gd")
const TOKEN_SCENE := preload("res://UI/Humanoid/HumanoidToken.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var firearm_ids := [
		"ak47", "carbon_rifle", "service_rifle", "shotgun",
		"carbon_pistol", "service_pistol", "unique_theoperator", "revolver",
		"unique_railgun", "unique_modifiedrifle", "unique_arcbornblaster",
	]
	for weapon_id in firearm_ids:
		if not HumanoidVisualCatalog.has_weapon_muzzle_profile(weapon_id):
			_failures.append("Missing token muzzle profile for %s." % weapon_id)
		var appearance := HumanoidVisualCatalog.appearance_from_slot_item_ids({
			GameEnums.EquipmentSlot.HAND: weapon_id,
		})
		var has_category_gun_layer := false
		for directory in HumanoidVisualCatalog.layer_directories(appearance):
			if "/weapons/guns/" in directory:
				has_category_gun_layer = true
				break
		if not has_category_gun_layer:
			_failures.append("Missing category gun layer for %s." % weapon_id)

	var arena := ARENA_SCRIPT.new() as TacticalArenaView
	arena.size = Vector2(960.0, 540.0)
	root.add_child(arena)
	var shooter := TOKEN_SCENE.instantiate() as HumanoidTokenView
	shooter.position = Vector2(180.0, 280.0)
	shooter.set_display_scale(1.0)
	shooter.set_direction_row(HumanoidVisualCatalog.DIRECTION_RIGHT)
	arena.add_child(shooter)
	shooter.set_slot_item_ids({GameEnums.EquipmentSlot.HAND: "revolver"})
	var target := TOKEN_SCENE.instantiate() as HumanoidTokenView
	target.position = Vector2(720.0, 280.0)
	target.set_display_scale(1.0)
	arena.add_child(target)
	arena._actor_tokens = {"shooter": shooter, "target": target}

	arena._ensure_token_overlays(shooter)
	var overlay := shooter.get_meta("combat_top_overlay") as CombatTokenOverlay
	overlay.configure_top(
		{"actor_id": "shooter", "team_id": "player", "name": "Shooter"},
		48.0,
		1.0,
		shooter.combat_overhead_anchor(),
		"east"
	)

	var cue := CombatPresentationCue.new()
	cue.action_id = "fire"
	cue.actor_id = "shooter"
	cue.target_actor_id = "target"
	cue.weapon_id = "revolver"
	cue.weapon_class = GameEnums.WeaponClass.PISTOL
	cue.target_body_region = GameEnums.LimbRegion.HEAD
	cue.start_sector = Vector2i.ZERO
	cue.end_sector = Vector2i(1, 0)
	cue.presentation_direction = "east"
	overlay.set_weapon_cue(cue, 0.5)
	var expected_start := shooter.position + shooter.combat_weapon_muzzle_anchor(cue.weapon_id)
	var actual_start: Vector2 = arena._projectile_start_for(cue)
	if not actual_start.is_equal_approx(expected_start):
		_failures.append("Projectile start did not come from the humanoid token weapon layer.")
	overlay.position += Vector2(12.0, -7.0)
	if not arena._projectile_start_for(cue).is_equal_approx(expected_start):
		_failures.append("Moving the visual-only firearm overlay changed projectile origin.")
	var head_end: Vector2 = arena._projectile_end_for(cue)
	cue.target_body_region = GameEnums.LimbRegion.LEFT_LEG
	var leg_end: Vector2 = arena._projectile_end_for(cue)
	if head_end.is_equal_approx(leg_end) or head_end.y >= leg_end.y:
		_failures.append("Aimed projectile endpoints did not follow body-region anchors.")
	if cue.to_dict().get("target_body_region", -1) != GameEnums.LimbRegion.LEFT_LEG:
		_failures.append("Presentation cue did not serialize the resolved body region.")

	var sequence := CombatPresentationSequence.new()
	sequence.cues.append(cue)
	arena.begin_sequence(sequence)
	if shooter._suppress_equipment_layers:
		_failures.append("Firearm presentation hid the physical token weapon layer.")

	if _failures.is_empty():
		print("COMBAT_PROJECTILE_AUTHORITY_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
