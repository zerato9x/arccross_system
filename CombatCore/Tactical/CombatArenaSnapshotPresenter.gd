extends RefCounted
class_name CombatArenaSnapshotPresenter

func build(snapshot: Dictionary) -> Dictionary:
	return {
		"arena": snapshot.get("arena", {}).duplicate(true),
		"actors": snapshot.get("actors", []).duplicate(true),
	}
