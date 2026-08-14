extends SceneTree

const OVERLAY_SCRIPT := preload("res://CombatCore/Tactical/CombatTokenOverlay.gd")
const VISUAL_PROFILE = preload("res://CombatCore/Tactical/readable_moody_visual_profile.tres")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if VISUAL_PROFILE.backdrop_modulate.r < 0.70 or VISUAL_PROFILE.backdrop_modulate.g < 0.70:
		_failures.append("Readable combat backdrop exposure regressed.")
	if VISUAL_PROFILE.duel_surface_alpha < 0.30 or VISUAL_PROFILE.panel_opacity > 0.96:
		_failures.append("Combat visual profile lost battlefield separation or panel restraint.")
	var body_rect := Rect2(Vector2(-64.0, -64.0), Vector2(128.0, 128.0))
	for direction in ["north", "east", "south", "west"]:
		for action_id in ["fire", "specialized_fire", "reload", "cycle"]:
			var overlay := OVERLAY_SCRIPT.new() as CombatTokenOverlay
			overlay.z_index = 40
			root.add_child(overlay)
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
			elif weapon_rect.end.y >= -94.0:
				_failures.append("Weapon crossed the overhead anchor for %s/%s: %s" % [direction, action_id, weapon_rect])
			elif weapon_rect.intersects(body_rect):
				_failures.append("Weapon overlapped the humanoid body for %s/%s: %s" % [direction, action_id, weapon_rect])
			if overlay.has_method("weapon_muzzle_local_position"):
				_failures.append("Decorative weapon overlay still exposes projectile geometry for %s/%s." % [direction, action_id])
			overlay.queue_free()
	var melee_overlay := OVERLAY_SCRIPT.new() as CombatTokenOverlay
	root.add_child(melee_overlay)
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
	if _failures.is_empty():
		print("COMBAT_WEAPON_OVERLAY_GEOMETRY_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
