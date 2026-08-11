extends RefCounted
class_name CombatRevisionAuthority

## Encounter-local gameplay revision.  Presentation and passive redraws never
## call bump(); only authoritative state boundaries do.

signal revision_changed(revision: int, reason: String)

var revision: int = 0
var last_reason: String = "initial"
var history: Array[Dictionary] = []


func reset(value: int = 0, reason: String = "reset") -> int:
	revision = maxi(0, value)
	last_reason = reason
	history.clear()
	return revision


func bump(reason: String = "authoritative_change") -> int:
	revision += 1
	last_reason = reason
	history.append({"revision": revision, "reason": reason})
	if history.size() > 32:
		history.pop_front()
	revision_changed.emit(revision, reason)
	return revision


func is_current(candidate_revision: int) -> bool:
	return candidate_revision == revision


func to_dict() -> Dictionary:
	return {
		"revision": revision,
		"last_reason": last_reason,
		"history": history.duplicate(true),
	}
