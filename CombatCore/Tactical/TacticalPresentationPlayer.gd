extends Node
class_name TacticalPresentationPlayer

signal sequence_started(sequence: CombatPresentationSequence)
signal cue_started(cue: CombatPresentationCue)
signal cue_finished(cue: CombatPresentationCue)
signal sequence_finished(sequence: CombatPresentationSequence)

var view: TacticalArenaView
var _playing := false


func configure(arena_view: TacticalArenaView) -> void:
	view = arena_view


func play(sequence: CombatPresentationSequence) -> void:
	if sequence == null:
		return
	if DisplayServer.get_name().contains("headless"):
		sequence_finished.emit(sequence)
		return
	_playing = true
	sequence_started.emit(sequence)
	for cue in sequence.cues:
		if cue == null:
			continue
		cue_started.emit(cue)
		if view != null:
			view.begin_cue(cue)
			var tween := create_tween()
			tween.tween_method(view.update_cue.bind(cue), 0.0, 1.0, maxf(0.01, cue.duration_seconds))
			await tween.finished
			view.end_cue(cue)
		else:
			await get_tree().create_timer(maxf(0.01, cue.duration_seconds)).timeout
		cue_finished.emit(cue)
	_playing = false
	sequence_finished.emit(sequence)


func is_playing() -> bool:
	return _playing
