extends RefCounted
class_name CombatTurnStatusSnapshotPresenter

func build(snapshot: Dictionary) -> Dictionary:
	return {
		"initiative_order": snapshot.get("initiative_order", []).duplicate(true),
		"round": int(snapshot.get("round", 0)),
		"ap": int(snapshot.get("ap", 0)),
		"reserved_ap": snapshot.get("reserved_ap", {}).duplicate(true),
		"active_actor_id": str(snapshot.get("active_actor_id", "")),
	}
