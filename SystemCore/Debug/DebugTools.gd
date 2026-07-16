extends CanvasLayer
## In-game developer debug overlay for ARCCROSS.
##
## Autoloaded as `DebugTools`. Toggle with the backtick / tilde key (`) or F3.
## Provides live tooling that operates on the running game:
##   • Item Spawner  — spawn any catalogued item into the backpack, equip it,
##                     or drop it on the player's current hex.
##   • Stats Editor  — live sliders for vitals, limb HP, and the four attribute
##                     pillars, plus one-click heal / kill / revive / god mode.
##   • World Tools   — teleport, advance world time, spawn a hostile, quick
##                     save / load.
##
## The overlay never ships: it deletes itself outside debug builds. It talks to
## the game exclusively through the public `debug_*` hooks on MacroGameManager,
## the LootCatalog listing helpers, and the HumanoidCore/Body runtime state, so
## it stays decoupled from internal systems.

const TOGGLE_KEYS := [KEY_QUOTELEFT, KEY_F3]
const SCALE_MAX := 12.0
const HUD_THEME_PATH := "res://UI/HUD/PocketInventoryTheme.tres"
const ACCENT_COLOR := Color(0.937, 0.882, 0.741)   # warm HUD cream
const OK_COLOR := Color(0.725, 0.867, 0.412)        # HUD lime
const WARN_COLOR := Color(0.87, 0.45, 0.42)         # alert red

var _root: Control
var _toggle_button: Button
var _tabs: TabContainer
var _status_label: Label
var _target_label: Label

# Item spawner widgets
var _item_filter: LineEdit
var _item_list: ItemList
var _item_qty: SpinBox
var _item_count_label: Label
var _filtered_ids: Array[String] = []

# Stats widgets
var _stat_sliders: Dictionary = {}   # key -> HSlider
var _stat_value_labels: Dictionary = {}
var _attr_spins: Dictionary = {}      # key -> SpinBox
var _limb_sliders: Dictionary = {}    # LimbRegion(int) -> HSlider
var _limb_value_labels: Dictionary = {}
var _god_checkbox: CheckBox

# World widgets
var _tp_x: SpinBox
var _tp_y: SpinBox
var _time_amount: SpinBox
var _faction_option: OptionButton
var _difficulty_spin: SpinBox

var _refreshing := false
var _god_mode := false
var _god_accum := 0.0

# Cached scene references, revalidated on demand.
var _macro: Node
var _player: Node
var _director: Node


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_build_ui()
	_set_open(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in TOGGLE_KEYS:
			_toggle()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _god_mode:
		return
	_god_accum += delta
	if _god_accum < 0.5:
		return
	_god_accum = 0.0
	var core = _get_core()
	if core == null:
		return
	core.is_dead = false
	core.current_max_ap = 12
	var body = core.body
	body.blood_level = SCALE_MAX
	body.hunger = SCALE_MAX
	body.thirst = SCALE_MAX
	body.fatigue = 0.0
	body.core_temperature = 37.0
	for limb in body.limb_hp.keys():
		body.limb_hp[limb] = body.get_limb_max(limb)
		body.limb_trauma[limb] = 0  # TraumaType.NONE


# ---------------------------------------------------------
# TOGGLE & REFRESH
# ---------------------------------------------------------

func _toggle() -> void:
	_set_open(not _root.visible)


func _set_open(open: bool) -> void:
	if _root != null:
		_root.visible = open
	if _toggle_button != null:
		_toggle_button.text = "⚙ CHEATS ▾" if open else "⚙ CHEATS"
		_toggle_button.modulate = Color(1, 1, 1, 1.0) if open else Color(1, 1, 1, 0.7)
	if open:
		_refresh_all()


func _refresh_all() -> void:
	_refresh_target_label()
	_populate_item_list()
	_refresh_stats()


func _refresh_target_label() -> void:
	var core = _get_core()
	if core == null:
		_target_label.text = "TARGET: <no player in scene>"
		_target_label.modulate = WARN_COLOR
	else:
		var coords := "?"
		if is_instance_valid(_player) and "current_hex_coords" in _player:
			coords = str(_player.current_hex_coords)
		_target_label.text = "TARGET: %s @ %s" % [_player.name, coords]
		_target_label.modulate = OK_COLOR


func _set_status(text: String, ok: bool = true) -> void:
	_status_label.text = text
	_status_label.modulate = OK_COLOR if ok else WARN_COLOR


# ---------------------------------------------------------
# SCENE LOOKUP
# ---------------------------------------------------------

func _find_first(pred: Callable) -> Node:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node != self and pred.call(node):
			return node
		for child in node.get_children():
			stack.append(child)
	return null


func _get_macro() -> Node:
	if is_instance_valid(_macro):
		return _macro
	_macro = _find_first(func(n): return n is MacroGameManager)
	return _macro


func _get_player() -> Node:
	if is_instance_valid(_player):
		return _player
	var macro := _get_macro()
	if macro != null and "player_token" in macro and is_instance_valid(macro.player_token):
		_player = macro.player_token
		return _player
	_player = _find_first(func(n): return n.has_method("get_humanoid_core"))
	return _player


func _get_core() -> HumanoidCore:
	var player := _get_player()
	if player == null:
		return null
	return player.get_humanoid_core()


func _get_director() -> Node:
	if is_instance_valid(_director):
		return _director
	_director = _find_first(func(n): return n is GameDirector)
	return _director


func _get_loot() -> Node:
	return get_node_or_null("/root/LootCatalog")


# ---------------------------------------------------------
# UI CONSTRUCTION
# ---------------------------------------------------------

func _build_ui() -> void:
	var hud_theme: Theme = null
	if ResourceLoader.exists(HUD_THEME_PATH):
		hud_theme = load(HUD_THEME_PATH) as Theme

	_build_toggle_button(hud_theme)

	# Centered cheat-console window. Corners are owned by the real HUD panels
	# (health / inventory / hex / world status), so the console docks in the
	# middle and only covers the map view while it is open.
	_root = PanelContainer.new()
	_root.name = "DebugOverlayRoot"
	if hud_theme != null:
		_root.theme = hud_theme
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.anchor_left = 0.5
	_root.anchor_right = 0.5
	_root.anchor_top = 0.5
	_root.anchor_bottom = 0.5
	_root.offset_left = -250.0
	_root.offset_right = 250.0
	_root.offset_top = -340.0
	_root.offset_bottom = 340.0
	_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_root.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)

	var header_row := HBoxContainer.new()
	outer.add_child(header_row)
	var header := Label.new()
	header.text = "▓ CHEAT CONSOLE ▓"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", ACCENT_COLOR)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(34, 0)
	close_btn.pressed.connect(func(): _set_open(false))
	header_row.add_child(close_btn)

	var rule := HSeparator.new()
	outer.add_child(rule)

	_target_label = Label.new()
	_target_label.text = "TARGET: ..."
	_target_label.add_theme_font_size_override("font_size", 12)
	outer.add_child(_target_label)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_tabs)

	_build_items_tab()
	_build_stats_tab()
	_build_world_tab()

	_status_label = Label.new()
	_status_label.text = "Press ` or F3 to toggle."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 12)
	outer.add_child(_status_label)


## Always-on-screen toggle button. Anchored top-center because the four HUD
## corners are already occupied by the health / inventory / hex / world panels.
func _build_toggle_button(hud_theme: Theme) -> void:
	_toggle_button = Button.new()
	_toggle_button.name = "DebugToggleButton"
	if hud_theme != null:
		_toggle_button.theme = hud_theme
	_toggle_button.text = "⚙ CHEATS"
	_toggle_button.tooltip_text = "Toggle the cheat console  ( ` or F3 )"
	_toggle_button.focus_mode = Control.FOCUS_NONE
	_toggle_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toggle_button.anchor_left = 0.5
	_toggle_button.anchor_right = 0.5
	_toggle_button.anchor_top = 0.0
	_toggle_button.anchor_bottom = 0.0
	_toggle_button.offset_left = -70.0
	_toggle_button.offset_right = 70.0
	_toggle_button.offset_top = 6.0
	_toggle_button.offset_bottom = 34.0
	_toggle_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toggle_button.modulate = Color(1, 1, 1, 0.7)
	_toggle_button.mouse_entered.connect(
		func(): _toggle_button.modulate = Color(1, 1, 1, 1.0)
	)
	_toggle_button.mouse_exited.connect(
		func(): _toggle_button.modulate = (
			Color(1, 1, 1, 1.0) if _root != null and _root.visible
			else Color(1, 1, 1, 0.7)
		)
	)
	_toggle_button.pressed.connect(_toggle)
	add_child(_toggle_button)


func _section_label(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(0.7, 0.85, 1.0)
	parent.add_child(label)


func _make_button(parent: Node, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


# ---------------------------------------------------------
# ITEMS TAB
# ---------------------------------------------------------

func _build_items_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Items"
	tab.add_theme_constant_override("separation", 6)
	_tabs.add_child(tab)

	_item_filter = LineEdit.new()
	_item_filter.placeholder_text = "Filter by name or id..."
	_item_filter.text_changed.connect(func(_t): _populate_item_list())
	tab.add_child(_item_filter)

	_item_count_label = Label.new()
	_item_count_label.add_theme_font_size_override("font_size", 11)
	tab.add_child(_item_count_label)

	_item_list = ItemList.new()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.custom_minimum_size = Vector2(0, 240)
	tab.add_child(_item_list)

	var qty_row := HBoxContainer.new()
	tab.add_child(qty_row)
	var qty_label := Label.new()
	qty_label.text = "Quantity"
	qty_row.add_child(qty_label)
	_item_qty = SpinBox.new()
	_item_qty.min_value = 1
	_item_qty.max_value = 999
	_item_qty.value = 1
	_item_qty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qty_row.add_child(_item_qty)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	tab.add_child(btn_row)
	var to_pack := _make_button(btn_row, "To Backpack", _spawn_to_backpack)
	to_pack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var equip := _make_button(btn_row, "Equip", _spawn_equip)
	equip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var drop := _make_button(btn_row, "Drop Here", _spawn_drop)
	drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _populate_item_list() -> void:
	_item_list.clear()
	_filtered_ids.clear()
	var loot := _get_loot()
	if loot == null or not loot.has_method("get_all_item_rows"):
		_item_count_label.text = "LootCatalog unavailable."
		return
	var needle := _item_filter.text.strip_edges().to_lower()
	var rows: Array = loot.get_all_item_rows()
	for row in rows:
		var id_str := str(row.get("id", ""))
		var display := str(row.get("display_name", id_str))
		if not needle.is_empty() and not (
			needle in id_str.to_lower() or needle in display.to_lower()
		):
			continue
		var type_name := _enum_name(GameEnums.ItemType.keys(), int(row.get("item_type", 0)))
		_item_list.add_item("%s  [%s]" % [display, type_name])
		_filtered_ids.append(id_str)
	_item_count_label.text = "%d / %d items" % [_filtered_ids.size(), rows.size()]


func _selected_item_id() -> String:
	var selection := _item_list.get_selected_items()
	if selection.is_empty():
		return ""
	var index: int = selection[0]
	if index < 0 or index >= _filtered_ids.size():
		return ""
	return _filtered_ids[index]


func _make_runtime_item(item_id: String):
	var loot := _get_loot()
	if loot == null:
		return null
	var definition = loot.get_item_definition(item_id)
	if definition == null:
		return null
	return definition.create_runtime_instance()


func _spawn_to_backpack() -> void:
	var item_id := _selected_item_id()
	if item_id.is_empty():
		_set_status("Select an item first.", false)
		return
	var core = _get_core()
	if core == null:
		_set_status("No player to receive items.", false)
		return
	var remaining := int(_item_qty.value)
	var added := 0
	while remaining > 0:
		var item = _make_runtime_item(item_id)
		if item == null:
			break
		var limit: int = item.get_stack_limit()
		var take: int = mini(remaining, limit)
		item.stack_count = take
		if core.inventory.add_to_backpack(item):
			added += take
			remaining -= take
		else:
			break
	_sync_after_mutation()
	if added > 0:
		_set_status("Added %dx %s to backpack." % [added, item_id])
	else:
		_set_status("Could not stow %s (no space?)." % item_id, false)


func _spawn_equip() -> void:
	var item_id := _selected_item_id()
	if item_id.is_empty():
		_set_status("Select an item first.", false)
		return
	var core = _get_core()
	if core == null:
		_set_status("No player to equip.", false)
		return
	var item = _make_runtime_item(item_id)
	if item == null:
		_set_status("Unknown item id: %s" % item_id, false)
		return
	var slot = core.inventory.get_preferred_equipment_slot(item)
	if core.inventory.equip_item(item, slot):
		_sync_after_mutation()
		_set_status("Equipped %s in slot %s." % [
			item_id, _enum_name(GameEnums.EquipmentSlot.keys(), slot)
		])
	else:
		_set_status("Could not equip %s (added to backpack instead)." % item_id, false)
		core.inventory.add_to_backpack(item)
		_sync_after_mutation()


func _spawn_drop() -> void:
	var item_id := _selected_item_id()
	if item_id.is_empty():
		_set_status("Select an item first.", false)
		return
	var macro := _get_macro()
	var player := _get_player()
	if macro == null or player == null or not macro.has_method("add_ground_item_states"):
		_set_status("No macro world to drop into.", false)
		return
	var loot := _get_loot()
	var states: Array = []
	var remaining := int(_item_qty.value)
	while remaining > 0:
		var item = _make_runtime_item(item_id)
		if item == null:
			break
		var take: int = mini(remaining, item.get_stack_limit())
		item.stack_count = take
		states.append(item.to_runtime_state())
		remaining -= take
	if states.is_empty():
		_set_status("Unknown item id: %s" % item_id, false)
		return
	macro.add_ground_item_states(player.current_hex_coords, states)
	if macro.has_method("debug_sync_player_after_mutation"):
		macro.debug_sync_player_after_mutation()
	_set_status("Dropped %s x%d at %s." % [
		item_id, int(_item_qty.value), str(player.current_hex_coords)
	])


# ---------------------------------------------------------
# STATS TAB
# ---------------------------------------------------------

func _build_stats_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Stats"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)

	var tab := VBoxContainer.new()
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 4)
	scroll.add_child(tab)

	_section_label(tab, "Vitals (0 - 12)")
	_add_stat_slider(tab, "blood", "Blood", 0.0, SCALE_MAX, 0.5)
	_add_stat_slider(tab, "hunger", "Hunger", 0.0, SCALE_MAX, 0.5)
	_add_stat_slider(tab, "thirst", "Thirst", 0.0, SCALE_MAX, 0.5)
	_add_stat_slider(tab, "fatigue", "Fatigue", 0.0, SCALE_MAX, 0.5)
	_add_stat_slider(tab, "morale", "Morale", 0.0, SCALE_MAX, 0.5)
	_add_stat_slider(tab, "stance", "Stance", 0.0, SCALE_MAX, 1.0)
	_add_stat_slider(tab, "arc", "Arc Energy", 0.0, SCALE_MAX, 0.5)
	_add_stat_slider(tab, "redmist", "Red Mist", 0.0, SCALE_MAX, 0.5)
	_add_stat_slider(tab, "temp", "Core Temp (C)", 20.0, 42.0, 0.5)

	_section_label(tab, "Limb HP")
	for limb in GameEnums.LimbRegion.values():
		_add_limb_slider(tab, limb)

	_section_label(tab, "Attributes (1 - 12)")
	for pillar in ["brawn", "finesse", "fortitude", "will"]:
		_add_attr_spin(tab, pillar)

	_section_label(tab, "Quick Actions")
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	tab.add_child(row1)
	_make_button(row1, "Full Heal", _action_full_heal).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_make_button(row1, "Full Vitals", _action_full_vitals).size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	tab.add_child(row2)
	_make_button(row2, "Clear Trauma", _action_clear_trauma).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_make_button(row2, "Reset Stance", _action_reset_stance).size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 4)
	tab.add_child(row3)
	_make_button(row3, "Revive", _action_revive).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_make_button(row3, "Kill", _action_kill).size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_god_checkbox = CheckBox.new()
	_god_checkbox.text = "God Mode (auto full vitals)"
	_god_checkbox.toggled.connect(_on_god_toggled)
	tab.add_child(_god_checkbox)


func _add_stat_slider(parent: Node, key: String, text: String, min_v: float, max_v: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := Label.new()
	name_label.text = text
	name_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v): _on_stat_slider_changed(key, v))
	slider.drag_ended.connect(func(_c): _sync_after_mutation())
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(42, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_stat_sliders[key] = slider
	_stat_value_labels[key] = value_label


func _add_limb_slider(parent: Node, limb: int) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := Label.new()
	name_label.text = _enum_name(GameEnums.LimbRegion.keys(), limb).capitalize()
	name_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = SCALE_MAX
	slider.step = 0.5
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v): _on_limb_slider_changed(limb, v))
	slider.drag_ended.connect(func(_c): _sync_after_mutation())
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(42, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_limb_sliders[limb] = slider
	_limb_value_labels[limb] = value_label


func _add_attr_spin(parent: Node, key: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := Label.new()
	name_label.text = key.capitalize()
	name_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(name_label)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 12
	spin.step = 1
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v): _on_attr_changed(key, v))
	row.add_child(spin)
	_attr_spins[key] = spin


func _refresh_stats() -> void:
	var core = _get_core()
	if core == null:
		return
	_refreshing = true
	var body = core.body
	_set_slider("blood", body.blood_level)
	_set_slider("hunger", body.hunger)
	_set_slider("thirst", body.thirst)
	_set_slider("fatigue", body.fatigue)
	_set_slider("morale", core.current_morale)
	_set_slider("stance", core.stance_points)
	_set_slider("arc", core.current_arc_energy)
	_set_slider("redmist", core.red_mist_corruption)
	_set_slider("temp", body.core_temperature)
	for limb in _limb_sliders.keys():
		var slider: HSlider = _limb_sliders[limb]
		slider.max_value = maxf(SCALE_MAX, body.get_limb_max(limb))
		var hp := float(body.limb_hp.get(limb, 0.0))
		slider.value = hp
		_limb_value_labels[limb].text = "%.1f" % hp
	if core.definition != null:
		_attr_spins["brawn"].value = core.definition.brawn
		_attr_spins["finesse"].value = core.definition.finesse
		_attr_spins["fortitude"].value = core.definition.fortitude
		_attr_spins["will"].value = core.definition.will
	if _god_checkbox != null:
		_god_checkbox.button_pressed = _god_mode
	_refreshing = false


func _set_slider(key: String, value: float) -> void:
	if not _stat_sliders.has(key):
		return
	_stat_sliders[key].value = value
	_stat_value_labels[key].text = "%.1f" % value


func _on_stat_slider_changed(key: String, value: float) -> void:
	if _stat_value_labels.has(key):
		_stat_value_labels[key].text = "%.1f" % value
	if _refreshing:
		return
	var core = _get_core()
	if core == null:
		return
	var body = core.body
	match key:
		"blood":
			body.blood_level = value
			body.blood_level_changed.emit(value)
		"hunger": body.hunger = value
		"thirst": body.thirst = value
		"fatigue": body.fatigue = value
		"morale": core.current_morale = value
		"stance":
			core.stance_points = int(value)
			core.call("_evaluate_stance_state")
		"arc": core.current_arc_energy = value
		"redmist": core.red_mist_corruption = value
		"temp": body.core_temperature = value
	core.call("_calculate_kinetic_burden")


func _on_limb_slider_changed(limb: int, value: float) -> void:
	if _limb_value_labels.has(limb):
		_limb_value_labels[limb].text = "%.1f" % value
	if _refreshing:
		return
	var core = _get_core()
	if core == null:
		return
	core.body.limb_hp[limb] = value
	if value > 0.0 and int(core.body.limb_trauma.get(limb, 0)) == GameEnums.TraumaType.SHATTERED_LIMB:
		core.body.limb_trauma[limb] = GameEnums.TraumaType.NONE
	core.call("_calculate_kinetic_burden")


func _on_attr_changed(key: String, value: float) -> void:
	if _refreshing:
		return
	var core = _get_core()
	if core == null or core.definition == null:
		return
	var int_value := int(value)
	core.definition.set(key, int_value)
	if key == "fortitude":
		core.body.configure_structure(int_value)
		_refresh_stats()
	core.call("_calculate_kinetic_burden")
	_sync_after_mutation()
	_set_status("%s set to %d." % [key, int_value])


func _action_full_heal() -> void:
	var core = _get_core()
	if core == null:
		return
	var body = core.body
	for limb in body.limb_hp.keys():
		body.limb_hp[limb] = body.get_limb_max(limb)
		body.limb_trauma[limb] = GameEnums.TraumaType.NONE
	body.blood_level = SCALE_MAX
	core.call("_calculate_kinetic_burden")
	_refresh_stats()
	_sync_after_mutation()
	_set_status("Full heal applied.")


func _action_full_vitals() -> void:
	var core = _get_core()
	if core == null:
		return
	var body = core.body
	body.blood_level = SCALE_MAX
	body.hunger = SCALE_MAX
	body.thirst = SCALE_MAX
	body.fatigue = 0.0
	body.core_temperature = 37.0
	core.current_morale = SCALE_MAX
	core.call("_calculate_kinetic_burden")
	_refresh_stats()
	_sync_after_mutation()
	_set_status("Vitals restored.")


func _action_clear_trauma() -> void:
	var core = _get_core()
	if core == null:
		return
	for limb in core.body.limb_trauma.keys():
		core.body.limb_trauma[limb] = GameEnums.TraumaType.NONE
	core.call("_calculate_kinetic_burden")
	_refresh_stats()
	_sync_after_mutation()
	_set_status("All trauma cleared.")


func _action_reset_stance() -> void:
	var core = _get_core()
	if core == null:
		return
	core.reset_stance()
	_refresh_stats()
	_sync_after_mutation()
	_set_status("Stance reset to 12.")


func _action_revive() -> void:
	var core = _get_core()
	if core == null:
		return
	core.is_dead = false
	core.is_comatose = false
	core.current_max_ap = 12
	var body = core.body
	for limb in body.limb_hp.keys():
		if body.limb_hp[limb] <= 0.0:
			body.limb_hp[limb] = body.get_limb_max(limb)
		body.limb_trauma[limb] = GameEnums.TraumaType.NONE
	body.blood_level = SCALE_MAX
	core.reset_stance()
	core.call("_calculate_kinetic_burden")
	_refresh_stats()
	_sync_after_mutation()
	_set_status("Player revived.")


func _action_kill() -> void:
	var core = _get_core()
	if core == null:
		return
	core.body.apply_targeted_hit(GameEnums.LimbRegion.HEAD, 999.0, 0.0)
	_refresh_stats()
	_sync_after_mutation()
	_set_status("Player killed.", false)


func _on_god_toggled(pressed: bool) -> void:
	_god_mode = pressed
	set_process(pressed)
	_set_status("God mode %s." % ("ON" if pressed else "OFF"))


# ---------------------------------------------------------
# WORLD TAB
# ---------------------------------------------------------

func _build_world_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "World"
	tab.add_theme_constant_override("separation", 6)
	_tabs.add_child(tab)

	_section_label(tab, "Teleport")
	var tp_row := HBoxContainer.new()
	tab.add_child(tp_row)
	tp_row.add_child(_labeled("X", func(): return))
	_tp_x = _make_coord_spin()
	tp_row.add_child(_tp_x)
	tp_row.add_child(_labeled("Y", func(): return))
	_tp_y = _make_coord_spin()
	tp_row.add_child(_tp_y)
	_make_button(tab, "Teleport To Hex", _do_teleport)

	_section_label(tab, "World Clock")
	var time_row := HBoxContainer.new()
	tab.add_child(time_row)
	var tlabel := Label.new()
	tlabel.text = "Minutes"
	time_row.add_child(tlabel)
	_time_amount = SpinBox.new()
	_time_amount.min_value = 15
	_time_amount.max_value = 1440
	_time_amount.step = 15
	_time_amount.value = 60
	_time_amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(_time_amount)
	_make_button(tab, "Advance Time (+survival)", _do_advance_time)

	_section_label(tab, "Spawn Hostile")
	var faction_row := HBoxContainer.new()
	tab.add_child(faction_row)
	var flabel := Label.new()
	flabel.text = "Faction"
	faction_row.add_child(flabel)
	_faction_option = OptionButton.new()
	_faction_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for faction in GameEnums.Faction.values():
		_faction_option.add_item(
			_enum_name(GameEnums.Faction.keys(), faction).capitalize(), faction
		)
	_faction_option.select(1)
	faction_row.add_child(_faction_option)
	var diff_row := HBoxContainer.new()
	tab.add_child(diff_row)
	var dlabel := Label.new()
	dlabel.text = "Difficulty"
	diff_row.add_child(dlabel)
	_difficulty_spin = SpinBox.new()
	_difficulty_spin.min_value = 0
	_difficulty_spin.max_value = 5
	_difficulty_spin.step = 1
	_difficulty_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_row.add_child(_difficulty_spin)
	_make_button(tab, "Spawn Near Player", _do_spawn_enemy)

	_section_label(tab, "Persistence")
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 4)
	tab.add_child(save_row)
	_make_button(save_row, "Quick Save", _do_save).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_make_button(save_row, "Quick Load", _do_load).size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _labeled(text: String, _unused: Callable) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _make_coord_spin() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -99
	spin.max_value = 99
	spin.step = 1
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _do_teleport() -> void:
	var macro := _get_macro()
	if macro == null or not macro.has_method("debug_teleport_player"):
		_set_status("No macro world to teleport in.", false)
		return
	var coords := Vector2i(int(_tp_x.value), int(_tp_y.value))
	macro.debug_teleport_player(coords)
	_refresh_target_label()
	_set_status("Teleported to %s." % str(coords))


func _do_advance_time() -> void:
	var world_state := get_node_or_null("/root/WorldState")
	if world_state == null:
		_set_status("WorldState unavailable.", false)
		return
	var minutes := int(_time_amount.value)
	world_state.advance_world_time(minutes)
	var core = _get_core()
	if core != null and core.has_method("process_survival_time"):
		core.process_survival_time(minutes, 15.0, 1.0)
	_sync_after_mutation()
	_refresh_stats()
	_set_status("Advanced world time by %d minutes." % minutes)


func _do_spawn_enemy() -> void:
	var macro := _get_macro()
	if macro == null or not macro.has_method("debug_spawn_enemy_near_player"):
		_set_status("No macro world to spawn into.", false)
		return
	var faction: int = _faction_option.get_selected_id()
	var difficulty := int(_difficulty_spin.value)
	if macro.debug_spawn_enemy_near_player(faction, difficulty):
		_set_status("Spawned %s hostile near player." % _enum_name(
			GameEnums.Faction.keys(), faction
		))
	else:
		_set_status("No free adjacent hex to spawn a hostile.", false)


func _do_save() -> void:
	var director := _get_director()
	if director != null and director.has_method("save_game"):
		director.save_game()
		_set_status("Quick save complete.")
	else:
		_set_status("GameDirector not found.", false)


func _do_load() -> void:
	var director := _get_director()
	if director != null and director.has_method("load_saved_run"):
		director.load_saved_run()
		_set_status("Quick load requested.")
	else:
		_set_status("GameDirector not found.", false)


# ---------------------------------------------------------
# SHARED
# ---------------------------------------------------------

func _sync_after_mutation() -> void:
	var macro := _get_macro()
	if macro != null and macro.has_method("debug_sync_player_after_mutation"):
		macro.debug_sync_player_after_mutation()


func _enum_name(keys: Array, value: int) -> String:
	if value >= 0 and value < keys.size():
		return str(keys[value])
	return str(value)
