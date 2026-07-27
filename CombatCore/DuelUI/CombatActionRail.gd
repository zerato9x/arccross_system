extends Node2D
class_name CombatActionRail

## Action command rail extracted from CombatLaneHUD: group tabs, action buttons,
## firearm/melee/aim/push menus, and hotkey activation helpers.

const ACTION_BUTTON_SIZE := Vector2(174.0, 42.0)
const ACTION_BUTTON_GAP := Vector2(10.0, 8.0)
const ACTION_BUTTON_COLUMNS := 4
const GROUP_BUTTON_SIZE := Vector2(98.0, 30.0)

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

signal action_requested(action: int, target_limb: int, item_instance_id: String)
signal pass_requested
signal reaction_selected(reaction: int)
signal target_limb_focused(limb: int)
signal target_limb_unfocused
signal context_changed

var _action_button_scene: PackedScene
var _action_button_root: Node2D
var _group_tab_root: Node2D
var _action_panel_box: Polygon2D
var _action_panel_border: Line2D
var _action_panel_frame: Sprite2D
var _action_title_label: Label
var _weapon_panel_root: Node2D

var _hud_density_scale := 1.0
var _group_tabs_rect := Rect2()
var _action_list_rect := Rect2()

var _snapshot: Dictionary = {}
var _reaction_prompt: Dictionary = {}
var _melee_lock := false

var _action_buttons: Array = []
var _group_buttons: Array = []
var _selected_action_group := ACTION_GROUP_FIREARM
var _action_group_locked_by_user := false
var _visible_action_groups: Array[String] = []
var _command_menu_path: Array[String] = []


func configure(
	action_button_root: Node2D,
	group_tab_root: Node2D,
	action_panel_box: Polygon2D,
	action_panel_border: Line2D,
	action_panel_frame: Sprite2D,
	action_title_label: Label,
	weapon_panel_root: Node2D,
	action_button_scene: PackedScene,
	density_scale: float = 1.0
) -> void:
	_action_button_root = action_button_root
	_group_tab_root = group_tab_root
	_action_panel_box = action_panel_box
	_action_panel_border = action_panel_border
	_action_panel_frame = action_panel_frame
	_action_title_label = action_title_label
	_weapon_panel_root = weapon_panel_root
	_action_button_scene = action_button_scene
	_hud_density_scale = density_scale


func set_density_scale(density: float) -> void:
	_hud_density_scale = density


func set_layout_rects(group_tabs_rect: Rect2, action_list_rect: Rect2) -> void:
	_group_tabs_rect = group_tabs_rect
	_action_list_rect = action_list_rect


func unlock_group_selection() -> void:
	_action_group_locked_by_user = false


func get_selected_action_group() -> String:
	return _selected_action_group


func get_command_menu_path() -> Array[String]:
	return _command_menu_path.duplicate()


func clear() -> void:
	_clear_action_buttons()
	_clear_group_buttons()
	_command_menu_path.clear()
	_visible_action_groups.clear()
	_selected_action_group = ACTION_GROUP_FIREARM
	_action_group_locked_by_user = false
	_snapshot.clear()
	_reaction_prompt.clear()
	_melee_lock = false


func render(
	snapshot: Dictionary,
	reaction_prompt: Dictionary,
	melee_lock: bool = false
) -> void:
	_snapshot = snapshot
	_reaction_prompt = reaction_prompt
	_melee_lock = melee_lock
	_render_actions()


func cycle_group(direction: int) -> void:
	_cycle_action_group(direction)


func activate_index(index: int) -> bool:
	if index < 0 or index >= _action_buttons.size():
		return false
	var button := _action_buttons[index] as CombatActionButton
	if button == null or not is_instance_valid(button):
		return false
	button.activate()
	return true


func activate_zero() -> bool:
	for raw_button in _action_buttons:
		var button := raw_button as CombatActionButton
		if button == null or not is_instance_valid(button):
			continue
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
			return true
	return false


func group_label(group: String) -> String:
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


func group_hint(group: String, audio_family: String = "") -> String:
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


func _render_actions() -> void:
	_clear_action_buttons()
	_clear_group_buttons()
	var has_snapshot := not _snapshot.is_empty()
	if _action_panel_box:
		_action_panel_box.visible = has_snapshot
	if _action_panel_border:
		_action_panel_border.visible = has_snapshot
	if _action_panel_frame:
		_action_panel_frame.visible = false
	if _action_title_label:
		_action_title_label.visible = has_snapshot
	if _action_button_root:
		_action_button_root.visible = has_snapshot
	if _weapon_panel_root:
		_weapon_panel_root.visible = has_snapshot
	if _group_tab_root:
		_group_tab_root.visible = has_snapshot
	if not has_snapshot:
		return

	if not _reaction_prompt.is_empty():
		if _action_title_label:
			_action_title_label.text = "REACTION"
		_render_reaction_buttons()
		return
	if not _snapshot.get("is_player_turn", false):
		if _action_title_label:
			_action_title_label.text = "ENEMY TURN"
		return
	if _snapshot.get("busy", false):
		if _action_title_label:
			_action_title_label.text = "RESOLVING"
		return

	if _action_title_label:
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
	if _melee_lock:
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
		var text := "%s %02d" % [group_label(group), count]
		_add_group_button(payload, text, index, group == _selected_action_group)
		index += 1


func _add_group_button(
	payload: Dictionary,
	text: String,
	index: int,
	selected: bool
) -> void:
	if _group_tab_root == null or _action_button_scene == null:
		return
	var button := _action_button_scene.instantiate() as CombatActionButton
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
	var logical_width := _group_tabs_rect.size.x / maxf(0.001, _hud_density_scale)
	var fit := int(
		floor(
			(logical_width + 8.0)
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
	if _action_button_root == null or _action_button_scene == null:
		return
	var button := _action_button_scene.instantiate() as CombatActionButton
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
	var logical_width := _action_list_rect.size.x / maxf(0.001, _hud_density_scale)
	var fit := int(
		floor(
			(logical_width + ACTION_BUTTON_GAP.x)
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
	context_changed.emit()


func _on_target_limb_focused(limb: int) -> void:
	target_limb_focused.emit(limb)


func _on_target_limb_unfocused() -> void:
	target_limb_unfocused.emit()


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
				context_changed.emit()
		BUTTON_MODE_BACK:
			if not _command_menu_path.is_empty():
				_command_menu_path.pop_back()
				_render_actions()
				context_changed.emit()


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
	context_changed.emit()


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
