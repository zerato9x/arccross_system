extends Node2D
class_name CombatTokenOverlay

enum Mode { GROUND, TOP }

var mode: Mode = Mode.GROUND
var actor_snapshot: Dictionary = {}
var team_color := Color("67a7c8")
var selected := false
var active := false
var reaction_threat := false
var facing := "east"
var footprint_width := 48.0
var display_scale := 1.0
var head_top_anchor := Vector2.ZERO
var cue: CombatPresentationCue
var cue_progress := 0.0


func configure_ground(
	actor: Dictionary,
	color: Color,
	selected_state: bool,
	active_state: bool,
	threat_state: bool,
	facing_id: String,
	width: float,
	scale_value: float
) -> void:
	mode = Mode.GROUND
	actor_snapshot = actor.duplicate(true)
	team_color = color
	selected = selected_state
	active = active_state
	reaction_threat = threat_state
	facing = facing_id
	footprint_width = width
	display_scale = scale_value
	queue_redraw()


func configure_top(
	actor: Dictionary,
	width: float,
	scale_value: float,
	head_anchor: Vector2 = Vector2.ZERO,
	facing_id: String = "east"
) -> void:
	mode = Mode.TOP
	actor_snapshot = actor.duplicate(true)
	footprint_width = width
	display_scale = scale_value
	head_top_anchor = head_anchor if head_anchor != Vector2.ZERO else Vector2(0.0, -64.0 * display_scale - 30.0)
	facing = facing_id
	queue_redraw()


func set_weapon_cue(value: CombatPresentationCue, progress: float = 0.0) -> void:
	cue = value
	cue_progress = progress
	queue_redraw()


func set_cue_progress(progress: float) -> void:
	cue_progress = progress
	queue_redraw()


func _draw() -> void:
	if mode == Mode.GROUND:
		_draw_ground()
	else:
		_draw_top()
		_draw_weapon()


func _draw_ground() -> void:
	var foot_y := display_scale * 48.0
	var radius := footprint_width * 0.5
	var outline := Color("f0ce76") if selected else team_color
	if reaction_threat:
		outline = Color("e56b59")
	if active:
		outline = Color("f5eee0")
	draw_set_transform(Vector2(0.0, foot_y), 0.0, Vector2(1.0, 0.56))
	draw_circle(Vector2.ZERO, radius, Color(0.03, 0.04, 0.04, 0.82))
	draw_circle(Vector2.ZERO, radius, outline, false, maxf(2.0, radius * 0.10))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var direction: Vector2 = {
		"north": Vector2.UP,
		"east": Vector2.RIGHT,
		"south": Vector2.DOWN,
		"west": Vector2.LEFT,
	}.get(facing, Vector2.RIGHT)
	var wedge_center := Vector2(0.0, foot_y) + direction * radius * 0.78
	var side := Vector2(-direction.y, direction.x) * radius * 0.16
	draw_colored_polygon(
		PackedVector2Array([wedge_center + direction * radius * 0.22, wedge_center - side, wedge_center + side]),
		outline
	)


func _draw_top() -> void:
	if str(actor_snapshot.get("team_id", "")) == "player":
		return
	var width := clampf(footprint_width * 1.45, 52.0, 116.0)
	var top_y := -display_scale * 64.0 - 18.0
	var name := str(actor_snapshot.get("name", actor_snapshot.get("actor_id", "HOSTILE"))).to_upper()
	draw_string(ThemeDB.fallback_font, Vector2(-width * 0.5, top_y), name, HORIZONTAL_ALIGNMENT_CENTER, width, 10, Color("d9dfdc"))
	_draw_vital_bar(Vector2(-width * 0.5, top_y + 6.0), width, float(actor_snapshot.get("blood", 0.0)), Color("c85f55"))
	_draw_vital_bar(Vector2(-width * 0.5, top_y + 13.0), width, float(actor_snapshot.get("consciousness", 0.0)), Color("d6b85e"))


func _draw_vital_bar(origin: Vector2, width: float, value: float, color: Color) -> void:
	draw_rect(Rect2(origin, Vector2(width, 5.0)), Color(0.02, 0.025, 0.028, 0.95), true)
	draw_rect(
		Rect2(origin + Vector2.ONE, Vector2((width - 2.0) * clampf(value / GameEnums.SCALE_MAX, 0.0, 1.0), 3.0)),
		color,
		true
	)


func _draw_weapon() -> void:
	var geometry := _weapon_geometry()
	if geometry.is_empty():
		return
	var definition: CombatWeaponPresentationDefinition = geometry.definition
	var display_size: Vector2 = geometry.display_size
	var sheet := definition.sheet_for_action(cue.action_id)
	var frame_size := definition.frame_size_for_action(cue.action_id)
	if sheet == null or frame_size.x <= 0 or frame_size.y <= 0:
		return
	var columns := maxi(1, floori(float(sheet.get_width()) / float(frame_size.x)))
	var rows := maxi(1, floori(float(sheet.get_height()) / float(frame_size.y)))
	var frame_count := maxi(1, columns * rows)
	# The presentation player supplies sequence-wide progress. Re-interpolating
	# it per cue made weapon sheets restart and visibly double-play.
	var sequence_progress := clampf(cue_progress, 0.0, 1.0)
	var authored_release := definition.release_progress_for_action(cue.action_id)
	var sequence_release := cue.weapon_release_sequence_progress
	if sequence_release > 0.0 and sequence_release < 1.0 and authored_release > 0.0 and authored_release < 1.0:
		if sequence_progress <= sequence_release:
			sequence_progress = (sequence_progress / sequence_release) * authored_release
		else:
			sequence_progress = authored_release + ((sequence_progress - sequence_release) / (1.0 - sequence_release)) * (1.0 - authored_release)
	var frame_index := clampi(floori(sequence_progress * float(frame_count)), 0, frame_count - 1)
	var source := Rect2(
		Vector2((frame_index % columns) * frame_size.x, floori(float(frame_index) / float(columns)) * frame_size.y),
		Vector2(frame_size)
	)
	# Weapon sheets are deliberately a calm, horizontal overhead layer. The
	# old hand anchor rotated and translated the sheet through the body on every
	# facing, which made the gun look like a second humanoid animation.
	var weapon_rect: Rect2 = geometry.rect
	var flip_x := -1.0 if facing == "west" else 1.0
	draw_set_transform(weapon_rect.get_center(), 0.0, Vector2(flip_x, 1.0))
	draw_texture_rect_region(sheet, Rect2(-display_size * 0.5, display_size), source)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func weapon_local_rect() -> Rect2:
	return _weapon_geometry().get("rect", Rect2())


func _weapon_geometry() -> Dictionary:
	if cue == null or cue.action_id not in ["fire", "aimed_fire", "reload", "cycle", "clear_malfunction"]:
		return {}
	var catalog: CombatWeaponPresentationCatalog = preload("res://CombatCore/Tactical/default_weapon_presentation_catalog.tres")
	var definition := catalog.definition_for(cue.weapon_id)
	if definition == null:
		return {}
	var frame_size := definition.frame_size_for_action(cue.action_id)
	if frame_size.x <= 0 or frame_size.y <= 0:
		return {}
	var display_size := Vector2(frame_size) * clampf(
		display_scale * 0.72 * definition.display_scale_for_action(cue.action_id),
		0.55,
		1.65
	)
	var authored_anchor := definition.hand_anchor_for_action(cue.action_id)
	var lateral_offset := (authored_anchor.x - 0.5) * display_size.x
	if facing == "west":
		lateral_offset = -lateral_offset
	# Bottom edge is kept above the explicit head anchor with a small readable
	# gap. This geometry is decorative and never owns battlefield coordinates.
	var center := head_top_anchor + Vector2(
		lateral_offset,
		-display_size.y * 0.5 - definition.overhead_gap_pixels
	)
	return {
		"definition": definition,
		"display_size": display_size,
		"rect": Rect2(center - display_size * 0.5, display_size),
	}
