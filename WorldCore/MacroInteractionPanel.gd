extends CanvasLayer
class_name MacroInteractionPanel

signal talk_action_submitted(action: GameEnums.TalkAction)
signal ambush_submitted(position: GameEnums.AmbushPosition)
signal interaction_closed

var _panel: PanelContainer
var _content: VBoxContainer
var _session: Dictionary = {}

func _ready() -> void:
	layer = 20
	_bind_authored_shell()
	_apply_hud_assets()
	close_panel(false)

func open_entity_collision(session: Dictionary) -> void:
	_session = session.duplicate(true)
	_panel.visible = true
	_clear_content()
	_add_title("ENTITY COLLISION")
	_add_body(
		"You collided with %s. Choose how the encounter begins."
		% _session.get("entity_name", "Unknown")
	)
	_add_button("TALK", _show_talk_options)
	_add_button("AMBUSH", _show_ambush_options)

func show_result(title: String, message: String) -> void:
	_panel.visible = true
	_clear_content()
	_add_title(title)
	_add_body(message)
	_add_button("CLOSE", close_panel)

func close_panel(notify: bool = true) -> void:
	if _panel:
		_panel.visible = false
	_session.clear()
	if notify:
		interaction_closed.emit()

func is_open() -> bool:
	return _panel != null and _panel.visible

func _bind_authored_shell() -> void:
	_panel = get_node_or_null("Panel") as PanelContainer
	_content = get_node_or_null("Panel/Margin/Content") as VBoxContainer
	if _panel == null or _content == null:
		push_error("MacroInteractionPanel requires authored Panel/Margin/Content nodes.")

func _apply_hud_assets() -> void:
	if _panel:
		HUDAssetLibrary.apply_panel(_panel, "warning")

func _show_talk_options() -> void:
	_clear_content()
	_add_title("TALK")
	_add_body(
		"THREAT pressures them to withdraw. ROB demands property. CEASEFIRE seeks a non-hostile settlement. Failure starts ordinary-position combat."
	)
	_add_button(
		"THREAT",
		func(): talk_action_submitted.emit(GameEnums.TalkAction.THREAT)
	)
	_add_button(
		"ROB",
		func(): talk_action_submitted.emit(GameEnums.TalkAction.ROB)
	)
	_add_button(
		"CEASEFIRE",
		func(): talk_action_submitted.emit(GameEnums.TalkAction.CEASEFIRE)
	)
	_add_button("BACK", open_entity_collision.bind(_session))

func _show_ambush_options() -> void:
	_clear_content()
	_add_title("AMBUSH")
	_add_body(
		"Choose the player's opening lane. As the colliding entity, the player acts first."
	)
	_add_button(
		"FAR APPROACH",
		func(): ambush_submitted.emit(GameEnums.AmbushPosition.FAR)
	)
	_add_button(
		"STANDARD APPROACH",
		func(): ambush_submitted.emit(GameEnums.AmbushPosition.STANDARD)
	)
	_add_button(
		"CLOSE APPROACH",
		func(): ambush_submitted.emit(GameEnums.AmbushPosition.CLOSE)
	)
	_add_button("BACK", open_entity_collision.bind(_session))

func _add_title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	HUDAssetLibrary.apply_label(title, "title")
	_content.add_child(title)

func _add_body(text: String) -> void:
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(body, "body")
	_content.add_child(body)

func _add_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	HUDAssetLibrary.apply_button(button, _icon_for_button(text))
	_content.add_child(button)
	return button

func _icon_for_button(text: String) -> String:
	var normalized := text.to_lower()
	if normalized.contains("talk") or normalized.contains("ceasefire"):
		return "talk"
	if normalized.contains("ambush"):
		return "warning"
	if normalized.contains("back") or normalized.contains("close"):
		return "pass"
	return ""

func _clear_content() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
