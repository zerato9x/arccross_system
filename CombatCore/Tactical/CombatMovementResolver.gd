extends RefCounted
class_name CombatMovementResolver

## Movement math shared by quoting, composite actions, and AP settlement.

func is_movement_action(action_id: String) -> bool:
	return action_id == "move"


func requested_path(request: CombatActionRequest) -> Array[Vector2i]:
	return request.approach_path if not request.approach_path.is_empty() else request.path


func movement_step_base(actor: HumanoidCore, _board: CombatBoard) -> int:
	match actor.kinetic_tier:
		GameEnums.KineticTier.LABORED:
			return 3
		GameEnums.KineticTier.AGONIZING:
			return 4
	return 2


func quote_path_indices(
	action_quote: CombatActionQuote,
	board: CombatBoard
) -> Array:
	var indices: Array = []
	if action_quote == null or board == null:
		return indices
	for coords in action_quote.path:
		indices.append(board.arena_state.index_for(coords))
	return indices


func movement_cost_for_steps(
	action_quote: CombatActionQuote,
	completed_steps: int
) -> int:
	if action_quote == null or completed_steps <= 0:
		return 0
	var total := 0
	for index in range(mini(completed_steps, action_quote.movement_step_costs.size())):
		total += int(action_quote.movement_step_costs[index])
	return total
