extends CanvasLayer
class_name InventorySlotContextMenuHost

const HOST_SCENE_PATH := "res://UI/Inventory/InventorySlotContextMenuHost.tscn"

var _menu: InventorySlotContextMenu
var _examine_card: InventorySlotExamineCard
var _pending_callback: Callable
var _pending_examine: Dictionary = {}


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_INHERIT
	add_to_group("slot_context_menu_host")
	_menu = get_node_or_null("InventorySlotContextMenu") as InventorySlotContextMenu
	_examine_card = get_node_or_null("InventorySlotExamineCard") as InventorySlotExamineCard
	if _menu == null:
		push_error("InventorySlotContextMenuHost is missing its menu child.")
		return
	if not _menu.menu_action_chosen.is_connected(_on_menu_action_chosen):
		_menu.menu_action_chosen.connect(_on_menu_action_chosen)
	if not _menu.menu_presented.is_connected(_on_menu_presented):
		_menu.menu_presented.connect(_on_menu_presented)
	if not _menu.menu_closed.is_connected(_on_menu_closed):
		_menu.menu_closed.connect(_on_menu_closed)


static func request_open(
	tree: SceneTree,
	global_pos: Vector2,
	header: String,
	entries: Array,
	callback: Callable,
	examine_descriptor: Dictionary = {}
) -> void:
	if tree == null:
		return
	var host := _resolve_or_create_host(tree)
	if host == null:
		push_error("InventorySlotContextMenuHost could not be created.")
		return
	host._open(global_pos, header, entries, callback, examine_descriptor)


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
	callback: Callable,
	examine_descriptor: Dictionary
) -> void:
	if _menu == null:
		push_error("InventorySlotContextMenuHost has no menu.")
		return
	_pending_callback = callback
	_pending_examine = examine_descriptor.duplicate(true)
	if _examine_card != null:
		if _pending_examine.is_empty():
			_examine_card.hide_card()
		else:
			_examine_card.show_descriptor(_pending_examine)
	var anchor := _resolve_anchor(global_pos)
	_menu.open_at(anchor, header, entries)


func _resolve_anchor(global_pos: Vector2) -> Vector2:
	if global_pos.length_squared() > 4.0:
		return global_pos
	var viewport := get_viewport()
	if viewport == null:
		return global_pos
	return viewport.get_mouse_position()


func _on_menu_presented(menu_rect: Rect2) -> void:
	if _examine_card == null or _pending_examine.is_empty():
		return
	_examine_card.position_beside_menu(menu_rect)


func _on_menu_closed() -> void:
	if _examine_card != null:
		_examine_card.hide_card()
	_pending_examine.clear()


func _on_menu_action_chosen(entry: Dictionary) -> void:
	if _pending_callback.is_valid():
		_pending_callback.call(entry)
	_pending_callback = Callable()
