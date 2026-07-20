extends CanvasLayer
class_name InventorySlotContextMenuHost

const HOST_SCENE_PATH := "res://UI/Inventory/InventorySlotContextMenuHost.tscn"

var _menu: InventorySlotContextMenu
var _pending_callback: Callable


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_INHERIT
	add_to_group("slot_context_menu_host")
	_menu = get_node_or_null("InventorySlotContextMenu") as InventorySlotContextMenu
	if _menu == null:
		push_error("InventorySlotContextMenuHost is missing its menu child.")
		return
	if not _menu.menu_action_chosen.is_connected(_on_menu_action_chosen):
		_menu.menu_action_chosen.connect(_on_menu_action_chosen)


static func request_open(
	tree: SceneTree,
	global_pos: Vector2,
	header: String,
	entries: Array,
	callback: Callable,
	_examine_descriptor: Dictionary = {}
) -> void:
	if tree == null:
		return
	var host := _resolve_or_create_host(tree)
	if host == null:
		push_error("InventorySlotContextMenuHost could not be created.")
		return
	host._open(global_pos, header, entries, callback)


static func _resolve_or_create_host(tree: SceneTree) -> InventorySlotContextMenuHost:
	var host := _resolve_host(tree)
	if host != null:
		return host
	if not ResourceLoader.exists(HOST_SCENE_PATH):
		return null
	var scene := load(HOST_SCENE_PATH) as PackedScene
	if scene == null:
		return null
	host = scene.instantiate() as InventorySlotContextMenuHost
	if host == null:
		return null
	host.name = "InventorySlotContextMenuHost"
	tree.root.add_child(host)
	return host


static func _resolve_host(tree: SceneTree) -> InventorySlotContextMenuHost:
	for node in tree.get_nodes_in_group("slot_context_menu_host"):
		if node is InventorySlotContextMenuHost:
			return node
	var named := tree.root.find_child("InventorySlotContextMenuHost", true, false)
	if named is InventorySlotContextMenuHost:
		return named
	return null


func _open(
	global_pos: Vector2,
	header: String,
	entries: Array,
	callback: Callable
) -> void:
	if _menu == null:
		push_error("InventorySlotContextMenuHost has no menu.")
		return
	_pending_callback = callback
	var anchor := _resolve_anchor(global_pos)
	_menu.open_at(anchor, header, entries)


func _resolve_anchor(global_pos: Vector2) -> Vector2:
	if global_pos.length_squared() > 4.0:
		return global_pos
	var viewport := get_viewport()
	if viewport == null:
		return global_pos
	return viewport.get_mouse_position()


func _on_menu_action_chosen(entry: Dictionary) -> void:
	if _pending_callback.is_valid():
		_pending_callback.call(entry)
	_pending_callback = Callable()
