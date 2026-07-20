extends RefCounted
class_name HudMotion

## Shared kill-safe tween presets for HUD visualization.
## Timing contract: response 0.12s / feedback 0.18s / panel entry 0.24s.

const RESPONSE_SEC := 0.12
const FEEDBACK_SEC := 0.18
const PANEL_ENTER_SEC := 0.24


static func kill(tween: Tween) -> void:
	if tween != null and is_instance_valid(tween):
		tween.kill()


static func pulse_alpha(
	host: Node,
	target: CanvasItem,
	low: float = 0.35,
	high: float = 1.0,
	half_duration: float = 0.9
) -> Tween:
	if host == null or target == null:
		return null
	var tween := host.create_tween().set_loops()
	tween.tween_property(target, "modulate:a", low, half_duration)
	tween.tween_property(target, "modulate:a", high, half_duration)
	return tween


static func flash_modulate(
	host: Node,
	target: CanvasItem,
	flash_color: Color,
	settle_color: Color = Color.WHITE,
	duration: float = FEEDBACK_SEC
) -> Tween:
	if host == null or target == null:
		return null
	target.modulate = flash_color
	var tween := host.create_tween()
	tween.tween_property(target, "modulate", settle_color, duration)
	return tween


static func fade_in(
	host: Node,
	target: CanvasItem,
	duration: float = FEEDBACK_SEC,
	from_alpha: float = 0.0
) -> Tween:
	if host == null or target == null:
		return null
	target.modulate.a = from_alpha
	var tween := host.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "modulate:a", 1.0, duration)
	return tween


static func slide_fade_in(
	host: Node,
	target: Control,
	duration: float = FEEDBACK_SEC,
	offset_y: float = 6.0
) -> Tween:
	if host == null or target == null:
		return null
	var end_y := target.position.y
	target.modulate.a = 0.0
	target.position.y = end_y + offset_y
	var tween := host.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)
	tween.tween_property(target, "modulate:a", 1.0, duration)
	tween.tween_property(target, "position:y", end_y, duration)
	return tween


static func micro_shake(
	host: Node,
	target: Control,
	amplitude: float = 3.0,
	duration: float = FEEDBACK_SEC
) -> Tween:
	if host == null or target == null:
		return null
	var origin := target.position
	var tween := host.create_tween()
	tween.tween_property(target, "position", origin + Vector2(amplitude, 0.0), duration * 0.25)
	tween.tween_property(target, "position", origin + Vector2(-amplitude, 0.0), duration * 0.25)
	tween.tween_property(target, "position", origin + Vector2(amplitude * 0.5, 0.0), duration * 0.25)
	tween.tween_property(target, "position", origin, duration * 0.25)
	return tween


static func lerp_progress(
	host: Node,
	bar: Range,
	target_value: float,
	duration: float = PANEL_ENTER_SEC
) -> Tween:
	if host == null or bar == null:
		return null
	var tween := host.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(bar, "value", target_value, duration)
	return tween


static func severity_flash(
	host: Node,
	target: CanvasItem,
	kind: String = "warning"
) -> Tween:
	var flash := HUDAssetLibrary.semantic_color(kind).lightened(0.35)
	flash.a = 1.0
	return flash_modulate(host, target, flash, Color.WHITE, 0.28)


static func panel_enter(
	host: Node,
	target: CanvasItem,
	duration: float = PANEL_ENTER_SEC
) -> Tween:
	if host == null or target == null:
		return null
	target.modulate.a = 0.0
	if target is Control:
		(target as Control).scale = Vector2(0.96, 0.96)
	var tween := host.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)
	tween.tween_property(target, "modulate:a", 1.0, duration)
	if target is Control:
		tween.tween_property(target, "scale", Vector2.ONE, duration)
	return tween


static func soft_pop(
	host: Node,
	target: CanvasItem,
	duration: float = RESPONSE_SEC
) -> Tween:
	if host == null or target == null:
		return null
	var tween := host.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if target is Control:
		(target as Control).scale = Vector2(0.92, 0.92)
		tween.tween_property(target, "scale", Vector2.ONE, duration)
	else:
		target.modulate.a = 0.35
		tween.tween_property(target, "modulate:a", 1.0, duration)
	return tween


static func severity_breathe(
	host: Node,
	target: CanvasItem,
	kind: String = "warning",
	half_duration: float = 0.7
) -> Tween:
	if host == null or target == null:
		return null
	var accent := HUDAssetLibrary.semantic_color(kind)
	var low := Color(1, 1, 1, 0.55)
	var high := Color(
		lerpf(1.0, accent.r, 0.35),
		lerpf(1.0, accent.g, 0.35),
		lerpf(1.0, accent.b, 0.35),
		1.0
	)
	target.modulate = low
	var tween := host.create_tween().set_loops()
	tween.tween_property(target, "modulate", high, half_duration).set_trans(Tween.TRANS_SINE)
	tween.tween_property(target, "modulate", low, half_duration).set_trans(Tween.TRANS_SINE)
	return tween
