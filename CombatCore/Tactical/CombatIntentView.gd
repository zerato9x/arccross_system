extends RefCounted
class_name CombatIntentView

## Coarse production-facing projection.  Detailed evaluator evidence stays in
## CombatDecisionTrace and is never required by the tactical HUD.

var actor_id: String = ""
var motive: String = ""
var subject_type: String = ""
var subject_id: String = ""
var subject_label: String = ""
var tactical_problem: String = ""
var readable_label: String = ""
var icon_id: String = ""
var profile_id: String = ""
var target_sector: Vector2i = Vector2i(-1, -1)
var intent_revision: int = 0
var snapshot_revision: int = -1
var reason_tags: Array[String] = []


func to_dict() -> Dictionary:
	return {
		"actor_id": actor_id,
		"motive": motive,
		"subject_type": subject_type,
		"subject_id": subject_id,
		"subject_label": subject_label,
		"tactical_problem": tactical_problem,
		"readable_label": readable_label,
		"icon_id": icon_id,
		"profile_id": profile_id,
		"target_sector": target_sector,
		"intent_revision": intent_revision,
		"snapshot_revision": snapshot_revision,
		"reason_tags": reason_tags.duplicate(),
	}
