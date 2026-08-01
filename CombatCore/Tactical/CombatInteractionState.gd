extends RefCounted
class_name CombatInteractionState

## Presentation-only interaction state. Combat authority remains in CombatActionController.

enum Phase {
	IDLE,
	SELECTED,
	ACTION_MENU,
	TARGETING,
	STAGED_PREVIEW,
	LOCAL_CONFIRMATION,
	PRESENTING,
}

var phase: Phase = Phase.IDLE
var selected_kind: String = ""
var selected_actor_id: String = ""
var selected_sector := Vector2i(-1, -1)
var selected_item_id: String = ""
var selected_wound_id: String = ""
var selected_body_region: int = -1
var previous_selection: Dictionary = {}
var staged_action_id: String = ""


func select(kind: String, data: Dictionary) -> void:
	previous_selection = capture_selection()
	selected_kind = kind
	selected_actor_id = str(data.get("actor_id", ""))
	selected_sector = data.get("sector", Vector2i(-1, -1))
	selected_item_id = str(data.get("item_id", ""))
	selected_wound_id = str(data.get("wound_id", ""))
	selected_body_region = int(data.get("body_region", -1))
	staged_action_id = ""
	phase = Phase.SELECTED


func open_actions() -> void:
	phase = Phase.ACTION_MENU


func begin_targeting(action_id: String) -> void:
	staged_action_id = action_id
	phase = Phase.TARGETING


func stage(action_id: String, legal: bool) -> void:
	staged_action_id = action_id
	phase = Phase.LOCAL_CONFIRMATION if legal else Phase.STAGED_PREVIEW


func begin_presentation() -> void:
	phase = Phase.PRESENTING


func finish_presentation() -> void:
	staged_action_id = ""
	phase = Phase.SELECTED if not selected_kind.is_empty() else Phase.IDLE


func cancel_one_step() -> void:
	match phase:
		Phase.PRESENTING:
			return
		Phase.LOCAL_CONFIRMATION, Phase.STAGED_PREVIEW, Phase.TARGETING:
			staged_action_id = ""
			phase = Phase.ACTION_MENU
		Phase.ACTION_MENU:
			phase = Phase.SELECTED
		Phase.SELECTED:
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
	staged_action_id = ""


func capture_selection() -> Dictionary:
	return {
		"kind": selected_kind,
		"actor_id": selected_actor_id,
		"sector": selected_sector,
		"item_id": selected_item_id,
		"wound_id": selected_wound_id,
		"body_region": selected_body_region,
	}
