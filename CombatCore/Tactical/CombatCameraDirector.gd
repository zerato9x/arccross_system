extends RefCounted
class_name CombatCameraDirector

## Presentation-only camera policy. Manual pan/zoom is captured once at the
## start of a sequence and restored after the final focus_out marker.

var arena: TacticalArenaView
var _active := false
var _manual_zoom := 1.0
var _manual_pan := Vector2.ZERO


func configure(arena_view: TacticalArenaView) -> void:
	arena = arena_view


func begin_sequence(sequence: CombatPresentationSequence) -> void:
	if arena == null or sequence == null:
		return
	if not _active:
		_manual_zoom = arena.camera_zoom()
		_manual_pan = arena.camera_pan()
	_active = true
	if sequence.camera_safe_rect.size.x > 0.0 and sequence.camera_safe_rect.size.y > 0.0:
		arena.set_camera_safe_rect(sequence.camera_safe_rect)


func begin_cue(cue: CombatPresentationCue) -> void:
	if not _active or arena == null or cue == null or cue.camera_cue_id.is_empty():
		return
	# Frame once at the beginning of the authored action. Reframing on release,
	# impact, and focus_out made every short marker fight the previous camera
	# position and produced the nauseating snap-zoom chain.
	if cue.marker_id == "focus_in" or (cue.marker_id.is_empty() and cue.phase_id == "focus_in"):
		arena.frame_cinematic_cue(cue)


func end_sequence(_sequence: CombatPresentationSequence) -> void:
	if arena == null or not _active:
		return
	arena.animate_camera_transform(_manual_zoom, _manual_pan)
	_active = false


func is_active() -> bool:
	return _active
