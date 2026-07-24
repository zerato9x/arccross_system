extends Node
class_name AudioConductorSystem

# ---------------------------------------------------------
# AUDIO CONDUCTOR: Simplified Audio Engine
# ---------------------------------------------------------
# Manages soundtrack routing and crossfading based
# on game state and world time.
# ---------------------------------------------------------

# ---------------------------------------------------------
# AUDIO SCENE STATE MACHINE
# ---------------------------------------------------------
enum AudioScene {
	SILENT,
	MACRO_DAY,
	MACRO_NIGHT,
	COMBAT_STANDARD,
	COMBAT_SPECIAL,
	GAME_OVER
}

var current_scene: AudioScene = AudioScene.SILENT
var _combat_first_strike_fired: bool = false

# ---------------------------------------------------------
# PLAYERS & BUSES
# ---------------------------------------------------------
var music_player: AudioStreamPlayer
var overlay_player: AudioStreamPlayer # Battlefield critical overlay
var algorave_bus_idx: int = -1
var overlay_bus_idx: int = -1

# ---------------------------------------------------------
# AUDIO EFFECTS
# ---------------------------------------------------------
var amp_effect: AudioEffectAmplify
var overlay_amp: AudioEffectAmplify

# ---------------------------------------------------------
# TARGET PARAMETERS (smoothed via _process)
# ---------------------------------------------------------
var target_gain_db: float = 0.0
var target_overlay_gain_db: float = -80.0 # Starts silent
var is_overlay_active: bool = false
var smooth_speed: float = 5.0

# ---------------------------------------------------------
# TRACK CATALOG
# ---------------------------------------------------------
const TRACKS: Dictionary = {
	# Macro World
	"Dawn": preload("res://SoundCore/Sound/soundtrack_1/Dawn - slow - scary.wav"),
	"Storm": preload("res://SoundCore/Sound/soundtrack_1/Storm(loop) - dark - heavy - lurking.wav"),
	# Standard Combat (randomly picked)
	"Outlaws": preload("res://SoundCore/Sound/soundtrack_1/Outlaws - violent - nervousness.wav"),
	"Assault": preload("res://SoundCore/Sound/soundtrack_1/Assault(loop) - angry - tension - battle.wav"),
	# Critical Overlay
	"Battlefield": preload("res://SoundCore/Sound/soundtrack_1/Battlefield(loop).wav"),
	# Special Combat
	"Waiting_game": preload("res://SoundCore/Sound/soundtrack_1/Waiting_game(loop).wav"),
	"War": preload("res://SoundCore/Sound/soundtrack_1/War(loop).wav"),
	# Game Over
	"Survivor": preload("res://SoundCore/Sound/soundtrack_1/Survivor - ending - lonely - sad - strings.wav"),
}

const COMBAT_TRACKS: Array = ["Outlaws", "Assault"]

# ---------------------------------------------------------
# INITIALIZATION
# ---------------------------------------------------------

func _ready() -> void:
	_setup_main_bus()
	_setup_overlay_bus()
	_setup_players()
	_setup_sfx_conductor()
	_setup_event_bus_listeners()
	set_process(true)


func _setup_event_bus_listeners() -> void:
	var bus = get_node_or_null("/root/GameEventBus")
	if bus == null:
		return
	if not bus.scene_audio_requested.is_connected(_on_scene_audio_requested):
		bus.scene_audio_requested.connect(_on_scene_audio_requested)
	if not bus.player_vitals_changed.is_connected(_on_player_vitals_changed):
		bus.player_vitals_changed.connect(_on_player_vitals_changed)


func _on_scene_audio_requested(scene_id: String, context: Dictionary) -> void:
	match scene_id:
		"macro_day":
			enter_scene(AudioScene.MACRO_DAY)
		"macro_night":
			enter_scene(AudioScene.MACRO_NIGHT)
		"combat_standard":
			enter_scene(AudioScene.COMBAT_STANDARD)
		"combat_special":
			enter_scene(AudioScene.COMBAT_SPECIAL)
		"game_over":
			enter_scene(AudioScene.GAME_OVER)
		"silent":
			enter_scene(AudioScene.SILENT)
		"world_time_changed":
			on_world_time_changed(int(context.get("hour", 8)))
		"first_strike":
			on_first_strike(int(context.get("action_type", 0)))


func _on_player_vitals_changed(context: Dictionary) -> void:
	var event_type := str(context.get("type", ""))
	match event_type:
		"kinetic_tier":
			on_kinetic_tier_changed(
				context.get("tier", GameEnums.KineticTier.FLUID),
				int(context.get("burden", 0))
			)
		"stance":
			on_stance_changed(
				context.get("stance", GameEnums.StanceState.PLANTED),
				int(context.get("points", 12))
			)
		"morale_broken":
			on_morale_broken()
		"player_died":
			on_player_died(str(context.get("cause", "")))

func _setup_sfx_conductor() -> void:
	var sfx = SfxConductor.new()
	sfx.name = "SfxConductor"
	add_child(sfx)

func _setup_main_bus() -> void:
	algorave_bus_idx = AudioServer.get_bus_index("AlgoraveBus")
	if algorave_bus_idx == -1:
		algorave_bus_idx = AudioServer.get_bus_count()
		AudioServer.add_bus(algorave_bus_idx)
		AudioServer.set_bus_name(algorave_bus_idx, "AlgoraveBus")
		AudioServer.set_bus_send(algorave_bus_idx, "Master")

	amp_effect = AudioEffectAmplify.new()

	while AudioServer.get_bus_effect_count(algorave_bus_idx) > 0:
		AudioServer.remove_bus_effect(algorave_bus_idx, 0)

	AudioServer.add_bus_effect(algorave_bus_idx, amp_effect)

func _setup_overlay_bus() -> void:
	overlay_bus_idx = AudioServer.get_bus_index("OverlayBus")
	if overlay_bus_idx == -1:
		overlay_bus_idx = AudioServer.get_bus_count()
		AudioServer.add_bus(overlay_bus_idx)
		AudioServer.set_bus_name(overlay_bus_idx, "OverlayBus")
		AudioServer.set_bus_send(overlay_bus_idx, "Master")

	overlay_amp = AudioEffectAmplify.new()
	overlay_amp.volume_db = -80.0

	while AudioServer.get_bus_effect_count(overlay_bus_idx) > 0:
		AudioServer.remove_bus_effect(overlay_bus_idx, 0)

	AudioServer.add_bus_effect(overlay_bus_idx, overlay_amp)

func _setup_players() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = "AlgoraveBus"
	music_player.name = "MusicPlayer"
	add_child(music_player)
	music_player.finished.connect(_on_music_finished)

	overlay_player = AudioStreamPlayer.new()
	overlay_player.bus = "OverlayBus"
	overlay_player.name = "OverlayPlayer"
	add_child(overlay_player)
	overlay_player.finished.connect(_on_overlay_finished)

# ---------------------------------------------------------
# SCENE MANAGEMENT (The Director's Interface)
# ---------------------------------------------------------

func enter_scene(scene: AudioScene) -> void:
	current_scene = scene
	_reset_algorave_params()

	match scene:
		AudioScene.MACRO_DAY:
			_play_main("Dawn")
			set_critical_overlay(false)
			print("[CONDUCTOR] Scene: MACRO_DAY → Dawn")
		AudioScene.MACRO_NIGHT:
			_play_main("Storm")
			set_critical_overlay(false)
			print("[CONDUCTOR] Scene: MACRO_NIGHT → Storm")
		AudioScene.COMBAT_STANDARD:
			var combat_track: String = COMBAT_TRACKS.pick_random()
			_play_main(combat_track)
			_combat_first_strike_fired = false
			print("[CONDUCTOR] Scene: COMBAT_STANDARD → ", combat_track)
		AudioScene.COMBAT_SPECIAL:
			_play_main("Waiting_game")
			_combat_first_strike_fired = false
			print("[CONDUCTOR] Scene: COMBAT_SPECIAL → Waiting_game (awaiting first strike)")
		AudioScene.GAME_OVER:
			_play_main("Survivor")
			set_critical_overlay(false)
			print("[CONDUCTOR] Scene: GAME_OVER → Survivor")
		AudioScene.SILENT:
			stop_all()
			print("[CONDUCTOR] Scene: SILENT")

func on_world_time_changed(hour: int) -> void:
	if current_scene != AudioScene.MACRO_DAY and current_scene != AudioScene.MACRO_NIGHT:
		return # Don't interrupt combat or game over

	if GameTimeRules.is_night_hour(hour):
		if current_scene != AudioScene.MACRO_NIGHT:
			enter_scene(AudioScene.MACRO_NIGHT)
	else:
		if current_scene != AudioScene.MACRO_DAY:
			enter_scene(AudioScene.MACRO_DAY)

# ---------------------------------------------------------
# FIRST STRIKE TRANSITION (Special Combat)
# ---------------------------------------------------------

func on_first_strike(_action_type: int) -> void:
	if current_scene != AudioScene.COMBAT_SPECIAL:
		return
	if _combat_first_strike_fired:
		return

	_combat_first_strike_fired = true
	print("[CONDUCTOR] FIRST STRIKE! Pausing for impact transition...")

	# Brief pause for the impact
	get_tree().paused = true
	music_player.stop()

	# Use a SceneTreeTimer which works even when paused
	var timer := get_tree().create_timer(0.15, true, false, true) # process_always = true
	await timer.timeout

	get_tree().paused = false
	_play_main("War")
	print("[CONDUCTOR] → War loop engaged.")

# ---------------------------------------------------------
# CRITICAL CONDITION OVERLAY
# ---------------------------------------------------------

func set_critical_overlay(active: bool) -> void:
	is_overlay_active = active
	if active:
		if not overlay_player.playing:
			overlay_player.stream = TRACKS["Battlefield"]
			overlay_player.play()
		target_overlay_gain_db = -12.0 # Low volume underneath
		print("[CONDUCTOR] Critical overlay: ON (Battlefield rumble)")
	else:
		target_overlay_gain_db = -80.0 # Fade to silence
		# overlay_player.stop() is handled by _process when gain reaches ~-79

# ---------------------------------------------------------
# PLAYER STATE HOOKS (Trigger SFX but no track warping)
# ---------------------------------------------------------

## Called when the player's kinetic burden tier changes.
func on_kinetic_tier_changed(tier: GameEnums.KineticTier, _burden: int) -> void:
	match tier:
		GameEnums.KineticTier.FLUID:
			set_critical_overlay(false)
		GameEnums.KineticTier.LABORED:
			set_critical_overlay(false)
		GameEnums.KineticTier.AGONIZING:
			# Only allow critical overlay during combat scenes
			if current_scene == AudioScene.COMBAT_STANDARD or current_scene == AudioScene.COMBAT_SPECIAL:
				set_critical_overlay(true)

## Called when the player's stance state changes.
func on_stance_changed(_new_state: GameEnums.StanceState, _points: int) -> void:
	pass

## Called when the player's morale breaks.
func on_morale_broken() -> void:
	print("[CONDUCTOR] MORALE BROKEN")

## Called on player death — fade out.
func on_player_died(_cause: String) -> void:
	set_gain(-80.0) # Fade out to silence
	set_critical_overlay(false)
	print("[CONDUCTOR] PLAYER DIED")

# ---------------------------------------------------------
# LOW-LEVEL CONTROLS
# ---------------------------------------------------------

func set_gain(gain_db: float, instant: bool = false) -> void:
	target_gain_db = clampf(gain_db, -80.0, 24.0)
	if instant:
		amp_effect.volume_db = target_gain_db

func stop_all() -> void:
	music_player.stop()
	overlay_player.stop()

# ---------------------------------------------------------
# INTERNAL
# ---------------------------------------------------------

func _play_main(track_name: String) -> void:
	if TRACKS.has(track_name):
		music_player.stream = TRACKS[track_name]
		music_player.play()
	else:
		push_error("[CONDUCTOR] Unknown track: " + track_name)

func _reset_algorave_params() -> void:
	target_gain_db = 0.0
	amp_effect.volume_db = 0.0

func _on_music_finished() -> void:
	# Re-loop the current track (Dawn, Storm, combat tracks are all loops)
	if current_scene != AudioScene.GAME_OVER and current_scene != AudioScene.SILENT:
		music_player.play()

func _on_overlay_finished() -> void:
	if is_overlay_active:
		overlay_player.play()

# ---------------------------------------------------------
# PROCESS LOOP (Smooth Interpolation)
# ---------------------------------------------------------

func _process(delta: float) -> void:
	var t: float = delta * smooth_speed

	# Main Gain
	amp_effect.volume_db = lerpf(amp_effect.volume_db, target_gain_db, t)

	# Overlay Gain
	overlay_amp.volume_db = lerpf(overlay_amp.volume_db, target_overlay_gain_db, t)
	if not is_overlay_active and overlay_amp.volume_db < -78.0 and overlay_player.playing:
		overlay_player.stop()

# ---------------------------------------------------------
# LEGACY COMPAT
# ---------------------------------------------------------

func play_track(stream: AudioStream) -> void:
	music_player.stream = stream
	music_player.play()

func play_preset(preset_name: String) -> void:
	if TRACKS.has(preset_name):
		play_track(TRACKS[preset_name])
	else:
		push_error("AudioConductor: Track not found: " + preset_name)

func stop_track() -> void:
	music_player.stop()
