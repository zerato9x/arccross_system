extends Resource
class_name CombatActionDefinition

const AP_QUICK := "quick"
const AP_MINOR := "minor"
const AP_MAJOR := "major"
const AP_HEAVY := "heavy"
const AP_COMMITTED := "committed"
const AP_FREE := "free"

const TARGET_SELF := "self"
const TARGET_ACTOR := "actor"
const TARGET_SECTOR := "sector"
const TARGET_PATH := "path"
const TARGET_OBJECT := "object"
const TARGET_ITEM := "item"
const TARGET_WOUND := "wound"

@export var action_id: String = ""
@export var label: String = ""
@export_multiline var description: String = ""
@export_enum("move", "attack", "aim", "guard", "maneuver", "item", "interact", "end_turn", "reaction") var menu_family: String = "interact"
@export var menu_priority: int = 0
@export var icon_id: String = ""
@export_enum("always", "target_context", "when_relevant", "reaction_only") var context_visibility: String = "when_relevant"
@export var requires_confirmation: bool = true
@export var automatic_reaction: bool = false
@export_enum("quick", "minor", "major", "heavy", "committed", "free") var ap_category: String = AP_MINOR
@export_enum("none", "path", "path_plus_action") var movement_cost_policy: String = "none"
@export_enum("self", "actor", "sector", "path", "object", "item", "wound") var target_mode: String = TARGET_SELF
@export var minimum_range_cells: int = 0
@export var maximum_range_cells: int = 0
@export var reach_cells: int = 0
@export var requires_line_of_sight: bool = false
@export var required_postures: Array[String] = []
@export var required_limb_tags: Array[String] = []
@export var required_equipment_tags: Array[String] = []
@export var required_control_state: String = ""
@export var resolver_id: String = ""
@export var reaction_tags: Array[String] = []
@export var ai_tags: Array[String] = []
@export var presentation_profile: CombatPresentationProfile
@export var targeting_profile: CombatTargetingProfile
@export var effect_profile: CombatActionEffectProfile


func base_ap_cost(kinetic_tier: int, remaining_ap: int) -> int:
	if ap_category == AP_FREE:
		return 0
	if ap_category == AP_COMMITTED:
		return maxi(0, remaining_ap)
	var costs := {
		AP_QUICK: [1, 2, 3],
		AP_MINOR: [2, 3, 4],
		AP_MAJOR: [3, 4, 6],
		AP_HEAVY: [4, 6, 12],
	}
	var tier := clampi(kinetic_tier, 0, 2)
	return int(costs.get(ap_category, [0, 0, 0])[tier])
