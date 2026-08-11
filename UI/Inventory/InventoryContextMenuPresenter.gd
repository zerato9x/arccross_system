extends RefCounted
class_name InventoryContextMenuPresenter

const CONTEXT_MENU_HOST := preload("res://UI/Inventory/InventorySlotContextMenuHost.gd")


func present(
	tree: SceneTree,
	global_position: Vector2,
	header: String,
	entries: Array,
	callback: Callable,
	item_descriptor: Dictionary
) -> void:
	if tree == null or entries.is_empty() or not callback.is_valid():
		return
	CONTEXT_MENU_HOST.request_open(
		tree,
		global_position,
		header,
		entries,
		callback,
		item_descriptor.duplicate(true)
	)
