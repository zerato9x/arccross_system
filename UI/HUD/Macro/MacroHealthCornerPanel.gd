extends MacroCornerPanel
class_name MacroHealthCornerPanel

signal inventory_requested
signal settings_requested
signal medical_action_requested(instance_id: String, limb_region: int)

var _preview_hud: FieldHealthHUD
var _detail_hud: FieldHealthHUD
var _flash_tween: Tween
var _vignette: TextureRect


func _ready() -> void:
	panel_id = "health"
	panel_corner = PanelCorner.TOP_LEFT
	preview_size = Vector2(548.0, 418.0)
	expanded_min_size = Vector2(760.0, 520.0)
	expanded_max_size = Vector2(960.0, 660.0)
	super._ready()
	_install_health_huds()
	_install_vignette()


func _install_health_huds() -> void:
	_preview_hud = %PreviewRoot.get_node_or_null("FieldHealthPreview") as FieldHealthHUD
	_detail_hud = %ExpandedRoot.get_node_or_null("FieldHealthDetail") as FieldHealthHUD
	if _preview_hud == null or _detail_hud == null:
		push_error("MacroHealthCornerPanel requires both FieldHealthHUD instances.")
		return
	_preview_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_hud.details_requested.connect(expand)
	# Inventory / settings are owned by inventory corner and world status panel.
	_detail_hud.limb_treatment_requested.connect(
		func(instance_id: String, region: int):
			medical_action_requested.emit(instance_id, region)
	)


func _install_vignette() -> void:
	if _emergency_overlay == null or _vignette != null:
		return
	_vignette = TextureRect.new()
	_vignette.name = "EmergencyVignette"
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_vignette.modulate.a = 0.55
	_vignette.visible = false
	_emergency_overlay.add_child(_vignette)


func _render_preview() -> void:
	if _snapshot.is_empty():
		return
	if _preview_hud:
		_preview_hud.apply_snapshot(_snapshot)
	var emergencies: Array = _snapshot.get("emergencies", [])
	_set_emergency_flash(not emergencies.is_empty(), emergencies)


func _render_expanded() -> void:
	if _detail_hud:
		_detail_hud.apply_snapshot(_snapshot)


func _set_emergency_flash(active: bool, emergencies: Array) -> void:
	var tint := Color(HUDAssetLibrary.COLOR_CRITICAL.r, HUDAssetLibrary.COLOR_CRITICAL.g, HUDAssetLibrary.COLOR_CRITICAL.b, 0.28)
	var vignette_kind := "critical"
	for entry in emergencies:
		var token := str(entry).to_lower()
		if token.contains("anomaly"):
			vignette_kind = "anomaly"
			tint = Color(HUDAssetLibrary.COLOR_ANOMALY.r, HUDAssetLibrary.COLOR_ANOMALY.g, HUDAssetLibrary.COLOR_ANOMALY.b, 0.28)
			break
		if token.contains("warn") or token.contains("infection"):
			vignette_kind = "warning"
			tint = Color(HUDAssetLibrary.COLOR_CAUTION.r, HUDAssetLibrary.COLOR_CAUTION.g, HUDAssetLibrary.COLOR_CAUTION.b, 0.24)
	set_emergency_active(active, tint)
	if _vignette:
		_vignette.texture = HUDAssetLibrary.vignette_texture(vignette_kind)
		_vignette.visible = active
	HudMotion.kill(_flash_tween)
	if not active or _emergency_overlay == null:
		return
	_flash_tween = HudMotion.severity_breathe(self, _emergency_overlay, vignette_kind, 0.75)


func restyle_scheme() -> void:
	super.restyle_scheme()
	if _preview_hud and _preview_hud.has_method("restyle"):
		_preview_hud.restyle()
	if _detail_hud and _detail_hud.has_method("restyle"):
		_detail_hud.restyle()
	if not _snapshot.is_empty():
		apply_snapshot(_snapshot)


func _set_state(state: PanelState) -> void:
	super._set_state(state)
	if state == PanelState.EXPANDED:
		_render_expanded()


func _is_primary_action_click(global_pos: Vector2) -> bool:
	return _preview_hud != null and _preview_hud.is_action_button_at(global_pos)
