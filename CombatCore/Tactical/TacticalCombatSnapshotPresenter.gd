extends RefCounted
class_name TacticalCombatSnapshotPresenter

const _Arena := preload("res://CombatCore/Tactical/CombatArenaSnapshotPresenter.gd")
const _ActionMenu := preload(
	"res://CombatCore/Tactical/CombatActionMenuSnapshotPresenter.gd"
)
const _Targeting := preload(
	"res://CombatCore/Tactical/CombatTargetingSnapshotPresenter.gd"
)
const _Inventory := preload(
	"res://CombatCore/Tactical/CombatInventorySnapshotPresenter.gd"
)
const _Feedback := preload(
	"res://CombatCore/Tactical/CombatFeedbackSnapshotPresenter.gd"
)
const _TurnStatus := preload(
	"res://CombatCore/Tactical/CombatTurnStatusSnapshotPresenter.gd"
)

var arena := _Arena.new()
var action_menu := _ActionMenu.new()
var targeting := _Targeting.new()
var inventory := _Inventory.new()
var feedback := _Feedback.new()
var turn_status := _TurnStatus.new()


func compose(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	result["presentation"] = {
		"arena": arena.build(snapshot),
		"action_menu": action_menu.build(snapshot),
		"targeting": targeting.build(snapshot),
		"inventory": inventory.build(snapshot),
		"feedback": feedback.build(snapshot),
		"turn_status": turn_status.build(snapshot),
	}
	return result
