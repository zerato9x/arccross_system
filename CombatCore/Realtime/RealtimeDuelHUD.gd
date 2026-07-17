extends Node2D
class_name RealtimeDuelHUD

signal resolve_continue_requested

const MOVE_INITIAL_REPEAT := 1.0
const MOVE_REPEAT := 0.82
const BULLET_TEXTURE := preload("res://Asset/Guns_Animation/Bullet.png")
const BLOOD_TEXTURE := preload("res://Asset/VFX/BLOOD VFX/1/1_000.png")

@onready var lane_view: CombatLaneView = %CombatLaneView
@onready var ui_root: Control = %UIRoot
@onready var combat_camera: CinematicCamera2D = %CombatCamera
@onready var camera_focus: Node2D = %CameraFocus
@onready var wide_camera: VirtualCamera2D = %WideCamera
@onready var lock_camera: VirtualCamera2D = %LockCamera
@onready var player_panel: RealtimeActorPanel = %PlayerActorPanel
@onready var enemy_panel: RealtimeActorPanel = %EnemyActorPanel
@onready var player_weapon_card: RealtimeWeaponCard = %PlayerWeaponCard
@onready var enemy_weapon_card: RealtimeWeaponCard = %EnemyWeaponCard
@onready var intent_label: Label = %IntentLabel
@onready var phase_label: Label = %PhaseLabel
@onready var timeline_bar: ProgressBar = %TimelineBar
@onready var impact_marker: ColorRect = %ImpactMarker
@onready var hint_label: Label = %HintLabel
@onready var feedback_label: Label = %FeedbackLabel
@onready var context_label: Label = %ContextLabel
@onready var aim_bar: ProgressBar = %AimBar
@onready var combo_label: Label = %ComboLabel
@onready var resolve_overlay: Control = %ResolveOverlay
@onready var resolve_title: Label = %ResolveTitle
@onready var resolve_detail: Label = %ResolveDetail
@onready var resolve_body_report: Label = %ResolveBodyReport
@onready var resolve_stats: Label = %ResolveStats
@onready var presentation_root: Node2D = %PresentationRoot
@onready var readability_effects: DuelReadabilityEffects = %DuelReadabilityEffects

var runtime: RealtimeDuelRuntime
var player_core: HumanoidCore
var _snapshot: Dictionary = {}
var _held_away := false
var _held_toward := false
var _away_repeat := 0.0
var _toward_repeat := 0.0
var _feedback_time := 0.0
var _resolve_focus_side := ""
var _impact_tween: Tween
var _active_timeline: Dictionary = {}
var _active_timeline_started := 0.0

func _ready() -> void:
	visible = false
	resolve_overlay.visible = false
	aim_bar.visible = false
	combat_camera.follow_node = camera_focus
	combat_camera.virtual_camera = wide_camera
	combat_camera.enabled = false
	lane_view.layout_for_viewport(get_viewport_rect().size)
	_layout_ui_root()
	_layout_camera_for_viewport()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	hint_label.text = "A / D  MOVE    //    LMB  STRIKE / FIRE    //    RMB  HEAVY / AIM\nSPACE  BLOCK / PARRY    //    R  SERVICE WEAPON"

func configure(duel_runtime: RealtimeDuelRuntime, player: HumanoidCore) -> void:
	runtime = duel_runtime
	player_core = player
	lane_view.configure_realtime_pacing(1.0)
	if not runtime.snapshot_changed.is_connected(show_snapshot):
		runtime.snapshot_changed.connect(show_snapshot)
	if not runtime.presentation_event.is_connected(show_presentation_event):
		runtime.presentation_event.connect(show_presentation_event)
	if not runtime.feedback.is_connected(show_feedback):
		runtime.feedback.connect(show_feedback)
	show_snapshot(runtime.get_snapshot())

func open_hud() -> void:
	combat_camera.enabled = true
	combat_camera.make_current()
	visible = true
	set_process(true)
	set_process_unhandled_input(true)

func close_hud() -> void:
	_held_away = false
	_held_toward = false
	set_process_unhandled_input(false)
	combat_camera.enabled = false
	visible = false

func show_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	lane_view.show_snapshot(_snapshot)
	var player: Dictionary = _snapshot.get("player", {})
	var enemy: Dictionary = _snapshot.get("enemy", {})
	player_panel.show_actor(player)
	enemy_panel.show_actor(enemy)
	player_weapon_card.show_actor_weapon(player)
	enemy_weapon_card.show_actor_weapon(enemy)
	aim_bar.visible = bool(player.get("aiming", false))
	aim_bar.value = float(player.get("aim_progress", 0.0)) * 100.0
	var combo_step := int(player.get("combo_step", 0))
	combo_label.text = "COMBO CHAIN  %d / 3" % combo_step if combo_step > 0 else ""
	if float(player.get("follow_window", 0.0)) > 0.0:
		combo_label.text = "FOLLOW WINDOW  //  D TO CHASE  //  LMB TO SHOOT  //  %.1fs" % float(player.get("follow_window", 0.0))
	context_label.text = _lane_context(player)
	_update_camera()

func show_presentation_event(event: Dictionary) -> void:
	lane_view.show_realtime_event(event)
	var event_type := str(event.get("type", ""))
	if event_type == "action_timeline":
		_start_timeline(event)
		var side := str(event.get("side", ""))
		var card := player_weapon_card if side == "player" else enemy_weapon_card
		card.play_action(int(event.get("action", GameEnums.DuelActionType.NONE)), float(event.get("duration", 1.0)))
		if int(event.get("action", GameEnums.DuelActionType.NONE)) in [GameEnums.DuelActionType.BLIND_FIRE, GameEnums.DuelActionType.AIMED_FIRE]:
			_play_projectile_timeline(event)
		return
	readability_effects.show_event(event, bool(_snapshot.get("is_melee_locked", false)))
	match event_type:
		"shot":
			_play_shot_impact(event)
		"parry":
			show_feedback("PARRY // attacker staggered")
			_play_camera_impact(2.5, 0.12)
		"block":
			show_feedback("BLOCK // impact absorbed")
		"heavy_cancel":
			show_feedback("HEAVY FEINT // 1 AP committed")
		"damage":
			var source := str(event.get("source", ""))
			if source in ["heavy", "combo_finisher"]:
				_play_camera_impact(2.0 if source == "heavy" else 3.5, 0.14)

func show_feedback(message: String) -> void:
	feedback_label.text = message
	_feedback_time = 1.8

func show_resolve_screen(data: Dictionary) -> void:
	_resolve_focus_side = str(data.get("dead_side", data.get("focus_side", "")))
	resolve_title.text = str(data.get("title", "DUEL RESOLVED"))
	resolve_detail.text = "%s\n%s" % [
		str(data.get("result", data.get("dead_name", "Combatant"))),
		str(data.get("cause", "The lane has made its ruling.")),
	]
	var snapshot := runtime.get_snapshot() if runtime != null else _snapshot
	resolve_body_report.text = _resolve_body_report(snapshot)
	resolve_stats.text = "DURATION  //  %.1f SEC    LOOT DROPPED  //  %d\nCombat simulation is halted. Continue when you are finished reading the damage report." % [
		float(snapshot.get("elapsed", 0.0)),
		int(data.get("loot_count", 0)),
	]
	resolve_overlay.visible = true
	await resolve_continue_requested
	resolve_overlay.visible = false

func play_final_blow(side: String) -> void:
	combat_camera.virtual_camera = lock_camera
	combat_camera.transition_speed = 1.4
	await lane_view.play_presentation_event({"type": "final_blow", "side": side, "animation_speed": 0.42})

func request_resolve_continue() -> void:
	if resolve_overlay.visible:
		resolve_continue_requested.emit()

func is_resolve_screen_visible() -> bool:
	return resolve_overlay.visible

func is_result_overlay_waiting() -> bool:
	return resolve_overlay.visible

func get_resolve_focus_side() -> String:
	return _resolve_focus_side

func get_camera_zoom_value() -> float:
	return combat_camera.zoom.x

func _process(delta: float) -> void:
	if not visible or runtime == null or player_core == null:
		return
	if _feedback_time > 0.0:
		_feedback_time -= delta
		if _feedback_time <= 0.0:
			feedback_label.text = ""
	_process_move_repeat(delta)
	_process_timeline()
	_update_camera()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or runtime == null or player_core == null:
		return
	if resolve_overlay.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			request_resolve_continue()
		elif event is InputEventMouseButton and event.pressed:
			request_resolve_continue()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			runtime.request_intent(player_core, GameEnums.DuelIntent.FIRE)
			get_viewport().set_input_as_handled()
		elif mouse.button_index == MOUSE_BUTTON_RIGHT:
			if mouse.pressed:
				if bool(_snapshot.get("is_melee_locked", false)):
					runtime.request_intent(player_core, GameEnums.DuelIntent.HEAVY_ATTACK)
				else:
					runtime.request_intent(player_core, GameEnums.DuelIntent.AIM_START)
			else:
				runtime.request_intent(player_core, GameEnums.DuelIntent.AIM_CANCEL)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key := event as InputEventKey
		match key.physical_keycode:
			KEY_A:
				_set_move_hold(false, key.pressed and not key.echo)
				if not key.pressed:
					_held_away = false
			KEY_D:
				_set_move_hold(true, key.pressed and not key.echo)
				if not key.pressed:
					_held_toward = false
			KEY_SPACE:
				if key.pressed and not key.echo:
					runtime.request_intent(player_core, GameEnums.DuelIntent.GUARD)
			KEY_R:
				if key.pressed and not key.echo:
					runtime.request_intent(player_core, GameEnums.DuelIntent.RELOAD_OR_CYCLE)

func _set_move_hold(toward: bool, pressed: bool) -> void:
	if not pressed:
		return
	if toward:
		_held_toward = true
		_toward_repeat = MOVE_INITIAL_REPEAT
		runtime.request_intent(player_core, GameEnums.DuelIntent.MOVE_TOWARD)
	else:
		_held_away = true
		_away_repeat = MOVE_INITIAL_REPEAT
		runtime.request_intent(player_core, GameEnums.DuelIntent.MOVE_AWAY)

func _process_move_repeat(delta: float) -> void:
	if _held_toward:
		_toward_repeat -= delta
		if _toward_repeat <= 0.0:
			_toward_repeat = MOVE_REPEAT
			runtime.request_intent(player_core, GameEnums.DuelIntent.MOVE_TOWARD)
	if _held_away:
		_away_repeat -= delta
		if _away_repeat <= 0.0:
			_away_repeat = MOVE_REPEAT
			runtime.request_intent(player_core, GameEnums.DuelIntent.MOVE_AWAY)

func _start_timeline(event: Dictionary) -> void:
	var incoming_side := str(event.get("side", ""))
	if not _active_timeline.is_empty() and incoming_side == "player" and str(_active_timeline.get("side", "")) == "enemy":
		return
	_active_timeline = event.duplicate()
	_active_timeline_started = Time.get_ticks_msec() / 1000.0
	var action := int(event.get("action", GameEnums.DuelActionType.NONE))
	var prefix := "INCOMING" if incoming_side == "enemy" else "YOUR ACTION"
	intent_label.text = "%s  //  %s" % [prefix, _action_name(action)]
	intent_label.modulate = Color(1.0, 0.42, 0.3) if incoming_side == "enemy" else Color(0.45, 0.85, 1.0)
	timeline_bar.max_value = maxf(0.05, float(event.get("duration", 1.0)))
	timeline_bar.value = 0.0
	var impact_ratio := clampf(float(event.get("impact_time", 0.5)) / timeline_bar.max_value, 0.0, 1.0)
	impact_marker.position.x = timeline_bar.position.x + timeline_bar.size.x * impact_ratio - 2.0
	impact_marker.visible = true

func _process_timeline() -> void:
	if _active_timeline.is_empty():
		intent_label.text = "DUEL READOUT // READY"
		phase_label.text = "Watch the body, then commit."
		impact_marker.visible = false
		return
	var elapsed := Time.get_ticks_msec() / 1000.0 - _active_timeline_started
	var duration := maxf(0.05, float(_active_timeline.get("duration", 1.0)))
	var impact := float(_active_timeline.get("impact_time", duration * 0.6))
	timeline_bar.value = minf(duration, elapsed)
	if elapsed < impact:
		phase_label.text = "TELEGRAPH  //  IMPACT IN %.2fs" % maxf(0.0, impact - elapsed)
	else:
		phase_label.text = "RECOVERY  //  OPEN FOR %.2fs" % maxf(0.0, duration - elapsed)
	if elapsed >= duration:
		_active_timeline.clear()

func _action_name(action: int) -> String:
	var names := GameEnums.DuelActionType.keys()
	return str(names[action]).replace("_", " ") if action >= 0 and action < names.size() else "ACTION"

func _lane_context(player: Dictionary) -> String:
	var lane := int(player.get("lane", -1))
	for raw_slot in _snapshot.get("lane_slots", []):
		var slot: Dictionary = raw_slot
		if int(slot.get("index", -2)) != lane:
			continue
		var tags: Array[String] = []
		for raw_modifier in slot.get("terrain_modifiers", []):
			var tag := str(raw_modifier).split(":", true, 1)[0].strip_edges().to_upper()
			if not tag.is_empty() and not tags.has(tag):
				tags.append(tag)
			if tags.size() >= 3:
				break
		var detail := " + ".join(tags) if not tags.is_empty() else "CLEAR"
		return "HEX %02d  //  %s  //  %s" % [
			lane,
			str(slot.get("background_label", "PLAINS")).to_upper(),
			detail,
		]
	return "HEX -- // NO POSITION DATA"


func _resolve_body_report(snapshot: Dictionary) -> String:
	var lines: Array[String] = []
	for side in ["player", "enemy"]:
		var actor: Dictionary = snapshot.get(side, {})
		if actor.is_empty():
			continue
		var wounds: Array[String] = []
		for raw_limb in actor.get("limbs", []):
			var limb: Dictionary = raw_limb
			var current := float(limb.get("current", 0.0))
			var maximum := maxf(1.0, float(limb.get("maximum", 1.0)))
			var trauma := str(limb.get("trauma", "NONE"))
			if current < maximum * 0.95 or trauma != "NONE":
				wounds.append("%s %d/%d%s" % [
					str(limb.get("code", "??")),
					roundi(current),
					roundi(maximum),
					" " + trauma if trauma != "NONE" else "",
				])
		var wound_text := "NO LIMB TRAUMA" if wounds.is_empty() else "   ".join(wounds)
		lines.append("%s  //  BLOOD %.1f / %.0f  //  %s" % [
			side.to_upper(),
			float(actor.get("blood", 0.0)),
			float(actor.get("blood_max", GameEnums.SCALE_MAX)),
			wound_text,
		])
	return "\n".join(lines)

func _update_camera() -> void:
	if lane_view == null or camera_focus == null:
		return
	if bool(_snapshot.get("is_melee_locked", false)):
		camera_focus.global_position = lane_view.get_combat_focus_global()
		combat_camera.virtual_camera = lock_camera
		combat_camera.transition_speed = 1.35
	else:
		camera_focus.global_position = lane_view.get_stage_center_global()
		combat_camera.virtual_camera = wide_camera
		combat_camera.transition_speed = 1.15

func _play_projectile_timeline(event: Dictionary) -> void:
	var side := str(event.get("side", "player"))
	var target_side := str(event.get("opponent_side", "enemy"))
	var start := lane_view.get_projectile_anchor_global(side)
	var finish := lane_view.get_projectile_anchor_global(target_side)
	var bullet := Sprite2D.new()
	bullet.texture = BULLET_TEXTURE
	bullet.scale = Vector2(0.12, 0.12)
	bullet.global_position = start
	bullet.z_index = 80
	presentation_root.add_child(bullet)
	var impact_time := maxf(0.25, float(event.get("impact_time", 0.7)))
	var muzzle_delay := minf(0.22, impact_time * 0.28)
	var tween := create_tween()
	tween.tween_interval(muzzle_delay)
	tween.tween_property(bullet, "global_position", finish, maxf(0.12, impact_time - muzzle_delay)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(bullet.queue_free)

func _play_shot_impact(event: Dictionary) -> void:
	if not bool(event.get("hit", false)):
		return
	var finish := lane_view.get_projectile_anchor_global(str(event.get("target_side", "enemy")), int(event.get("target_lane", -1)))
	var blood := Sprite2D.new()
	blood.texture = BLOOD_TEXTURE
	blood.scale = Vector2(0.42, 0.42)
	blood.global_position = finish
	blood.z_index = 79
	presentation_root.add_child(blood)
	var tween := create_tween()
	tween.tween_property(blood, "modulate:a", 0.0, 0.65)
	tween.finished.connect(blood.queue_free)

func _play_camera_impact(strength: float, duration: float) -> void:
	if _impact_tween != null and _impact_tween.is_valid():
		_impact_tween.kill()
	combat_camera.offset = Vector2(-strength, strength * 0.25)
	_impact_tween = create_tween()
	_impact_tween.set_trans(Tween.TRANS_SINE)
	_impact_tween.set_ease(Tween.EASE_OUT)
	_impact_tween.tween_property(combat_camera, "offset", Vector2.ZERO, duration)

func _on_viewport_size_changed() -> void:
	lane_view.layout_for_viewport(get_viewport_rect().size)
	_layout_ui_root()
	_layout_camera_for_viewport()

func _layout_ui_root() -> void:
	if ui_root == null:
		return
	var viewport_size := get_viewport_rect().size
	# CanvasLayer coordinates still track the physical viewport. Scale once against a
	# 1080p reference so the HUD remains readable on high-DPI/debug viewports without
	# recreating the previous 1440x900 billboard effect at 2048x1152.
	var ui_scale := clampf(
		minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0),
		0.85,
		1.5
	)
	ui_root.scale = Vector2.ONE * ui_scale
	ui_root.position = Vector2.ZERO
	ui_root.size = viewport_size / ui_scale


func _layout_camera_for_viewport() -> void:
	if lane_view == null or wide_camera == null or lock_camera == null:
		return
	var viewport_size := get_viewport_rect().size
	var wide_zoom := clampf(lane_view.get_camera_min_zoom(viewport_size), 0.5, 1.0)
	wide_camera.zoom = Vector2.ONE * wide_zoom
	lock_camera.zoom = Vector2.ONE * minf(1.25, wide_zoom * 1.28)
	var bounds := lane_view.get_camera_bounds_global()
	for virtual_camera in [wide_camera, lock_camera]:
		virtual_camera.limit_left = floori(bounds.position.x)
		virtual_camera.limit_top = floori(bounds.position.y)
		virtual_camera.limit_right = ceili(bounds.end.x)
		virtual_camera.limit_bottom = ceili(bounds.end.y)
	_update_camera()
