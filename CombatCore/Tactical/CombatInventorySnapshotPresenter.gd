extends RefCounted
class_name CombatInventorySnapshotPresenter

func build(snapshot: Dictionary) -> Dictionary:
	var accessible_by_actor: Dictionary = {}
	for raw_actor in snapshot.get("actors", []):
		if not raw_actor is Dictionary:
			continue
		var actor: Dictionary = raw_actor
		var actor_id := str(actor.get("actor_id", ""))
		var accessible: Array = []
		for raw_item in actor.get("items", []):
			if not raw_item is Dictionary:
				continue
			var item: Dictionary = raw_item
			var access := str(item.get("access_tier", item.get("access", ""))).to_lower()
			if access in ["hands", "quick"]:
				accessible.append(item.duplicate(true))
		accessible_by_actor[actor_id] = accessible
	return {
		"actors": snapshot.get("actors", []).duplicate(true),
		"ground_items": snapshot.get("ground_items", []).duplicate(true),
		"selected_item_id": str(snapshot.get("selected_item_id", "")),
		"accessible_items_by_actor": accessible_by_actor,
	}
