extends Node
class_name GameSettingsStore

signal settings_changed(snapshot: Dictionary)

const SETTINGS_PATH := "user://arccross_settings.cfg"
const COMBAT_REALTIME := "realtime"
const COMBAT_TURN_BASED := "turn_based"
const REALTIME_SCENE_PATH := "res://CombatCore/MainDuelScene.tscn"
const TURN_BASED_SCENE_PATH := "res://CombatCore/TurnBased/TurnBasedDuelScene.tscn"

var combat_mode := COMBAT_REALTIME
var screen_noise_enabled := false
var hud_scale := 1.0


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		settings_changed.emit(get_snapshot())
		return
	combat_mode = _sanitize_combat_mode(
		str(config.get_value("combat", "mode", COMBAT_REALTIME))
	)
	screen_noise_enabled = bool(
		config.get_value("presentation", "screen_noise", false)
	)
	hud_scale = clampf(
		float(config.get_value("presentation", "hud_scale", 1.0)),
		0.85,
		1.25
	)
	settings_changed.emit(get_snapshot())


func save_settings() -> bool:
	var config := ConfigFile.new()
	config.set_value("combat", "mode", combat_mode)
	config.set_value("presentation", "screen_noise", screen_noise_enabled)
	config.set_value("presentation", "hud_scale", hud_scale)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("[GameSettings] Could not save settings: %s" % error_string(error))
		return false
	return true


func set_combat_mode(mode: String) -> void:
	var sanitized := _sanitize_combat_mode(mode)
	if combat_mode == sanitized:
		return
	combat_mode = sanitized
	_commit_change()


func set_screen_noise_enabled(enabled: bool) -> void:
	if screen_noise_enabled == enabled:
		return
	screen_noise_enabled = enabled
	_commit_change()


func set_hud_scale(value: float) -> void:
	var sanitized := clampf(value, 0.85, 1.25)
	if is_equal_approx(hud_scale, sanitized):
		return
	hud_scale = sanitized
	_commit_change()


func get_combat_scene_path() -> String:
	return (
		TURN_BASED_SCENE_PATH
		if combat_mode == COMBAT_TURN_BASED
		else REALTIME_SCENE_PATH
	)


func get_combat_mode_label() -> String:
	return "TURN-BASED" if combat_mode == COMBAT_TURN_BASED else "REAL-TIME"


func get_snapshot() -> Dictionary:
	return {
		"combat_mode": combat_mode,
		"combat_mode_label": get_combat_mode_label(),
		"screen_noise_enabled": screen_noise_enabled,
		"hud_scale": hud_scale,
	}


func _sanitize_combat_mode(mode: String) -> String:
	return COMBAT_TURN_BASED if mode == COMBAT_TURN_BASED else COMBAT_REALTIME


func _commit_change() -> void:
	save_settings()
	settings_changed.emit(get_snapshot())
