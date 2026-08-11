extends RefCounted
class_name CombatTacticalProblem

const READY := "READY"
const NEED_ENGAGE := "NEED_ENGAGE"
const NEED_RANGE := "NEED_RANGE"
const NEED_LINE_OF_FIRE := "NEED_LINE_OF_FIRE"
const NEED_RELOAD := "NEED_RELOAD"
const NEED_UNJAM := "NEED_UNJAM"
const NEED_READY := "NEED_READY"
const NEED_POSITION := "NEED_POSITION"
const NEED_COVER := "NEED_COVER"
const NEED_BREAK_ENGAGEMENT := "NEED_BREAK_ENGAGEMENT"
const NEED_SHOVE_OPENING := "NEED_SHOVE_OPENING"
const NEED_RETREAT := "NEED_RETREAT"
const PATH_BLOCKED := "PATH_BLOCKED"
const SUBJECT_INVALID := "SUBJECT_INVALID"
const NO_LEGAL_ACTION := "NO_LEGAL_ACTION"

var problem_id: String = NO_LEGAL_ACTION
var motive: String = ""
var subject_type: String = ""
var subject_id: String = ""
var reason_tags: Array[String] = []
var feasible: bool = false
var terminal: bool = false


func to_dict() -> Dictionary:
	return {
		"problem_id": problem_id,
		"motive": motive,
		"subject_type": subject_type,
		"subject_id": subject_id,
		"reason_tags": reason_tags.duplicate(),
		"feasible": feasible,
		"terminal": terminal,
	}
