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
	for facing in ["north", "east", "south", "west"]:
		for action_id in ["fire", "reload", "cycle", "clear_malfunction"]:
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
			cue.actor_id = "player"
			cue.facing = facing
			overlay.facing = facing
			overlay.set_weapon_cue(cue, 0.5)
			var weapon_rect := overlay.weapon_local_rect()
			if weapon_rect.size == Vector2.ZERO:
				_failures.append("No weapon geometry for %s/%s." % [facing, action_id])
			elif weapon_rect.end.y >= -94.0:
				_failures.append("Weapon crossed the overhead anchor for %s/%s: %s" % [facing, action_id, weapon_rect])
			elif weapon_rect.intersects(body_rect):
				_failures.append("Weapon overlapped the humanoid body for %s/%s: %s" % [facing, action_id, weapon_rect])
			if overlay.has_method("weapon_muzzle_local_position"):
				_failures.append("Decorative weapon overlay still exposes projectile geometry for %s/%s." % [facing, action_id])
			overlay.queue_free()
	if _failures.is_empty():
		print("COMBAT_WEAPON_OVERLAY_GEOMETRY_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
