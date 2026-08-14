extends SceneTree

var _failures: Array[String] = []
var _scene_audio_events: Array[Dictionary] = []
var _injury_events: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var bus := root.get_node_or_null("GameEventBus")
	if bus == null:
		_failures.append("GameEventBus autoload is unavailable.")
	else:
		bus.scene_audio_requested.connect(_on_scene_audio_requested)
		bus.humanoid_injured.connect(_on_humanoid_injured)

	var player := TacticalPresentationPlayer.new()
	root.add_child(player)
	var cue := CombatPresentationCue.new()
	cue.phase_id = "impact"
	cue.marker_id = "impact"
	cue.sfx_id = "weapon_contact"
	cue.outcome_tag = "hit"
	cue.encounter_id = "audio_identity"
	cue.action_event_id = "audio_identity:7:fire"
	cue.action_id = "fire"
	cue.actor_id = "shooter"
	cue.target_actor_id = "victim"
	cue.target_body_region = GameEnums.LimbRegion.UPPER_TORSO
	cue.source_item_instance_id = "pistol_instance_7"
	cue.weapon_class = GameEnums.WeaponClass.PISTOL
	cue.weapon_id = "service_pistol"
	player._play_audio_cue(cue)

	if _scene_audio_events.size() != 2:
		_failures.append("An impact cue did not emit exactly action and contact audio events.")
	for event in _scene_audio_events:
		var context: Dictionary = event.get("context", {})
		for key in ["encounter_id", "action_event_id", "action_id", "attacker_id", "victim_id", "body_region", "source_item_instance_id", "weapon_class", "weapon_id", "result"]:
			if not context.has(key):
				_failures.append("Audio payload omitted identity field %s." % key)
	if not _injury_events.is_empty():
		_failures.append("Impact contact incorrectly emitted HumanInjured before wound creation.")

	var body := HumanoidBody.new()
	root.add_child(body)
	await process_frame
	body.apply_targeted_hit(
		GameEnums.LimbRegion.UPPER_TORSO,
		3.0,
		2.0,
		GameEnums.DamageType.BALLISTIC,
		TacticalPresentationPlayer.audio_payload_for_cue(cue)
	)
	if _injury_events.size() != 1:
		_failures.append("One created wound did not emit exactly one HumanInjured event.")
	elif str(_injury_events[0].get("action_event_id", "")) != cue.action_event_id:
		_failures.append("HumanInjured did not preserve the originating action identity.")

	var presentation_source := FileAccess.get_file_as_string(
		"res://CombatCore/Tactical/TacticalPresentationPlayer.gd"
	)
	if presentation_source.contains("combat_damage_sfx"):
		_failures.append("The duplicate combat-damage audio route still exists.")
	if not presentation_source.contains("combat_impact_sfx"):
		_failures.append("The contact-only impact audio route is missing.")

	if _failures.is_empty():
		print("COMBAT_AUDIO_IDENTITY_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _on_scene_audio_requested(scene_id: String, context: Dictionary) -> void:
	_scene_audio_events.append({"scene_id": scene_id, "context": context.duplicate(true)})


func _on_humanoid_injured(_entity: Node, _wound_type: int, context: Dictionary) -> void:
	_injury_events.append(context.duplicate(true))
