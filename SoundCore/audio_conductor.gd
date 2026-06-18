extends Node
class_name AudioConductorSystem

# ---------------------------------------------------------
# AUDIO CONDUCTOR: Algorave Realtime Sound Engine
# ---------------------------------------------------------
# Manages procedural audio buses and soundtrack routing based
# on game state, player actions, and world time.
# Tracks the player's subjective experience only.
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
# AUDIO EFFECTS (Main Bus)
# ---------------------------------------------------------
var eq_effect: AudioEffectEQ6
var phantom_eq: AudioEffectBandPassFilter
var pitch_shift: AudioEffectPitchShift
var amp_effect: AudioEffectAmplify

# ---------------------------------------------------------
# AUDIO EFFECTS (Overlay Bus)
# ---------------------------------------------------------
var overlay_eq: AudioEffectEQ6
var overlay_amp: AudioEffectAmplify

# ---------------------------------------------------------
# TARGET PARAMETERS (smoothed via _process)
# ---------------------------------------------------------
var target_low_db: float = 0.0
var target_mid_db: float = 0.0
var target_high_db: float = 0.0
var target_time_scale: float = 1.0
var target_gain_db: float = 0.0
var target_phantom_cutoff: float = 2000.0
var target_overlay_gain_db: float = -80.0 # Starts silent

var is_pitch_preserved: bool = true
var is_phantom_active: bool = false
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
	set_process(true)

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

	eq_effect = AudioEffectEQ6.new()
	phantom_eq = AudioEffectBandPassFilter.new()
	phantom_eq.resonance = 0.7
	pitch_shift = AudioEffectPitchShift.new()
	amp_effect = AudioEffectAmplify.new()

	while AudioServer.get_bus_effect_count(algorave_bus_idx) > 0:
		AudioServer.remove_bus_effect(algorave_bus_idx, 0)

	AudioServer.add_bus_effect(algorave_bus_idx, eq_effect)       # 0
	AudioServer.add_bus_effect(algorave_bus_idx, phantom_eq)      # 1
	AudioServer.add_bus_effect(algorave_bus_idx, pitch_shift)     # 2
	AudioServer.add_bus_effect(algorave_bus_idx, amp_effect)      # 3

	AudioServer.set_bus_effect_enabled(algorave_bus_idx, 1, false) # phantom off
	AudioServer.set_bus_effect_enabled(algorave_bus_idx, 2, false) # pitch shift off

func _setup_overlay_bus() -> void:
	overlay_bus_idx = AudioServer.get_bus_index("OverlayBus")
	if overlay_bus_idx == -1:
		overlay_bus_idx = AudioServer.get_bus_count()
		AudioServer.add_bus(overlay_bus_idx)
		AudioServer.set_bus_name(overlay_bus_idx, "OverlayBus")
		AudioServer.set_bus_send(overlay_bus_idx, "Master")

	overlay_eq = AudioEffectEQ6.new()
	overlay_amp = AudioEffectAmplify.new()
	overlay_amp.volume_db = -80.0

	while AudioServer.get_bus_effect_count(overlay_bus_idx) > 0:
		AudioServer.remove_bus_effect(overlay_bus_idx, 0)

	AudioServer.add_bus_effect(overlay_bus_idx, overlay_eq)  # 0
	AudioServer.add_bus_effect(overlay_bus_idx, overlay_amp) # 1

	# Carve the overlay EQ so Battlefield doesn't clash with the combat track:
	# Cut highs, boost lows — rumbling dread underneath
	overlay_eq.set_band_gain_db(0, 3.0)   # 32Hz  — boost
	overlay_eq.set_band_gain_db(1, 2.0)   # 100Hz — boost
	overlay_eq.set_band_gain_db(2, -2.0)  # 320Hz — slight cut
	overlay_eq.set_band_gain_db(3, -6.0)  # 1kHz  — cut
	overlay_eq.set_band_gain_db(4, -12.0) # 3.2kHz — heavy cut
	overlay_eq.set_band_gain_db(5, -20.0) # 10kHz — near silent

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

	if hour >= 6 and hour < 18:
		if current_scene != AudioScene.MACRO_DAY:
			enter_scene(AudioScene.MACRO_DAY)
	else:
		if current_scene != AudioScene.MACRO_NIGHT:
			enter_scene(AudioScene.MACRO_NIGHT)

# ---------------------------------------------------------
# FIRST STRIKE TRANSITION (Special Combat)
# ---------------------------------------------------------

func on_first_strike() -> void:
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
# PLAYER STATE HOOKS (Algorave Warping — No Track Override)
# ---------------------------------------------------------

## Called when the player's kinetic burden tier changes.
func on_kinetic_tier_changed(tier: GameEnums.KineticTier, _burden: int) -> void:
	match tier:
		GameEnums.KineticTier.FLUID:
			set_time_stretch(1.0)
			set_3band_eq(0.0, 0.0, 0.0)
			set_critical_overlay(false)
		GameEnums.KineticTier.LABORED:
			set_time_stretch(0.92)
			set_3band_eq(1.0, -1.0, -2.0)
			set_critical_overlay(false)
		GameEnums.KineticTier.AGONIZING:
			set_time_stretch(0.82)
			set_3band_eq(2.0, -3.0, -8.0) # Muffled, labored breathing feel
			
			# Only allow critical overlay during combat scenes
			if current_scene == AudioScene.COMBAT_STANDARD or current_scene == AudioScene.COMBAT_SPECIAL:
				set_critical_overlay(true)

## Called when the player's stance state changes.
func on_stance_changed(new_state: GameEnums.StanceState, _points: int) -> void:
	match new_state:
		GameEnums.StanceState.PLANTED:
			set_phantom_eq(false)
		GameEnums.StanceState.STUMBLING:
			set_3band_eq(0.0, 0.0, -4.0) # Slight high cut
		GameEnums.StanceState.FELLED:
			# Activate phantom sweep — ringing/daze effect
			set_phantom_eq(true, 600.0, 0.9)
			set_3band_eq(3.0, -6.0, -15.0) # Heavy high cut, boosted lows

## Called when the player's morale breaks — warp existing track, no override.
func on_morale_broken() -> void:
	set_time_stretch(0.7, false) # Raw vinyl stretch — pitch drops
	set_phantom_eq(true, 400.0, 0.95) # Deep, narrow sweep
	set_3band_eq(4.0, -8.0, -20.0) # Underwater panic
	print("[CONDUCTOR] MORALE BROKEN — algorave panic warp engaged")

## Called on player death — vinyl stop effect.
func on_player_died(_cause: String) -> void:
	set_time_stretch(0.1, false, true) # Instant slow-to-stop
	set_3band_eq(-10.0, -20.0, -40.0, true) # Instant mute highs
	set_critical_overlay(false)
	print("[CONDUCTOR] PLAYER DIED — vinyl stop")

# ---------------------------------------------------------
# LOW-LEVEL CONTROLS
# ---------------------------------------------------------

func set_3band_eq(low_db: float, mid_db: float, high_db: float, instant: bool = false) -> void:
	target_low_db = clampf(low_db, -60.0, 24.0)
	target_mid_db = clampf(mid_db, -60.0, 24.0)
	target_high_db = clampf(high_db, -60.0, 24.0)
	if instant:
		_apply_eq(target_low_db, target_mid_db, target_high_db)

func set_phantom_eq(active: bool, cutoff_hz: float = 2000.0, resonance: float = 0.7, instant: bool = false) -> void:
	is_phantom_active = active
	AudioServer.set_bus_effect_enabled(algorave_bus_idx, 1, active)
	target_phantom_cutoff = clampf(cutoff_hz, 20.0, 20000.0)
	phantom_eq.resonance = resonance
	if instant:
		phantom_eq.cutoff_hz = target_phantom_cutoff

func set_time_stretch(time_scale: float, pitch_preserve: bool = true, instant: bool = false) -> void:
	target_time_scale = maxf(time_scale, 0.01)
	is_pitch_preserved = pitch_preserve
	if instant:
		_apply_time_stretch(target_time_scale)

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
	target_low_db = 0.0
	target_mid_db = 0.0
	target_high_db = 0.0
	target_time_scale = 1.0
	target_gain_db = 0.0
	is_pitch_preserved = true
	set_phantom_eq(false, 2000.0, 0.7, true)
	_apply_eq(0.0, 0.0, 0.0)
	_apply_time_stretch(1.0)
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

	# Main EQ
	var current_low = eq_effect.get_band_gain_db(0)
	var current_mid = eq_effect.get_band_gain_db(2)
	var current_high = eq_effect.get_band_gain_db(4)
	_apply_eq(
		lerpf(current_low, target_low_db, t),
		lerpf(current_mid, target_mid_db, t),
		lerpf(current_high, target_high_db, t)
	)

	# Time Stretch
	_apply_time_stretch(lerpf(music_player.pitch_scale, target_time_scale, t))

	# Main Gain
	amp_effect.volume_db = lerpf(amp_effect.volume_db, target_gain_db, t)

	# Phantom EQ
	if is_phantom_active:
		phantom_eq.cutoff_hz = lerpf(phantom_eq.cutoff_hz, target_phantom_cutoff, t)

	# Overlay Gain
	overlay_amp.volume_db = lerpf(overlay_amp.volume_db, target_overlay_gain_db, t)
	if not is_overlay_active and overlay_amp.volume_db < -78.0 and overlay_player.playing:
		overlay_player.stop()

func _apply_eq(low: float, mid: float, high: float) -> void:
	eq_effect.set_band_gain_db(0, low)
	eq_effect.set_band_gain_db(1, low)
	eq_effect.set_band_gain_db(2, mid)
	eq_effect.set_band_gain_db(3, mid)
	eq_effect.set_band_gain_db(4, high)
	eq_effect.set_band_gain_db(5, high)

func _apply_time_stretch(scale: float) -> void:
	music_player.pitch_scale = scale
	if is_pitch_preserved:
		AudioServer.set_bus_effect_enabled(algorave_bus_idx, 2, true)
		pitch_shift.pitch_scale = clampf(1.0 / scale, 0.01, 16.0)
	else:
		AudioServer.set_bus_effect_enabled(algorave_bus_idx, 2, false)

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
