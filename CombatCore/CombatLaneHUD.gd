extends Node2D
class_name CombatLaneHUD

const ACTION_BUTTON_SCENE := preload(
	"res://CombatCore/DuelUI/CombatActionButton.tscn"
)
const PORTRAIT_TOKEN_SCENE := preload("res://UI/Humanoid/HumanoidToken.tscn")
const ACTION_PANEL_SIZE := Vector2(204.0, 286.0)
const ACTION_BUTTON_SIZE := Vector2(176.0, 38.0)
const ACTION_BUTTON_GAP := Vector2(10.0, 8.0)
const ACTION_BUTTON_COLUMNS := 1
const COLOR_ACTION_PANEL := Color(0.07, 0.075, 0.06, 0.91)
const COLOR_ACTION_BORDER := Color(0.73, 0.62, 0.45, 0.88)
const COLOR_SHELL_PANEL := Color(0.04, 0.035, 0.025, 0.20)
const COLOR_SHELL_BORDER := Color(0.03, 0.025, 0.018, 0.72)
const COLOR_PORTRAIT_PLATE := Color(0.58, 0.18, 0.15, 0.72)
const COLOR_COMMAND_RAIL := Color(0.08, 0.055, 0.045, 0.36)
const BUTTON_MODE_ACTION := "action"
const BUTTON_MODE_PASS := "pass"
const BUTTON_MODE_REACTION := "reaction"
const CAMERA_PAN_SPEED := 760.0
const CAMERA_ZOOM_STEP := 0.12
const CAMERA_MIN_ZOOM := 0.65
const CAMERA_MAX_ZOOM := 2.15
const CAMERA_FOLLOW_SPEED := 8.0
const CAMERA_ZOOM_SPEED := 10.0

signal action_requested(action: int, target_limb: int, item_instance_id: String)
signal pass_requested
signal reaction_selected(reaction: int)

var _snapshot: Dictionary = {}
var _reaction_prompt: Dictionary = {}
var _feedback := ""
var _font: SystemFont
var _last_viewport_size := Vector2.ZERO
var _action_buttons: Array = []
var _camera_manual_offset := Vector2.ZERO
var _camera_zoom_bias := 0.0
var _camera_dragging := false
var _camera_initialized := false

# Presentation timing is intentionally independent of the HUD frame.  Keep
# combat events ordered so movement/impact animations finish before snapshots
# replace the actors underneath them.
var _presentation_queue: Array[Dictionary] = []
var _is_processing_queue: bool = false

var _round_label: Label
var _active_label: Label
var _player_label: Label
var _enemy_label: Label
var _player_portrait_token: HumanoidTokenView
var _enemy_portrait_token: HumanoidTokenView
var _player_top_rect := Rect2()
var _enemy_top_rect := Rect2()
var _player_bottom_rect := Rect2()
var _enemy_bottom_rect := Rect2()
var _player_portrait_rect := Rect2()
var _enemy_portrait_rect := Rect2()
var _player_command_rect := Rect2()
var _enemy_status_rect := Rect2()
var _enemy_status_bars: Array[Polygon2D] = []

@onready var _lane_view: CombatLaneView = %CombatLaneView
@onready var _combat_camera: Camera2D = %CombatCamera
@onready var _context_board: Node2D = %CombatContextBoard
@onready var _grid_hover_card: Node2D = %CombatGridHoverCard
@onready var _player_actor_hud: CombatActorFloatHUD = %PlayerActorHUD
@onready var _enemy_actor_hud: CombatActorFloatHUD = %EnemyActorHUD
@onready var _action_panel_box: Polygon2D = %ActionPanelBox
@onready var _action_panel_border: Line2D = %ActionPanelBorder
@onready var _action_title_label: Label = %ActionTitleLabel
@onready var _action_button_root: Node2D = %ActionButtons
@onready var _action_panel_frame: Sprite2D = %ActionPanelFrame
@onready var _feedback_label: Label = %FeedbackLabel
@onready var _legacy_readouts: Node = %LegacyReadouts
@onready var _duel_layout_shell: Node2D = %DuelLayoutShell
@onready var _player_top_panel_box: Polygon2D = %PlayerTopPanelBox
@onready var _player_top_panel_border: Line2D = %PlayerTopPanelBorder
@onready var _enemy_top_panel_box: Polygon2D = %EnemyTopPanelBox
@onready var _enemy_top_panel_border: Line2D = %EnemyTopPanelBorder
@onready var _player_bottom_panel_box: Polygon2D = %PlayerBottomPanelBox
@onready var _player_bottom_panel_border: Line2D = %PlayerBottomPanelBorder
@onready var _enemy_bottom_panel_box: Polygon2D = %EnemyBottomPanelBox
@onready var _enemy_bottom_panel_border: Line2D = %EnemyBottomPanelBorder
@onready var _player_portrait_plate: Polygon2D = %PlayerPortraitPlate
@onready var _player_portrait_border: Line2D = %PlayerPortraitBorder
@onready var _enemy_portrait_plate: Polygon2D = %EnemyPortraitPlate
@onready var _enemy_portrait_border: Line2D = %EnemyPortraitBorder
@onready var _player_command_rail: Node2D = %PlayerCommandRail
@onready var _enemy_status_rail: Node2D = %EnemyStatusRail
@onready var _portrait_root: Node2D = %PortraitRoot

func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	_bind_legacy_labels()
	_setup_duel_layout_shell()
	_setup_portrait_tokens()
	_lane_view.slot_hovered.connect(_on_lane_slot_hovered)
	_lane_view.slot_unhovered.connect(_on_lane_slot_unhovered)
	_grid_hover_card.hide_card()
	_setup_action_panel()
	_combat_camera.enabled = true
	_combat_camera.make_current()
	_feedback_label.visible = false
	visible = false
	set_process(true)

func _process(delta: float) -> void:
	if not visible:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size != _last_viewport_size:
		_last_viewport_size = viewport_size
		_layout_for_viewport(viewport_size)
	_update_camera_input(delta)
	_update_camera(delta, viewport_size)
	if not _snapshot.is_empty():
		_sync_actor_huds(viewport_size)

func open_hud() -> void:
	visible = true
	_layout_for_viewport(get_viewport_rect().size)
	_update_camera(0.0, get_viewport_rect().size)

func close_hud() -> void:
	visible = false
	_presentation_queue.clear()
	_snapshot.clear()
	_reaction_prompt.clear()
	_feedback = ""
	_grid_hover_card.hide_card()
	_clear_action_buttons()
	_feedback_label.visible = false

func show_snapshot(snapshot: Dictionary) -> void:
	_presentation_queue.append({ "type": "snapshot", "data": snapshot.duplicate(true) })
	_try_process_queue()

func show_reaction(prompt: Dictionary) -> void:
	_presentation_queue.append({ "type": "reaction", "data": prompt.duplicate(true) })
	_try_process_queue()

func show_feedback(message: String) -> void:
	_presentation_queue.append({ "type": "feedback", "data": message })
	_try_process_queue()

func show_presentation_event(event: Dictionary) -> void:
	_presentation_queue.append({ "type": "presentation", "data": event.duplicate(true) })
	_try_process_queue()

func _try_process_queue() -> void:
	if _is_processing_queue or _presentation_queue.is_empty():
		return
	_is_processing_queue = true
	_process_queue()

func _process_queue() -> void:
	while not _presentation_queue.is_empty():
		var item: Dictionary = _presentation_queue.pop_front()
		match str(item.get("type", "")):
			"snapshot":
				_apply_snapshot(item.get("data", {}))
			"reaction":
				_apply_reaction(item.get("data", {}))
			"feedback":
				_apply_feedback(item.get("data", ""))
			"presentation":
				_apply_presentation_event(item.get("data", {}))
				await get_tree().create_timer(0.6).timeout
	_is_processing_queue = false

func _apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	if not _snapshot.get("reaction_pending", false):
		_reaction_prompt.clear()
	visible = true
	_render()

func _apply_reaction(prompt: Dictionary) -> void:
	_reaction_prompt = prompt
	_render_actions()
	_render_feedback()

func _apply_feedback(message: String) -> void:
	_feedback = message
	_render_feedback()

func _apply_presentation_event(event: Dictionary) -> void:
	if _lane_view:
		_lane_view.show_presentation_event(event)

func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func is_showing_melee_lock() -> bool:
	return _lane_view != null and _lane_view.is_showing_melee_lock()

func _layout_for_viewport(viewport_size: Vector2) -> void:
	_lane_view.layout_for_viewport(viewport_size)
	_layout_screen_hud(viewport_size)

func _layout_screen_hud(viewport_size: Vector2) -> void:
	var ui_scale := Vector2.ONE / _camera_zoom_value()
	_calculate_duel_layout(viewport_size)
	_layout_duel_shell(viewport_size, ui_scale)

	var center_gap := maxf(
		160.0,
		_enemy_top_rect.position.x - _player_top_rect.end.x
	)
	var context_scale := minf(1.0, (center_gap - 24.0) / 430.0)
	var context_position := Vector2(
		viewport_size.x * 0.5 - 215.0 * context_scale,
		24.0
	)
	_context_board.global_position = _screen_to_world(
		context_position,
		viewport_size
	)
	_context_board.scale = ui_scale * context_scale
	var action_panel_screen_position := _player_command_rect.position
	var action_panel_size := _player_command_rect.size
	_set_box(_action_panel_box, action_panel_size)
	_set_outline(_action_panel_border, action_panel_size)
	_action_panel_box.global_position = _screen_to_world(
		action_panel_screen_position,
		viewport_size
	)
	_action_panel_border.global_position = _action_panel_box.global_position
	_action_panel_frame.global_position = _action_panel_box.global_position
	_action_title_label.global_position = _screen_to_world(
		action_panel_screen_position + Vector2(14.0, 10.0),
		viewport_size
	)
	_action_button_root.global_position = _screen_to_world(
		action_panel_screen_position + Vector2(14.0, 42.0),
		viewport_size
	)
	_action_panel_box.scale = ui_scale
	_action_panel_border.scale = ui_scale
	_action_panel_frame.scale = Vector2(
		action_panel_size.x / 64.0,
		action_panel_size.y / 64.0
	) * ui_scale
	_action_title_label.scale = ui_scale
	_action_button_root.scale = ui_scale
	_feedback_label.global_position = _screen_to_world(
		_enemy_status_rect.position + Vector2(0.0, _enemy_status_rect.size.y + 8.0),
		viewport_size
	)
	_feedback_label.scale = ui_scale
	_sync_duel_portraits(viewport_size)

func _calculate_duel_layout(viewport_size: Vector2) -> void:
	var margin := maxf(18.0, viewport_size.x * 0.014)
	var grid_center_y := viewport_size.y * 0.49
	var grid_height := clampf(viewport_size.y * 0.13, 82.0, 116.0)
	var grid_top := grid_center_y - grid_height * 0.5
	var grid_bottom := grid_center_y + grid_height * 0.5
	var side_width := minf(660.0, viewport_size.x * 0.335)
	var top_height := maxf(160.0, grid_top - margin * 2.0)
	var bottom_y := grid_bottom + margin
	var bottom_height := maxf(180.0, viewport_size.y - bottom_y - margin)

	_player_top_rect = Rect2(Vector2(margin, margin), Vector2(side_width, top_height))
	_enemy_top_rect = Rect2(
		Vector2(viewport_size.x - margin - side_width, margin),
		Vector2(side_width, top_height)
	)
	_player_bottom_rect = Rect2(
		Vector2(margin, bottom_y),
		Vector2(side_width, bottom_height)
	)
	_enemy_bottom_rect = Rect2(
		Vector2(viewport_size.x - margin - side_width, bottom_y),
		Vector2(side_width, bottom_height)
	)

	var portrait_size := Vector2(
		minf(250.0, side_width * 0.37),
		maxf(150.0, bottom_height - 30.0)
	)
	_player_portrait_rect = Rect2(
		Vector2(
			_player_bottom_rect.position.x + side_width * 0.52,
			_player_bottom_rect.position.y + 15.0
		),
		portrait_size
	)
	_enemy_portrait_rect = Rect2(
		Vector2(
			_enemy_bottom_rect.position.x + side_width * 0.52,
			_enemy_bottom_rect.position.y + 15.0
		),
		portrait_size
	)
	_player_command_rect = Rect2(
		Vector2(
			_player_bottom_rect.position.x + maxf(42.0, side_width * 0.16),
			_player_bottom_rect.position.y + 24.0
		),
		Vector2(ACTION_PANEL_SIZE.x, minf(ACTION_PANEL_SIZE.y, bottom_height - 48.0))
	)
	_enemy_status_rect = Rect2(
		Vector2(
			_enemy_bottom_rect.position.x + maxf(42.0, side_width * 0.16),
			_enemy_bottom_rect.position.y + 42.0
		),
		Vector2(176.0, minf(286.0, bottom_height - 72.0))
	)

func _layout_duel_shell(viewport_size: Vector2, ui_scale: Vector2) -> void:
	_duel_layout_shell.visible = not _snapshot.is_empty()
	if not _duel_layout_shell.visible:
		return
	_place_panel(_player_top_panel_box, _player_top_panel_border, _player_top_rect, viewport_size, ui_scale)
	_place_panel(_enemy_top_panel_box, _enemy_top_panel_border, _enemy_top_rect, viewport_size, ui_scale)
	_place_panel(_player_bottom_panel_box, _player_bottom_panel_border, _player_bottom_rect, viewport_size, ui_scale)
	_place_panel(_enemy_bottom_panel_box, _enemy_bottom_panel_border, _enemy_bottom_rect, viewport_size, ui_scale)
	_place_panel(_player_portrait_plate, _player_portrait_border, _player_portrait_rect, viewport_size, ui_scale)
	_place_panel(_enemy_portrait_plate, _enemy_portrait_border, _enemy_portrait_rect, viewport_size, ui_scale)
	_layout_enemy_status_bars(viewport_size, ui_scale)

func _place_panel(
	box: Polygon2D,
	border: Line2D,
	rect: Rect2,
	viewport_size: Vector2,
	ui_scale: Vector2
) -> void:
	_set_box(box, rect.size)
	_set_outline(border, rect.size)
	box.global_position = _screen_to_world(rect.position, viewport_size)
	border.global_position = box.global_position
	box.scale = ui_scale
	border.scale = ui_scale

func _layout_enemy_status_bars(viewport_size: Vector2, ui_scale: Vector2) -> void:
	_enemy_status_rail.global_position = _screen_to_world(
		_enemy_status_rect.position,
		viewport_size
	)
	_enemy_status_rail.scale = ui_scale
	var bar_height := 36.0
	var gap := 11.0
	for index in range(_enemy_status_bars.size()):
		var bar := _enemy_status_bars[index]
		_set_box(bar, Vector2(_enemy_status_rect.size.x, bar_height))
		bar.position = Vector2(0.0, float(index) * (bar_height + gap))

func _render() -> void:
	_render_legacy_readouts()
	if _snapshot.is_empty():
		_lane_view.show_snapshot({})
		_context_board.visible = false
		_player_actor_hud.visible = false
		_enemy_actor_hud.visible = false
		_duel_layout_shell.visible = false
		_sync_duel_portraits(get_viewport_rect().size)
		_grid_hover_card.hide_card()
		_render_actions()
		_render_feedback()
		return
	_lane_view.show_snapshot(_snapshot)
	_context_board.show_snapshot(_snapshot)
	_sync_actor_huds(get_viewport_rect().size)
	_render_actions()
	_render_feedback()

func _setup_action_panel() -> void:
	_set_box(_action_panel_box, ACTION_PANEL_SIZE)
	_action_panel_box.color = Color(COLOR_ACTION_PANEL, 0.96)
	_set_outline(_action_panel_border, ACTION_PANEL_SIZE)
	_action_panel_border.default_color = COLOR_ACTION_BORDER
	_action_panel_border.width = 1.0
	HUDAssetLibrary.texture_panel_sprite(
		_action_panel_frame,
		"neutral",
		ACTION_PANEL_SIZE
	)
	_action_title_label.text = "ACTIONS"

func _setup_duel_layout_shell() -> void:
	for polygon in [
		_player_top_panel_box,
		_enemy_top_panel_box,
		_player_bottom_panel_box,
		_enemy_bottom_panel_box,
	]:
		polygon.color = COLOR_SHELL_PANEL
	for line in [
		_player_top_panel_border,
		_enemy_top_panel_border,
		_player_bottom_panel_border,
		_enemy_bottom_panel_border,
	]:
		line.default_color = COLOR_SHELL_BORDER
		line.width = 2.0
	for plate in [_player_portrait_plate, _enemy_portrait_plate]:
		plate.color = COLOR_PORTRAIT_PLATE
	for border in [_player_portrait_border, _enemy_portrait_border]:
		border.default_color = Color(COLOR_ACTION_BORDER, 0.72)
		border.width = 1.25
	_build_enemy_status_bars()

func _setup_portrait_tokens() -> void:
	_player_portrait_token = PORTRAIT_TOKEN_SCENE.instantiate()
	_player_portrait_token.name = "PlayerPortraitToken"
	_portrait_root.add_child(_player_portrait_token)
	_player_portrait_token.visible = false

	_enemy_portrait_token = PORTRAIT_TOKEN_SCENE.instantiate()
	_enemy_portrait_token.name = "EnemyPortraitToken"
	_portrait_root.add_child(_enemy_portrait_token)
	_enemy_portrait_token.visible = false

func _build_enemy_status_bars() -> void:
	for child in _enemy_status_rail.get_children():
		child.queue_free()
	_enemy_status_bars.clear()
	for index in range(5):
		var bar := Polygon2D.new()
		bar.name = "EnemyStatusBar_%02d" % index
		bar.color = Color(0.48, 0.14, 0.13, 0.78)
		bar.z_index = 1
		_enemy_status_rail.add_child(bar)
		_enemy_status_bars.append(bar)

func _render_actions() -> void:
	_clear_action_buttons()
	var has_snapshot := not _snapshot.is_empty()
	_action_panel_box.visible = has_snapshot
	_action_panel_border.visible = has_snapshot
	_action_panel_frame.visible = false
	_action_title_label.visible = has_snapshot
	_action_button_root.visible = has_snapshot
	if not has_snapshot:
		return

	if not _reaction_prompt.is_empty():
		_action_title_label.text = "REACTION"
		_render_reaction_buttons()
		return
	if not _snapshot.get("is_player_turn", false):
		_action_title_label.text = "ENEMY TURN"
		return
	if _snapshot.get("busy", false):
		_action_title_label.text = "RESOLVING"
		return

	_action_title_label.text = "ACTIONS"
	var actions: Array = _snapshot.get("actions", [])
	for index in range(actions.size()):
		var descriptor: Dictionary = actions[index]
		_add_action_button(descriptor, index)
	if _snapshot.get("can_pass", false):
		_add_pass_button(actions.size())

func _render_reaction_buttons() -> void:
	var reactions: Array = _reaction_prompt.get("reactions", [])
	for index in range(reactions.size()):
		var descriptor: Dictionary = reactions[index]
		_add_reaction_button(descriptor, index)
	_add_decline_button(reactions.size())

func _add_action_button(descriptor: Dictionary, index: int) -> void:
	var payload := {
		"mode": BUTTON_MODE_ACTION,
		"descriptor": descriptor.duplicate(true),
		"target_limbs": descriptor.get("target_limbs", []).duplicate(),
	}
	var text := "[%d] %s  AP %02d" % [
		index + 1,
		str(descriptor.get("label", "ACTION")),
		int(descriptor.get("cost", 0)),
	]
	_add_button(payload, text, index)

func _add_pass_button(index: int) -> void:
	var payload := {"mode": BUTTON_MODE_PASS}
	_add_button(payload, "[0] PASS / RESERVE", index)

func _add_reaction_button(descriptor: Dictionary, index: int) -> void:
	var payload := {
		"mode": BUTTON_MODE_REACTION,
		"reaction": int(descriptor.get("action", -1)),
	}
	var text := "[%d] %s  AP %02d" % [
		index + 1,
		str(descriptor.get("label", "REACT")),
		int(descriptor.get("cost", 0)),
	]
	_add_button(payload, text, index)

func _add_decline_button(index: int) -> void:
	var payload := {
		"mode": BUTTON_MODE_REACTION,
		"reaction": -1,
	}
	_add_button(payload, "[0] DECLINE", index)

func _add_button(payload: Dictionary, text: String, index: int) -> void:
	var button := ACTION_BUTTON_SCENE.instantiate()
	button.name = "ActionButton_%02d" % index
	button.set_button_size(ACTION_BUTTON_SIZE)
	button.configure(payload, text)
	button.pressed.connect(_on_action_button_pressed)
	button.target_limb_focused.connect(_on_target_limb_focused)
	button.target_limb_unfocused.connect(_on_target_limb_unfocused)
	var column := index % ACTION_BUTTON_COLUMNS
	var row := index / ACTION_BUTTON_COLUMNS
	button.position = Vector2(
		float(column) * (ACTION_BUTTON_SIZE.x + ACTION_BUTTON_GAP.x),
		float(row) * (ACTION_BUTTON_SIZE.y + ACTION_BUTTON_GAP.y)
	)
	_action_button_root.add_child(button)
	_action_buttons.append(button)

func _clear_action_buttons() -> void:
	for button in _action_buttons:
		if is_instance_valid(button):
			button.queue_free()
	_action_buttons.clear()
	_on_target_limb_unfocused()

func _on_target_limb_focused(limb: int) -> void:
	if _enemy_actor_hud == null:
		return
	_enemy_actor_hud.set_targeted_limb(limb)

func _on_target_limb_unfocused() -> void:
	if _enemy_actor_hud == null:
		return
	_enemy_actor_hud.clear_targeted_limb()

func _on_action_button_pressed(payload: Dictionary) -> void:
	match str(payload.get("mode", "")):
		BUTTON_MODE_ACTION:
			var descriptor: Dictionary = payload.get("descriptor", {})
			action_requested.emit(
				int(descriptor.get("action", -1)),
				int(payload.get(
					"target_limb",
					GameEnums.LimbRegion.UPPER_TORSO
				)),
				str(descriptor.get("item_instance_id", ""))
			)
		BUTTON_MODE_PASS:
			pass_requested.emit()
		BUTTON_MODE_REACTION:
			reaction_selected.emit(int(payload.get("reaction", -1)))

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_HOME or event.keycode == KEY_F:
		_reset_camera()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_EQUAL or event.keycode == KEY_PLUS:
		_adjust_camera_zoom(CAMERA_ZOOM_STEP)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_MINUS:
		_adjust_camera_zoom(-CAMERA_ZOOM_STEP)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_0:
		for button in _action_buttons:
			var payload: Dictionary = button.get_payload()
			var mode := str(payload.get("mode", ""))
			if (
				mode == BUTTON_MODE_PASS
				or (
					mode == BUTTON_MODE_REACTION
					and int(payload.get("reaction", 0)) == -1
				)
			):
				button.activate()
				get_viewport().set_input_as_handled()
				return
	if event.keycode < KEY_1 or event.keycode > KEY_9:
		return
	var index := int(event.keycode - KEY_1)
	if index >= 0 and index < _action_buttons.size():
		_action_buttons[index].activate()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_camera_dragging = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_camera_zoom(CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_camera_zoom(-CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _camera_dragging:
		_camera_manual_offset -= event.relative / _camera_zoom_value()
		get_viewport().set_input_as_handled()

func _update_camera_input(delta: float) -> void:
	var axis := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		axis.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		axis.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		axis.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		axis.y += 1.0
	if axis.length_squared() <= 0.0:
		return
	_camera_manual_offset += (
		axis.normalized()
		* CAMERA_PAN_SPEED
		* delta
		/ _camera_zoom_value()
	)

func _update_camera(delta: float, viewport_size: Vector2) -> void:
	if _combat_camera == null or _lane_view == null:
		return
	var target_zoom := clampf(
		_lane_view.get_focus_zoom() + _camera_zoom_bias,
		CAMERA_MIN_ZOOM,
		CAMERA_MAX_ZOOM
	)
	var target_position := (
		_lane_view.get_combat_focus_global()
		+ _camera_manual_offset
	)
	if not _camera_initialized or delta <= 0.0:
		_combat_camera.global_position = target_position
		_combat_camera.zoom = Vector2.ONE * target_zoom
		_camera_initialized = true
	else:
		var follow_t := clampf(delta * CAMERA_FOLLOW_SPEED, 0.0, 1.0)
		var zoom_t := clampf(delta * CAMERA_ZOOM_SPEED, 0.0, 1.0)
		_combat_camera.global_position = _combat_camera.global_position.lerp(
			target_position,
			follow_t
		)
		_combat_camera.zoom = _combat_camera.zoom.lerp(
			Vector2.ONE * target_zoom,
			zoom_t
		)
	_layout_screen_hud(viewport_size)

func _reset_camera() -> void:
	_camera_manual_offset = Vector2.ZERO
	_camera_zoom_bias = 0.0
	_update_camera(0.0, get_viewport_rect().size)

func _adjust_camera_zoom(delta: float) -> void:
	var auto_zoom := _lane_view.get_focus_zoom() if _lane_view else 1.0
	_camera_zoom_bias = clampf(
		_camera_zoom_bias + delta,
		CAMERA_MIN_ZOOM - auto_zoom,
		CAMERA_MAX_ZOOM - auto_zoom
	)
	_update_camera(0.0, get_viewport_rect().size)

func _screen_to_world(screen_position: Vector2, viewport_size: Vector2) -> Vector2:
	if _combat_camera == null:
		return screen_position
	return (
		_combat_camera.global_position
		+ (screen_position - viewport_size * 0.5) / _camera_zoom_value()
	)

func _camera_zoom_value() -> float:
	if _combat_camera == null:
		return 1.0
	return maxf(0.01, _combat_camera.zoom.x)

func _sync_actor_huds(viewport_size: Vector2) -> void:
	if _snapshot.is_empty():
		return
	var ui_scale := 1.0 / _camera_zoom_value()
	var actor_panel_scale := ui_scale * 1.45
	var player_hud_position := _screen_to_world(
		_player_top_rect.position + Vector2(36.0, 32.0),
		viewport_size
	)
	var enemy_hud_position := _screen_to_world(
		_enemy_top_rect.position + Vector2(36.0, 32.0),
		viewport_size
	)
	_player_actor_hud.set_fixed_actor(
		_snapshot.get("player", {}),
		"player",
		player_hud_position,
		actor_panel_scale
	)
	_enemy_actor_hud.set_fixed_actor(
		_snapshot.get("enemy", {}),
		"enemy",
		enemy_hud_position,
		actor_panel_scale
	)
	_sync_duel_portraits(viewport_size)

func _sync_duel_portraits(viewport_size: Vector2) -> void:
	if _snapshot.is_empty() or _player_portrait_token == null:
		if _player_portrait_token:
			_player_portrait_token.visible = false
		if _enemy_portrait_token:
			_enemy_portrait_token.visible = false
		return
	var ui_scale := Vector2.ONE / _camera_zoom_value()
	_sync_portrait_token(
		_player_portrait_token,
		_snapshot.get("player", {}),
		_player_portrait_rect,
		true,
		viewport_size,
		ui_scale
	)
	_sync_portrait_token(
		_enemy_portrait_token,
		_snapshot.get("enemy", {}),
		_enemy_portrait_rect,
		false,
		viewport_size,
		ui_scale
	)

func _sync_portrait_token(
	token: HumanoidTokenView,
	data: Dictionary,
	rect: Rect2,
	is_player: bool,
	viewport_size: Vector2,
	ui_scale: Vector2
) -> void:
	if token == null:
		return
	token.visible = not data.is_empty()
	if not token.visible:
		return
	token.set_appearance(data.get(
		"appearance",
		HumanoidVisualCatalog.appearance_from_slot_item_ids({})
	))
	token.set_direction_row(
		HumanoidVisualCatalog.DIRECTION_RIGHT
		if is_player
		else HumanoidVisualCatalog.DIRECTION_LEFT
	)
	if not token.is_playing_one_shot():
		token.play_animation("Idle2", false)
	var display_scale := clampf(rect.size.y / 78.0, 2.2, 7.0)
	token.set_display_scale(display_scale)
	token.scale = ui_scale
	token.global_position = _screen_to_world(
		rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.68),
		viewport_size
	)

func _on_lane_slot_hovered(
	slot_data: Dictionary,
	global_position: Vector2
) -> void:
	if _snapshot.is_empty():
		return
	_grid_hover_card.show_slot(
		slot_data,
		_snapshot.get("actions", []),
		_snapshot,
		global_position,
		get_viewport_rect().size
	)

func _on_lane_slot_unhovered() -> void:
	_grid_hover_card.hide_card()

func _render_feedback() -> void:
	var rows := PackedStringArray()
	if not _feedback.is_empty():
		rows.append(_feedback)
	if not _reaction_prompt.is_empty():
		rows.append("REACTION // %s" % _reaction_prompt.get("trigger", "ATTACK"))
		for descriptor in _reaction_prompt.get("reactions", []):
			rows.append("- %s AP %02d" % [
				descriptor.get("label", "REACT"),
				int(descriptor.get("cost", 0)),
			])
	if rows.is_empty():
		_feedback_label.visible = false
		return
	_feedback_label.visible = true
	_feedback_label.text = "\n".join(rows)

func _bind_legacy_labels() -> void:
	_round_label = _legacy_readouts.get_node("RoundLabel") as Label
	_active_label = _legacy_readouts.get_node("ActiveLabel") as Label
	_player_label = _legacy_readouts.get_node("PlayerLabel") as Label
	_enemy_label = _legacy_readouts.get_node("EnemyLabel") as Label
	for label in [_round_label, _active_label, _player_label, _enemy_label]:
		label.visible = false
		label.add_theme_font_override("font", _font)
		label.add_theme_font_size_override("font_size", 12)

func _render_legacy_readouts() -> void:
	if _snapshot.is_empty():
		_round_label.text = "ROUND --"
		_active_label.text = "AWAITING COMBAT"
		_player_label.text = "PLAYER // NO SIGNAL"
		_enemy_label.text = "ENEMY // NO SIGNAL"
		return
	_round_label.text = "ROUND %02d" % int(_snapshot.get("round", 0))
	_active_label.text = "ACTIVE %s // AP %02d" % [
		str(_snapshot.get("active_name", "UNKNOWN")).to_upper(),
		int(_snapshot.get("ap", 0)),
	]
	_player_label.text = _combatant_text(_snapshot.get("player", {}), "PLAYER")
	_enemy_label.text = _combatant_text(_snapshot.get("enemy", {}), "ENEMY")

func _combatant_text(data: Dictionary, heading: String) -> String:
	var active_marker := " [ACTIVE]" if data.get("is_active", false) else ""
	var escape_marker := " [ESCAPING]" if data.get("is_escaping", false) else ""
	var guard_marker := " [GUARDED]" if data.get("stance_recovery_guard", false) else ""
	return (
		"%s%s // SLOT %02d\n"
		+ "%s\n"
		+ "BLOOD %04.1f  STANCE %02d %s%s  MORALE %04.1f\n"
		+ "AP-R %02d  KINETIC %s  WEAPON %s%s%s\n"
		+ "%s"
	) % [
		heading,
		active_marker,
		int(data.get("lane", -1)),
		str(data.get("archetype", data.get("name", "UNKNOWN"))).to_upper(),
		float(data.get("blood", 0.0)),
		int(data.get("stance", 0)),
		str(data.get("stance_state", "UNKNOWN")),
		guard_marker,
		float(data.get("morale", 0.0)),
		int(data.get("reserved_ap", 0)),
		str(data.get("kinetic_tier", "UNKNOWN")),
		str(data.get("weapon", "UNARMED")).to_upper(),
		str(data.get("weapon_detail", "")),
		escape_marker,
		_limb_text(data.get("limbs", [])),
	]

func _limb_text(limbs: Array) -> String:
	if limbs.size() < 7:
		return "LIMBS // NO SIGNAL"
	return "\n".join([
		"CORE " + _format_limb(limbs[0]) + " " + _format_limb(limbs[1]) + " " + _format_limb(limbs[2]),
		"ARMS " + _format_limb(limbs[3]) + " " + _format_limb(limbs[4]),
		"LEGS " + _format_limb(limbs[5]) + " " + _format_limb(limbs[6]),
	])

func _format_limb(limb: Dictionary) -> String:
	var trauma_marker := "!" if limb.get("trauma", "NONE") != "NONE" else ""
	return "%s%s %s/%s" % [
		limb.get("code", "??"),
		trauma_marker,
		_compact_number(float(limb.get("current", 0.0))),
		_compact_number(float(limb.get("maximum", 0.0))),
	]

func _compact_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value

func _set_box(polygon: Polygon2D, box_size: Vector2) -> void:
	polygon.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(box_size.x, 0.0),
		box_size,
		Vector2(0.0, box_size.y),
	])

func _set_outline(line: Line2D, box_size: Vector2) -> void:
	line.points = PackedVector2Array([
		Vector2.ZERO,
		Vector2(box_size.x, 0.0),
		box_size,
		Vector2(0.0, box_size.y),
		Vector2.ZERO,
	])
