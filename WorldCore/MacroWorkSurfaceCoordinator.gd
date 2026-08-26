extends RefCounted
class_name MacroWorkSurfaceCoordinator

## Owns macro fullscreen-surface arbitration and Node Map overlays.
##
## MacroGameManager remains the public compatibility facade and supplies neutral
## snapshots/callbacks. This coordinator never reads or mutates world authority.

enum Surface {
	NONE,
	INVENTORY,
	HEALTH,
	HERE,
	HEX_MAP,
	SETTINGS,
	SAVE_LOAD,
	NODE_MAP,
	EVENT,
}

const NODE_MAP_INVENTORY_LAYER := 36
const NODE_MAP_OVERLAY_LAYER := 36

var host: Node
var inventory_panel: InventoryUI
var macro_hud: MacroHudController
var node_map_system_scene: PackedScene
var node_map_medical_scene: PackedScene
var node_map_system: CanvasLayer

var _inventory_home_layer: CanvasLayer
var _node_map_overlay_layer: CanvasLayer
var _node_map_medical: Control
var _node_map_inventory_layer_restore := 1
var _callbacks: Dictionary = {}


func configure(
	host_node: Node,
	inventory: InventoryUI,
	hud: MacroHudController,
	node_map_scene: PackedScene,
	medical_scene: PackedScene,
	callbacks: Dictionary
) -> void:
	host = host_node
	inventory_panel = inventory
	macro_hud = hud
	node_map_system_scene = node_map_scene
	node_map_medical_scene = medical_scene
	_callbacks = callbacks.duplicate()
	if inventory_panel != null:
		_inventory_home_layer = inventory_panel.get_parent() as CanvasLayer


func ensure_node_map_system() -> void:
	if node_map_system != null or host == null:
		return
	if node_map_system_scene == null:
		push_error("MacroGameManager requires an authored node_map_system_scene.")
		return
	node_map_system = node_map_system_scene.instantiate() as CanvasLayer
	if node_map_system == null:
		push_error("MacroGameManager node_map_system_scene must instantiate a CanvasLayer.")
		return
	node_map_system.name = "NodeMapSystem"
	host.add_child(node_map_system)
	_connect_if_valid("closed", _callback("node_map_closed"))
	_connect_if_valid("enter_node_requested", _callback("node_map_enter_requested"))
	_connect_if_valid("advance_requested", _callback("node_map_advance_requested"))
	_connect_if_valid("inventory_requested", Callable(self, "open_node_map_inventory"))
	_connect_if_valid("medical_requested", Callable(self, "open_node_map_medical"))


func open_node_map(snapshot: Dictionary) -> bool:
	close_ordinary_surfaces(Surface.NODE_MAP)
	ensure_node_map_system()
	if node_map_system == null:
		return false
	node_map_system.call("open", snapshot)
	_emit_surface_changed()
	return true


func close_node_map() -> void:
	if is_node_map_open():
		node_map_system.call("close")


func refresh_node_map(snapshot: Dictionary) -> void:
	if is_node_map_open():
		node_map_system.call("refresh", snapshot)


func is_node_map_open() -> bool:
	return node_map_system != null and bool(node_map_system.call("is_open"))


func active_surface(event_pending: bool = false) -> int:
	if is_node_map_open():
		return Surface.NODE_MAP
	if (macro_hud != null and macro_hud.is_event_open()) or event_pending:
		return Surface.EVENT
	if inventory_panel != null and inventory_panel.is_open():
		return Surface.INVENTORY
	if macro_hud == null:
		return Surface.NONE
	match macro_hud.get_active_primary_surface():
		&"health":
			return Surface.HEALTH
		&"here":
			return Surface.HERE
		&"hex_map":
			return Surface.HEX_MAP
		&"settings":
			return Surface.SETTINGS
		&"save_load":
			return Surface.SAVE_LOAD
	return Surface.NONE


func close_active_surface() -> bool:
	if is_node_map_open():
		if is_node_map_medical_open():
			close_node_map_medical()
			return true
		if is_node_map_inventory_open():
			inventory_panel.close_top_surface()
			return true
		close_node_map()
		return true
	if macro_hud != null and macro_hud.is_event_open():
		_call("close_interaction")
		return true
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close_top_surface()
		return true
	if macro_hud != null and macro_hud.close_active_primary_surface():
		return true
	return false


func close_ordinary_surfaces(except: int = Surface.NONE) -> void:
	if except != Surface.NODE_MAP and is_node_map_open():
		close_node_map()
	if (
		except != Surface.INVENTORY
		and inventory_panel != null
		and inventory_panel.is_open()
	):
		inventory_panel.close_panel(false)
	if macro_hud != null:
		var hud_except := &""
		match except:
			Surface.HEALTH:
				hud_except = &"health"
			Surface.HERE:
				hud_except = &"here"
			Surface.HEX_MAP:
				hud_except = &"hex_map"
			Surface.SETTINGS:
				hud_except = &"settings"
			Surface.SAVE_LOAD:
				hud_except = &"save_load"
		macro_hud.close_primary_surfaces(hud_except)
	_emit_surface_changed()


func open_hex_world_map() -> bool:
	if macro_hud == null or macro_hud.is_event_open():
		return false
	close_ordinary_surfaces(Surface.HEX_MAP)
	macro_hud.open_hex_world_map()
	_emit_surface_changed()
	return true


func toggle_inventory(snapshot: Dictionary) -> bool:
	if inventory_panel == null:
		return false
	if inventory_panel.is_open():
		inventory_panel.close_panel()
		return true
	if macro_hud != null and macro_hud.is_event_open():
		return false
	close_ordinary_surfaces(Surface.INVENTORY)
	_restore_inventory_parent()
	inventory_panel.open_inventory(snapshot)
	_emit_surface_changed()
	return true


func open_node_map_inventory() -> void:
	if inventory_panel == null:
		return
	close_node_map_medical(false)
	if macro_hud != null:
		var corner := macro_hud.get_inventory_corner_panel()
		if corner != null and corner.is_expanded():
			corner.collapse()
	_restore_inventory_parent()
	var snapshot: Variant = _call("build_inventory_snapshot")
	if not snapshot is Dictionary:
		return
	if _inventory_home_layer != null:
		_node_map_inventory_layer_restore = _inventory_home_layer.layer
	inventory_panel.open_inventory(snapshot)
	if _inventory_home_layer != null:
		_inventory_home_layer.layer = NODE_MAP_INVENTORY_LAYER


func open_node_map_medical() -> void:
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close_panel(false)
		restore_node_map_inventory_layer()
	ensure_node_map_overlay_layer()
	if _node_map_overlay_layer == null:
		return
	if _node_map_medical == null:
		if node_map_medical_scene == null:
			push_error("MacroGameManager requires an authored node_map_medical_scene.")
			return
		var medical_host := Control.new()
		medical_host.name = "NodeMapMedicalHost"
		medical_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		medical_host.mouse_filter = Control.MOUSE_FILTER_STOP
		_node_map_overlay_layer.add_child(medical_host)

		var dim := ColorRect.new()
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.color = Color(0, 0, 0, 0.55)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		medical_host.add_child(dim)

		_node_map_medical = node_map_medical_scene.instantiate() as Control
		if _node_map_medical == null:
			push_error("MacroGameManager node_map_medical_scene must instantiate a Control.")
			return
		_node_map_medical.set("display_mode", 1)
		medical_host.add_child(_node_map_medical)
		_node_map_medical.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_node_map_medical.offset_left = 48.0
		_node_map_medical.offset_top = 48.0
		_node_map_medical.offset_right = -48.0
		_node_map_medical.offset_bottom = -72.0
		var treatment_callback := _callback("medical_action_requested")
		if treatment_callback.is_valid():
			_node_map_medical.connect("limb_treatment_requested", treatment_callback)

		var close_button := Button.new()
		close_button.name = "CloseMedicalButton"
		close_button.text = "Close Medical"
		close_button.custom_minimum_size = HUDAssetLibrary.macro_button_minimum_size(140.0)
		HUDAssetLibrary.apply_button(close_button, "pass")
		close_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		close_button.offset_left = -180.0
		close_button.offset_top = -52.0
		close_button.offset_right = -48.0
		close_button.offset_bottom = -20.0
		close_button.pressed.connect(close_node_map_medical)
		medical_host.add_child(close_button)
	var snapshot: Variant = _call("build_world_hud_snapshot")
	var inventory_snapshot: Variant = _call("build_inventory_snapshot")
	if not snapshot is Dictionary or not inventory_snapshot is Dictionary:
		return
	var inventory_defaults := {
		"equipment": [],
		"containers": [],
		"backpack": [],
		"current_capacity": 0.0,
		"maximum_capacity": 0.0,
		"loadout_stats": {},
	}
	for key in inventory_defaults:
		snapshot[key] = inventory_snapshot.get(key, inventory_defaults[key])
	_node_map_medical.call("apply_snapshot", snapshot)
	_node_map_medical.visible = true
	_node_map_overlay_layer.visible = true


func is_node_map_medical_open() -> bool:
	return _node_map_medical != null and _node_map_medical.visible


func is_node_map_inventory_open() -> bool:
	return (
		inventory_panel != null
		and inventory_panel.is_open()
		and _inventory_home_layer != null
		and _inventory_home_layer.layer == NODE_MAP_INVENTORY_LAYER
	)


func ensure_node_map_overlay_layer() -> void:
	if _node_map_overlay_layer != null or host == null:
		return
	_node_map_overlay_layer = CanvasLayer.new()
	_node_map_overlay_layer.name = "NodeMapOverlayLayer"
	_node_map_overlay_layer.layer = NODE_MAP_OVERLAY_LAYER
	_node_map_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_node_map_overlay_layer)


func close_node_map_medical(_emit_closed: bool = true) -> void:
	if not is_node_map_medical_open():
		return
	_node_map_medical.visible = false
	if _node_map_overlay_layer != null:
		_node_map_overlay_layer.visible = false


func close_node_map_overlays() -> void:
	if is_node_map_inventory_open():
		inventory_panel.close_panel(false)
	restore_node_map_inventory_layer()
	close_node_map_medical(false)


func restore_node_map_inventory_layer() -> void:
	if _inventory_home_layer == null:
		return
	if _inventory_home_layer.layer == NODE_MAP_INVENTORY_LAYER:
		_inventory_home_layer.layer = _node_map_inventory_layer_restore


func inventory_closed() -> void:
	restore_node_map_inventory_layer()
	_emit_surface_changed()


func _restore_inventory_parent() -> void:
	if inventory_panel == null:
		return
	if _inventory_home_layer == null:
		_inventory_home_layer = inventory_panel.get_parent() as CanvasLayer
	if (
		_inventory_home_layer != null
		and inventory_panel.get_parent() != _inventory_home_layer
	):
		inventory_panel.reparent(_inventory_home_layer)


func _connect_if_valid(signal_name: StringName, callback: Callable) -> void:
	if callback.is_valid() and not node_map_system.is_connected(signal_name, callback):
		node_map_system.connect(signal_name, callback)


func _emit_surface_changed() -> void:
	var callback := _callback("surface_changed")
	if callback.is_valid():
		callback.call()


func _call(name: String, args: Array = []) -> Variant:
	var callback := _callback(name)
	if not callback.is_valid():
		return null
	return callback.callv(args)


func _callback(name: String) -> Callable:
	var value: Variant = _callbacks.get(name, Callable())
	return value if value is Callable else Callable()
