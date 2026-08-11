extends RefCounted
class_name CombatActionMenuSnapshotPresenter

func build(snapshot: Dictionary) -> Dictionary:
	return {
		"quotes": snapshot.get("quotes", []).duplicate(true),
		"active_actor_id": str(snapshot.get("active_actor_id", "")),
		"selected_sector": snapshot.get("selected_sector", Vector2i(-1, -1)),
	}
