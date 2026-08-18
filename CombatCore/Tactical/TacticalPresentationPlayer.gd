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
var dialogue_director := CombatDialogueDirector.new()
var encounter_seed := ""


func configure(arena_view: TacticalArenaView) -> void:
	view = arena_view
	dialogue_director.configure()


func configure_dialogue_seed(encounter_seed_value: String) -> void:
	encounter_seed = encounter_seed_value


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
			var tween := create_tween()
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.set_ease(Tween.EASE_IN_OUT)
			tween.tween_method(view.update_cue.bind(cue), 0.0, 1.0, maxf(0.01, cue.duration_seconds))
			await tween.finished
			view.end_cue(cue)
			_try_show_dialogue(cue)
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
		event_bus.emit_scene_audio("combat_action_sfx", audio_payload_for_cue(cue))
	if cue.phase_id == "impact" and cue.outcome_tag not in ["miss", "neutral", "malfunction"]:
		# Impact is contact presentation only. HumanInjured is emitted exactly once
		# by wound creation and is the sole authority for injury vocals.
		event_bus.emit_scene_audio("combat_impact_sfx", audio_payload_for_cue(cue))


static func audio_payload_for_cue(cue: CombatPresentationCue) -> Dictionary:
	if cue == null:
		return {}
	return {
		"encounter_id": cue.encounter_id,
		"action_event_id": cue.action_event_id,
		"action_id": cue.action_id,
		"attacker_id": cue.actor_id,
		"victim_id": cue.target_actor_id,
		"body_region": cue.target_body_region,
		"source_item_instance_id": cue.source_item_instance_id,
		"weapon_class": cue.weapon_class,
		"weapon_id": cue.weapon_id,
		"result": cue.outcome_tag,
	}


func _try_show_dialogue(cue: CombatPresentationCue) -> void:
	if view == null or cue == null or cue.dialogue_event.is_empty() or not bool(cue.presentation_flags.get("dialogue_allowed", false)):
		return
	var actor := view.actor_snapshot_for_presentation(cue.actor_id)
	var round_index := int(view.snapshot.get("round", 0))
	var payload := dialogue_director.request_bark(
		actor,
		cue.dialogue_event,
		encounter_seed,
		int(view.snapshot.get("revision", 0)),
		round_index,
		cue.dialogue_id,
		cue.dialogue_priority
	)
	if not payload.is_empty():
		view.show_dialogue(payload)
