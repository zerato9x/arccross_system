extends RefCounted
class_name CombatInteractionState

## Presentation-only interaction state. Combat authority remains in CombatActionController.

enum Phase {
	IDLE = 0,
	ROUTE_PREVIEW = 1,
	CONTEXT_MENU = 2,
	ACTION_PREVIEW = 3,
	COMMUNICATION = 4,
	INVENTORY = 5,
	CONFIRMATION = 6,
	PRESENTING = 7,
	REACTION = 8,
	# Compatibility names retained for older presentation and smoke callers.
	NAVIGATION = IDLE,
	BUMP_MENU = CONTEXT_MENU,
	MOVE_PREVIEW = ROUTE_PREVIEW,
	TARGET_MENU = CONTEXT_MENU,
	AIMING = ACTION_PREVIEW,
	WEAPON_MENU = INVENTORY,
	SELF_MENU = CONTEXT_MENU,
	OBJECT_MENU = CONTEXT_MENU,
	SELECTED = IDLE,
	ACTION_MENU = CONTEXT_MENU,
	TARGETING = ACTION_PREVIEW,
	STAGED_PREVIEW = ACTION_PREVIEW,
	LOCAL_CONFIRMATION = CONFIRMATION,
}

var phase: Phase = Phase.IDLE
var controlled_actor_id: String = ""
var selected_kind: String = ""
var selected_actor_id: String = ""
var selected_sector := Vector2i(-1, -1)
var selected_item_id: String = ""
var selected_wound_id: String = ""
var selected_body_region: int = -1
var selected_shove_direction: String = ""
var declared_neutral_attack_confirmation: bool = false
var previous_selection: Dictionary = {}
var staged_action_id: String = ""
var route_path: Array[Vector2i] = []
var projected_origin := Vector2i(-1, -1)
var bumped_actor_id := ""
var highlighted_action_index := 0
var current_quote: CombatActionQuote
var pending_request: CombatActionRequest


func select(kind: String, data: Dictionary) -> void:
	previous_selection = capture_selection()
	selected_kind = kind
	selected_actor_id = str(data.get("actor_id", ""))
	selected_sector = data.get("sector", Vector2i(-1, -1))
	selected_item_id = str(data.get("item_id", ""))
	selected_wound_id = str(data.get("wound_id", ""))
	selected_body_region = int(data.get("body_region", -1))
	selected_shove_direction = str(data.get("shove_direction", ""))
	declared_neutral_attack_confirmation = false
	staged_action_id = ""
	route_path.clear()
	projected_origin = selected_sector
	bumped_actor_id = ""
	highlighted_action_index = 0
	phase = Phase.NAVIGATION


func open_actions() -> void:
	phase = Phase.BUMP_MENU


func begin_targeting(action_id: String) -> void:
	staged_action_id = action_id
	phase = Phase.ACTION_PREVIEW


func stage(action_id: String, legal: bool) -> void:
	staged_action_id = action_id
	phase = Phase.CONFIRMATION if legal else Phase.ACTION_PREVIEW


func begin_presentation() -> void:
	phase = Phase.PRESENTING


func finish_presentation() -> void:
	staged_action_id = ""
	current_quote = null
	pending_request = null
	phase = Phase.NAVIGATION if not selected_kind.is_empty() else Phase.IDLE


func cancel_one_step() -> void:
	match phase:
		Phase.PRESENTING:
			return
		Phase.CONFIRMATION, Phase.ACTION_PREVIEW:
			staged_action_id = ""
			phase = Phase.BUMP_MENU
		Phase.BUMP_MENU:
			phase = Phase.ROUTE_PREVIEW if not route_path.is_empty() else Phase.NAVIGATION
		Phase.ROUTE_PREVIEW:
			route_path.clear()
			projected_origin = selected_sector
			phase = Phase.NAVIGATION
		Phase.NAVIGATION:
			clear()
		_:
			clear()


func clear() -> void:
	phase = Phase.IDLE
	selected_kind = ""
	selected_actor_id = ""
	selected_sector = Vector2i(-1, -1)
	selected_item_id = ""
	selected_wound_id = ""
	selected_body_region = -1
	selected_shove_direction = ""
	declared_neutral_attack_confirmation = false
	staged_action_id = ""
	route_path.clear()
	projected_origin = Vector2i(-1, -1)
	bumped_actor_id = ""
	highlighted_action_index = 0
	current_quote = null
	pending_request = null


func capture_selection() -> Dictionary:
	return {
		"kind": selected_kind,
		"actor_id": selected_actor_id,
		"sector": selected_sector,
		"item_id": selected_item_id,
		"wound_id": selected_wound_id,
		"body_region": selected_body_region,
		"shove_direction": selected_shove_direction,
		"declared_neutral_attack_confirmation": declared_neutral_attack_confirmation,
	}
