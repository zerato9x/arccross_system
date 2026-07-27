extends RefCounted
class_name MacroWorldLighting

## Applies day/night lighting to macro vision + HUD. Extracted from MacroGameManager
## so world-sim orchestration does not own presentation lighting details.

static func apply_from_minutes(
	total_minutes: int,
	vision_vignette: Node,
	macro_hud: Node
) -> void:
	if vision_vignette == null:
		return
	var clock: Dictionary = GameTimeRules.clock_snapshot(total_minutes)
	var hour := int(clock.get("hour", 8))
	var phase := GameTimeRules.phase_for_hour(hour)
	if vision_vignette.has_method("apply_lighting_phase"):
		vision_vignette.apply_lighting_phase(phase)
	if macro_hud != null and macro_hud.has_method("apply_lighting_phase"):
		macro_hud.apply_lighting_phase(phase)
