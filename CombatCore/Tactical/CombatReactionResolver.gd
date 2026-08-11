extends RefCounted
class_name CombatReactionResolver

## Reaction threat discovery is read-only. AP reservation and attack execution
## stay in CombatActionController/CombatResolutionEngine.

func steps_for_path(
	actor: HumanoidCore,
	indices: Array,
	board: CombatBoard
) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	if actor == null or board == null:
		return steps
	for offset in range(1, indices.size()):
		var from_index := int(indices[offset - 1])
		var to_index := int(indices[offset])
		var threat_ids: Array[String] = board.reaction_threats(actor, [from_index, to_index])
		if threat_ids.is_empty():
			continue
		steps.append({
			"step_index": offset - 1,
			"from": board.arena_state.coords_for(from_index),
			"to": board.arena_state.coords_for(to_index),
			"threat_ids": threat_ids.duplicate(),
		})
	return steps
