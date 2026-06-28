extends Node2D
class_name CombatLaneHUD

const ACTION_BUTTON_SCENE := preload(
	"res://CombatCore/DuelUI/CombatActionButton.tscn"
)
const GUN_ANIMATION_CATALOG := preload(
	"res://CombatCore/DuelUI/GunAnimationCatalog.gd"
)
const PAPERDOLL_SCENE := preload("res://UI/Inventory/PaperDollModel.tscn")
const ACTION_PANEL_SIZE := Vector2(760.0, 224.0)
const ACTION_BUTTON_SIZE := Vector2(174.0, 42.0)
const ACTION_BUTTON_GAP := Vector2(10.0, 8.0)
const ACTION_BUTTON_COLUMNS := 4
const GROUP_BUTTON_SIZE := Vector2(98.0, 30.0)
const WEAPON_CARD_SIZE := Vector2(232.0, 168.0)
const COMMAND_CONTEXT_SIZE := Vector2(360.0, 196.0)
const BODY_BAR_SIZE := Vector2(150.0, 10.0)
const BODY_BAR_GAP := 8.0
const BODY_LIMB_ORDER := ["HD", "UT", "LT", "LA", "RA", "LL", "RL"]
const COLOR_ACTION_PANEL := Color(0.07, 0.075, 0.06, 0.91)
const COLOR_ACTION_BORDER := Color(0.73, 0.62, 0.45, 0.88)
const COLOR_SHELL_PANEL := Color(0.04, 0.035, 0.025, 0.13)
const COLOR_SHELL_BORDER := Color(0.03, 0.025, 0.018, 0.58)
const COLOR_PORTRAIT_PLATE := Color(0.58, 0.18, 0.15, 0.72)
const COLOR_COMMAND_RAIL := Color(0.08, 0.055, 0.045, 0.36)
const COLOR_BODY_BAR_BACK := Color(0.08, 0.04, 0.035, 0.86)
const COLOR_BODY_BAR_HEALTH := Color(0.72, 0.18, 0.18, 0.92)
const COLOR_BODY_BAR_DAMAGED := Color(0.88, 0.46, 0.16, 0.94)
const COLOR_BODY_BAR_CRITICAL := Color(0.86, 0.08, 0.12, 0.98)
const ACTION_GROUP_FIREARM := "firearm"
const ACTION_GROUP_MOVEMENT := "movement"
const ACTION_GROUP_MELEE := "melee"
const ACTION_GROUP_FIELD := "field"
const ACTION_GROUP_ITEMS := "items"
const ACTION_GROUP_REACTION := "reaction"
const ACTION_GROUP_ORDER := [
	ACTION_GROUP_FIREARM,
	ACTION_GROUP_MOVEMENT,
	ACTION_GROUP_MELEE,
	ACTION_GROUP_FIELD,
	ACTION_GROUP_ITEMS,
]
const BUTTON_MODE_ACTION := "action"
const BUTTON_MODE_PASS := "pass"
const BUTTON_MODE_REACTION := "reaction"
const BUTTON_MODE_GROUP := "group"
const BUTTON_MODE_SUBMENU := "submenu"
const BUTTON_MODE_BACK := "back"
const MENU_AIM := "aim"
const MENU_PUSH := "push"
const CAMERA_PAN_SPEED := 760.0
const CAMERA_ZOOM_STEP := 0.12
const CAMERA_MIN_ZOOM := 0.65
const CAMERA_MAX_ZOOM := 2.15
const CAMERA_FOLLOW_SPEED := 8.0
const CAMERA_ZOOM_SPEED := 10.0
const RESOLVE_PRESENTATION_SECONDS := 1.8
const RESOLVE_CAMERA_ZOOM := 1.9
const RESOLVE_PANEL_SIZE := Vector2(430.0, 112.0)

signal action_requested(action: int, target_limb: int, item_instance_id: String)
signal pass_requested
signal reaction_selected(reaction: int)

var _snapshot: Dictionary = {}
var _reaction_prompt: Dictionary = {}
var _feedback := ""
var _font: SystemFont
var _last_viewport_size := Vector2.ZERO
var _action_buttons: Array = []
var _group_buttons: Array = []
var _selected_action_group := ACTION_GROUP_FIREARM
var _action_group_locked_by_user := false
var _visible_action_groups: Array[String] = []
var _command_menu_path: Array[String] = []
var _camera_manual_offset := Vector2.ZERO
var _camera_zoom_bias := 0.0
var _camera_dragging := false
var _camera_initialized := false
var _targeted_limb := -1
var _resolve_active := false
var _resolve_focus_side := ""
var _weapon_preview_effect := ""
var _weapon_animation_key := ""
var _weapon_animation_time := 0.0
var _weapon_animation_playing := false
var _weapon_animation_frame_size := Vector2i.ONE
var _weapon_animation_frame_count := 1
var _weapon_animation_fps := 12.0
var _combat_log_rows: Array[String] = []

# Presentation timing is intentionally independent of the HUD frame.  Keep
# combat events ordered so movement/impact animations finish before snapshots
# replace the actors underneath them.
var _presentation_queue: Array[Dictionary] = []
var _is_processing_queue: bool = false

var _round_label: Label
var _active_label: Label
var _player_label: Label
var _enemy_label: Label
var _player_portrait_model: PaperDollModel
var _enemy_portrait_model: PaperDollModel
var _player_top_rect := Rect2()
var _enemy_top_rect := Rect2()
var _player_bottom_rect := Rect2()
var _enemy_bottom_rect := Rect2()
var _player_portrait_rect := Rect2()
var _enemy_portrait_rect := Rect2()
var _player_command_rect := Rect2()
var _enemy_status_rect := Rect2()
var _action_rect := Rect2()
var _weapon_card_rect := Rect2()
var _group_tabs_rect := Rect2()
var _action_list_rect := Rect2()
var _command_context_rect := Rect2()
var _top_info_rect := Rect2()
var _player_status_rows: Array[Dictionary] = []
var _enemy_status_rows: Array[Dictionary] = []
var _player_status_label: Label
var _enemy_status_label: Label
var _weapon_panel_root: Node2D
var _weapon_panel_box: Polygon2D
var _weapon_panel_border: Line2D
var _weapon_sprite: Sprite2D
var _weapon_name_label: Label
var _weapon_state_label: Label
var _weapon_detail_label: Label
var _group_tab_root: Node2D
var _command_context_box: Polygon2D
var _command_context_border: Line2D
var _command_context_label: Label
var _resolve_screen_root: Node2D
var _resolve_panel_box: Polygon2D
var _resolve_panel_border: Line2D
var _resolve_title_label: Label
var _resolve_body_label: Label

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
	_setup_resolve_screen()
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
	_update_weapon_animation(delta)
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
	_combat_log_rows.clear()
	_grid_hover_card.hide_card()
	_clear_action_buttons()
	_clear_group_buttons()
	_feedback_label.visible = false
	_resolve_active = false
	_resolve_focus_side = ""

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

func show_resolve_screen(resolve: Dictionary) -> void:
	visible = true
	_resolve_active = true
	_resolve_focus_side = str(resolve.get("focus_side", "enemy"))
	_camera_manual_offset = Vector2.ZERO
	_camera_zoom_bias = 0.0
	_update_resolve_text(resolve)
	if _lane_view:
		_lane_view.show_presentation_event({
			"side": str(resolve.get("dead_side", _resolve_focus_side)),
			"type": "death",
		})
	_update_camera(0.0, get_viewport_rect().size)
	await get_tree().create_timer(RESOLVE_PRESENTATION_SECONDS).timeout
	_resolve_active = false
	_resolve_focus_side = ""
	_layout_screen_hud(get_viewport_rect().size)

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
	_action_group_locked_by_user = false
	if not _snapshot.get("reaction_pending", false):
		_reaction_prompt.clear()
	visible = true
	_render()

func _apply_reaction(prompt: Dictionary) -> void:
	_reaction_prompt = prompt
	_push_combat_log("REACTION // %s" % str(prompt.get("trigger", "ATTACK")).to_upper())
	_render_actions()
	_render_command_context()
	_render_feedback()

func _apply_feedback(message: String) -> void:
	_feedback = message
	_push_combat_log(message)
	_render_command_context()
	_render_feedback()

func _apply_presentation_event(event: Dictionary) -> void:
	_push_combat_log(_presentation_log_line(event))
	_preview_weapon_event(event)
	if _lane_view:
		_lane_view.show_presentation_event(event)

func _push_combat_log(message: String) -> void:
	if message.strip_edges().is_empty():
		return
	_combat_log_rows.append(message.strip_edges())
	while _combat_log_rows.size() > 7:
		_combat_log_rows.pop_front()

func _presentation_log_line(event: Dictionary) -> String:
	var event_type := str(event.get("type", "action"))
	if event_type == "damage":
		return _damage_log_line(event)
	if event_type == "bleed":
		return "%s BLEEDS // -%s BLOOD (%s WOUNDS)" % [
			_side_log_label(str(event.get("side", ""))),
			_compact_number(float(event.get("blood_loss", 0.0))),
			str(event.get("active_bleeds", 0)),
		]
	if event_type == "death":
		return "%s DOWN" % _side_log_label(str(event.get("side", "")))
	var action := int(event.get("action", -1))
	return "%s // %s" % [
		_side_log_label(str(event.get("side", ""))),
		_action_log_label(action),
	]

func _damage_log_line(event: Dictionary) -> String:
	var rows := PackedStringArray()
	var limb := str(event.get("limb", "BODY")).replace("_", " ")
	var flesh := float(event.get("flesh_damage", 0.0))
	var stance := float(event.get("stance_damage", 0.0))
	var trauma := str(event.get("trauma", "NONE"))
	var prefix := "%s HIT // %s" % [
		_side_log_label(str(event.get("side", ""))),
		limb,
	]
	if flesh > 0.0:
		rows.append("FLESH -" + _compact_number(flesh))
	if stance > 0.0:
		rows.append("STANCE -" + _compact_number(stance))
	if trauma != "NONE":
		rows.append(trauma.replace("_", " "))
	if bool(event.get("was_felled", false)):
		rows.append("FELLED")
	if bool(event.get("was_killed", false)):
		rows.append("KILLED")
	if rows.is_empty():
		rows.append("DEFLECTED")
	return "%s %s" % [prefix, " / ".join(rows)]

func _side_log_label(side: String) -> String:
	match side:
		"player":
			return "YOU"
		"enemy":
			return "HOSTILE"
	return "COMBAT"

func _action_log_label(action: int) -> String:
	match action:
		GameEnums.ActionType.PUSH_STAY:
			return "PUSH"
		GameEnums.ActionType.PULL_FOLLOW:
			return "PULL"
		GameEnums.ActionType.BREAK:
			return "BREAK STANCE"
	var names := GameEnums.ActionType.keys()
	if action >= 0 and action < names.size():
		return str(names[action]).replace("_", " ")
	return "ACTION"

func _preview_weapon_event(event: Dictionary) -> void:
	if str(event.get("side", "")) != "player":
		return
	if str(event.get("type", "action")) != "action":
		return
	var effect := _weapon_effect_for_action(int(event.get("action", -1)))
	if effect.is_empty():
		return
	_weapon_preview_effect = effect
	_weapon_animation_key = ""
	_weapon_animation_time = 0.0
	_weapon_animation_playing = true
	_render_weapon_card()

func _weapon_effect_for_action(action: int) -> String:
	match action:
		GameEnums.ActionType.SHOOT:
			return GUN_ANIMATION_CATALOG.EFFECT_SHOOT
		GameEnums.ActionType.AIMED_SHOT:
			return GUN_ANIMATION_CATALOG.EFFECT_AIM
		GameEnums.ActionType.RELOAD:
			return GUN_ANIMATION_CATALOG.EFFECT_RELOAD
		GameEnums.ActionType.CYCLE:
			return GUN_ANIMATION_CATALOG.EFFECT_CYCLE
	return ""

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
	_layout_resolve_screen(viewport_size, ui_scale)

	var context_scale := minf(1.0, _top_info_rect.size.x / 430.0)
	var context_position := _top_info_rect.position
	_context_board.global_position = _screen_to_world(
		context_position,
		viewport_size
	)
	_context_board.scale = ui_scale * context_scale
	var action_panel_screen_position := _action_rect.position
	var action_panel_size := _action_rect.size
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
		_action_list_rect.position,
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
	_layout_weapon_card(viewport_size, ui_scale)
	_layout_group_tabs(viewport_size, ui_scale)
	_layout_command_context(viewport_size, ui_scale)
	_feedback_label.global_position = _screen_to_world(
		_command_context_rect.position + Vector2(12.0, 46.0),
		viewport_size
	)
	_feedback_label.scale = ui_scale
	_feedback_label.size = Vector2(
		_command_context_rect.size.x - 24.0,
		maxf(80.0, _command_context_rect.size.y - 58.0)
	)
	_layout_body_status_panel(
		_player_command_rail,
		_player_status_label,
		_player_status_rows,
		_player_command_rect,
		_snapshot.get("player", {}),
		"YOU",
		viewport_size,
		ui_scale
	)
	_layout_body_status_panel(
		_enemy_status_rail,
		_enemy_status_label,
		_enemy_status_rows,
		_enemy_status_rect,
		_snapshot.get("enemy", {}),
		"HOSTILE",
		viewport_size,
		ui_scale
	)
	_sync_duel_portraits(viewport_size)

func _calculate_duel_layout(viewport_size: Vector2) -> void:
	var margin := maxf(18.0, viewport_size.x * 0.014)
	var grid_center_y := viewport_size.y * 0.49
	var grid_height := clampf(viewport_size.y * 0.13, 82.0, 116.0)
	var grid_top := grid_center_y - grid_height * 0.5
	var side_width := minf(500.0, viewport_size.x * 0.25)
	var top_height := maxf(160.0, grid_top - margin * 2.0)
	var bottom_height := clampf(viewport_size.y * 0.18, 190.0, 236.0)
	var bottom_y := viewport_size.y - margin - bottom_height
	var panel_gap := maxf(12.0, viewport_size.x * 0.008)
	var action_width := maxf(
		420.0,
		viewport_size.x - margin * 2.0 - side_width * 2.0 - panel_gap * 2.0
	)

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
	_action_rect = Rect2(
		Vector2(_player_bottom_rect.end.x + panel_gap, bottom_y),
		Vector2(action_width, bottom_height)
	)

	var portrait_size := Vector2(
		minf(150.0, side_width * 0.32),
		maxf(138.0, bottom_height - 28.0)
	)
	_player_portrait_rect = Rect2(
		Vector2(
			_player_bottom_rect.position.x + side_width * 0.58,
			_player_bottom_rect.position.y + 14.0
		),
		portrait_size
	)
	_enemy_portrait_rect = Rect2(
		Vector2(
			_enemy_bottom_rect.position.x + side_width * 0.58,
			_enemy_bottom_rect.position.y + 14.0
		),
		portrait_size
	)
	_player_command_rect = Rect2(
		Vector2(
			_player_bottom_rect.position.x + maxf(24.0, side_width * 0.08),
			_player_bottom_rect.position.y + 18.0
		),
		Vector2(210.0, maxf(128.0, bottom_height - 36.0))
	)
	_enemy_status_rect = Rect2(
		Vector2(
			_enemy_bottom_rect.position.x + maxf(24.0, side_width * 0.08),
			_enemy_bottom_rect.position.y + 24.0
		),
		Vector2(210.0, maxf(124.0, bottom_height - 42.0))
	)
	_top_info_rect = Rect2(
		Vector2(
			viewport_size.x * 0.5 - 215.0,
			margin
		),
		Vector2(430.0, 132.0)
	)
	var deck_padding := 16.0
	var context_width := clampf(action_width * 0.34, 300.0, COMMAND_CONTEXT_SIZE.x)
	var weapon_width := minf(WEAPON_CARD_SIZE.x, maxf(190.0, action_width * 0.18))
	_weapon_card_rect = Rect2(
		_action_rect.position + Vector2(deck_padding, 52.0),
		Vector2(weapon_width, minf(WEAPON_CARD_SIZE.y, bottom_height - 68.0))
	)
	_command_context_rect = Rect2(
		Vector2(
			_action_rect.end.x - deck_padding - context_width,
			_action_rect.position.y + 18.0
		),
		Vector2(context_width, minf(COMMAND_CONTEXT_SIZE.y, bottom_height - 36.0))
	)
	var command_x := _weapon_card_rect.end.x + 18.0
	var command_width := maxf(
		ACTION_BUTTON_SIZE.x * 2.0 + ACTION_BUTTON_GAP.x,
		_command_context_rect.position.x - command_x - 18.0
	)
	_group_tabs_rect = Rect2(
		Vector2(command_x, _action_rect.position.y + 48.0),
		Vector2(command_width, GROUP_BUTTON_SIZE.y + 4.0)
	)
	_action_list_rect = Rect2(
		Vector2(command_x, _group_tabs_rect.end.y + 12.0),
		Vector2(command_width, maxf(92.0, _action_rect.end.y - _group_tabs_rect.end.y - 24.0))
	)

func _layout_duel_shell(viewport_size: Vector2, ui_scale: Vector2) -> void:
	_duel_layout_shell.visible = not _snapshot.is_empty()
	if not _duel_layout_shell.visible:
		return
	_player_top_panel_box.visible = false
	_player_top_panel_border.visible = false
	_enemy_top_panel_box.visible = false
	_enemy_top_panel_border.visible = false
	_place_panel(_player_bottom_panel_box, _player_bottom_panel_border, _player_bottom_rect, viewport_size, ui_scale)
	_place_panel(_enemy_bottom_panel_box, _enemy_bottom_panel_border, _enemy_bottom_rect, viewport_size, ui_scale)
	_place_panel(_player_portrait_plate, _player_portrait_border, _player_portrait_rect, viewport_size, ui_scale)
	_place_panel(_enemy_portrait_plate, _enemy_portrait_border, _enemy_portrait_rect, viewport_size, ui_scale)
	_player_command_rail.visible = true
	_enemy_status_rail.visible = true

func _layout_weapon_card(viewport_size: Vector2, ui_scale: Vector2) -> void:
	if _weapon_panel_root == null:
		return
	_weapon_panel_root.visible = not _snapshot.is_empty()
	if not _weapon_panel_root.visible:
		return
	_weapon_panel_root.global_position = _screen_to_world(
		_weapon_card_rect.position,
		viewport_size
	)
	_weapon_panel_root.scale = ui_scale
	_set_box(_weapon_panel_box, _weapon_card_rect.size)
	_set_outline(_weapon_panel_border, _weapon_card_rect.size)
	_weapon_sprite.position = Vector2(
		_weapon_card_rect.size.x * 0.5,
		_weapon_card_rect.size.y * 0.36
	)
	_weapon_name_label.position = Vector2(12.0, _weapon_card_rect.size.y - 66.0)
	_weapon_name_label.size = Vector2(_weapon_card_rect.size.x - 20.0, 20.0)
	_weapon_state_label.position = Vector2(12.0, _weapon_card_rect.size.y - 44.0)
	_weapon_state_label.size = Vector2(_weapon_card_rect.size.x - 20.0, 20.0)
	_weapon_detail_label.position = Vector2(12.0, _weapon_card_rect.size.y - 22.0)
	_weapon_detail_label.size = Vector2(_weapon_card_rect.size.x - 20.0, 20.0)

func _layout_group_tabs(viewport_size: Vector2, ui_scale: Vector2) -> void:
	if _group_tab_root == null:
		return
	_group_tab_root.visible = not _snapshot.is_empty()
	if not _group_tab_root.visible:
		return
	_group_tab_root.global_position = _screen_to_world(
		_group_tabs_rect.position,
		viewport_size
	)
	_group_tab_root.scale = ui_scale

func _layout_command_context(viewport_size: Vector2, ui_scale: Vector2) -> void:
	var visible_context := not _snapshot.is_empty()
	_command_context_box.visible = visible_context
	_command_context_border.visible = visible_context
	_command_context_label.visible = visible_context
	if not visible_context:
		return
	_set_box(_command_context_box, _command_context_rect.size)
	_set_outline(_command_context_border, _command_context_rect.size)
	_command_context_box.global_position = _screen_to_world(
		_command_context_rect.position,
		viewport_size
	)
	_command_context_border.global_position = _command_context_box.global_position
	_command_context_box.scale = ui_scale
	_command_context_border.scale = ui_scale
	_command_context_label.global_position = _screen_to_world(
		_command_context_rect.position + Vector2(12.0, 10.0),
		viewport_size
	)
	_command_context_label.scale = ui_scale
	_command_context_label.size = Vector2(
		_command_context_rect.size.x - 24.0,
		32.0
	)

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

func _layout_body_status_panel(
	root: Node2D,
	title_label: Label,
	rows: Array[Dictionary],
	rect: Rect2,
	data: Dictionary,
	heading: String,
	viewport_size: Vector2,
	ui_scale: Vector2
) -> void:
	if root == null:
		return
	root.global_position = _screen_to_world(rect.position, viewport_size)
	root.scale = ui_scale
	root.visible = not data.is_empty()
	if not root.visible:
		return
	if title_label:
		title_label.position = Vector2.ZERO
		title_label.text = _body_status_title(data, heading)
	var limbs: Array = data.get("limbs", [])
	var row_y := 45.0
	for index in range(rows.size()):
		var row := rows[index]
		var limb: Dictionary = limbs[index] if index < limbs.size() else {}
		_layout_limb_row(row, limb, Vector2(0.0, row_y))
		row_y += BODY_BAR_SIZE.y + BODY_BAR_GAP

func _layout_limb_row(row: Dictionary, limb: Dictionary, row_position: Vector2) -> void:
	var root := row.get("root") as Node2D
	var track := row.get("track") as Polygon2D
	var fill := row.get("fill") as Polygon2D
	var outline := row.get("outline") as Line2D
	var label := row.get("label") as Label
	if root == null or track == null or fill == null or outline == null or label == null:
		return
	root.position = row_position
	var maximum := maxf(1.0, float(limb.get("maximum", 1.0)))
	var current := clampf(float(limb.get("current", 0.0)), 0.0, maximum)
	var ratio := current / maximum
	var trauma := str(limb.get("trauma", "NONE"))
	var code := str(limb.get("code", row.get("code", "??")))
	var trauma_text := ""
	if trauma != "NONE":
		trauma_text = " " + trauma.replace("_", " ")
	_set_box(track, BODY_BAR_SIZE)
	_set_box(fill, Vector2(maxf(2.0, BODY_BAR_SIZE.x * ratio), BODY_BAR_SIZE.y))
	_set_outline(outline, BODY_BAR_SIZE)
	fill.color = _limb_bar_color(ratio, trauma)
	var is_targeted: bool = _targeted_limb >= 0 and code == _limb_code(_targeted_limb)
	outline.default_color = (
		HUDAssetLibrary.COLOR_CAUTION
		if is_targeted
		else Color(COLOR_ACTION_BORDER, 0.52)
	)
	outline.width = 2.0 if is_targeted else 1.0
	label.text = "%s %s/%s%s" % [
		code,
		_compact_number(current),
		_compact_number(maximum),
		trauma_text,
	]

func _body_status_title(data: Dictionary, heading: String) -> String:
	var active := " ACTIVE" if data.get("is_active", false) else ""
	var guard := " GUARD" if data.get("stance_recovery_guard", false) else ""
	return "%s%s // BLOOD %04.1f\nSTANCE %02d %s%s" % [
		heading,
		active,
		float(data.get("blood", 0.0)),
		int(data.get("stance", 0)),
		str(data.get("stance_state", "UNKNOWN")),
		guard,
	]

func _limb_bar_color(ratio: float, trauma: String) -> Color:
	if ratio <= 0.0 or trauma == "SHATTERED_LIMB":
		return Color(0.42, 0.05, 0.08, 0.98)
	if trauma != "NONE" or ratio <= 0.35:
		return COLOR_BODY_BAR_CRITICAL
	if ratio <= 0.7:
		return COLOR_BODY_BAR_DAMAGED
	return COLOR_BODY_BAR_HEALTH

func _limb_code(limb: int) -> String:
	match limb:
		GameEnums.LimbRegion.HEAD:
			return "HD"
		GameEnums.LimbRegion.UPPER_TORSO:
			return "UT"
		GameEnums.LimbRegion.LOWER_TORSO:
			return "LT"
		GameEnums.LimbRegion.LEFT_ARM:
			return "LA"
		GameEnums.LimbRegion.RIGHT_ARM:
			return "RA"
		GameEnums.LimbRegion.LEFT_LEG:
			return "LL"
		GameEnums.LimbRegion.RIGHT_LEG:
			return "RL"
	return "??"

func _render() -> void:
	_render_legacy_readouts()
	if _snapshot.is_empty():
		_lane_view.show_snapshot({})
		_context_board.visible = false
		_player_actor_hud.visible = false
		_enemy_actor_hud.visible = false
		_duel_layout_shell.visible = false
		_player_command_rail.visible = false
		_enemy_status_rail.visible = false
		_sync_duel_portraits(get_viewport_rect().size)
		_grid_hover_card.hide_card()
		_render_weapon_card()
		_render_actions()
		_render_command_context()
		_render_feedback()
		return
	_lane_view.show_snapshot(_snapshot)
	_context_board.show_snapshot(_snapshot)
	_sync_actor_huds(get_viewport_rect().size)
	_render_weapon_card()
	_render_actions()
	_render_command_context()
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
	_setup_weapon_card()
	_setup_group_tabs()
	_setup_command_context()

func _setup_weapon_card() -> void:
	_weapon_panel_root = Node2D.new()
	_weapon_panel_root.name = "WeaponCard"
	_weapon_panel_root.z_index = 35
	add_child(_weapon_panel_root)

	_weapon_panel_box = Polygon2D.new()
	_weapon_panel_box.name = "WeaponCardBox"
	_weapon_panel_box.color = Color(0.055, 0.05, 0.04, 0.94)
	_weapon_panel_root.add_child(_weapon_panel_box)

	_weapon_panel_border = Line2D.new()
	_weapon_panel_border.name = "WeaponCardBorder"
	_weapon_panel_border.default_color = Color(COLOR_ACTION_BORDER, 0.78)
	_weapon_panel_border.width = 1.0
	_weapon_panel_root.add_child(_weapon_panel_border)

	_weapon_sprite = Sprite2D.new()
	_weapon_sprite.name = "WeaponSprite"
	_weapon_sprite.centered = true
	_weapon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_weapon_sprite.z_index = 1
	_weapon_panel_root.add_child(_weapon_sprite)

	_weapon_name_label = _make_deck_label("WeaponNameLabel", _weapon_panel_root, 11)
	_weapon_state_label = _make_deck_label("WeaponStateLabel", _weapon_panel_root, 13)
	_weapon_detail_label = _make_deck_label("WeaponDetailLabel", _weapon_panel_root, 10)

func _setup_group_tabs() -> void:
	_group_tab_root = Node2D.new()
	_group_tab_root.name = "ActionGroupTabs"
	_group_tab_root.z_index = 35
	add_child(_group_tab_root)

func _setup_command_context() -> void:
	_command_context_box = Polygon2D.new()
	_command_context_box.name = "CommandContextBox"
	_command_context_box.z_index = 35
	_command_context_box.color = Color(0.055, 0.05, 0.04, 0.86)
	add_child(_command_context_box)

	_command_context_border = Line2D.new()
	_command_context_border.name = "CommandContextBorder"
	_command_context_border.z_index = 36
	_command_context_border.default_color = Color(COLOR_ACTION_BORDER, 0.58)
	_command_context_border.width = 1.0
	add_child(_command_context_border)

	_command_context_label = _make_deck_label("CommandContextLabel", self, 10)
	_command_context_label.z_index = 37
	_command_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _make_deck_label(label_name: String, parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.add_theme_color_override("font_color", Color(0.86, 0.82, 0.72, 1.0))
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

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
	_player_status_label = _make_status_label(
		"PlayerBodyStatusLabel",
		_player_command_rail
	)
	_enemy_status_label = _make_status_label(
		"EnemyBodyStatusLabel",
		_enemy_status_rail
	)
	_player_status_rows = _build_limb_rows(_player_command_rail)
	_enemy_status_rows = _build_limb_rows(_enemy_status_rail)

func _setup_resolve_screen() -> void:
	_resolve_screen_root = Node2D.new()
	_resolve_screen_root.name = "ResolveScreen"
	_resolve_screen_root.z_index = 220
	add_child(_resolve_screen_root)

	_resolve_panel_box = Polygon2D.new()
	_resolve_panel_box.name = "ResolvePanelBox"
	_resolve_panel_box.color = Color(0.045, 0.035, 0.025, 0.92)
	_resolve_screen_root.add_child(_resolve_panel_box)

	_resolve_panel_border = Line2D.new()
	_resolve_panel_border.name = "ResolvePanelBorder"
	_resolve_panel_border.default_color = Color(0.82, 0.67, 0.42, 0.92)
	_resolve_panel_border.width = 2.0
	_resolve_screen_root.add_child(_resolve_panel_border)

	_resolve_title_label = Label.new()
	_resolve_title_label.name = "ResolveTitleLabel"
	_resolve_title_label.position = Vector2(18.0, 14.0)
	_resolve_title_label.offset_right = RESOLVE_PANEL_SIZE.x - 36.0
	_resolve_title_label.offset_bottom = 30.0
	_resolve_title_label.add_theme_color_override(
		"font_color",
		Color(0.95, 0.74, 0.48, 1.0)
	)
	_resolve_title_label.add_theme_font_size_override("font_size", 20)
	_resolve_screen_root.add_child(_resolve_title_label)

	_resolve_body_label = Label.new()
	_resolve_body_label.name = "ResolveBodyLabel"
	_resolve_body_label.position = Vector2(18.0, 50.0)
	_resolve_body_label.offset_right = RESOLVE_PANEL_SIZE.x - 36.0
	_resolve_body_label.offset_bottom = 48.0
	_resolve_body_label.add_theme_color_override(
		"font_color",
		Color(0.84, 0.79, 0.66, 1.0)
	)
	_resolve_body_label.add_theme_font_size_override("font_size", 12)
	_resolve_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_resolve_screen_root.add_child(_resolve_body_label)
	_set_box(_resolve_panel_box, RESOLVE_PANEL_SIZE)
	_set_outline(_resolve_panel_border, RESOLVE_PANEL_SIZE)
	_resolve_screen_root.visible = false

func _layout_resolve_screen(viewport_size: Vector2, ui_scale: Vector2) -> void:
	if _resolve_screen_root == null:
		return
	_resolve_screen_root.visible = _resolve_active
	if not _resolve_active:
		return
	var panel_position := Vector2(
		viewport_size.x * 0.5 - RESOLVE_PANEL_SIZE.x * 0.5,
		maxf(22.0, viewport_size.y * 0.11)
	)
	_resolve_screen_root.global_position = _screen_to_world(
		panel_position,
		viewport_size
	)
	_resolve_screen_root.scale = ui_scale

func _update_resolve_text(resolve: Dictionary) -> void:
	if _resolve_title_label == null or _resolve_body_label == null:
		return
	_resolve_title_label.text = str(resolve.get("title", "COMBAT RESOLVED")).to_upper()
	var dead_name := str(resolve.get("dead_name", "HOSTILE"))
	var cause := str(resolve.get("cause", "unknown trauma"))
	_resolve_body_label.text = "%s DOWN\nCAUSE // %s" % [
		dead_name.to_upper(),
		cause.to_upper(),
	]

func _setup_portrait_tokens() -> void:
	_player_portrait_model = PAPERDOLL_SCENE.instantiate() as PaperDollModel
	_player_portrait_model.name = "PlayerPortraitPaperDoll"
	_portrait_root.add_child(_player_portrait_model)
	_player_portrait_model.visible = false
	_player_portrait_model.set_backdrop_visible(false)

	_enemy_portrait_model = PAPERDOLL_SCENE.instantiate() as PaperDollModel
	_enemy_portrait_model.name = "EnemyPortraitPaperDoll"
	_portrait_root.add_child(_enemy_portrait_model)
	_enemy_portrait_model.visible = false
	_enemy_portrait_model.set_backdrop_visible(false)

func _make_status_label(label_name: String, parent: Node) -> Label:
	var label := Label.new()
	label.name = label_name
	label.offset_right = 220.0
	label.offset_bottom = 34.0
	label.add_theme_color_override("font_color", Color(0.86, 0.78, 0.62, 1.0))
	label.add_theme_font_size_override("font_size", 11)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _build_limb_rows(parent: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for code in BODY_LIMB_ORDER:
		var row_root := Node2D.new()
		row_root.name = "%sRow" % code
		parent.add_child(row_root)

		var track := Polygon2D.new()
		track.name = "Track"
		track.color = COLOR_BODY_BAR_BACK
		row_root.add_child(track)

		var fill := Polygon2D.new()
		fill.name = "Fill"
		fill.color = COLOR_BODY_BAR_HEALTH
		fill.z_index = 1
		row_root.add_child(fill)

		var outline := Line2D.new()
		outline.name = "Outline"
		outline.default_color = Color(COLOR_ACTION_BORDER, 0.52)
		outline.width = 1.0
		outline.z_index = 2
		row_root.add_child(outline)

		var label := Label.new()
		label.name = "Label"
		label.position = Vector2(BODY_BAR_SIZE.x + 9.0, -4.0)
		label.offset_right = 82.0
		label.offset_bottom = 18.0
		label.add_theme_color_override(
			"font_color",
			Color(0.87, 0.82, 0.72, 1.0)
		)
		label.add_theme_font_size_override("font_size", 10)
		label.z_index = 3
		row_root.add_child(label)

		rows.append({
			"code": code,
			"root": row_root,
			"track": track,
			"fill": fill,
			"outline": outline,
			"label": label,
		})
	return rows

func _render_actions() -> void:
	_clear_action_buttons()
	_clear_group_buttons()
	var has_snapshot := not _snapshot.is_empty()
	_action_panel_box.visible = has_snapshot
	_action_panel_border.visible = has_snapshot
	_action_panel_frame.visible = false
	_action_title_label.visible = has_snapshot
	_action_button_root.visible = has_snapshot
	if _weapon_panel_root:
		_weapon_panel_root.visible = has_snapshot
	if _group_tab_root:
		_group_tab_root.visible = has_snapshot
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

	_action_title_label.text = (
		"COMMANDS // Q/E GROUPS // 1-9 ACTIONS"
		if _command_menu_path.is_empty()
		else "COMMANDS // 0 BACK // 1-9 SELECT"
	)
	var actions: Array = _snapshot.get("actions", [])
	var grouped := _group_actions(actions)
	_visible_action_groups = _ordered_action_groups(grouped)
	_select_default_action_group(grouped)
	_render_group_buttons(grouped)
	var rendered_actions: Array = grouped.get(_selected_action_group, [])
	var action_index := _render_command_menu(rendered_actions, 0)
	if not _command_menu_path.is_empty():
		_add_back_button(action_index)
	elif _snapshot.get("can_pass", false):
		_add_pass_button(action_index)

func _render_reaction_buttons() -> void:
	var reactions: Array = _reaction_prompt.get("reactions", [])
	_visible_action_groups = [ACTION_GROUP_REACTION]
	_selected_action_group = ACTION_GROUP_REACTION
	for index in range(reactions.size()):
		var descriptor: Dictionary = reactions[index]
		_add_reaction_button(descriptor, index)
	_add_decline_button(reactions.size())

func _group_actions(actions: Array) -> Dictionary:
	var grouped := {}
	for raw_descriptor in actions:
		var descriptor: Dictionary = raw_descriptor
		var group := str(descriptor.get("group", _fallback_action_group(descriptor)))
		if not grouped.has(group):
			grouped[group] = []
		grouped[group].append(descriptor)
	return grouped

func _ordered_action_groups(grouped: Dictionary) -> Array[String]:
	var ordered: Array[String] = []
	for group in ACTION_GROUP_ORDER:
		if grouped.has(group) and not grouped[group].is_empty():
			ordered.append(group)
	return ordered

func _select_default_action_group(grouped: Dictionary) -> void:
	var previous_group := _selected_action_group
	if (
		_action_group_locked_by_user
		and grouped.has(_selected_action_group)
		and not grouped[_selected_action_group].is_empty()
	):
		return
	var preferred := ACTION_GROUP_FIREARM
	if is_showing_melee_lock():
		preferred = ACTION_GROUP_MELEE
	elif not grouped.has(ACTION_GROUP_FIREARM):
		preferred = ACTION_GROUP_MOVEMENT
	if grouped.has(preferred) and not grouped[preferred].is_empty():
		_selected_action_group = preferred
		if _selected_action_group != previous_group:
			_command_menu_path.clear()
		return
	_selected_action_group = (
		_visible_action_groups[0]
		if not _visible_action_groups.is_empty()
		else ACTION_GROUP_FIELD
	)
	if _selected_action_group != previous_group:
		_command_menu_path.clear()

func _render_group_buttons(grouped: Dictionary) -> void:
	var index := 0
	for group in _visible_action_groups:
		var count := (grouped.get(group, []) as Array).size()
		var payload := {
			"mode": BUTTON_MODE_GROUP,
			"group": group,
		}
		var text := "%s %02d" % [_group_label(group), count]
		_add_group_button(payload, text, index, group == _selected_action_group)
		index += 1

func _add_group_button(
	payload: Dictionary,
	text: String,
	index: int,
	selected: bool
) -> void:
	var button := ACTION_BUTTON_SCENE.instantiate()
	button.name = "GroupButton_%02d" % index
	button.set_button_size(GROUP_BUTTON_SIZE)
	button.configure(payload, text, true)
	button.pressed.connect(_on_group_button_pressed)
	var columns := _group_button_columns()
	var column := index % columns
	var row := index / columns
	button.position = Vector2(
		float(column) * (GROUP_BUTTON_SIZE.x + 8.0),
		float(row) * (GROUP_BUTTON_SIZE.y + 8.0)
	)
	button.modulate = Color(1.0, 0.92, 0.68, 1.0) if selected else Color.WHITE
	_group_tab_root.add_child(button)
	_group_buttons.append(button)

func _group_button_columns() -> int:
	var fit := int(
		floor(
			(_group_tabs_rect.size.x + 8.0)
			/ (GROUP_BUTTON_SIZE.x + 8.0)
		)
	)
	return maxi(1, fit)

func _render_command_menu(descriptors: Array, index: int) -> int:
	if not _command_menu_path.is_empty():
		var page := str(_command_menu_path.back())
		match page:
			MENU_AIM:
				return _render_aim_menu(descriptors, index)
			MENU_PUSH:
				return _render_push_menu(descriptors, index)
		_command_menu_path.clear()
	match _selected_action_group:
		ACTION_GROUP_FIREARM:
			return _render_firearm_menu(descriptors, index)
		ACTION_GROUP_MELEE:
			return _render_melee_menu(descriptors, index)
	for descriptor in descriptors:
		_add_action_button(descriptor, index)
		index += 1
	return index

func _render_firearm_menu(descriptors: Array, index: int) -> int:
	index = _add_action_if_available(
		descriptors,
		GameEnums.ActionType.SHOOT,
		index
	)
	if not _find_descriptor(descriptors, GameEnums.ActionType.AIMED_SHOT).is_empty():
		_add_submenu_button(MENU_AIM, "AIM", index)
		index += 1
	index = _add_action_if_available(
		descriptors,
		GameEnums.ActionType.RELOAD,
		index
	)
	index = _add_action_if_available(
		descriptors,
		GameEnums.ActionType.CYCLE,
		index
	)
	return _add_remaining_actions(
		descriptors,
		index,
		[
			GameEnums.ActionType.SHOOT,
			GameEnums.ActionType.AIMED_SHOT,
			GameEnums.ActionType.RELOAD,
			GameEnums.ActionType.CYCLE,
		]
	)

func _render_melee_menu(descriptors: Array, index: int) -> int:
	index = _add_action_if_available(
		descriptors,
		GameEnums.ActionType.STRIKE,
		index
	)
	index = _add_action_if_available(
		descriptors,
		GameEnums.ActionType.GRAPPLE,
		index
	)
	index = _add_action_if_available(
		descriptors,
		GameEnums.ActionType.BREAK,
		index
	)
	index = _add_action_if_available(
		descriptors,
		GameEnums.ActionType.PUSH_STAY,
		index,
		"PUSH"
	)
	index = _add_action_if_available(
		descriptors,
		GameEnums.ActionType.PULL_FOLLOW,
		index,
		"PULL"
	)
	index = _add_action_if_available(
		descriptors,
		GameEnums.ActionType.EXECUTE,
		index
	)
	return _add_remaining_actions(
		descriptors,
		index,
		[
			GameEnums.ActionType.STRIKE,
			GameEnums.ActionType.GRAPPLE,
			GameEnums.ActionType.BREAK,
			GameEnums.ActionType.PUSH_STAY,
			GameEnums.ActionType.PULL_FOLLOW,
			GameEnums.ActionType.EXECUTE,
		]
	)

func _render_aim_menu(descriptors: Array, index: int) -> int:
	var descriptor := _find_descriptor(
		descriptors,
		GameEnums.ActionType.AIMED_SHOT
	)
	if descriptor.is_empty():
		return index
	var target_limbs: Array = descriptor.get("target_limbs", [])
	for limb in target_limbs:
		var limb_descriptor := descriptor.duplicate(true)
		limb_descriptor["target_limbs"] = [limb]
		limb_descriptor["label"] = _limb_aim_label(int(limb))
		_add_action_button(limb_descriptor, index)
		index += 1
	return index

func _render_push_menu(descriptors: Array, index: int) -> int:
	index = _add_action_if_available(
		descriptors,
		GameEnums.ActionType.PUSH_STAY,
		index,
		"PUSH"
	)
	return index

func _add_action_if_available(
	descriptors: Array,
	action: int,
	index: int,
	label_override: String = ""
) -> int:
	var descriptor := _find_descriptor(descriptors, action)
	if descriptor.is_empty():
		return index
	if not label_override.is_empty():
		descriptor = descriptor.duplicate(true)
		descriptor["label"] = label_override
	_add_action_button(descriptor, index)
	return index + 1

func _add_remaining_actions(
	descriptors: Array,
	index: int,
	handled_actions: Array
) -> int:
	for raw_descriptor in descriptors:
		var descriptor: Dictionary = raw_descriptor
		if handled_actions.has(int(descriptor.get("action", -1))):
			continue
		_add_action_button(descriptor, index)
		index += 1
	return index

func _find_descriptor(descriptors: Array, action: int) -> Dictionary:
	for raw_descriptor in descriptors:
		var descriptor: Dictionary = raw_descriptor
		if int(descriptor.get("action", -1)) == action:
			return descriptor
	return {}

func _limb_aim_label(limb: int) -> String:
	match limb:
		GameEnums.LimbRegion.HEAD:
			return "HEAD"
		GameEnums.LimbRegion.UPPER_TORSO:
			return "UPPER"
		GameEnums.LimbRegion.LOWER_TORSO:
			return "LOWER"
		GameEnums.LimbRegion.LEFT_ARM:
			return "L ARM"
		GameEnums.LimbRegion.RIGHT_ARM:
			return "R ARM"
		GameEnums.LimbRegion.LEFT_LEG:
			return "L LEG"
		GameEnums.LimbRegion.RIGHT_LEG:
			return "R LEG"
	return "TARGET"

func _add_submenu_button(menu: String, label: String, index: int) -> void:
	var payload := {
		"mode": BUTTON_MODE_SUBMENU,
		"menu": menu,
	}
	_add_button(payload, "[%d] %s >" % [index + 1, label], index)

func _add_back_button(index: int) -> void:
	var payload := {"mode": BUTTON_MODE_BACK}
	_add_button(payload, "[0] BACK", index)

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
	_add_button(
		payload,
		"[0] GUARD %02d AP" % int(_snapshot.get("ap", 0)),
		index
	)

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
	var columns := _action_button_columns()
	var column := index % columns
	var row := index / columns
	button.position = Vector2(
		float(column) * (ACTION_BUTTON_SIZE.x + ACTION_BUTTON_GAP.x),
		float(row) * (ACTION_BUTTON_SIZE.y + ACTION_BUTTON_GAP.y)
	)
	_action_button_root.add_child(button)
	_action_buttons.append(button)

func _action_button_columns() -> int:
	var fit := int(
		floor(
			(_action_list_rect.size.x + ACTION_BUTTON_GAP.x)
			/ (ACTION_BUTTON_SIZE.x + ACTION_BUTTON_GAP.x)
		)
	)
	return clampi(fit, 1, ACTION_BUTTON_COLUMNS)

func _clear_action_buttons() -> void:
	for button in _action_buttons:
		if is_instance_valid(button):
			button.queue_free()
	_action_buttons.clear()
	_on_target_limb_unfocused()

func _clear_group_buttons() -> void:
	for button in _group_buttons:
		if is_instance_valid(button):
			button.queue_free()
	_group_buttons.clear()

func _on_group_button_pressed(payload: Dictionary) -> void:
	var group := str(payload.get("group", _selected_action_group))
	if group.is_empty() or not _visible_action_groups.has(group):
		return
	_selected_action_group = group
	_action_group_locked_by_user = true
	_command_menu_path.clear()
	_render_actions()
	_render_command_context()

func _on_target_limb_focused(limb: int) -> void:
	_targeted_limb = limb
	if _enemy_actor_hud:
		_enemy_actor_hud.set_targeted_limb(limb)
	_layout_screen_hud(get_viewport_rect().size)

func _on_target_limb_unfocused() -> void:
	_targeted_limb = -1
	if _enemy_actor_hud:
		_enemy_actor_hud.clear_targeted_limb()
	_layout_screen_hud(get_viewport_rect().size)

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
			_command_menu_path.clear()
		BUTTON_MODE_PASS:
			pass_requested.emit()
		BUTTON_MODE_REACTION:
			reaction_selected.emit(int(payload.get("reaction", -1)))
		BUTTON_MODE_SUBMENU:
			var menu := str(payload.get("menu", ""))
			if not menu.is_empty():
				_command_menu_path = [menu]
				_render_actions()
				_render_command_context()
		BUTTON_MODE_BACK:
			if not _command_menu_path.is_empty():
				_command_menu_path.pop_back()
				_render_actions()
				_render_command_context()

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
	if event.keycode == KEY_Q:
		_cycle_action_group(-1)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_E:
		_cycle_action_group(1)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_0:
		for button in _action_buttons:
			var payload: Dictionary = button.get_payload()
			var mode := str(payload.get("mode", ""))
			if (
				mode == BUTTON_MODE_BACK
				or (
					_command_menu_path.is_empty()
					and mode == BUTTON_MODE_PASS
				)
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

func _cycle_action_group(direction: int) -> void:
	if _visible_action_groups.size() <= 1:
		return
	var current := _visible_action_groups.find(_selected_action_group)
	if current < 0:
		current = 0
	var next := posmod(current + direction, _visible_action_groups.size())
	_selected_action_group = _visible_action_groups[next]
	_action_group_locked_by_user = true
	_command_menu_path.clear()
	_render_actions()
	_render_command_context()

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
	var target_zoom := RESOLVE_CAMERA_ZOOM
	var target_position := _lane_view.get_actor_anchor_global(
		_resolve_focus_side
	)
	if not _resolve_active:
		target_zoom = clampf(
			_lane_view.get_focus_zoom() + _camera_zoom_bias,
			CAMERA_MIN_ZOOM,
			CAMERA_MAX_ZOOM
		)
		target_position = (
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

func get_camera_zoom_value() -> float:
	return _camera_zoom_value()

func is_resolve_screen_visible() -> bool:
	return _resolve_active

func get_resolve_focus_side() -> String:
	return _resolve_focus_side

func _sync_actor_huds(viewport_size: Vector2) -> void:
	if _snapshot.is_empty():
		return
	_player_actor_hud.visible = false
	_enemy_actor_hud.visible = false
	_sync_duel_portraits(viewport_size)

func _sync_duel_portraits(viewport_size: Vector2) -> void:
	if _snapshot.is_empty() or _player_portrait_model == null:
		if _player_portrait_model:
			_player_portrait_model.visible = false
		if _enemy_portrait_model:
			_enemy_portrait_model.visible = false
		return
	var ui_scale := Vector2.ONE / _camera_zoom_value()
	_sync_portrait_model(
		_player_portrait_model,
		_snapshot.get("player", {}),
		_player_portrait_rect,
		true,
		viewport_size,
		ui_scale
	)
	_sync_portrait_model(
		_enemy_portrait_model,
		_snapshot.get("enemy", {}),
		_enemy_portrait_rect,
		false,
		viewport_size,
		ui_scale
	)

func _sync_portrait_model(
	model: PaperDollModel,
	data: Dictionary,
	rect: Rect2,
	is_player: bool,
	viewport_size: Vector2,
	ui_scale: Vector2
) -> void:
	if model == null:
		return
	model.visible = not data.is_empty()
	if not model.visible:
		return
	var model_size := rect.size * 2.18
	model.size = model_size
	model.clip_contents = true
	model.scale = (
		ui_scale * Vector2(-1.0, 1.0)
		if not is_player
		else ui_scale
	)
	var paperdoll_origin := Vector2(
		rect.position.x + rect.size.x * 0.5 - model_size.x * 0.5,
		rect.position.y + rect.size.y * 0.54 - model_size.y * 0.5
	)
	paperdoll_origin.x += rect.size.x * (0.10 if is_player else -0.10)
	if not is_player:
		paperdoll_origin.x += model_size.x
	model.global_position = _screen_to_world(
		paperdoll_origin,
		viewport_size
	)
	model.update_model(data.get("equipment", []))
	model.update_wounds(data.get("limbs", []))

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

func _render_weapon_card() -> void:
	if _weapon_panel_root == null:
		return
	var player: Dictionary = _snapshot.get("player", {})
	var weapon: Dictionary = player.get("active_weapon", {})
	_weapon_panel_root.visible = not _snapshot.is_empty()
	if _snapshot.is_empty():
		return
	var weapon_name := str(player.get("weapon", "UNARMED")).to_upper()
	var weapon_state := str(player.get("weapon_state", "UNARMED")).to_upper()
	var weapon_id := str(player.get("weapon_id", ""))
	var sprite_path := str(player.get("weapon_sprite_path", ""))
	_weapon_name_label.text = weapon_name
	_weapon_state_label.text = _weapon_state_text(weapon_state)
	_weapon_detail_label.text = _weapon_detail_text(player, weapon)
	var effect := (
		_weapon_preview_effect
		if not _weapon_preview_effect.is_empty()
		else _weapon_effect_for_state(weapon_state)
	)
	var animation_texture: Texture2D = null
	if bool(player.get("has_firearm", false)):
		animation_texture = GUN_ANIMATION_CATALOG.texture(weapon_id, effect)
	_weapon_sprite.texture = (
		animation_texture
		if animation_texture != null
		else _load_weapon_texture(sprite_path)
	)
	_weapon_sprite.visible = _weapon_sprite.texture != null
	if _weapon_sprite.texture == null:
		return
	var frame_size := _configure_weapon_sprite_sheet(
		_weapon_sprite.texture,
		weapon_id,
		effect
	)
	var max_width := maxf(24.0, _weapon_card_rect.size.x - 24.0)
	var max_height := maxf(24.0, _weapon_card_rect.size.y * 0.52)
	var texture_size := Vector2(
		float(frame_size.x),
		float(frame_size.y)
	)
	var scale_factor := minf(
		max_width / maxf(1.0, texture_size.x),
		max_height / maxf(1.0, texture_size.y)
	)
	_weapon_sprite.scale = Vector2.ONE * scale_factor

func _configure_weapon_sprite_sheet(
	texture: Texture2D,
	weapon_id: String,
	effect: String
) -> Vector2i:
	var frame_spec := GUN_ANIMATION_CATALOG.frame_spec(weapon_id, effect)
	var frame_size := _weapon_frame_size(texture, frame_spec)
	var frame_count := _weapon_frame_count(texture, frame_size)
	var fps := float(frame_spec.get("fps", 12.0))
	_weapon_sprite.region_enabled = true
	_weapon_sprite.hframes = 1
	_weapon_sprite.vframes = 1
	var animation_key := "%s:%s:%s:%dx%d" % [
		weapon_id,
		effect,
		texture.resource_path,
		frame_size.x,
		frame_size.y,
	]
	if animation_key != _weapon_animation_key:
		_weapon_animation_key = animation_key
		_weapon_animation_time = 0.0
		if _weapon_preview_effect.is_empty():
			_weapon_animation_playing = false
	_weapon_animation_frame_size = frame_size
	_weapon_animation_frame_count = frame_count
	_weapon_animation_fps = maxf(1.0, fps)
	_set_weapon_animation_frame(_current_weapon_frame_index())
	return frame_size

func _weapon_frame_size(texture: Texture2D, frame_spec: Dictionary) -> Vector2i:
	var width := texture.get_width()
	var height := texture.get_height()
	if width <= 0 or height <= 0 or width == height:
		return Vector2i(maxi(1, width), maxi(1, height))
	var spec_width := int(frame_spec.get("w", 0))
	var spec_height := int(frame_spec.get("h", 0))
	if spec_width > 0 and spec_height > 0:
		return Vector2i(
			clampi(spec_width, 1, width),
			clampi(spec_height, 1, height)
		)
	if width > height:
		return Vector2i(mini(width, height), height)
	return Vector2i(width, mini(width, height))

func _weapon_frame_count(texture: Texture2D, frame_size: Vector2i) -> int:
	var columns := maxi(
		1,
		int(floor(float(texture.get_width()) / float(maxi(1, frame_size.x))))
	)
	var rows := maxi(
		1,
		int(floor(float(texture.get_height()) / float(maxi(1, frame_size.y))))
	)
	return maxi(1, columns * rows)

func _update_weapon_animation(delta: float) -> void:
	if _weapon_sprite == null or _weapon_sprite.texture == null:
		return
	if _weapon_animation_frame_count <= 1:
		_set_weapon_animation_frame(0)
		return
	if not _weapon_animation_playing:
		_set_weapon_animation_frame(0)
		return
	_weapon_animation_time += delta
	var frame_index := _current_weapon_frame_index()
	_set_weapon_animation_frame(frame_index)
	var duration := float(_weapon_animation_frame_count) / _weapon_animation_fps
	if _weapon_animation_time >= duration:
		_weapon_animation_playing = false
		_weapon_preview_effect = ""
		_weapon_animation_key = ""
		_render_weapon_card()

func _current_weapon_frame_index() -> int:
	if not _weapon_animation_playing:
		return 0
	return clampi(
		int(floor(_weapon_animation_time * _weapon_animation_fps)),
		0,
		maxi(0, _weapon_animation_frame_count - 1)
	)

func _set_weapon_animation_frame(frame_index: int) -> void:
	if _weapon_sprite == null or _weapon_sprite.texture == null:
		return
	var frame_size := _weapon_animation_frame_size
	var columns := maxi(
		1,
		int(floor(
			float(_weapon_sprite.texture.get_width())
			/ float(maxi(1, frame_size.x))
		))
	)
	var clamped_index := clampi(
		frame_index,
		0,
		maxi(0, _weapon_animation_frame_count - 1)
	)
	var column := clamped_index % columns
	var row := int(floor(float(clamped_index) / float(columns)))
	_weapon_sprite.region_rect = Rect2(
		Vector2(column * frame_size.x, row * frame_size.y),
		Vector2(float(frame_size.x), float(frame_size.y))
	)

func _weapon_effect_for_state(state: String) -> String:
	match state:
		"EMPTY":
			return GUN_ANIMATION_CATALOG.EFFECT_EMPTY
		"CYCLE":
			return GUN_ANIMATION_CATALOG.EFFECT_CYCLE
	return GUN_ANIMATION_CATALOG.EFFECT_AIM

func _render_command_context() -> void:
	if _command_context_label == null:
		return
	if _snapshot.is_empty():
		_command_context_label.text = ""
		return
	if not _reaction_prompt.is_empty():
		_command_context_label.text = "COMBAT LOG // REACTION"
		return
	if not _snapshot.get("is_player_turn", false):
		_command_context_label.text = "COMBAT LOG // HOSTILE TURN"
		return
	if _snapshot.get("busy", false):
		_command_context_label.text = "COMBAT LOG // RESOLVING"
		return
	var player: Dictionary = _snapshot.get("player", {})
	var distance := absi(
		int(player.get("lane", -1))
		- int(_snapshot.get("enemy", {}).get("lane", -1))
	)
	var page_label := _group_label(_selected_action_group)
	if not _command_menu_path.is_empty():
		page_label += " > " + str(_command_menu_path.back()).to_upper()
	var weapon_id := str(player.get("weapon_id", ""))
	var audio_family := GUN_ANIMATION_CATALOG.audio_family(weapon_id)
	_command_context_label.text = "COMBAT LOG // %s R%02d\n%s" % [
		page_label,
		distance,
		_group_hint(_selected_action_group, audio_family),
	]

func _weapon_state_text(state: String) -> String:
	match state:
		"READY":
			return "STATE // READY"
		"EMPTY":
			return "STATE // EMPTY"
		"CYCLE":
			return "STATE // CYCLE"
	return "STATE // " + state

func _weapon_detail_text(player: Dictionary, weapon: Dictionary) -> String:
	if weapon.is_empty():
		return "NO ACTIVE WEAPON"
	if not bool(player.get("has_firearm", false)):
		return "MELEE // %s" % str(weapon.get("damage_type", ""))
	return "AMMO %02d/%02d  RNG %02d/%02d" % [
		int(weapon.get("current_magazine", 0)),
		int(weapon.get("max_magazine", 0)),
		int(weapon.get("optimal_range", 0)),
		int(weapon.get("effective_range", 0)),
	]

func _load_weapon_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _group_label(group: String) -> String:
	match group:
		ACTION_GROUP_FIREARM:
			return "FIREARM"
		ACTION_GROUP_MOVEMENT:
			return "MOVE"
		ACTION_GROUP_MELEE:
			return "MELEE"
		ACTION_GROUP_FIELD:
			return "FIELD"
		ACTION_GROUP_ITEMS:
			return "ITEMS"
		ACTION_GROUP_REACTION:
			return "REACT"
	return group.to_upper()

func _group_hint(group: String, audio_family: String = "") -> String:
	match group:
		ACTION_GROUP_FIREARM:
			return "Input 1-9 -> VFX Guns_Animation -> SFX " + audio_family
		ACTION_GROUP_MOVEMENT:
			return "Position, recover, or escape."
		ACTION_GROUP_MELEE:
			return "Strike, grapple, push, pull."
		ACTION_GROUP_ITEMS:
			return "Use accessible combat items."
		ACTION_GROUP_REACTION:
			return "Spend guarded AP or decline."
	return "Cover, guard, and field options."

func _fallback_action_group(descriptor: Dictionary) -> String:
	var action := int(descriptor.get("action", -1))
	if action == GameEnums.ActionType.USE_ITEM:
		return ACTION_GROUP_ITEMS
	match action:
		GameEnums.ActionType.SHOOT, GameEnums.ActionType.AIMED_SHOT:
			return ACTION_GROUP_FIREARM
		GameEnums.ActionType.RELOAD, GameEnums.ActionType.CYCLE:
			return ACTION_GROUP_FIREARM
		GameEnums.ActionType.GET_UP, GameEnums.ActionType.MOVE_FORWARD:
			return ACTION_GROUP_MOVEMENT
		GameEnums.ActionType.MOVE_BACKWARD, GameEnums.ActionType.CHARGE:
			return ACTION_GROUP_MOVEMENT
		GameEnums.ActionType.STRIKE, GameEnums.ActionType.GRAPPLE:
			return ACTION_GROUP_MELEE
		GameEnums.ActionType.BREAK, GameEnums.ActionType.PUSH_STAY:
			return ACTION_GROUP_MELEE
		GameEnums.ActionType.PULL_FOLLOW:
			return ACTION_GROUP_MELEE
		GameEnums.ActionType.EXECUTE:
			return ACTION_GROUP_MELEE
	return ACTION_GROUP_FIELD

func _render_feedback() -> void:
	var rows := PackedStringArray()
	for row in _combat_log_rows:
		rows.append(row)
	if rows.is_empty():
		rows.append("Awaiting combat events.")
	if not _reaction_prompt.is_empty():
		var reaction_rows := PackedStringArray()
		for descriptor in _reaction_prompt.get("reactions", []):
			reaction_rows.append("%s AP %02d" % [
				descriptor.get("label", "REACT"),
				int(descriptor.get("cost", 0)),
			])
		if not reaction_rows.is_empty():
			rows.append("REACT: " + " / ".join(reaction_rows))
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
