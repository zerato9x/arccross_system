@tool
extends EditorPlugin

const EDITOR_SCENE_PATH := "res://WorldCore/world_map_editor.tscn"

var _dock: Control


func _enter_tree() -> void:
	_build_dock()
	add_control_to_dock(DOCK_SLOT_LEFT_BR, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
	_dock = null


func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "World Map"

	var title := Label.new()
	title.text = "World Map Tools"
	_dock.add_child(title)

	_dock.add_child(_button("Open World Map Editor", _open_editor_scene))
	_dock.add_child(_button("Bake Authored Map", _bake_current_scene))
	_dock.add_child(_button("Sync Selected Marker Coords", _sync_selected_markers))
	_dock.add_child(_button("Snap Selected Markers To Hex", _snap_selected_markers))
	_dock.add_child(_button("Sync Selected Decor Coords", _sync_selected_decor))

	var sep := HSeparator.new()
	_dock.add_child(sep)

	_dock.add_child(_button("Create Marker (at origin)", _create_marker))
	_dock.add_child(_button("Create Decor Prop (at origin)", _create_decor))


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _open_editor_scene() -> void:
	if not ResourceLoader.exists(EDITOR_SCENE_PATH):
		push_warning("Missing editor scene: %s" % EDITOR_SCENE_PATH)
		return
	EditorInterface.open_scene_from_path(EDITOR_SCENE_PATH)


func _current_scene_root() -> Node:
	return get_tree().edited_scene_root


func _bake_current_scene() -> void:
	var root := _current_scene_root()
	if root == null:
		return
	var baker := root.find_child("AuthoredWorldMapBaker", true, false)
	if baker != null and baker.has_method("bake_to_resource"):
		baker.call("bake_to_resource", true)
		return
	push_warning("No AuthoredWorldMapBaker found in current scene.")


func _sync_selected_markers() -> void:
	_call_world_map_editor_button("_editor_sync_selected_markers")


func _snap_selected_markers() -> void:
	_call_world_map_editor_button("_editor_snap_selected_markers")


func _sync_selected_decor() -> void:
	_call_world_map_editor_button("_editor_sync_selected_decor")


func _create_marker() -> void:
	_call_world_map_editor_button("_editor_create_marker")


func _create_decor() -> void:
	_call_world_map_editor_button("_editor_create_decor_prop")


func _call_world_map_editor_button(method_name: String) -> void:
	var root := _current_scene_root()
	if root == null:
		return
	if root.has_method(method_name):
		root.call(method_name)
		return
	var editor := root.find_child("WorldMapEditor", true, false)
	if editor != null and editor.has_method(method_name):
		editor.call(method_name)
		return
	push_warning("WorldMapEditor method missing: %s" % method_name)

