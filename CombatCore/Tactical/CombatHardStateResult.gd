extends RefCounted
class_name CombatHardStateResult

const INACTIVE := "INACTIVE"
const ENGAGED := "ENGAGED"
const BROKEN := "BROKEN"
const CRITICAL := "CRITICAL"
const WEAPON_DISABLED := "WEAPON_DISABLED"
const OUT_OF_AMMO := "OUT_OF_AMMO"
const THREATENED := "THREATENED"
const OUTNUMBERED := "OUTNUMBERED"
const EXPOSED := "EXPOSED"
const TRAPPED := "TRAPPED"
const STABLE := "STABLE"

var snapshot_revision: int = 0
var tags: Array[String] = []
var dominant_tag: String = STABLE
var terminal: bool = false
var reason_tags: Array[String] = []


func to_dict() -> Dictionary:
	return {
		"snapshot_revision": snapshot_revision,
		"tags": tags.duplicate(),
		"dominant_tag": dominant_tag,
		"terminal": terminal,
		"reason_tags": reason_tags.duplicate(),
	}


func duplicate_result():
	var copy = (load("res://CombatCore/Tactical/CombatHardStateResult.gd") as Script).new()
	copy.snapshot_revision = snapshot_revision
	copy.tags = tags.duplicate()
	copy.dominant_tag = dominant_tag
	copy.terminal = terminal
	copy.reason_tags = reason_tags.duplicate()
	return copy
