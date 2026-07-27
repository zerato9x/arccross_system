extends Node2D
class_name CombatLaneHUD

@export var paper_doll_scene: PackedScene

const ACTION_BUTTON_SCENE := preload(
	"res://CombatCore/DuelUI/CombatActionButton.tscn"
)
const GUN_ANIMATION_CATALOG := preload(
	"res://CombatCore/DuelUI/GunAnimationCatalog.gd"
)
const BULLET_TEXTURE := preload("res://Asset/Guns_Animation/Bullet.png")
const ACTION_PANEL_SIZE := Vector2(760.0, 224.0)
const ACTION_BUTTON_SIZE := CombatActionRail.ACTION_BUTTON_SIZE
const ACTION_BUTTON_GAP := CombatActionRail.ACTION_BUTTON_GAP
const GROUP_BUTTON_SIZE := CombatActionRail.GROUP_BUTTON_SIZE
const WEAPON_CARD_SIZE := Vector2(232.0, 168.0)
const TOP_WEAPON_CARD_SIZE := Vector2(158.0, 52.0)
const COMMAND_CONTEXT_SIZE := Vector2(360.0, 196.0)
const COLOR_ACTION_PANEL := Color(0.07, 0.075, 0.06, 0.91)
const COLOR_ACTION_BORDER := Color(0.73, 0.62, 0.45, 0.88)
const COLOR_SHELL_PANEL := Color(0.04, 0.035, 0.025, 0.13)
const COLOR_SHELL_BORDER := Color(0.03, 0.025, 0.018, 0.58)
const COLOR_PORTRAIT_PLATE := Color(0.58, 0.18, 0.15, 0.72)
const COLOR_COMMAND_RAIL := Color(0.08, 0.055, 0.045, 0.36)
const RESOLVE_PRESENTATION_SECONDS := 1.15
const RESULT_PANEL_SIZE := Vector2(620.0, 360.0)
const PROJECTILE_DURATION_SECONDS := 0.28
const FINAL_HEADSHOT_PROJECTILE_DURATION_SECONDS := 0.68
const PROJECTILE_HIT_PAUSE_SECONDS := 0.08
const PROJECTILE_FADE_SECONDS := 0.12
const PROJECTILE_TRACE_LENGTH := 92.0
const FINAL_BLOW_ANIMATION_SPEED := 0.38
const FINAL_BLOW_HOLD_SECONDS := 0.72
const FINAL_BLOW_CORPSE_HOLD_SECONDS := 1.15
const FINAL_HEADSHOT_CAMERA_SPEED := 1.8
const BLOOD_FRAME_COUNT := CombatBloodVfxPresenter.FRAME_COUNT
const BLOOD_FPS := CombatBloodVfxPresenter.FPS
const CAMERA_MODE_NEUTRAL := CombatCameraController.MODE_NEUTRAL
const CAMERA_MODE_BULLET := CombatCameraController.MODE_BULLET
const CAMERA_MODE_FINAL := CombatCameraController.MODE_FINAL
const CAMERA_MODE_RESULTS := CombatCameraController.MODE_RESULTS
const HUD_REFERENCE_SIZE := Vector2(1920.0, 1080.0)
const HUD_MAX_DENSITY_SCALE := 1.45

signal action_requested(action: int, target_limb: int, item_instance_id: String)
signal pass_requested
signal reaction_selected(reaction: int)
signal presentation_queue_drained

var _snapshot: Dictionary = {}
var _reaction_prompt: Dictionary = {}
var _feedback := ""
var _font: SystemFont
var _last_viewport_size := Vector2.ZERO
var _hud_density_scale := 1.0
var _action_rail: CombatActionRail
var _targeted_limb := -1
var _resolve_active := false
var _resolve_focus_side := ""
var _resolve_data: Dictionary = {}
var _resolve_continue_requested := false
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
var _presentation_queue_controller: CombatPresentationQueue
var _sfx_emitter: CombatSfxEmitter
var _camera_controller: CombatCameraController
var _body_status_presenter: CombatBodyStatusPresenter
var _active_projectile_nodes: Array[Node] = []
var _last_shot_event: Dictionary = {}
var _final_blow_sides: Dictionary = {}
var _final_blow_complete_sides: Dictionary = {}
var _impact_sound_play_count := 0

var _round_label: Label
var _active_label: Label
var _player_label: Label
var _enemy_label: Label
@onready var _player_portrait_model: PaperDollModel = %PlayerPortraitPaperDoll
@onready var _enemy_portrait_model: PaperDollModel = %EnemyPortraitPaperDoll
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
var _duel_layout := CombatDuelLayout.new()
@onready var _player_status_label: Label = %PlayerBodyStatusLabel
@onready var _enemy_status_label: Label = %EnemyBodyStatusLabel
@onready var _player_condition_sprite: Sprite2D = %PlayerConditionToken
@onready var _enemy_condition_sprite: Sprite2D = %EnemyConditionToken
@onready var _player_top_label: Label = %PlayerTopStatusLabel
@onready var _enemy_top_label: Label = %EnemyTopStatusLabel
var _player_ranged_card: Dictionary = {}
var _player_melee_card: Dictionary = {}
var _enemy_ranged_card: Dictionary = {}
var _enemy_melee_card: Dictionary = {}
@onready var _weapon_panel_root: Node2D = %WeaponCard
@onready var _weapon_panel_box: Polygon2D = $WeaponCard/WeaponCardBox
@onready var _weapon_panel_border: Line2D = $WeaponCard/WeaponCardBorder
@onready var _weapon_sprite: Sprite2D = $WeaponCard/WeaponSprite
@onready var _weapon_effect_sprite: Sprite2D = $WeaponCard/WeaponEffectSprite
@onready var _weapon_name_label: Label = $WeaponCard/WeaponNameLabel
@onready var _weapon_state_label: Label = $WeaponCard/WeaponStateLabel
@onready var _weapon_detail_label: Label = $WeaponCard/WeaponDetailLabel
@onready var _shared_item_card: RealtimeWeaponCard = %SharedItemCard
@onready var _group_tab_root: Node2D = %ActionGroupTabs
@onready var _command_context_box: Polygon2D = %CommandContextBox
@onready var _command_context_border: Line2D = %CommandContextBorder
@onready var _command_context_rule: Sprite2D = %OfficialCombatLogRule
@onready var _command_context_label: Label = %CommandContextLabel
@onready var _equipment_hover_box: Polygon2D = %HealthEquipmentHoverBox
@onready var _equipment_hover_border: Line2D = %HealthEquipmentHoverBorder
@onready var _equipment_hover_label: Label = %HealthEquipmentHoverLabel
@onready var _resolve_screen_root: Node2D = %ResolveScreen
@onready var _resolve_panel_box: Polygon2D = $ResolveScreen/ResolvePanelBox
@onready var _resolve_panel_border: Line2D = $ResolveScreen/ResolvePanelBorder
@onready var _resolve_title_label: Label = $ResolveScreen/ResolveTitleLabel
@onready var _resolve_body_label: Label = $ResolveScreen/ResolveBodyLabel
@onready var _camera_focus_anchor: Node2D = %CombatCameraFocus
@onready var _projectile_root: Node2D = %ProjectileVFX
@onready var _blood_vfx_root: Node2D = %BloodVFX
@onready var _impact_sound_player: AudioStreamPlayer = %ImpactSoundPlayer

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
	_sfx_emitter = CombatSfxEmitter.new(get_node_or_null("/root/GameEventBus"))
	_presentation_queue_controller = CombatPresentationQueue.new()
	_presentation_queue_controller.name = "PresentationQueue"
	add_child(_presentation_queue_controller)
	_presentation_queue_controller.configure(
		_apply_snapshot,
		_apply_reaction,
		_apply_feedback,
		_apply_presentation_event
	)
	_presentation_queue_controller.presentation_queue_drained.connect(
		func() -> void: presentation_queue_drained.emit()
	)
	_camera_controller = CombatCameraController.new()
	_camera_controller.name = "CameraController"
	add_child(_camera_controller)
	_body_status_presenter = CombatBodyStatusPresenter.new()
	_body_status_presenter.configure(
		_combat_camera,
		_player_command_rail,
		_enemy_status_rail,
		_player_status_label,
		_enemy_status_label,
		_player_condition_sprite,
		_enemy_condition_sprite,
		_player_portrait_model,
		_enemy_portrait_model,
		_player_actor_hud,
		_enemy_actor_hud
	)
	_action_rail = CombatActionRail.new()
	_action_rail.name = "ActionRail"
	add_child(_action_rail)
	_action_rail.configure(
		_action_button_root,
		_group_tab_root,
		_action_panel_box,
		_action_panel_border,
		_action_panel_frame,
		_action_title_label,
		_weapon_panel_root,
		ACTION_BUTTON_SCENE,
		_hud_density_scale
	)
	_action_rail.action_requested.connect(
		func(action: int, target_limb: int, item_instance_id: String) -> void:
			action_requested.emit(action, target_limb, item_instance_id)
	)
	_action_rail.pass_requested.connect(func() -> void: pass_requested.emit())
	_action_rail.reaction_selected.connect(
		func(reaction: int) -> void: reaction_selected.emit(reaction)
	)
	_action_rail.target_limb_focused.connect(_on_target_limb_focused)
	_action_rail.target_limb_unfocused.connect(_on_target_limb_unfocused)
	_action_rail.context_changed.connect(_render_command_context)
	HUDAssetLibrary.connect_scheme_changed(_apply_standardized_hud_theme)
	_bind_legacy_labels()
	_setup_duel_layout_shell()
	_setup_portrait_tokens()
	_setup_camera_rig()
	_setup_presentation_layers()
	_setup_resolve_screen()
	_lane_view.slot_hovered.connect(_on_lane_slot_hovered)
	_lane_view.slot_unhovered.connect(_on_lane_slot_unhovered)
	_grid_hover_card.hide_card()
	_setup_action_panel()
	_apply_standardized_hud_theme()
	_combat_camera.enabled = true
	_combat_camera.make_current()
	_feedback_label.visible = false
	visible = false
	set_process(true)

func _exit_tree() -> void:
	HUDAssetLibrary.disconnect_scheme_changed(_apply_standardized_hud_theme)

func _process(delta: float) -> void:
	if not visible:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size != _last_viewport_size:
		_last_viewport_size = viewport_size
		_layout_for_viewport(viewport_size)
	_update_camera(delta, viewport_size)
	_update_weapon_animation(delta)
	_body_status_presenter.update_condition_animations(delta)
	_update_health_equipment_hover()
	if not _snapshot.is_empty():
		_sync_actor_huds(viewport_size)

func open_hud() -> void:
	visible = true
	_layout_for_viewport(get_viewport_rect().size)
	_update_camera(0.0, get_viewport_rect().size)

func close_hud() -> void:
	visible = false
	_presentation_queue_controller.clear()
	_snapshot.clear()
	_reaction_prompt.clear()
	_feedback = ""
	_combat_log_rows.clear()
	_grid_hover_card.hide_card()
	if _action_rail:
		_action_rail.clear()
	_feedback_label.visible = false
	_resolve_active = false
	_resolve_focus_side = ""
	_resolve_data.clear()
	_resolve_continue_requested = false
	_camera_controller.enter_neutral_mode()
	_camera_controller.resolve_focus_side = ""
	_clear_projectile_nodes()
	_last_shot_event.clear()
	_final_blow_sides.clear()
	_final_blow_complete_sides.clear()
	_set_equipment_hover_visible(false)

func show_snapshot(snapshot: Dictionary) -> void:
	_presentation_queue_controller.show_snapshot(snapshot)

func show_reaction(prompt: Dictionary) -> void:
	_presentation_queue_controller.show_reaction(prompt)

func show_feedback(message: String) -> void:
	_presentation_queue_controller.show_feedback(message)

func show_presentation_event(event: Dictionary) -> void:
	_presentation_queue_controller.show_presentation_event(event)


func wait_for_presentation_idle() -> void:
	await _presentation_queue_controller.wait_for_presentation_idle()

func show_resolve_screen(resolve: Dictionary) -> void:
	visible = true
	_resolve_active = true
	_resolve_focus_side = str(resolve.get("focus_side", "enemy"))
	_resolve_data = resolve.duplicate(true)
	_resolve_continue_requested = false
	_camera_controller.resolve_focus_side = _resolve_focus_side
	_camera_controller.enter_final_mode(_resolve_focus_side)
	_update_resolve_text(_resolve_data, false)
	_update_camera(0.0, get_viewport_rect().size)
	var dead_side := str(resolve.get("dead_side", _resolve_focus_side))
	await get_tree().process_frame
	var final_wait_frames := 180
	while (
		not _final_blow_complete_sides.has(dead_side)
		and _presentation_queue_controller.is_busy()
		and final_wait_frames > 0
	):
		final_wait_frames -= 1
		await get_tree().process_frame
	if not _final_blow_complete_sides.has(dead_side):
		await _play_final_blow(dead_side)
	await get_tree().create_timer(RESOLVE_PRESENTATION_SECONDS).timeout
	_camera_controller.enter_results_mode()
	_update_resolve_text(_resolve_data, true)
	_layout_screen_hud(get_viewport_rect().size)
	while _resolve_active and not _resolve_continue_requested:
		await get_tree().process_frame
	_resolve_active = false
	_resolve_focus_side = ""
	_camera_controller.resolve_focus_side = ""
	_resolve_data.clear()
	_resolve_continue_requested = false
	_camera_controller.enter_neutral_mode()
	_layout_screen_hud(get_viewport_rect().size)

func request_resolve_continue() -> void:
	if _resolve_active:
		_resolve_continue_requested = true

func _apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	if _action_rail:
		_action_rail.unlock_group_selection()
	if not _snapshot.get("reaction_pending", false):
		_reaction_prompt.clear()
	visible = true
	_render()
	if _lane_view and _lane_view.has_active_motion():
		await _lane_view.wait_for_motion_complete()

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
	if _feedback_label != null and _feedback_label.visible:
		HudMotion.soft_pop(self, _feedback_label, HudMotion.RESPONSE_SEC)

func _apply_presentation_event(event: Dictionary) -> void:
	_push_combat_log(_presentation_log_line(event))
	_preview_weapon_event(event)
	var event_type := str(event.get("type", ""))
	if event_type == "shot":
		await _play_shot_event(event)
		return
	if event.get("skip_lane_presentation", false):
		return
	if event_type == "damage" and event.get("was_killed", false):
		await _play_final_blow(str(event.get("side", "")))
		return
	if event_type == "death":
		await _play_final_blow(str(event.get("side", "")))
		return
	if _lane_view:
		if event_type == "action":
			_emit_action_sfx_at_animation_start(event)
		elif event_type == "damage":
			_emit_damage_sfx_at_impact(event)
		await _lane_view.play_presentation_event(event)

func _emit_action_sfx_at_animation_start(event: Dictionary) -> void:
	_sfx_emitter.emit_action_sfx_at_animation_start(event)

func _emit_shot_sfx_at_projectile_start(event: Dictionary) -> void:
	_sfx_emitter.emit_shot_sfx_at_projectile_start(event)

func _emit_damage_sfx_at_impact(event: Dictionary) -> void:
	_sfx_emitter.emit_damage_sfx_at_impact(event, _play_impact_sound)

func _push_combat_log(message: String) -> void:
	if message.strip_edges().is_empty():
		return
	_combat_log_rows.append(message.strip_edges())
	while _combat_log_rows.size() > 7:
		_combat_log_rows.pop_front()

func _presentation_log_line(event: Dictionary) -> String:
	return CombatLogFormatter.presentation_log_line(event)

func _shot_log_line(event: Dictionary) -> String:
	return CombatLogFormatter.shot_log_line(event)

func _damage_log_line(event: Dictionary) -> String:
	return CombatLogFormatter.damage_log_line(event)

func _side_log_label(side: String) -> String:
	return CombatLogFormatter.side_log_label(side)

func _action_log_label(action: int) -> String:
	return CombatLogFormatter.action_log_label(action)

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
	if _shared_item_card:
		_shared_item_card.play_turn_action(
			int(event.get("action", -1)),
			float(event.get("presentation_duration", 0.62))
		)

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
		GameEnums.ActionType.CLEAR_MALFUNCTION:
			return GUN_ANIMATION_CATALOG.EFFECT_RELOAD
	return ""

func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func is_showing_melee_lock() -> bool:
	return _lane_view != null and _lane_view.is_showing_melee_lock()

func _layout_for_viewport(viewport_size: Vector2) -> void:
	var next_density := clampf(
		minf(
			viewport_size.x / HUD_REFERENCE_SIZE.x,
			viewport_size.y / HUD_REFERENCE_SIZE.y
		),
		1.0,
		HUD_MAX_DENSITY_SCALE
	)
	if not is_equal_approx(next_density, _hud_density_scale):
		_hud_density_scale = next_density
		_body_status_presenter.set_density_scale(_hud_density_scale)
		if _action_rail:
			_action_rail.set_density_scale(_hud_density_scale)
		_apply_standardized_hud_theme()
	_lane_view.layout_for_viewport(viewport_size)
	_layout_screen_hud(viewport_size)

func _layout_screen_hud(viewport_size: Vector2) -> void:
	var ui_scale := Vector2.ONE / _camera_zoom_value()
	var content_scale := ui_scale * _hud_density_scale
	_calculate_duel_layout(viewport_size)
	_layout_duel_shell(viewport_size, ui_scale)
	_layout_resolve_screen(viewport_size, ui_scale)

	var context_scale := minf(
		1.0,
		_top_info_rect.size.x / (430.0 * _hud_density_scale)
	)
	var context_position := _top_info_rect.position
	_context_board.global_position = _screen_to_world(
		context_position,
		viewport_size
	)
	_context_board.scale = content_scale * context_scale
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
	# The official B&W pack is an atlas of small pixel elements. Stretching a
	# tiny region across the whole command deck turns it into white scanline soup.
	_action_panel_frame.visible = false
	_action_title_label.global_position = _screen_to_world(
		action_panel_screen_position
			+ Vector2(14.0, 10.0) * _hud_density_scale,
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
	_action_title_label.scale = content_scale
	_action_button_root.scale = content_scale
	_layout_weapon_card(viewport_size, ui_scale)
	_layout_group_tabs(viewport_size, ui_scale)
	_layout_command_context(viewport_size, ui_scale)
	_feedback_label.global_position = _screen_to_world(
		_command_context_rect.position
			+ Vector2(12.0, 46.0) * _hud_density_scale,
		viewport_size
	)
	_feedback_label.scale = content_scale
	_feedback_label.size = Vector2(
		_command_context_rect.size.x / _hud_density_scale - 24.0,
		maxf(
			80.0,
			_command_context_rect.size.y / _hud_density_scale - 58.0
		)
	)
	_body_status_presenter.set_density_scale(_hud_density_scale)
	_body_status_presenter.set_snapshot(_snapshot)
	_body_status_presenter.set_targeted_limb(_targeted_limb)
	_body_status_presenter.set_layout_rects(
		_player_command_rect,
		_enemy_status_rect,
		_player_portrait_rect,
		_enemy_portrait_rect
	)
	_body_status_presenter.layout_panels(viewport_size, ui_scale)
	_layout_top_hud(viewport_size, ui_scale)
	_sync_duel_portraits(viewport_size)

func _calculate_duel_layout(viewport_size: Vector2) -> void:
	if _duel_layout == null:
		_duel_layout = CombatDuelLayout.new()
	_duel_layout.compute(
		viewport_size,
		_hud_density_scale,
		WEAPON_CARD_SIZE,
		COMMAND_CONTEXT_SIZE,
		ACTION_BUTTON_SIZE,
		ACTION_BUTTON_GAP,
		GROUP_BUTTON_SIZE
	)
	_player_top_rect = _duel_layout.player_top_rect
	_enemy_top_rect = _duel_layout.enemy_top_rect
	_player_bottom_rect = _duel_layout.player_bottom_rect
	_enemy_bottom_rect = _duel_layout.enemy_bottom_rect
	_player_portrait_rect = _duel_layout.player_portrait_rect
	_enemy_portrait_rect = _duel_layout.enemy_portrait_rect
	_player_command_rect = _duel_layout.player_command_rect
	_enemy_status_rect = _duel_layout.enemy_status_rect
	_action_rect = _duel_layout.action_rect
	_weapon_card_rect = _duel_layout.weapon_card_rect
	_group_tabs_rect = _duel_layout.group_tabs_rect
	_action_list_rect = _duel_layout.action_list_rect
	_command_context_rect = _duel_layout.command_context_rect
	_top_info_rect = _duel_layout.top_info_rect
	if _action_rail:
		_action_rail.set_layout_rects(_group_tabs_rect, _action_list_rect)

func _layout_duel_shell(viewport_size: Vector2, ui_scale: Vector2) -> void:
	_duel_layout_shell.visible = not _snapshot.is_empty()
	if not _duel_layout_shell.visible:
		return
	_player_top_panel_box.visible = true
	_player_top_panel_border.visible = true
	_enemy_top_panel_box.visible = true
	_enemy_top_panel_border.visible = true
	_place_panel(_player_top_panel_box, _player_top_panel_border, _player_top_rect, viewport_size, ui_scale)
	_place_panel(_enemy_top_panel_box, _enemy_top_panel_border, _enemy_top_rect, viewport_size, ui_scale)
	_place_panel(_player_bottom_panel_box, _player_bottom_panel_border, _player_bottom_rect, viewport_size, ui_scale)
	_place_panel(_enemy_bottom_panel_box, _enemy_bottom_panel_border, _enemy_bottom_rect, viewport_size, ui_scale)
	_place_blood_portrait_plate(
		_player_portrait_plate,
		_player_portrait_border,
		_player_portrait_rect,
		_snapshot.get("player", {}),
		viewport_size,
		ui_scale
	)
	_place_blood_portrait_plate(
		_enemy_portrait_plate,
		_enemy_portrait_border,
		_enemy_portrait_rect,
		_snapshot.get("enemy", {}),
		viewport_size,
		ui_scale
	)
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
	var logical_size := _weapon_card_rect.size / _hud_density_scale
	_weapon_panel_root.scale = ui_scale * _hud_density_scale
	_set_box(_weapon_panel_box, logical_size)
	_set_outline(_weapon_panel_border, logical_size)
	_weapon_sprite.position = Vector2(
		logical_size.x * 0.5,
		logical_size.y * 0.36
	)
	_weapon_effect_sprite.position = _weapon_sprite.position
	_weapon_name_label.position = Vector2(12.0, logical_size.y - 66.0)
	_weapon_name_label.size = Vector2(logical_size.x - 20.0, 20.0)
	_weapon_state_label.position = Vector2(12.0, logical_size.y - 44.0)
	_weapon_state_label.size = Vector2(logical_size.x - 20.0, 20.0)
	_weapon_detail_label.position = Vector2(12.0, logical_size.y - 22.0)
	_weapon_detail_label.size = Vector2(logical_size.x - 20.0, 20.0)
	if _shared_item_card:
		_shared_item_card.position = Vector2.ZERO
		_shared_item_card.scale = Vector2(
			logical_size.x / 360.0,
			logical_size.y / 150.0
		)

func _layout_top_hud(viewport_size: Vector2, ui_scale: Vector2) -> void:
	_layout_top_status_side(
		_player_top_rect,
		_player_top_label,
		_player_ranged_card,
		_player_melee_card,
		_snapshot.get("player", {}),
		"YOU",
		viewport_size,
		ui_scale
	)
	_layout_top_status_side(
		_enemy_top_rect,
		_enemy_top_label,
		_enemy_ranged_card,
		_enemy_melee_card,
		_snapshot.get("enemy", {}),
		"HOSTILE",
		viewport_size,
		ui_scale
	)

func _layout_top_status_side(
	rect: Rect2,
	status_label: Label,
	ranged_card: Dictionary,
	melee_card: Dictionary,
	data: Dictionary,
	_heading: String,
	viewport_size: Vector2,
	ui_scale: Vector2
) -> void:
	if status_label == null:
		return
	var visible_side := not _snapshot.is_empty() and not data.is_empty()
	status_label.visible = visible_side
	_set_weapon_card_visible(ranged_card, visible_side)
	_set_weapon_card_visible(melee_card, visible_side)
	if not visible_side:
		return
	status_label.global_position = _screen_to_world(
		rect.position + Vector2(14.0, 10.0) * _hud_density_scale,
		viewport_size
	)
	status_label.scale = ui_scale * _hud_density_scale
	status_label.size = Vector2(
		rect.size.x / _hud_density_scale - 28.0,
		56.0
	)
	var card_gap := 8.0 * _hud_density_scale
	var card_width := minf(
		TOP_WEAPON_CARD_SIZE.x * _hud_density_scale,
		(
			rect.size.x
			- 28.0 * _hud_density_scale
			- card_gap
		) * 0.5
	)
	var card_height := minf(
		TOP_WEAPON_CARD_SIZE.y * _hud_density_scale,
		maxf(
			48.0 * _hud_density_scale,
			rect.size.y - 88.0 * _hud_density_scale
		)
	)
	var card_y := rect.position.y + 76.0 * _hud_density_scale
	var left_rect := Rect2(
		Vector2(
			rect.position.x + 14.0 * _hud_density_scale,
			card_y
		),
		Vector2(card_width, card_height)
	)
	var right_rect := Rect2(
		Vector2(left_rect.end.x + card_gap, card_y),
		Vector2(card_width, card_height)
	)
	_layout_top_weapon_card(ranged_card, left_rect, viewport_size, ui_scale)
	_layout_top_weapon_card(melee_card, right_rect, viewport_size, ui_scale)

func _layout_top_weapon_card(
	card: Dictionary,
	rect: Rect2,
	viewport_size: Vector2,
	ui_scale: Vector2
) -> void:
	var root := card.get("root") as Node2D
	if root == null:
		return
	root.global_position = _screen_to_world(rect.position, viewport_size)
	root.scale = ui_scale * _hud_density_scale
	var logical_size := rect.size / _hud_density_scale
	var box := card.get("box") as Polygon2D
	if box:
		box.visible = true
		_set_box(box, logical_size)
	var border := card.get("border") as Line2D
	if border:
		border.visible = true
		_set_outline(border, logical_size)
	var sprite := card.get("sprite") as Sprite2D
	if sprite:
		sprite.position = Vector2(24.0, logical_size.y * 0.5)
	var title := card.get("title") as Label
	if title:
		title.position = Vector2(9.0, 6.0)
		title.size = Vector2(logical_size.x - 18.0, 16.0)
	var name_label := card.get("name") as Label
	if name_label:
		name_label.position = Vector2(52.0, 20.0)
		name_label.size = Vector2(
			maxf(44.0, logical_size.x - 58.0),
			16.0
		)
	var detail := card.get("detail") as Label
	if detail:
		detail.position = Vector2(52.0, 36.0)
		detail.size = Vector2(
			maxf(44.0, logical_size.x - 58.0),
			logical_size.y - 36.0
		)

func _set_weapon_card_visible(card: Dictionary, visible_card: bool) -> void:
	var root := card.get("root") as Node2D
	if root:
		root.visible = visible_card

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
	_group_tab_root.scale = ui_scale * _hud_density_scale

func _layout_command_context(viewport_size: Vector2, ui_scale: Vector2) -> void:
	var visible_context := not _snapshot.is_empty()
	_command_context_box.visible = visible_context
	_command_context_border.visible = visible_context
	_command_context_rule.visible = visible_context
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
	CombatHudGeometry.layout_meter_frame(
		_command_context_rule,
		Vector2(
			_command_context_rect.size.x / _hud_density_scale - 24.0,
			8.0
		),
		Color(0.86, 0.82, 0.72, 0.42)
	)
	_command_context_rule.global_position = _screen_to_world(
		_command_context_rect.position
			+ Vector2(12.0, 36.0) * _hud_density_scale,
		viewport_size
	)
	_command_context_rule.scale *= ui_scale * _hud_density_scale
	_command_context_label.global_position = _screen_to_world(
		_command_context_rect.position
			+ Vector2(12.0, 10.0) * _hud_density_scale,
		viewport_size
	)
	_command_context_label.scale = ui_scale * _hud_density_scale
	_command_context_label.size = Vector2(
		_command_context_rect.size.x / _hud_density_scale - 24.0,
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

func _place_blood_portrait_plate(
	plate: Polygon2D,
	border: Line2D,
	rect: Rect2,
	data: Dictionary,
	viewport_size: Vector2,
	ui_scale: Vector2
) -> void:
	var blood_ratio := clampf(
		float(data.get("blood", GameEnums.SCALE_MAX)) / GameEnums.SCALE_MAX,
		0.0,
		1.0
	)
	var fill_height := maxf(4.0, rect.size.y * blood_ratio)
	var fill_rect := Rect2(
		Vector2(0.0, rect.size.y - fill_height),
		Vector2(rect.size.x, fill_height)
	)
	_set_box(plate, fill_rect.size)
	plate.position = fill_rect.position
	_set_outline(border, rect.size)
	var danger := 1.0 - blood_ratio
	plate.color = Color(
		lerpf(0.42, 0.86, danger),
		lerpf(0.10, 0.04, danger),
		lerpf(0.09, 0.06, danger),
		lerpf(0.48, 0.86, danger)
	)
	var origin := _screen_to_world(rect.position, viewport_size)
	plate.global_position = origin + fill_rect.position * ui_scale
	border.global_position = origin
	plate.scale = ui_scale
	border.scale = ui_scale

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
		_render_top_hud()
		_render_actions()
		_render_command_context()
		_render_feedback()
		return
	_lane_view.show_snapshot(_snapshot)
	_context_board.show_snapshot(_snapshot)
	_sync_actor_huds(get_viewport_rect().size)
	_render_weapon_card()
	_render_top_hud()
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
	_action_panel_frame.z_index = 33
	_action_panel_border.z_index = 34
	_action_title_label.z_index = 35
	_action_button_root.z_index = 35
	_action_title_label.text = "ACTIONS"
	_setup_weapon_card()
	_setup_group_tabs()
	_setup_command_context()

func _setup_weapon_card() -> void:
	_weapon_panel_box.color = Color(0.055, 0.05, 0.04, 0.94)
	_weapon_panel_border.default_color = Color(COLOR_ACTION_BORDER, 0.78)
	_weapon_panel_border.width = 1.0
	for legacy_visual in [
		_weapon_panel_box,
		_weapon_panel_border,
		_weapon_sprite,
		_weapon_effect_sprite,
		_weapon_name_label,
		_weapon_state_label,
		_weapon_detail_label,
	]:
		legacy_visual.modulate.a = 0.0

func _setup_group_tabs() -> void:
	pass

func _setup_command_context() -> void:
	_command_context_box.color = Color(0.055, 0.05, 0.04, 0.86)
	_command_context_border.default_color = Color(COLOR_ACTION_BORDER, 0.58)
	_command_context_border.width = 1.0
	_command_context_rule.texture = HUDAssetLibrary.meter_frame_texture("compact")

func _make_deck_label(label_name: String, parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.add_theme_color_override("font_color", HUDAssetLibrary.COLOR_TEXT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_color_override(
		"font_outline_color",
		Color(HUDAssetLibrary.COLOR_PANEL, 0.92)
	)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _make_top_weapon_card(card_name: String) -> Dictionary:
	return _bind_top_weapon_card(get_node(card_name) as Node2D)

func _bind_top_weapon_card(root: Node2D) -> Dictionary:
	return {
		"root": root,
		"box": root.get_node("Box") as Polygon2D,
		"border": root.get_node("Border") as Line2D,
		"sprite": root.get_node("Sprite") as Sprite2D,
		"title": root.get_node("Title") as Label,
		"name": root.get_node("Name") as Label,
		"detail": root.get_node("Detail") as Label,
	}

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
	_body_status_presenter.collect_limb_rows()
	_player_ranged_card = _bind_top_weapon_card(%PlayerRangedWeaponCard)
	_player_melee_card = _bind_top_weapon_card(%PlayerMeleeWeaponCard)
	_enemy_ranged_card = _bind_top_weapon_card(%EnemyRangedWeaponCard)
	_enemy_melee_card = _bind_top_weapon_card(%EnemyMeleeWeaponCard)
	_configure_top_weapon_cards()
	_setup_equipment_hover_card()

func _configure_top_weapon_cards() -> void:
	for card in [
		_player_ranged_card,
		_player_melee_card,
		_enemy_ranged_card,
		_enemy_melee_card,
	]:
		(card.get("box") as Polygon2D).color = Color(
			HUDAssetLibrary.COLOR_PANEL_ALT,
			0.94
		)
		(card.get("border") as Line2D).default_color = Color(
			HUDAssetLibrary.COLOR_BORDER,
			0.92
		)
		(card.get("border") as Line2D).width = 1.0

func _apply_standardized_hud_theme(_scheme_id: String = "") -> void:
	var panel_fill := Color(HUDAssetLibrary.COLOR_PANEL, 0.94)
	var inset_fill := Color(HUDAssetLibrary.COLOR_PANEL_ALT, 0.94)
	var border_color := Color(HUDAssetLibrary.COLOR_BORDER, 0.92)

	for polygon in [
		_player_top_panel_box,
		_enemy_top_panel_box,
		_player_bottom_panel_box,
		_enemy_bottom_panel_box,
	]:
		if polygon:
			polygon.color = panel_fill
	for line in [
		_player_top_panel_border,
		_enemy_top_panel_border,
		_player_bottom_panel_border,
		_enemy_bottom_panel_border,
	]:
		if line:
			line.default_color = border_color

	_action_panel_box.color = panel_fill
	_action_panel_border.default_color = Color(
		HUDAssetLibrary.COLOR_INFO,
		0.94
	)
	_weapon_panel_box.color = inset_fill
	_weapon_panel_border.default_color = border_color
	_command_context_box.color = inset_fill
	_command_context_border.default_color = border_color
	_equipment_hover_box.color = Color(HUDAssetLibrary.COLOR_PANEL, 0.98)
	_equipment_hover_border.default_color = Color(
		HUDAssetLibrary.COLOR_CAUTION,
		0.94
	)
	_resolve_panel_box.color = Color(HUDAssetLibrary.COLOR_PANEL, 0.98)
	_resolve_panel_border.default_color = Color(
		HUDAssetLibrary.COLOR_CAUTION,
		0.96
	)
	_player_portrait_plate.color = Color(
		HUDAssetLibrary.COLOR_TRAVEL,
		0.62
	)
	_enemy_portrait_plate.color = Color(
		HUDAssetLibrary.COLOR_CRITICAL,
		0.62
	)
	_player_portrait_border.default_color = Color(
		HUDAssetLibrary.COLOR_TRAVEL,
		0.92
	)
	_enemy_portrait_border.default_color = Color(
		HUDAssetLibrary.COLOR_CRITICAL,
		0.92
	)
	_configure_top_weapon_cards()

	_apply_combat_label(_action_title_label, 13, "info")
	_apply_combat_label(_command_context_label, 12, "body")
	_apply_combat_label(_feedback_label, 11, "muted")
	_apply_combat_label(_player_status_label, 13, "body")
	_apply_combat_label(_enemy_status_label, 13, "body")
	_apply_combat_label(_player_top_label, 15, "body")
	_apply_combat_label(_enemy_top_label, 15, "body")
	_apply_combat_label(_weapon_name_label, 13, "body")
	_apply_combat_label(_weapon_state_label, 12, "info")
	_apply_combat_label(_weapon_detail_label, 11, "muted")
	_apply_combat_label(_equipment_hover_label, 11, "body")
	_apply_combat_label(_resolve_title_label, 20, "warning")
	_apply_combat_label(_resolve_body_label, 12, "body")

	for card in [
		_player_ranged_card,
		_player_melee_card,
		_enemy_ranged_card,
		_enemy_melee_card,
	]:
		_apply_combat_label(card.get("title") as Label, 10, "muted")
		_apply_combat_label(card.get("name") as Label, 11, "body")
		_apply_combat_label(card.get("detail") as Label, 10, "muted")

	for row in (
		_body_status_presenter.player_status_rows
		+ _body_status_presenter.enemy_status_rows
	):
		_apply_combat_label(row.get("label") as Label, 11, "body")

func _apply_combat_label(
	label: Label,
	font_size: int,
	role: String
) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override(
		"font_color",
		HUDAssetLibrary.COLOR_TEXT
		if role == "body"
		else HUDAssetLibrary.color_for_role(role)
	)
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_color_override(
		"font_outline_color",
		Color(HUDAssetLibrary.COLOR_PANEL, 0.94)
	)

func _setup_equipment_hover_card() -> void:
	_equipment_hover_box.color = Color(0.045, 0.04, 0.032, 0.96)
	_equipment_hover_border.default_color = Color(COLOR_ACTION_BORDER, 0.82)
	_equipment_hover_border.width = 1.0

func _setup_camera_rig() -> void:
	_camera_controller.configure(
		_combat_camera,
		_camera_focus_anchor,
		_lane_view,
		$NeutralVirtualCamera as VirtualCamera2D,
		$BulletVirtualCamera as VirtualCamera2D,
		$FinalBlowVirtualCamera as VirtualCamera2D,
		$ResultsVirtualCamera as VirtualCamera2D
	)

func _setup_presentation_layers() -> void:
	if _impact_sound_player.stream == null:
		_impact_sound_player.stream = GUN_ANIMATION_CATALOG.impact_sound_stream()

func _setup_resolve_screen() -> void:
	_resolve_panel_box.color = Color(0.045, 0.035, 0.025, 0.92)
	_resolve_panel_border.default_color = Color(0.82, 0.67, 0.42, 0.92)
	_resolve_panel_border.width = 2.0
	_set_box(_resolve_panel_box, RESULT_PANEL_SIZE)
	_set_outline(_resolve_panel_border, RESULT_PANEL_SIZE)
	_resolve_screen_root.visible = false

func _layout_resolve_screen(viewport_size: Vector2, ui_scale: Vector2) -> void:
	if _resolve_screen_root == null:
		return
	_resolve_screen_root.visible = _resolve_active
	if not _resolve_active:
		return
	var panel_position := Vector2(
		viewport_size.x * 0.5
			- RESULT_PANEL_SIZE.x * _hud_density_scale * 0.5,
		maxf(22.0 * _hud_density_scale, viewport_size.y * 0.10)
	)
	_resolve_screen_root.global_position = _screen_to_world(
		panel_position,
		viewport_size
	)
	_resolve_screen_root.scale = ui_scale * _hud_density_scale

func _update_resolve_text(resolve: Dictionary, show_results: bool) -> void:
	if _resolve_title_label == null or _resolve_body_label == null:
		return
	_resolve_title_label.text = str(
		resolve.get("title", "COMBAT RESOLVED")
	).to_upper()
	var dead_name := str(resolve.get("dead_name", "HOSTILE"))
	var cause := str(resolve.get("cause", "unknown trauma"))
	if not show_results:
		_resolve_body_label.text = "%s DOWN\nCAUSE // %s" % [
			dead_name.to_upper(),
			cause.to_upper(),
		]
		return

	var rows := PackedStringArray()
	rows.append("%s DOWN" % dead_name.to_upper())
	rows.append("CAUSE // %s" % cause.to_upper())
	rows.append("")
	rows.append("COMBAT LOG")
	for log_line in _combat_log_rows:
		rows.append("  " + log_line)
	rows.append("")
	rows.append("LOOT")
	var loot_names: Array = resolve.get("loot_names", [])
	if loot_names.is_empty():
		rows.append("  NONE")
	else:
		for raw_name in loot_names:
			rows.append("  " + str(raw_name).to_upper())
	rows.append("")
	rows.append("PRESS ENTER / SPACE / CLICK TO CONTINUE")
	_resolve_body_label.text = "\n".join(rows)

func _setup_portrait_tokens() -> void:
	_player_portrait_model.set_backdrop_visible(false)
	_enemy_portrait_model.set_backdrop_visible(false)


func _render_actions() -> void:
	if _action_rail == null:
		return
	_action_rail.render(_snapshot, _reaction_prompt, is_showing_melee_lock())


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

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	if _resolve_active:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
			request_resolve_continue()
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_HOME or event.keycode == KEY_F:
		_reset_camera()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_Q:
		if _action_rail:
			_action_rail.cycle_group(-1)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_E:
		if _action_rail:
			_action_rail.cycle_group(1)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_0:
		if _action_rail and _action_rail.activate_zero():
			get_viewport().set_input_as_handled()
		return
	if event.keycode < KEY_1 or event.keycode > KEY_9:
		return
	var index := int(event.keycode - KEY_1)
	if _action_rail and _action_rail.activate_index(index):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if (
		_resolve_active
		and event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		request_resolve_continue()
		get_viewport().set_input_as_handled()

func _update_camera(delta: float, viewport_size: Vector2) -> void:
	_camera_controller.resolve_focus_side = _resolve_focus_side
	_camera_controller.update(delta, viewport_size)
	_layout_screen_hud(viewport_size)

func _reset_camera() -> void:
	_camera_controller.resolve_focus_side = _resolve_focus_side
	_camera_controller.reset()
	_layout_screen_hud(get_viewport_rect().size)

func _play_shot_event(event: Dictionary) -> void:
	if _lane_view == null or _projectile_root == null:
		return
	_last_shot_event = event.duplicate(true)
	_clear_projectile_nodes()
	var attacker_side := str(event.get("attacker_side", event.get("side", "player")))
	var target_side := str(event.get("target_side", _opposite_side(attacker_side)))
	var origin_lane := int(event.get("origin_lane", -1))
	var target_lane := int(event.get("target_lane", -1))
	var result := str(event.get("result", "miss"))
	var is_final_headshot := _is_final_headshot_event(event)
	var start := _lane_view.get_projectile_anchor_global(attacker_side, origin_lane)
	var end := _shot_end_position(result, attacker_side, target_side, target_lane)

	var trail := Line2D.new()
	trail.name = "BulletTrail"
	trail.width = 1.6
	trail.default_color = Color(1.0, 0.78, 0.38, 0.58)
	trail.texture_mode = Line2D.LINE_TEXTURE_NONE
	trail.points = PackedVector2Array([start, start])
	_projectile_root.add_child(trail)
	_active_projectile_nodes.append(trail)

	var bullet := Sprite2D.new()
	bullet.name = "BulletSprite"
	bullet.texture = BULLET_TEXTURE
	bullet.centered = true
	bullet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bullet.global_position = start
	bullet.rotation = (end - start).angle()
	bullet.scale = Vector2(2.2, 1.15)
	bullet.modulate = Color(1.0, 0.92, 0.62, 0.92)
	_projectile_root.add_child(bullet)
	_active_projectile_nodes.append(bullet)

	_camera_controller.enter_bullet_mode(
		start,
		FINAL_HEADSHOT_CAMERA_SPEED if is_final_headshot else -1.0
	)
	_emit_shot_sfx_at_projectile_start(event)
	var travel_direction := (end - start).normalized()
	var tween := create_tween()
	tween.tween_property(
		bullet,
		"global_position",
		end,
		(
			FINAL_HEADSHOT_PROJECTILE_DURATION_SECONDS
			if is_final_headshot
			else PROJECTILE_DURATION_SECONDS
		)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	while tween.is_valid() and tween.is_running():
		_camera_controller.set_focus_override(bullet.global_position)
		trail.points = _projectile_trace_points(
			start,
			bullet.global_position,
			travel_direction
		)
		await get_tree().process_frame
	_camera_controller.set_focus_override(end)
	trail.points = _projectile_trace_points(start, end, travel_direction)
	bullet.visible = false

	if _shot_result_has_blood(result):
		_drop_projectile_node(trail)
		_play_blood_vfx(end, event)
		_emit_damage_sfx_at_impact(event)
		if event.get("was_killed", false):
			await _play_final_blow(target_side)
		elif _lane_view:
			await _lane_view.play_presentation_event(
				_shot_impact_damage_event(event, target_side)
			)
		await get_tree().create_timer(PROJECTILE_HIT_PAUSE_SECONDS).timeout
	else:
		await get_tree().create_timer(PROJECTILE_HIT_PAUSE_SECONDS).timeout

	if is_instance_valid(trail):
		var fade := create_tween()
		fade.tween_property(
			trail,
			"modulate:a",
			0.0,
			PROJECTILE_FADE_SECONDS
		)
		await fade.finished
	if is_instance_valid(trail):
		_drop_projectile_node(trail)
	if is_instance_valid(bullet):
		_drop_projectile_node(bullet)
	_camera_controller.clear_focus_override()
	if not event.get("was_killed", false):
		_camera_controller.enter_neutral_mode()

func _shot_end_position(
	result: String,
	attacker_side: String,
	target_side: String,
	target_lane: int
) -> Vector2:
	if result in ["hit", "collateral_hit", "shield_block"]:
		return _lane_view.get_projectile_anchor_global(target_side, target_lane)
	if result == "cover_impact":
		return _lane_view.get_slot_center_global(target_lane) + Vector2(0.0, -20.0)
	return _lane_view.get_projectile_miss_anchor_global(attacker_side, target_lane)

func _shot_result_has_blood(result: String) -> bool:
	return result in ["hit", "collateral_hit"]

func _is_final_headshot_event(event: Dictionary) -> bool:
	return (
		event.get("was_killed", false)
		and int(event.get("limb_index", -1)) == GameEnums.LimbRegion.HEAD
	)

func _projectile_trace_points(
	start: Vector2,
	current: Vector2,
	direction: Vector2
) -> PackedVector2Array:
	var travelled := start.distance_to(current)
	if travelled <= 0.1 or direction.length_squared() <= 0.001:
		return PackedVector2Array([start, current])
	var tail_distance := minf(PROJECTILE_TRACE_LENGTH, travelled)
	return PackedVector2Array([
		current - direction * tail_distance,
		current,
	])

func _shot_impact_damage_event(event: Dictionary, target_side: String) -> Dictionary:
	var impact := event.duplicate(true)
	impact["type"] = "damage"
	impact["side"] = target_side
	impact["skip_lane_presentation"] = false
	return impact

func _play_final_blow(side: String) -> void:
	if side.is_empty():
		return
	if _final_blow_complete_sides.has(side):
		_camera_controller.enter_final_mode(side)
		return
	if _final_blow_sides.has(side):
		var wait_frames := 240
		while (
			not _final_blow_complete_sides.has(side)
			and wait_frames > 0
		):
			wait_frames -= 1
			await get_tree().process_frame
		return
	_final_blow_sides[side] = true
	_resolve_focus_side = side
	_camera_controller.enter_final_mode(side)
	_update_camera(0.0, get_viewport_rect().size)
	if _lane_view:
		await _lane_view.play_presentation_event({
			"side": side,
			"type": "final_blow",
			"animation_speed": FINAL_BLOW_ANIMATION_SPEED,
		})
		await get_tree().create_timer(FINAL_BLOW_CORPSE_HOLD_SECONDS).timeout
	else:
		await get_tree().create_timer(FINAL_BLOW_HOLD_SECONDS).timeout
	_final_blow_complete_sides[side] = true

func _play_impact_sound() -> void:
	if _impact_sound_player == null or GUN_ANIMATION_CATALOG.impact_sound_stream() == null:
		return
	_impact_sound_play_count += 1
	_impact_sound_player.stop()
	_impact_sound_player.play()

func _play_blood_vfx(position: Vector2, event: Dictionary) -> void:
	if _blood_vfx_root == null:
		return
	var variant := CombatBloodVfxPresenter.variant_for_event(event)
	var sprite := Sprite2D.new()
	sprite.name = "BloodImpact"
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.global_position = position
	sprite.scale = Vector2.ONE * 2.2
	_blood_vfx_root.add_child(sprite)
	_active_projectile_nodes.append(sprite)

	for frame_index in range(CombatBloodVfxPresenter.frame_count(variant)):
		if not is_instance_valid(sprite):
			return
		var path := CombatBloodVfxPresenter.frame_path(variant, frame_index)
		var texture := load(path) as Texture2D
		if texture:
			sprite.texture = texture
		await get_tree().create_timer(1.0 / BLOOD_FPS).timeout
	_drop_projectile_node(sprite)

func _blood_variant(event: Dictionary) -> int:
	return CombatBloodVfxPresenter.variant_for_event(event)

func _clear_projectile_nodes() -> void:
	for node in _active_projectile_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_active_projectile_nodes.clear()

func _drop_projectile_node(node: Node) -> void:
	if node == null:
		return
	_active_projectile_nodes.erase(node)
	if is_instance_valid(node):
		node.queue_free()

func _opposite_side(side: String) -> String:
	return "enemy" if side == "player" else "player"

func has_projectile_vfx() -> bool:
	for node in _active_projectile_nodes:
		if is_instance_valid(node) and node.name == "BulletTrail":
			return true
	return false

func has_blood_vfx() -> bool:
	for node in _active_projectile_nodes:
		if is_instance_valid(node) and node.name == "BloodImpact":
			return true
	return false

func _screen_to_world(screen_position: Vector2, viewport_size: Vector2) -> Vector2:
	return CombatHudGeometry.screen_to_world(_combat_camera, screen_position, viewport_size)

func _camera_zoom_value() -> float:
	return _camera_controller.zoom_value()

func get_camera_zoom_value() -> float:
	return _camera_zoom_value()

func is_resolve_screen_visible() -> bool:
	return _resolve_active

func is_result_overlay_waiting() -> bool:
	return (
		_resolve_active
		and _camera_controller.camera_mode == CAMERA_MODE_RESULTS
	)

func get_resolve_focus_side() -> String:
	return _resolve_focus_side

func get_last_shot_event() -> Dictionary:
	return _last_shot_event.duplicate(true)

func _sync_actor_huds(viewport_size: Vector2) -> void:
	_body_status_presenter.set_snapshot(_snapshot)
	_body_status_presenter.set_layout_rects(
		_player_command_rect,
		_enemy_status_rect,
		_player_portrait_rect,
		_enemy_portrait_rect
	)
	_body_status_presenter.sync_actor_huds(viewport_size)

func _sync_duel_portraits(viewport_size: Vector2) -> void:
	_body_status_presenter.set_snapshot(_snapshot)
	_body_status_presenter.set_layout_rects(
		_player_command_rect,
		_enemy_status_rect,
		_player_portrait_rect,
		_enemy_portrait_rect
	)
	_body_status_presenter.sync_duel_portraits(viewport_size)

func _update_health_equipment_hover() -> void:
	if (
		_snapshot.is_empty()
		or _equipment_hover_box == null
		or _equipment_hover_border == null
		or _equipment_hover_label == null
	):
		_set_equipment_hover_visible(false)
		return
	var mouse_position := get_viewport().get_mouse_position()
	var heading := ""
	var data := {}
	if (
		_player_bottom_rect.has_point(mouse_position)
		or _player_command_rect.has_point(mouse_position)
		or _player_portrait_rect.has_point(mouse_position)
	):
		heading = "YOU"
		data = _snapshot.get("player", {})
	elif (
		_enemy_bottom_rect.has_point(mouse_position)
		or _enemy_status_rect.has_point(mouse_position)
		or _enemy_portrait_rect.has_point(mouse_position)
	):
		heading = "HOSTILE"
		data = _snapshot.get("enemy", {})
	else:
		_set_equipment_hover_visible(false)
		return
	if data.is_empty():
		_set_equipment_hover_visible(false)
		return
	var equipment: Array = data.get("equipment", [])
	var logical_box_size := Vector2(
		320.0,
		clampf(106.0 + float(equipment.size()) * 16.0, 132.0, 260.0)
	)
	var box_size := logical_box_size * _hud_density_scale
	var viewport_size := get_viewport_rect().size
	var screen_position := (
		mouse_position
		+ Vector2(18.0, 18.0) * _hud_density_scale
	)
	screen_position.x = clampf(
		screen_position.x,
		12.0,
		maxf(12.0, viewport_size.x - box_size.x - 12.0)
	)
	screen_position.y = clampf(
		screen_position.y,
		12.0,
		maxf(12.0, viewport_size.y - box_size.y - 12.0)
	)
	var ui_scale := Vector2.ONE / _camera_zoom_value()
	_set_box(_equipment_hover_box, box_size)
	_set_outline(_equipment_hover_border, box_size)
	_equipment_hover_box.global_position = _screen_to_world(
		screen_position,
		viewport_size
	)
	_equipment_hover_border.global_position = _equipment_hover_box.global_position
	_equipment_hover_label.global_position = _screen_to_world(
		screen_position
			+ Vector2(12.0, 10.0) * _hud_density_scale,
		viewport_size
	)
	_equipment_hover_box.scale = ui_scale
	_equipment_hover_border.scale = ui_scale
	_equipment_hover_label.scale = ui_scale * _hud_density_scale
	_equipment_hover_label.size = Vector2(
		logical_box_size.x - 24.0,
		logical_box_size.y - 20.0
	)
	_equipment_hover_label.text = _equipment_hover_text(data, heading)
	_set_equipment_hover_visible(true)

func _set_equipment_hover_visible(show_hover: bool) -> void:
	if _equipment_hover_box:
		_equipment_hover_box.visible = show_hover
	if _equipment_hover_border:
		_equipment_hover_border.visible = show_hover
	if _equipment_hover_label:
		_equipment_hover_label.visible = show_hover

func _equipment_hover_text(data: Dictionary, heading: String) -> String:
	var rows := PackedStringArray()
	rows.append("%s EQUIPMENT" % heading)
	rows.append("RANGED  %s" % _equipment_weapon_line(data.get("ranged_weapon", {})))
	rows.append("MELEE   %s" % _equipment_weapon_line(data.get("melee_weapon", {})))
	rows.append("GEAR")
	var equipment: Array = data.get("equipment", [])
	if equipment.is_empty():
		rows.append("  NONE")
	else:
		var count := 0
		for raw_descriptor in equipment:
			var descriptor: Dictionary = raw_descriptor
			rows.append("  %s  %s" % [
				_equipment_slot_label(int(descriptor.get("equipment_slot", -1))),
				str(
					descriptor.get(
						"display_name",
						descriptor.get("name", "ITEM")
					)
				).to_upper(),
			])
			count += 1
			if count >= 8:
				if equipment.size() > count:
					rows.append("  +%d MORE" % (equipment.size() - count))
				break
	return "\n".join(rows)

func _equipment_weapon_line(weapon: Dictionary) -> String:
	if weapon.is_empty():
		return "NONE"
	return str(weapon.get("display_name", weapon.get("name", "WEAPON"))).to_upper()

func _equipment_slot_label(slot: int) -> String:
	var names := GameEnums.EquipmentSlot.keys()
	if slot >= 0 and slot < names.size():
		return str(names[slot]).replace("_", " ")
	return "SLOT"

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
	_weapon_panel_root.visible = not _snapshot.is_empty()
	if _snapshot.is_empty():
		return
	var locked_in_melee := is_showing_melee_lock()
	var weapon: Dictionary = (
		player.get("melee_weapon", {})
		if locked_in_melee
		else player.get("active_weapon", {})
	)
	var weapon_name := "UNARMED"
	var weapon_state := "READY"
	var weapon_id := ""
	var sprite_path := ""
	if locked_in_melee:
		if not weapon.is_empty():
			weapon_name = str(weapon.get("display_name", "MELEE")).to_upper()
			weapon_state = str(weapon.get("state", "READY")).to_upper()
			weapon_id = str(weapon.get("id", ""))
			sprite_path = str(weapon.get("sprite_path", ""))
	else:
		weapon_name = str(player.get("weapon", "UNARMED")).to_upper()
		weapon_state = str(player.get("weapon_state", "UNARMED")).to_upper()
		weapon_id = str(player.get("weapon_id", ""))
		sprite_path = str(player.get("weapon_sprite_path", ""))
	_weapon_name_label.text = weapon_name
	_weapon_state_label.text = _weapon_state_text(weapon_state)
	var detail_text := _weapon_detail_text(player, weapon)
	if locked_in_melee:
		detail_text = (
			_weapon_slot_detail(weapon, "MELEE")
			if not weapon.is_empty()
			else "MELEE // UNARMED"
		)
	_weapon_detail_label.text = detail_text
	if _shared_item_card:
		_shared_item_card.show_descriptor(
			weapon,
			not locked_in_melee and not weapon.is_empty()
		)
	var effect := (
		_weapon_preview_effect
		if not _weapon_preview_effect.is_empty()
		else _weapon_effect_for_state(weapon_state)
	)
	var animation_texture: Texture2D = null
	var effect_texture: Texture2D = null
	if bool(player.get("has_firearm", false)) and not locked_in_melee:
		animation_texture = GUN_ANIMATION_CATALOG.texture(weapon_id, effect)
		effect_texture = GUN_ANIMATION_CATALOG.effect_texture(weapon_id, effect)
	_weapon_sprite.texture = (
		animation_texture
		if animation_texture != null
		else _load_weapon_texture(sprite_path)
	)
	_weapon_sprite.visible = _weapon_sprite.texture != null
	if _weapon_sprite.texture == null:
		_weapon_sprite.region_enabled = false
		_clear_weapon_effect_sprite()
		_weapon_animation_key = ""
		_weapon_animation_playing = false
		_weapon_animation_frame_count = 1
		return
	var frame_size := Vector2i(
		_weapon_sprite.texture.get_width(),
		_weapon_sprite.texture.get_height()
	)
	if animation_texture != null:
		frame_size = _configure_weapon_sprite_sheet(
			_weapon_sprite.texture,
			weapon_id,
			effect
		)
		_configure_weapon_effect_sprite(
			effect_texture,
			weapon_id,
			effect,
			frame_size
		)
	else:
		_weapon_sprite.region_enabled = false
		_clear_weapon_effect_sprite()
		_weapon_animation_key = ""
		_weapon_animation_playing = false
		_weapon_animation_frame_count = 1
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
	_weapon_effect_sprite.scale = _weapon_sprite.scale

func _render_top_hud() -> void:
	if _snapshot.is_empty():
		if _player_top_label:
			_player_top_label.visible = false
		if _enemy_top_label:
			_enemy_top_label.visible = false
		for card in [
			_player_ranged_card,
			_player_melee_card,
			_enemy_ranged_card,
			_enemy_melee_card,
		]:
			_set_weapon_card_visible(card, false)
		return
	var player: Dictionary = _snapshot.get("player", {})
	var enemy: Dictionary = _snapshot.get("enemy", {})
	if _player_top_label:
		_player_top_label.text = _top_status_text(player, "YOU")
	if _enemy_top_label:
		_enemy_top_label.text = _top_status_text(enemy, "HOSTILE")
	_render_top_weapon_card(_player_ranged_card, player.get("ranged_weapon", {}), "RANGED")
	_render_top_weapon_card(_player_melee_card, player.get("melee_weapon", {}), "MELEE")
	_render_top_weapon_card(_enemy_ranged_card, enemy.get("ranged_weapon", {}), "RANGED")
	_render_top_weapon_card(_enemy_melee_card, enemy.get("melee_weapon", {}), "MELEE")

func _top_status_text(data: Dictionary, heading: String) -> String:
	if data.is_empty():
		return heading + " // NO SIGNAL"
	var enemy: Dictionary = _snapshot.get("enemy", {})
	var player: Dictionary = _snapshot.get("player", {})
	var range_text := "--"
	if not enemy.is_empty() and not player.is_empty():
		range_text = "%02d" % absi(
			int(player.get("lane", -1))
			- int(enemy.get("lane", -1))
		)
	var active := " *" if data.get("is_active", false) else ""
	var ap_text := (
		"%02d" % int(_snapshot.get("ap", 0))
		if data.get("is_active", false)
		else "--"
	)
	return (
		"%s%s   AP %s   RES %02d\n"
		+ "BLOOD %04.1f   STANCE %02d\n"
		+ "LANE %02d   RANGE %s"
	) % [
		heading,
		active,
		ap_text,
		int(data.get("reserved_ap", 0)),
		float(data.get("blood", 0.0)),
		int(data.get("stance", 0)),
		int(data.get("lane", -1)),
		range_text,
	]

func _render_top_weapon_card(card: Dictionary, weapon: Dictionary, slot_label: String) -> void:
	var root := card.get("root") as Node2D
	if root == null:
		return
	var title := card.get("title") as Label
	var name_label := card.get("name") as Label
	var detail := card.get("detail") as Label
	var sprite := card.get("sprite") as Sprite2D
	if title:
		title.text = slot_label
	if weapon.is_empty():
		if name_label:
			name_label.text = "UNARMED" if slot_label == "MELEE" else "NONE"
		if detail:
			detail.text = "NO SLOT WEAPON"
		if sprite:
			sprite.texture = null
			sprite.visible = false
		return
	if name_label:
		name_label.text = str(weapon.get("display_name", "WEAPON")).to_upper()
	if detail:
		detail.text = _weapon_slot_detail(weapon, slot_label)
	if sprite:
		sprite.texture = _load_weapon_texture(str(weapon.get("sprite_path", "")))
		sprite.visible = sprite.texture != null
		if sprite.texture:
			sprite.region_enabled = false
			var texture_size := Vector2(
				float(sprite.texture.get_width()),
				float(sprite.texture.get_height())
			)
			var max_size := Vector2(48.0, 42.0)
			var scale_factor := minf(
				max_size.x / maxf(1.0, texture_size.x),
				max_size.y / maxf(1.0, texture_size.y)
			)
			sprite.scale = Vector2.ONE * scale_factor

func _weapon_slot_detail(weapon: Dictionary, slot_label: String) -> String:
	if slot_label == "RANGED":
		var state := str(weapon.get("state", "READY"))
		return "AMMO %02d/%02d\nRANGE %02d-%02d%s" % [
			int(weapon.get("current_magazine", 0)),
			int(weapon.get("max_magazine", 0)),
			int(weapon.get("optimal_range", 0)),
			int(weapon.get("effective_range", 0)),
			(" " + state) if state != "READY" else "",
		]
	var damage_type := "DMG"
	var damage_index := int(weapon.get("damage_type", GameEnums.DamageType.BLUNT))
	if damage_index >= 0 and damage_index < GameEnums.DamageType.keys().size():
		damage_type = str(GameEnums.DamageType.keys()[damage_index])
	return "%s\nDMG %02.0f STN %02.0f PEN %02.0f" % [
		damage_type,
		float(weapon.get("flesh_damage", 0.0)),
		float(weapon.get("stance_damage", 0.0)),
		float(weapon.get("armor_penetration", 0.0)),
	]

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

func _configure_weapon_effect_sprite(
	texture: Texture2D,
	weapon_id: String,
	effect: String,
	base_frame_size: Vector2i
) -> void:
	if texture == null:
		_clear_weapon_effect_sprite()
		return
	var frame_spec := GUN_ANIMATION_CATALOG.effect_frame_spec(weapon_id, effect)
	var frame_size := _weapon_frame_size(texture, frame_spec)
	var frame_count := _weapon_frame_count(texture, frame_size)
	if frame_size != base_frame_size or frame_count != _weapon_animation_frame_count:
		_clear_weapon_effect_sprite()
		push_warning(
			"Weapon effect sheet does not align with its base animation: %s %s"
			% [weapon_id, effect]
		)
		return
	_weapon_effect_sprite.texture = texture
	_weapon_effect_sprite.visible = true
	_weapon_effect_sprite.region_enabled = true
	_weapon_effect_sprite.hframes = 1
	_weapon_effect_sprite.vframes = 1
	_set_weapon_animation_frame(_current_weapon_frame_index())

func _clear_weapon_effect_sprite() -> void:
	_weapon_effect_sprite.texture = null
	_weapon_effect_sprite.visible = false
	_weapon_effect_sprite.region_enabled = false

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
	if _weapon_effect_sprite.visible and _weapon_effect_sprite.texture != null:
		var effect_columns := maxi(
			1,
			int(floor(
				float(_weapon_effect_sprite.texture.get_width())
				/ float(maxi(1, frame_size.x))
			))
		)
		var effect_column := clamped_index % effect_columns
		var effect_row := int(floor(float(clamped_index) / float(effect_columns)))
		_weapon_effect_sprite.region_rect = Rect2(
			Vector2(effect_column * frame_size.x, effect_row * frame_size.y),
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
	var selected_group := (
		_action_rail.get_selected_action_group()
		if _action_rail
		else CombatActionRail.ACTION_GROUP_FIELD
	)
	var menu_path: Array[String] = (
		_action_rail.get_command_menu_path()
		if _action_rail
		else []
	)
	var page_label := (
		_action_rail.group_label(selected_group)
		if _action_rail
		else selected_group.to_upper()
	)
	if not menu_path.is_empty():
		page_label += " > " + str(menu_path.back()).to_upper()
	var weapon_id := str(player.get("weapon_id", ""))
	var audio_family := GUN_ANIMATION_CATALOG.audio_family(weapon_id)
	var hint := (
		_action_rail.group_hint(selected_group, audio_family)
		if _action_rail
		else ""
	)
	_command_context_label.text = "COMBAT LOG // %s R%02d\n%s" % [
		page_label,
		distance,
		hint,
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
	return CombatHudGeometry.compact_number(value)

func _set_box(polygon: Polygon2D, box_size: Vector2) -> void:
	CombatHudGeometry.set_box(polygon, box_size)

func _set_outline(line: Line2D, box_size: Vector2) -> void:
	CombatHudGeometry.set_outline(line, box_size)
