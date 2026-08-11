extends RefCounted
class_name CornerPanelStateContract

## Neutral preview/expanded state shared by macro and combat presentations.
## Layout and input ownership stay in the consuming surface.

signal changed(panel_id: String, state: int)

enum State { PREVIEW, EXPANDED }

var panel_id: String = ""
var state: State = State.PREVIEW


func configure(id: String, initial_state: State = State.PREVIEW) -> void:
	panel_id = id
	state = initial_state


func set_expanded(expanded: bool) -> void:
	var next_state := State.EXPANDED if expanded else State.PREVIEW
	if state == next_state:
		return
	state = next_state
	changed.emit(panel_id, state)


func toggle() -> void:
	set_expanded(state != State.EXPANDED)


func is_expanded() -> bool:
	return state == State.EXPANDED
