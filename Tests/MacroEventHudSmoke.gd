extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_director: Node = await _spawn_game()
	if game_director == null:
		return

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	if macro_map == null or macro_map.macro_hud == null:
		_fail("Macro map or HUD did not initialize.")
		return

	macro_map.debug_begin_macro_event()
	await process_frame
	await process_frame

	if (
		macro_map.get_pending_interaction_type()
		!= GameEnums.MacroInteractionType.MACRO_EVENT
	):
		_fail("Macro event did not become the pending interaction.")
		return

	var event_hud := macro_map.macro_hud.get_node_or_null("MacroEventHud") as MacroEventHud
	if event_hud == null:
		_fail("MacroEventHud is not present under the macro HUD shell.")
		return
	if not event_hud.is_open():
		_fail("MacroEventHud did not open.")
		return
	if macro_map.exploration_window != null and event_hud.layer <= macro_map.exploration_window.layer:
		_fail("MacroEventHud layer must be above the exploration window.")
		return

	var choice_list := event_hud.get_node_or_null("%ChoiceList") as VBoxContainer
	if choice_list == null or choice_list.get_child_count() < 5:
		_fail("MacroEventHud did not render the prototype event choices.")
		return

	if not _has_disabled_choice(choice_list, "Disable the alarm circuit"):
		_fail("Locked contextual choice was missing or lacked a disabled reason.")
		return

	if not _choice_has_label(choice_list, "Listen before touching the door", "OBSERVE"):
		_fail("Event choice did not expose its action kind stake chip.")
		return
	if not _choice_has_label(choice_list, "Listen before touching the door", "+5 MIN"):
		_fail("Event choice did not expose its time stake chip.")
		return
	if not _choice_has_label(choice_list, "Disable the alarm circuit", "LOCKED"):
		_fail("Locked event choice did not expose a locked state chip.")
		return

	var inventory_panel := macro_map.macro_hud.get_inventory_corner_panel()
	var inventory_key := InputEventKey.new()
	inventory_key.pressed = true
	inventory_key.keycode = KEY_I
	macro_map._unhandled_input(inventory_key)
	await process_frame
	if inventory_panel != null and inventory_panel.is_expanded():
		_fail("Macro event modal allowed inventory shortcut input through.")
		return

	var listen_button := _find_choice_button(choice_list, "Listen before touching the door")
	if listen_button == null:
		_fail("Always-available event choice was missing.")
		return
	listen_button.pressed.emit()
	await process_frame

	var result_box := event_hud.get_node_or_null("%ResultBox") as PanelContainer
	if result_box == null or not result_box.visible:
		_fail("Selecting an event choice did not show the result state.")
		return

	var result_meta := event_hud.get_node_or_null("%ResultMeta") as Label
	if result_meta == null or not result_meta.visible or not result_meta.text.contains("+5 min"):
		_fail("Event result did not summarize time/exertion consequences.")
		return

	var continue_button := event_hud.get_node_or_null("%ContinueButton") as Button
	if continue_button == null or not continue_button.visible:
		_fail("Event result did not expose a continue button.")
		return
	continue_button.pressed.emit()
	await process_frame

	if event_hud.is_open():
		_fail("Continuing the event did not close the event HUD.")
		return
	if macro_map.get_pending_interaction_type() != GameEnums.MacroInteractionType.NONE:
		_fail("Closing the event did not clear the pending interaction.")
		return

	print("[TEST PASS] Macro event HUD modal flow and contextual choices.")
	quit(0)


func _spawn_game() -> Node:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	if main_scene == null:
		_fail("Could not load game director scene.")
		return null
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame
	return game_director


func _has_disabled_choice(choice_list: VBoxContainer, label: String) -> bool:
	for row in choice_list.get_children():
		var button := _find_button_in(row, label)
		if button == null or not button.disabled:
			continue
		var reason := _first_label_after_button(row)
		return reason != null and reason.text.begins_with("Requires ")
	return false


func _find_choice_button(choice_list: VBoxContainer, label: String) -> Button:
	for row in choice_list.get_children():
		var button := _find_button_in(row, label)
		if button != null:
			return button
	return null


func _choice_has_label(choice_list: VBoxContainer, choice_label: String, label_text: String) -> bool:
	for row in choice_list.get_children():
		var button := _find_button_in(row, choice_label)
		if button == null:
			continue
		var labels: Array[Label] = []
		_collect_labels(row, labels)
		for label in labels:
			if label.text.contains(label_text):
				return true
	return false


func _find_button_in(node: Node, label: String) -> Button:
	if node is Button and (node as Button).text.contains(label):
		return node as Button
	for child in node.get_children():
		var found := _find_button_in(child, label)
		if found != null:
			return found
	return null


func _first_label_after_button(node: Node) -> Label:
	var labels: Array[Label] = []
	_collect_labels(node, labels)
	return labels[0] if not labels.is_empty() else null


func _collect_labels(node: Node, labels: Array[Label]) -> void:
	if node is Label:
		labels.append(node as Label)
	for child in node.get_children():
		_collect_labels(child, labels)


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
