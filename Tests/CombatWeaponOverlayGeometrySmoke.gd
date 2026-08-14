extends SceneTree

const OVERLAY_SCRIPT := preload("res://CombatCore/Tactical/CombatTokenOverlay.gd")
const TOKEN_SCENE := preload("res://UI/Humanoid/HumanoidToken.tscn")
const VISUAL_PROFILE = preload("res://CombatCore/Tactical/readable_moody_visual_profile.tres")
const WEAPON_CATALOG := preload("res://CombatCore/Tactical/default_weapon_presentation_catalog.tres")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if VISUAL_PROFILE.backdrop_modulate.r < 0.70 or VISUAL_PROFILE.backdrop_modulate.g < 0.70:
		_failures.append("Readable combat backdrop exposure regressed.")
	if VISUAL_PROFILE.duel_surface_alpha < 0.30 or VISUAL_PROFILE.panel_opacity > 0.96:
		_failures.append("Combat visual profile lost battlefield separation or panel restraint.")
	var token := TOKEN_SCENE.instantiate() as HumanoidTokenView
	root.add_child(token)
	token.set_display_scale(1.0)
	var weapon_definition := WEAPON_CATALOG.definition_for("revolver")
	for direction in ["north", "east", "south", "west"]:
		token.face_direction({"north": Vector2.UP, "east": Vector2.RIGHT, "south": Vector2.DOWN, "west": Vector2.LEFT}[direction])
		for action_id in ["fire", "specialized_fire", "reload", "cycle"]:
			var overlay := OVERLAY_SCRIPT.new() as CombatTokenOverlay
			overlay.z_index = 40
			token.add_child(overlay)
			overlay.configure_top(
				{"actor_id": "player", "team_id": "player", "name": "Player"},
				48.0,
				1.0,
				Vector2(0.0, -94.0)
			)
			var cue := CombatPresentationCue.new()
			cue.action_id = action_id
			cue.weapon_id = "revolver"
			cue.weapon_class = GameEnums.WeaponClass.PISTOL
			cue.actor_id = "player"
			cue.presentation_direction = direction
			overlay.presentation_direction = direction
			overlay.set_weapon_cue(cue, 0.5)
			var weapon_rect := overlay.weapon_local_rect()
			if weapon_rect.size == Vector2.ZERO:
				_failures.append("No weapon geometry for %s/%s." % [direction, action_id])
			else:
				var display_size := Vector2(weapon_definition.frame_size_for_action(action_id)) * clampf(0.72 * weapon_definition.display_scale_for_action(action_id), 0.55, 1.65)
				var anchor := weapon_definition.hand_anchor_for_action(action_id)
				var lateral := (anchor.x - 0.5) * display_size.x
				if direction == "west":
					lateral = -lateral
				var expected_center := token.combat_weapon_hand_anchor("revolver") + Vector2(lateral, anchor.y * display_size.y)
				if weapon_rect.get_center().distance_to(expected_center) > 0.01:
					_failures.append("Weapon lost the production hand anchor for %s/%s: %s != %s" % [direction, action_id, weapon_rect.get_center(), expected_center])
			if overlay.has_method("weapon_muzzle_local_position"):
				_failures.append("Decorative weapon overlay still exposes projectile geometry for %s/%s." % [direction, action_id])
			overlay.queue_free()
	var melee_overlay := OVERLAY_SCRIPT.new() as CombatTokenOverlay
	token.add_child(melee_overlay)
	melee_overlay.configure_top(
		{
			"actor_id": "player",
			"team_id": "player",
			"name": "Player",
			"melee_weapon": {
				"definition_id": "baton",
				"equipped_sprite_path": "res://Asset/Innawoods_Asset/Weapons/Melee_Blunt/equip_baton.png",
				"presentation": {"sprite_path": "res://Asset/Innawoods_Asset/Weapons/Melee_Blunt/equip_baton.png"},
			},
		},
		48.0,
		1.0,
		Vector2(0.0, -94.0)
	)
	var melee_cue := CombatPresentationCue.new()
	melee_cue.action_id = "strike"
	melee_cue.weapon_id = "baton"
	melee_cue.weapon_class = GameEnums.WeaponClass.BLUNT
	melee_cue.actor_id = "player"
	melee_overlay.set_weapon_cue(melee_cue, 0.5)
	if melee_overlay.weapon_local_rect().size == Vector2.ZERO:
		_failures.append("Melee overlay did not reuse the equipped-item sprite geometry.")
	melee_overlay.queue_free()
	token.queue_free()
	if _failures.is_empty():
		print("COMBAT_WEAPON_OVERLAY_GEOMETRY_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
