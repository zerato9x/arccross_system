extends Node2D
class_name CombatWeaponAnimator

const GUN_ROOT := "res://Asset/GUNS_V1.00/V1.00/"

var _weapon := AnimatedSprite2D.new()
var _muzzle_fx := AnimatedSprite2D.new()
var _secondary_fx := AnimatedSprite2D.new()
var _profile := "unarmed"
var _event := "idle"

func _ready() -> void:
	_weapon.name = "Weapon"
	_muzzle_fx.name = "MuzzleFX"
	_secondary_fx.name = "SecondaryFX"
	for sprite in [_weapon, _muzzle_fx, _secondary_fx]:
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
	_muzzle_fx.z_index = 1
	_secondary_fx.z_index = 2
	_weapon.animation_finished.connect(_on_weapon_animation_finished)
	_build_animation_library()
	set_profile("unarmed")

func set_profile(profile: String) -> void:
	var resolved := profile if _known_profile(profile) else "unarmed"
	if resolved == _profile and visible == (resolved != "unarmed"):
		return
	_profile = resolved
	visible = _profile != "unarmed"
	if visible:
		play_event("idle")
	else:
		_stop_fx()
		_weapon.stop()

func get_profile() -> String:
	return _profile

func get_current_event() -> String:
	return _event

func has_animation(event_name: String) -> bool:
	if not _weapon.sprite_frames:
		return false
	return _weapon.sprite_frames.has_animation(_animation_name(event_name))

func has_fx_animation(event_name: String) -> bool:
	var animation_name := _animation_name(event_name)
	return (
		_muzzle_fx.sprite_frames.has_animation(animation_name)
		or _secondary_fx.sprite_frames.has_animation(animation_name)
	)

func play_event(event_name: String) -> void:
	if _profile == "unarmed":
		return
	var requested := _animation_name(event_name)
	if not _weapon.sprite_frames.has_animation(requested):
		requested = _animation_name("idle")
	_event = event_name if requested.ends_with(event_name) else "idle"
	_weapon.play(requested)
	_play_optional(_muzzle_fx, requested)
	_play_optional(_secondary_fx, requested)

func _build_animation_library() -> void:
	_weapon.sprite_frames = SpriteFrames.new()
	_muzzle_fx.sprite_frames = SpriteFrames.new()
	_secondary_fx.sprite_frames = SpriteFrames.new()
	for frames in [
		_weapon.sprite_frames,
		_muzzle_fx.sprite_frames,
		_secondary_fx.sprite_frames,
	]:
		frames.remove_animation("default")

	_build_pistol()
	_build_shotgun()
	_build_assault_rifle()
	_build_kar98()

func _build_pistol() -> void:
	var weapon_path := (
		GUN_ROOT
		+ "Sprite-sheets/Pistol_V1.00/Weapon/[SHOOTING]PistolV1.00.png"
	)
	_add_static(_weapon.sprite_frames, "pistol_idle", weapon_path, Vector2i(64, 32))
	_add_strip(
		_weapon.sprite_frames,
		"pistol_fire",
		weapon_path,
		Vector2i(64, 32),
		12,
		true,
		18.0
	)
	_add_static(_weapon.sprite_frames, "pistol_reload", weapon_path, Vector2i(64, 32))
	_add_strip(
		_muzzle_fx.sprite_frames,
		"pistol_fire",
		GUN_ROOT
		+ "Sprite-sheets/Pistol_V1.00/FX/[FULL_MUZZLE_FLASH] PistolV1.00.png",
		Vector2i(64, 32),
		12,
		true,
		18.0
	)
	_add_strip(
		_secondary_fx.sprite_frames,
		"pistol_fire",
		GUN_ROOT + "Sprite-sheets/Pistol_V1.00/FX/[CASING] PistolV1.00.png",
		Vector2i(64, 32),
		12,
		true,
		18.0
	)

func _build_shotgun() -> void:
	var fire_path := (
		GUN_ROOT
		+ "Sprite-sheets/Shotgun_V1.00/Weapon/"
		+ "[SHOOTING_CHAMBER_CLOSED] Shotgun_V1.02.png"
	)
	var reload_path := (
		GUN_ROOT
		+ "Sprite-sheets/Shotgun_V1.00/Weapon/"
		+ "[RELOAD] Shotgun_V1.02 - Rreloading_01.png"
	)
	var cycle_path := (
		GUN_ROOT
		+ "Sprite-sheets/Shotgun_V1.00/Weapon/"
		+ "[SHOOTING_CHAMBER_OPEN] Shotgun_V1.02.png"
	)
	_add_static(_weapon.sprite_frames, "shotgun_idle", fire_path, Vector2i(160, 32))
	_add_strip(
		_weapon.sprite_frames, "shotgun_fire", fire_path,
		Vector2i(160, 32), 14, true, 18.0
	)
	_add_strip(
		_weapon.sprite_frames, "shotgun_reload", reload_path,
		Vector2i(128, 32), 14, true, 14.0
	)
	_add_strip(
		_weapon.sprite_frames, "shotgun_cycle", cycle_path,
		Vector2i(160, 32), 14, true, 18.0
	)
	_add_strip(
		_muzzle_fx.sprite_frames,
		"shotgun_fire",
		GUN_ROOT
		+ "Sprite-sheets/Shotgun_V1.00/FX/[FULL_MUZZLE_FLASH] Shotgun_V1.02.png",
		Vector2i(160, 32),
		14,
		true,
		18.0
	)
	_add_strip(
		_secondary_fx.sprite_frames,
		"shotgun_fire",
		GUN_ROOT
		+ "Sprite-sheets/Shotgun_V1.00/FX/[SHOOTING_SHELL_01] Shotgun_V1.02.png",
		Vector2i(160, 32),
		14,
		true,
		18.0
	)
	_add_strip(
		_secondary_fx.sprite_frames,
		"shotgun_reload",
		GUN_ROOT
		+ "Sprite-sheets/Shotgun_V1.00/FX/"
		+ "[RELOAD_SHELL_01] Shotgun_V1.02 - Rreloading_01.png",
		Vector2i(128, 32),
		14,
		true,
		14.0
	)

func _build_assault_rifle() -> void:
	var fire_path := (
		GUN_ROOT
		+ "Sprite-sheets/Assault_rifle_V1.00/WEAPON/"
		+ "[SINGLE_SHOT] Assault_rifle_V1.00.png"
	)
	var reload_path := (
		GUN_ROOT
		+ "Sprite-sheets/Assault_rifle_V1.00/WEAPON/"
		+ "[RELOAD] Assault_rifle_V1.00 - Reload.png"
	)
	_add_static(_weapon.sprite_frames, "assault_idle", fire_path, Vector2i(128, 48))
	_add_strip(
		_weapon.sprite_frames, "assault_fire", fire_path,
		Vector2i(128, 48), 16, true, 20.0
	)
	_add_strip(
		_weapon.sprite_frames, "assault_reload", reload_path,
		Vector2i(128, 64), 12, true, 14.0
	)
	_add_strip(
		_weapon.sprite_frames,
		"assault_burst",
		GUN_ROOT
		+ "Sprite-sheets/Assault_rifle_V1.00/WEAPON/"
		+ "[FULL_AUTO]_Assault_rifle_V1.00.png",
		Vector2i(128, 48),
		24,
		true,
		24.0
	)
	_add_strip(
		_muzzle_fx.sprite_frames,
		"assault_fire",
		GUN_ROOT
		+ "Sprite-sheets/Assault_rifle_V1.00/FX/Muzzle_flash/"
		+ "[FULL_MUZZLE_FLASH] Assault_rifle_V1.00.png",
		Vector2i(128, 48),
		16,
		true,
		20.0
	)
	_add_strip(
		_secondary_fx.sprite_frames,
		"assault_fire",
		GUN_ROOT
		+ "Sprite-sheets/Assault_rifle_V1.00/FX/"
		+ "[CASING_SINGLE_SHOT] Assault_rifle_V1.00.png",
		Vector2i(128, 48),
		16,
		true,
		20.0
	)

func _build_kar98() -> void:
	var fire_path := (
		GUN_ROOT
		+ "Sprite-sheets/SNIPER_RIFLE_V1.00 [KAR98]/WEAPON/"
		+ "[SNIPER_SHOOTING]_Sniper_rifle_[KAR98]_V1.00.png"
	)
	var reload_path := (
		GUN_ROOT
		+ "Sprite-sheets/SNIPER_RIFLE_V1.00 [KAR98]/WEAPON/"
		+ "[SINGLE_BULLET_RELOADING]_Sniper_rifle_[KAR98]_V1.00.png"
	)
	var cycle_path := (
		GUN_ROOT
		+ "Sprite-sheets/SNIPER_RIFLE_V1.00 [KAR98]/WEAPON/"
		+ "[SNIPER_EMPTYING]_Sniper_rifle_[KAR98]_V1.00.png"
	)
	_add_static(_weapon.sprite_frames, "kar98_idle", fire_path, Vector2i(160, 32))
	_add_strip(
		_weapon.sprite_frames, "kar98_fire", fire_path,
		Vector2i(160, 32), 28, false, 24.0
	)
	_add_strip(
		_weapon.sprite_frames, "kar98_reload", reload_path,
		Vector2i(128, 32), 40, false, 20.0
	)
	_add_strip(
		_weapon.sprite_frames, "kar98_cycle", cycle_path,
		Vector2i(128, 32), 28, false, 24.0
	)
	_add_strip(
		_muzzle_fx.sprite_frames,
		"kar98_fire",
		GUN_ROOT
		+ "Sprite-sheets/SNIPER_RIFLE_V1.00 [KAR98]/FX/"
		+ "[SNIPER_MUZZLE_FLASH]_Sniper_rifle_[KAR98]_V1.00.png",
		Vector2i(160, 32),
		28,
		false,
		24.0
	)
	_add_strip(
		_secondary_fx.sprite_frames,
		"kar98_cycle",
		GUN_ROOT
		+ "Sprite-sheets/SNIPER_RIFLE_V1.00 [KAR98]/FX/"
		+ "[RELOADING_CASING_ONLY]_Sniper_rifle_[KAR98]_V1.00.png",
		Vector2i(128, 32),
		28,
		false,
		24.0
	)

func _add_static(
	frames: SpriteFrames,
	animation_name: String,
	path: String,
	frame_size: Vector2i
) -> void:
	_add_strip(frames, animation_name, path, frame_size, 1, true, 1.0, true)

func _add_strip(
	frames: SpriteFrames,
	animation_name: String,
	path: String,
	frame_size: Vector2i,
	frame_count: int,
	horizontal: bool,
	fps: float,
	loop: bool = false
) -> void:
	var texture := load(path) as Texture2D
	if texture == null:
		push_warning("Missing combat weapon sheet: " + path)
		return
	frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, fps)
	frames.set_animation_loop(animation_name, loop)
	for index in range(frame_count):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(
			Vector2(
				index * frame_size.x if horizontal else 0,
				0 if horizontal else index * frame_size.y
			),
			Vector2(frame_size)
		)
		frames.add_frame(animation_name, atlas)

func _play_optional(sprite: AnimatedSprite2D, animation_name: String) -> void:
	if sprite.sprite_frames.has_animation(animation_name):
		sprite.visible = true
		sprite.play(animation_name)
	else:
		sprite.stop()
		sprite.visible = false

func _stop_fx() -> void:
	for sprite in [_muzzle_fx, _secondary_fx]:
		sprite.stop()
		sprite.visible = false

func _animation_name(event_name: String) -> String:
	return _profile + "_" + event_name

func _known_profile(profile: String) -> bool:
	return profile in ["unarmed", "pistol", "shotgun", "assault", "kar98"]

func _on_weapon_animation_finished() -> void:
	if _event != "idle":
		play_event("idle")
