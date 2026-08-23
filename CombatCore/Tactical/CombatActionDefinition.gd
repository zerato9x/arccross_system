@tool
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

const CONTEXT_SELF := "self"
const CONTEXT_HOSTILE_ACTOR := "hostile_actor"
const CONTEXT_FRIENDLY_ACTOR := "friendly_actor"
const CONTEXT_NEUTRAL_ACTOR := "neutral_actor"
const CONTEXT_SECTOR := "sector"
const CONTEXT_ITEM := "item"
const CONTEXT_WOUND := "wound"
const CONTEXT_OBJECT := "object"
const CONTEXT_BODY := "body"

const WEAPON_FAMILY_NONE := "none"
const WEAPON_FAMILY_MELEE := "melee"
const WEAPON_FAMILY_RANGED := "ranged"

@export var action_id: String = ""
@export var label: String = ""
@export_multiline var description: String = ""
@export_enum("move", "attack", "maneuver", "item", "interact", "end_turn") var menu_family: String = "interact"
@export var menu_priority: int = 0
@export var icon_id: String = ""
@export_enum("always", "target_context", "when_relevant") var context_visibility: String = "when_relevant"
## UI metadata is authored with the action definition so the HUD can remain a
## passive renderer.  Compatibility actions may still resolve internally, but
## only core/maintenance/global entries are surfaced to players by default.
@export_enum("core", "rare", "maintenance", "global", "compatibility") var visibility_tier: String = "core"
@export var surface_id: String = "context"
@export var capability_applicability: Array[String] = []
@export var relevant_selection_contexts: Array[String] = []
@export var capability_requirements: Array[String] = []
@export var keep_temporary_denial_visible: bool = true
@export_multiline var player_consequence: String = ""
@export var requires_confirmation: bool = true
@export_enum("quick", "minor", "major", "heavy", "committed", "free") var ap_category: String = AP_MINOR
@export_enum("none", "path", "path_plus_action") var movement_cost_policy: String = "none"
@export_enum("self", "actor", "sector", "path", "object", "item", "wound") var target_mode: String = TARGET_SELF
@export var minimum_range_cells: int = 0
@export var maximum_range_cells: int = 0
## Some object actions are valid only while the actor occupies the target
## sector. This is distinct from a normal maximum range.
@export var requires_same_sector: bool = false
@export var reach_cells: int = 0
@export var requires_line_of_sight: bool = false
@export var required_limb_tags: Array[String] = []
@export var required_equipment_tags: Array[String] = []
@export var required_control_state: String = ""
@export var resolver_id: String = ""
## Typed classification shared by quote, forecast, controller, AI, and HUD.
## IDs select content; this field selects the reusable attack algorithm.
@export_enum("none", "melee", "ranged") var weapon_action_family: String = WEAPON_FAMILY_NONE
@export var ai_tags: Array[String] = []
## Planning semantics are authored with the action.  Uncertain outcomes end a
## projected plan instead of letting AI guess through a random resolution.
@export_enum("deterministic", "uncertain") var planning_outcome: String = "deterministic"
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


func presentation_ready() -> bool:
	return not description.strip_edges().is_empty() and presentation_profile != null and not inferred_selection_contexts().is_empty()


func is_weapon_action() -> bool:
	return weapon_action_family in [WEAPON_FAMILY_MELEE, WEAPON_FAMILY_RANGED]


func is_melee_weapon_action() -> bool:
	return weapon_action_family == WEAPON_FAMILY_MELEE


func is_ranged_weapon_action() -> bool:
	return weapon_action_family == WEAPON_FAMILY_RANGED


func inferred_selection_contexts() -> Array[String]:
	if not relevant_selection_contexts.is_empty():
		return relevant_selection_contexts
	match target_mode:
		TARGET_SELF:
			return [CONTEXT_SELF]
		TARGET_ACTOR:
			return [CONTEXT_HOSTILE_ACTOR]
		TARGET_PATH, TARGET_SECTOR:
			return [CONTEXT_SECTOR]
		TARGET_ITEM:
			return [CONTEXT_ITEM]
		TARGET_WOUND:
			return [CONTEXT_WOUND]
		TARGET_OBJECT:
			return [CONTEXT_OBJECT]
	return []
