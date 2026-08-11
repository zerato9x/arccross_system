extends RefCounted
class_name CombatFeedbackSnapshotPresenter

func build(snapshot: Dictionary) -> Dictionary:
	return {
		"feedback": str(snapshot.get("feedback", "")),
		"result_events": snapshot.get("result_events", []).duplicate(true),
		"presentation_events": snapshot.get("presentation_events", []).duplicate(true),
	}
