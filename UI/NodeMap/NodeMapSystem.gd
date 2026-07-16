extends CanvasLayer
class_name NodeMapSystem

## Fullscreen Node Map System window — independent of MacroHudShell.

signal closed
signal enter_node_requested(node_id: String)
signal advance_requested
signal inventory_requested
signal medical_requested

const LAYER_BELOW_EVENT := 30

var _snapshot: Dictionary = {}

@onready var _root: Control = %Root
@onready var _title_label: Label = %TitleLabel
@onready var _close_button: Button = %CloseButton
@onready var _graph_view: Control = %NodeMapGraphView
@onready var _inspector: PanelContainer = %NodeMapInspector
@onready var _player_panel: PanelContainer = %NodeMapPlayerPanel
@onready var _shell_panel: PanelContainer = %ShellPanel


func _ready() -> void:
	layer = LAYER_BELOW_EVENT
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	HUDAssetLibrary.apply_panel(_shell_panel, "anomaly")
	HUDAssetLibrary.apply_label(_title_label, "title")
	HUDAssetLibrary.apply_button(_close_button, "pass")
	_close_button.custom_minimum_size = HUDAssetLibrary.macro_button_minimum_size(96.0)
	_close_button.pressed.connect(close)
	_graph_view.connect("node_selected", _on_node_selected)
	_inspector.connect("enter_requested", func(node_id: String): enter_node_requested.emit(node_id))
	_inspector.connect("advance_requested", func(): advance_requested.emit())
	_player_panel.connect("inventory_requested", func(): inventory_requested.emit())
	_player_panel.connect("medical_requested", func(): medical_requested.emit())


func open(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	visible = true
	if _graph_view.has_method("prepare_open"):
		_graph_view.call("prepare_open")
	_apply_snapshot()
	_graph_view.grab_focus()


func refresh(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	if visible:
		_apply_snapshot()


func close(notify: bool = true) -> void:
	if not visible:
		return
	visible = false
	if notify:
		closed.emit()


func is_open() -> bool:
	return visible


func get_selected_node_id() -> String:
	return str(_graph_view.call("get_selected_id"))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_P:
			close()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			_try_enter_selected()
			get_viewport().set_input_as_handled()


func _apply_snapshot() -> void:
	_graph_view.call("apply_snapshot", _snapshot)
	_inspector.call("apply_snapshot", _snapshot)
	_player_panel.call("apply_snapshot", _snapshot)
	var selected: String = str(_graph_view.call("get_selected_id"))
	if not selected.is_empty():
		_inspector.call("select_node", selected)


func _on_node_selected(node_id: String) -> void:
	_inspector.call("select_node", node_id)


func _try_enter_selected() -> void:
	var node_id: String = str(_graph_view.call("get_selected_id"))
	if node_id.is_empty():
		return
	for entry in _snapshot.get("nodes", []):
		if entry is Dictionary and str(entry.get("id", "")) == node_id:
			if bool(entry.get("can_enter", false)):
				enter_node_requested.emit(node_id)
			return
