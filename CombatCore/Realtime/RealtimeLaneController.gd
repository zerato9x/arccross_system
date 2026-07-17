extends Node
class_name RealtimeLaneController

@export var lane_manager: CombatLaneManager

func commit_move(entity: HumanoidCore, from_lane: int, to_lane: int) -> bool:
	if lane_manager == null:
		return false
	return lane_manager.move_entity(entity, from_lane, to_lane)

func push(initiator: HumanoidCore, target: HumanoidCore, direction: int) -> int:
	if lane_manager == null or initiator == null or target == null:
		return -1
	var shared_lane := lane_manager._find_entity_lane(initiator)
	if shared_lane < 0 or lane_manager._find_entity_lane(target) != shared_lane:
		return -1
	var destination := shared_lane + direction
	if destination < 0 or destination >= lane_manager.lane_slots.size():
		return -1
	if not lane_manager._relocate_entity(target, shared_lane, destination, true):
		return -1
	lane_manager.lane_changed.emit()
	return destination

func follow(entity: HumanoidCore, destination: int) -> bool:
	if lane_manager == null or destination < 0:
		return false
	var from_lane := lane_manager._find_entity_lane(entity)
	if not lane_manager._relocate_entity(entity, from_lane, destination, true):
		return false
	lane_manager.lane_changed.emit()
	return true
