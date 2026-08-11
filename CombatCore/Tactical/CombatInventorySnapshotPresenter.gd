extends RefCounted
class_name CombatInventorySnapshotPresenter

func build(snapshot: Dictionary) -> Dictionary:
	return {
		"actors": snapshot.get("actors", []).duplicate(true),
		"ground_items": snapshot.get("ground_items", []).duplicate(true),
		"selected_item_id": str(snapshot.get("selected_item_id", "")),
	}
