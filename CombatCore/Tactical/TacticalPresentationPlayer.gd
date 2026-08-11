extends Node
class_name TacticalPresentationPlayer

signal sequence_started(sequence: CombatPresentationSequence)
signal cue_started(cue: CombatPresentationCue)
signal cue_finished(cue: CombatPresentationCue)
signal sequence_finished(sequence: CombatPresentationSequence)
signal timeline_finished(timeline_id: String)

var view: TacticalArenaView
var _playing := false
var _drain_scheduled := false
var _queued_sequences: Array[CombatPresentationSequence] = []


func configure(arena_view: TacticalArenaView) -> void:
	view = arena_view


func play(sequence: CombatPresentationSequence) -> void:
	if sequence == null:
		return
	if DisplayServer.get_name().contains("headless"):
		sequence_finished.emit(sequence)
		timeline_finished.emit(sequence.timeline_id)
		return
	_queued_sequences.append(sequence)
	if not _playing and not _drain_scheduled:
		_drain_scheduled = true
		call_deferred("_drain_queue")
	while true:
		var completed_timeline: String = await timeline_finished
		if completed_timeline == sequence.timeline_id:
			return


func _drain_queue() -> void:
	_drain_scheduled = false
	if _playing:
		return
	while not _queued_sequences.is_empty():
		var next: CombatPresentationSequence = _queued_sequences.pop_front() as CombatPresentationSequence
		await _play_sequence(next)
		timeline_finished.emit(next.timeline_id)


func _play_sequence(sequence: CombatPresentationSequence) -> void:
	_playing = true
	sequence_started.emit(sequence)
	if view != null:
		view.begin_sequence(sequence)
	var elapsed := 0.0
	for cue in sequence.cues:
		if cue == null:
			continue
		var scheduled_delay := maxf(0.0, cue.start_time_seconds - elapsed)
		if scheduled_delay > 0.0:
			await get_tree().create_timer(scheduled_delay).timeout
		cue_started.emit(cue)
		_play_audio_cue(cue)
		if view != null:
			view.begin_cue(cue)
			if cue.hit_stop_seconds > 0.0:
				view.update_cue(0.0, cue)
				await get_tree().create_timer(cue.hit_stop_seconds).timeout
			var tween := create_tween()
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.set_ease(Tween.EASE_IN_OUT)
			tween.tween_method(view.update_cue.bind(cue), 0.0, 1.0, maxf(0.01, cue.duration_seconds))
			await tween.finished
			view.end_cue(cue)
		else:
			await get_tree().create_timer(maxf(0.01, cue.duration_seconds)).timeout
		cue_finished.emit(cue)
		elapsed = cue.start_time_seconds + cue.duration_seconds
	if view != null:
		view.end_sequence(sequence)
	_playing = false
	sequence_finished.emit(sequence)


func is_playing() -> bool:
	return _playing


func _play_audio_cue(cue: CombatPresentationCue) -> void:
	if cue == null:
		return
	var event_bus := get_node_or_null("/root/GameEventBus")
	if event_bus == null:
		return
	if not cue.sfx_id.is_empty():
		event_bus.emit_scene_audio("combat_action_sfx", {
			"action_id": cue.action_id,
			"weapon_class": cue.weapon_class,
			"weapon_id": cue.weapon_id,
		})
	if cue.phase_id == "impact" and cue.outcome_tag not in ["miss", "dodge", "neutral", "malfunction"]:
		event_bus.emit_scene_audio("combat_damage_sfx", {"result": cue.outcome_tag})
