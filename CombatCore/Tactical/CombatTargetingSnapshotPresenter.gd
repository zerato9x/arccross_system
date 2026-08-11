extends RefCounted
class_name CombatTargetingSnapshotPresenter

func build(snapshot: Dictionary) -> Dictionary:
	return {
		"targeting": snapshot.get("targeting", {}).duplicate(true),
		"selected_actor_id": str(snapshot.get("selected_actor_id", "")),
		"selected_body_region": int(snapshot.get("selected_body_region", -1)),
	}
