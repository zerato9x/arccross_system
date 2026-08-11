extends RefCounted
class_name CombatAttackResolver

## Action-family classification and weapon metadata. Exceptional attack
## algorithms remain selected by CombatActionDefinition.resolver_id.

const MELEE_ACTIONS := [
	"strike", "power_strike", "aimed_strike", "shove", "opportunity_strike"
]
const RANGED_ACTIONS := ["fire", "aimed_fire"]


func is_melee_action(action_id: String) -> bool:
	return action_id in MELEE_ACTIONS


func is_ranged_action(action_id: String) -> bool:
	return action_id in RANGED_ACTIONS


func maximum_range(
	action_id: String,
	definition: CombatActionDefinition,
	actor: HumanoidCore,
	board: CombatBoard
) -> int:
	if is_melee_action(action_id):
		return board.weapon_reach(actor)
	var weapon := actor.inventory.get_active_weapon(false) if actor != null and actor.inventory != null else null
	if weapon != null and weapon.maximum_range_cells > 0:
		return mini(definition.maximum_range_cells, weapon.maximum_range_cells)
	return definition.maximum_range_cells
