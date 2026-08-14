extends RefCounted
class_name CombatIntent

const _IntentView := preload("res://CombatCore/Tactical/CombatIntentView.gd")

## Immutable-at-publication decision record.  The orchestrator may replace the
## current intent after a new perception snapshot, but a controller never
## receives a mutable AI target outside the request carried by this record.

var actor_id: String = ""
var motive: String = ""
var subject_type: String = ""
var subject_id: String = ""
var tactical_problem: String = ""
var plan = null
var current_request: CombatActionRequest
var target_actor_id: String = ""
var target_sector: Vector2i = Vector2i(-1, -1)
var reason_tags: Array[String] = []
var score: float = 0.0
var snapshot_revision: int = -1
var intent_revision: int = 0
var decision_seed: String = ""


func to_dict() -> Dictionary:
	return {
		"actor_id": actor_id,
		"motive": motive,
		"subject_type": subject_type,
		"subject_id": subject_id,
		"tactical_problem": tactical_problem,
		"plan": plan.to_dict() if plan != null and plan.has_method("to_dict") else {},
		"current_request": current_request.to_dict() if current_request != null else {},
		"target_actor_id": target_actor_id,
		"target_sector": target_sector,
		"reason_tags": reason_tags.duplicate(),
		"score": score,
		"snapshot_revision": snapshot_revision,
		"intent_revision": intent_revision,
		"decision_seed": decision_seed,
	}


func to_view(profile_id: String = ""):
	var view = _IntentView.new()
	view.actor_id = actor_id
	view.motive = motive
	view.subject_type = subject_type
	view.subject_id = subject_id
	view.subject_label = _subject_label(subject_type, subject_id)
	view.tactical_problem = tactical_problem
	view.readable_label = _readable_label(motive, tactical_problem, current_request)
	view.icon_id = _icon_id(motive, tactical_problem, current_request)
	view.profile_id = profile_id
	view.target_sector = target_sector
	view.intent_revision = intent_revision
	view.snapshot_revision = snapshot_revision
	view.reason_tags = reason_tags.duplicate()
	return view


static func _subject_label(subject_type_value: String, subject_id_value: String) -> String:
	if subject_type_value == "actor" and not subject_id_value.is_empty():
		return subject_id_value
	return "Self"


static func _readable_label(motive_value: String, problem_value: String, request: CombatActionRequest) -> String:
	var action_id := request.action_id if request != null else ""
	match action_id:
		"engage": return "CLOSING DISTANCE"
		"move": return "REPOSITIONING"
		"reload": return "RELOADING"
		"cycle": return "CYCLING JAM"
		"ready": return "READYING WEAPON"
		"escape": return "RETREATING"
		"take_cover": return "SEEKING COVER"
		"end_turn": return "HOLDING"
		"fire", "strike", "incapacitate", "execute", "shove": return "ATTACKING"
		"offense", "defense", "support", "flee", "threaten", "ceasefire": return "COMMUNICATING"
	if problem_value == "NEED_ENGAGE":
		return "CLOSING DISTANCE"
	if motive_value in ["EXIT", "ESCAPE", "SURVIVE"]:
		return "EXITING" if motive_value in ["EXIT", "ESCAPE"] else "SURVIVING"
	if motive_value in ["SUPPORT", "PROTECT"]:
		return "PROTECTING"
	if motive_value == "HOLD":
		return "HOLDING"
	if motive_value == "COMMUNICATE":
		return "COMMUNICATING"
	return motive_value


static func _icon_id(motive_value: String, problem_value: String, request: CombatActionRequest) -> String:
	if request != null and not request.action_id.is_empty():
		return request.action_id
	if not problem_value.is_empty():
		return problem_value.to_lower()
	return motive_value.to_lower()
