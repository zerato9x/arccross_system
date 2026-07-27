extends Node
class_name GameSettingsStore

signal settings_changed(snapshot: Dictionary)

const SETTINGS_PATH := "user://arccross_settings.cfg"
## Real-time is retained for Combat Lab (WaveMode) tooling only.
## Production macro combat always uses turn-based via GameDirector.
const COMBAT_REALTIME := "realtime"
const COMBAT_TURN_BASED := "turn_based"
const DEFAULT_COMBAT_MODE := COMBAT_TURN_BASED

## Persisted preference kept for lab/legacy settings files. GameDirector ignores
## this and always launches the turn-based duel scene.
var combat_mode := DEFAULT_COMBAT_MODE
var screen_noise_enabled := false
var hud_scale := 1.0
var hud_scheme := HUDAssetLibrary.DEFAULT_SCHEME


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		_apply_hud_scheme(false)
		settings_changed.emit(get_snapshot())
		return
	combat_mode = _sanitize_combat_mode(
		str(config.get_value("combat", "mode", DEFAULT_COMBAT_MODE))
	)
	screen_noise_enabled = bool(
		config.get_value("presentation", "screen_noise", false)
	)
	hud_scale = clampf(
		float(config.get_value("presentation", "hud_scale", 1.0)),
		0.85,
		1.25
	)
	hud_scheme = _sanitize_hud_scheme(
		str(config.get_value("presentation", "hud_scheme", HUDAssetLibrary.DEFAULT_SCHEME))
	)
	_apply_hud_scheme(false)
	settings_changed.emit(get_snapshot())


func save_settings() -> bool:
	var config := ConfigFile.new()
	config.set_value("combat", "mode", combat_mode)
	config.set_value("presentation", "screen_noise", screen_noise_enabled)
	config.set_value("presentation", "hud_scale", hud_scale)
	config.set_value("presentation", "hud_scheme", hud_scheme)
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


func set_hud_scheme(scheme_id: String) -> void:
	var sanitized := _sanitize_hud_scheme(scheme_id)
	if hud_scheme == sanitized:
		return
	hud_scheme = sanitized
	_apply_hud_scheme(true)
	_commit_change()


func get_combat_mode_label() -> String:
	return "TURN-BASED" if combat_mode == COMBAT_TURN_BASED else "REAL-TIME"


func get_hud_scheme_label() -> String:
	return HUDAssetLibrary.scheme_label(hud_scheme)


func get_snapshot() -> Dictionary:
	return {
		"combat_mode": combat_mode,
		"combat_mode_label": get_combat_mode_label(),
		"screen_noise_enabled": screen_noise_enabled,
		"hud_scale": hud_scale,
		"hud_scheme": hud_scheme,
		"hud_scheme_label": get_hud_scheme_label(),
	}


func _sanitize_combat_mode(mode: String) -> String:
	if mode in [COMBAT_TURN_BASED, COMBAT_REALTIME]:
		return mode
	return DEFAULT_COMBAT_MODE


func _sanitize_hud_scheme(scheme_id: String) -> String:
	return HUDAssetLibrary.sanitize_scheme_id(scheme_id)


func _apply_hud_scheme(notify_library: bool) -> void:
	HUDAssetLibrary.apply_scheme(hud_scheme, notify_library)


func _commit_change() -> void:
	save_settings()
	settings_changed.emit(get_snapshot())
