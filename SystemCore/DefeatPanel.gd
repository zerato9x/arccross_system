extends CanvasLayer
class_name DefeatPanel

signal restart_requested
signal load_requested

var _overlay: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _body_label: Label
var _load_button: Button
var _restart_button: Button

func _ready() -> void:
	layer = 100
	_bind_authored_nodes()
	close_panel()

func open_panel(can_load: bool) -> void:
	_overlay.visible = true
	_load_button.disabled = not can_load

func close_panel() -> void:
	if _overlay:
		_overlay.visible = false

func is_open() -> bool:
	return _overlay != null and _overlay.visible

func _bind_authored_nodes() -> void:
	_overlay = get_node_or_null("Overlay") as ColorRect
	_panel = get_node_or_null("Overlay/Center/Panel") as PanelContainer
	_title_label = get_node_or_null(
		"Overlay/Center/Panel/Margin/Content/TitleLabel"
	) as Label
	_body_label = get_node_or_null(
		"Overlay/Center/Panel/Margin/Content/BodyLabel"
	) as Label
	_restart_button = get_node_or_null(
		"Overlay/Center/Panel/Margin/Content/BeginNewRunButton"
	) as Button
	_load_button = get_node_or_null(
		"Overlay/Center/Panel/Margin/Content/LoadSavedRunButton"
	) as Button

	if (
		_overlay == null
		or _panel == null
		or _restart_button == null
		or _load_button == null
	):
		push_error("DefeatPanel requires its authored Overlay button tree.")
		return

	HUDAssetLibrary.apply_panel(_panel, "critical")
	HUDAssetLibrary.apply_label(_title_label, "critical")
	HUDAssetLibrary.apply_label(_body_label, "body")
	HUDAssetLibrary.apply_button(_restart_button, "rest")
	HUDAssetLibrary.apply_button(_load_button, "load")

	if not _restart_button.pressed.is_connected(restart_requested.emit):
		_restart_button.pressed.connect(restart_requested.emit)
	if not _load_button.pressed.is_connected(load_requested.emit):
		_load_button.pressed.connect(load_requested.emit)
