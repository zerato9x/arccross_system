extends RefCounted
class_name CombatTurnStatusSnapshotPresenter

func build(snapshot: Dictionary) -> Dictionary:
	var active_actor_id := str(snapshot.get("active_actor_id", ""))
	var max_ap := int(snapshot.get("max_ap", 12))
	for raw_actor in snapshot.get("actors", []):
		if raw_actor is Dictionary and str(raw_actor.get("actor_id", "")) == active_actor_id:
			max_ap = int(raw_actor.get("max_ap", max_ap))
			break
	var communication_points: Dictionary = snapshot.get("arena", {}).get("communication_points", {})
	return {
		"initiative_order": snapshot.get("initiative_order", []).duplicate(true),
		"round": int(snapshot.get("round", 0)),
		"ap": int(snapshot.get("ap", 0)),
		"active_actor_id": active_actor_id,
		"max_ap": maxi(0, max_ap),
		"communication_points": communication_points.duplicate(true),
	}
