extends Node2D
class_name CombatTokenOverlay

## Presentation projection only. Battlefield position and combat state remain
## owned by the tactical board; direction is derived for visual readability.

enum Mode { GROUND, TOP }

var mode: Mode = Mode.GROUND
var actor_snapshot: Dictionary = {}
var team_color := Color("67a7c8")
var relationship_color := Color("b5c2bd")
var relationship_id := "neutral"
var selected := false
var active := false
var presentation_direction := "east"
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
	direction_id: String,
	width: float,
	scale_value: float
) -> void:
	mode = Mode.GROUND
	actor_snapshot = actor.duplicate(true)
	team_color = color
	selected = selected_state
	active = active_state
	presentation_direction = direction_id
	footprint_width = width
	display_scale = scale_value
	queue_redraw()


func configure_top(
	actor: Dictionary,
	width: float,
	scale_value: float,
	head_anchor: Vector2 = Vector2.ZERO,
	direction_id: String = "east",
	relation_color: Color = Color("b5c2bd"),
	relation_id: String = "neutral"
) -> void:
	mode = Mode.TOP
	actor_snapshot = actor.duplicate(true)
	footprint_width = width
	display_scale = scale_value
	head_top_anchor = head_anchor if head_anchor != Vector2.ZERO else Vector2(0.0, -64.0 * display_scale - 30.0)
	presentation_direction = direction_id
	relationship_color = relation_color
	relationship_id = relation_id
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
		# Ground discs and facing wedges were visually loud and duplicated the
		# token's authored pose. Selection is communicated by the HUD/outline.
		return
	_draw_top()
	_draw_weapon()


func _draw_top() -> void:
	if str(actor_snapshot.get("team_id", "")) == "player" or bool(actor_snapshot.get("is_player", false)):
		return
	var width := clampf(footprint_width * 1.65, 76.0, 152.0)
	var top_y := -display_scale * 64.0 - 24.0
	var intent: Dictionary = actor_snapshot.get("public_intent", actor_snapshot.get("coarse_intent", {}))
	if intent.is_empty():
		intent = actor_snapshot.get("intent", {})
	var intent_label := str(intent.get("readable_label", intent.get("label", "HOLDING"))).to_upper()
	var icon_id := str(intent.get("icon_id", intent.get("icon", "hold"))).to_lower()
	var icon := _intent_icon(icon_id, intent_label)
	var name := str(actor_snapshot.get("name", actor_snapshot.get("actor_id", "ACTOR"))).to_upper()
	var plate := Rect2(-width * 0.5, top_y - 14.0, width, 30.0)
	draw_rect(plate, Color(0.025, 0.035, 0.036, 0.92), true)
	draw_rect(plate, relationship_color, false, 1.5)
	draw_circle(Vector2(plate.position.x + 10.0, plate.position.y + 10.0), 5.0, relationship_color)
	draw_string(ThemeDB.fallback_font, Vector2(plate.position.x + 19.0, plate.position.y + 12.0), name, HORIZONTAL_ALIGNMENT_LEFT, width - 24.0, 9, Color("e1e4de"))
	draw_string(ThemeDB.fallback_font, Vector2(plate.position.x + 8.0, plate.position.y + 25.0), "%s  %s" % [icon, intent_label], HORIZONTAL_ALIGNMENT_LEFT, width - 16.0, 9, relationship_color)


func _intent_icon(icon_id: String, label: String) -> String:
	if icon_id.contains("attack") or label.contains("ATTACK"):
		return "[A]"
	if icon_id.contains("exit") or icon_id.contains("escape") or label.contains("RETREAT"):
		return "[E]"
	if icon_id.contains("support") or label.contains("SUPPORT"):
		return "[S]"
	if icon_id.contains("commun") or label.contains("COMMUNIC"):
		return "[C]"
	if icon_id.contains("surviv") or label.contains("SURVIV"):
		return "[V]"
	return "[H]"


func _draw_weapon() -> void:
	if cue == null:
		return
	if _is_melee_cue():
		_draw_melee_weapon()
		return
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
	# `cue_progress` is already normalized to the weapon sheet's authored FPS
	# duration by TacticalArenaView. The action sequence has a different clock;
	# warping between the two moves the release frame when their durations differ.
	var weapon_progress := clampf(cue_progress, 0.0, 1.0)
	var frame_index := clampi(floori(weapon_progress * float(frame_count)), 0, frame_count - 1)
	var source := Rect2(Vector2((frame_index % columns) * frame_size.x, floori(float(frame_index) / float(columns)) * frame_size.y), Vector2(frame_size))
	var weapon_rect: Rect2 = geometry.rect
	var flip_x := -1.0 if presentation_direction == "west" else 1.0
	draw_set_transform(weapon_rect.get_center(), 0.0, Vector2(flip_x, 1.0))
	draw_texture_rect_region(sheet, Rect2(-display_size * 0.5, display_size), source)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_melee_weapon() -> void:
	var token := get_parent() as HumanoidTokenView
	if token == null:
		return
	var geometry := _melee_weapon_geometry()
	if geometry.is_empty():
		return
	var texture: Texture2D = geometry.texture
	var hand := token.combat_melee_hand_anchor()
	var direction := _facing_vector(presentation_direction)
	var progress := clampf(cue_progress, 0.0, 1.0)
	var anticipation := sin(progress * PI)
	var swing := lerpf(-0.42, 0.56, progress)
	var angle := direction.angle() + swing
	var frame_rect: Rect2 = geometry.rect
	# The equipped-item image is authored in the same token-local canvas as the
	# humanoid layers. Rotate that existing image around the hand pivot instead
	# of inventing a second melee effect asset.
	draw_set_transform(hand, angle, Vector2.ONE)
	draw_texture_rect(texture, Rect2(frame_rect.position - hand, frame_rect.size), false, Color(1.0, 1.0, 1.0, 0.72 + anticipation * 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func weapon_local_rect() -> Rect2:
	if _is_melee_cue():
		return _melee_weapon_geometry().get("rect", Rect2())
	return _weapon_geometry().get("rect", Rect2())


func _is_melee_cue() -> bool:
	return (
		cue != null
		and (
			cue.action_id in ["strike", "shove", "incapacitate", "execute"]
			or cue.weapon_class in [GameEnums.WeaponClass.BLUNT, GameEnums.WeaponClass.BLADE]
		)
	)


func _melee_weapon_geometry() -> Dictionary:
	if cue == null:
		return {}
	var weapon: Dictionary = actor_snapshot.get("melee_weapon", {})
	var presentation: Dictionary = weapon.get("presentation", {})
	var sprite_path := str(presentation.get(
		"sprite_path",
		weapon.get("equipped_sprite_path", weapon.get("sprite_path", ""))
	))
	if sprite_path.is_empty() or not ResourceLoader.exists(sprite_path):
		return {}
	var texture := load(sprite_path) as Texture2D
	if texture == null:
		return {}
	var frame_size := texture.get_size() * display_scale
	return {
		"texture": texture,
		"sprite_path": sprite_path,
		"rect": Rect2(-frame_size * 0.5, frame_size),
	}


func _weapon_geometry() -> Dictionary:
	if cue == null or cue.weapon_class < GameEnums.WeaponClass.PISTOL:
		return {}
	var catalog: CombatWeaponPresentationCatalog = preload("res://CombatCore/Tactical/default_weapon_presentation_catalog.tres")
	var definition := catalog.definition_for(cue.weapon_id)
	if definition == null:
		return {}
	var frame_size := definition.frame_size_for_action(cue.action_id)
	if frame_size.x <= 0 or frame_size.y <= 0:
		return {}
	var display_size := Vector2(frame_size) * clampf(display_scale * 0.72 * definition.display_scale_for_action(cue.action_id), 0.55, 1.65)
	var token := get_parent() as HumanoidTokenView
	# In production the parent token supplies the physical hand anchor. The
	# headless geometry contract has no parent node, so keep its fallback above
	# the supplied overhead anchor instead of letting a detached weapon cross
	# the nameplate/body region.
	var hand := token.combat_weapon_hand_anchor(cue.weapon_id) if token != null else head_top_anchor + Vector2(0.0, -display_size.y * 1.1)
	var authored_anchor := definition.hand_anchor_for_action(cue.action_id)
	var lateral_offset := (authored_anchor.x - 0.5) * display_size.x
	if presentation_direction == "west":
		lateral_offset = -lateral_offset
	var center := hand + Vector2(lateral_offset, authored_anchor.y * display_size.y)
	return {
		"definition": definition,
		"display_size": display_size,
		"rect": Rect2(center - display_size * 0.5, display_size),
	}


func _facing_vector(value: String) -> Vector2:
	return {
		"north": Vector2.UP,
		"east": Vector2.RIGHT,
		"south": Vector2.DOWN,
		"west": Vector2.LEFT,
	}.get(value, Vector2.RIGHT)
