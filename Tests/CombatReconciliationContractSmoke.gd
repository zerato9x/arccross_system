extends SceneTree


func _init() -> void:
	var failures: Array[String] = []
	var catalog := load("res://CombatCore/Tactical/default_combat_action_catalog.tres") as CombatActionCatalog
	for action_id in ["aimed_strike", "aimed_fire", "power_strike", "stand", "crouch", "disengage", "clear_malfunction", "block", "dodge", "opportunity_strike"]:
		if catalog.definition(action_id) != null:
			failures.append("Retired action remains loadable: %s" % action_id)

	if CombatArenaState.SCHEMA_VERSION != 4:
		failures.append("Combat arena schema was not advanced to the strict reconciliation version.")

	var forbidden_by_path := {
		"res://SystemCore/CombatActionRequest.gd": ["final_facing"],
		"res://SystemCore/CombatActionQuote.gd": ["final_facing", "reaction_threat", "reaction_step"],
		"res://SystemCore/CombatActionOutcome.gd": ["reaction_outcomes"],
		"res://CombatCore/Tactical/TacticalTurnManager.gd": ["reserved_ap", "reaction_ap", "reaction_requested"],
		"res://CombatCore/Tactical/CombatActionDefinition.gd": ["required_postures", "reaction_tags", "reaction_only", "automatic_reaction"],
		"res://CombatCore/Tactical/CombatBoard.gd": ["actor_facings", "actor_postures", "reaction_threats", "attack_arc"],
		"res://SystemCore/CombatPresentationCue.gd": ["lunge_pixels", "recoil_pixels", "shake_amplitude", "hit_stop_seconds", "camera_impulse_pixels", "impact_scale", "impact_rotation_degrees"],
		"res://CombatCore/Tactical/CombatEffectRecipe.gd": ["lunge_pixels", "recoil_pixels", "shake_amplitude", "hit_stop_seconds", "camera_impulse_pixels", "impact_scale", "impact_rotation_degrees"],
		"res://CombatCore/Tactical/TacticalCombatHUD.tscn": ["ReactionPanel", "PostureChip", "TargetPosture"],
	}
	for path: String in forbidden_by_path:
		var source := FileAccess.get_file_as_string(path)
		for forbidden: String in forbidden_by_path[path]:
			if source.contains(forbidden):
				failures.append("%s still contains retired structural field %s." % [path, forbidden])

	if ResourceLoader.exists("res://CombatCore/Tactical/CombatReactionResolver.gd"):
		failures.append("CombatReactionResolver remains loadable.")
	if ResourceLoader.exists("res://CombatCore/Tactical/aim_effect_profile.tres"):
		failures.append("The retired aim effect profile remains loadable.")
	if ResourceLoader.exists("res://CombatCore/Tactical/power_effect_profile.tres"):
		failures.append("The retired power effect profile remains loadable.")

	if failures.is_empty():
		print("COMBAT_RECONCILIATION_CONTRACT_SMOKE: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
