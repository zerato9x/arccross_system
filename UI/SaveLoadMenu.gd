extends PanelContainer
class_name SaveLoadMenu

signal slot_selected(slot_index: int)
signal menu_closed

@onready var slots_container = %SlotsContainer
@onready var btn_close = %BtnClose
@onready var title_label = %TitleLabel

var _mode := "load" # "save" or "load"

func _ready() -> void:
	HUDAssetLibrary.apply_panel(self, "neutral")
	HUDAssetLibrary.apply_button(btn_close)
	btn_close.pressed.connect(func(): menu_closed.emit())

func setup_mode(mode: String) -> void:
	_mode = mode
	if title_label:
		title_label.text = "SAVE GAME" if _mode == "save" else "LOAD GAME"
	refresh_slots()

func refresh_slots() -> void:
	if not is_inside_tree():
		return
	
	for child in slots_container.get_children():
		child.queue_free()
		
	var save_service = get_node_or_null("/root/SaveLoadService")
	if save_service == null:
		return
	
	for i in range(3):
		var btn = Button.new()
		var meta = save_service.get_save_metadata(i)
		var text = "Slot " + str(i + 1)
		
		if meta.is_empty():
			text += " - Empty"
		elif not bool(meta.get("compatible", false)):
			text += " - Legacy run incompatible\nSelect to start a fresh character (Meta preserved)"
		else:
			var day = (int(meta.get("world_time_minutes", 0)) / 1440) + 1
			text += " - Day " + str(day) + "\n" + str(meta.get("timestamp", ""))
			
		btn.text = text
		btn.custom_minimum_size = Vector2(300, 60)
		HUDAssetLibrary.apply_button(btn)
		
		if _mode == "load" and meta.is_empty():
			btn.disabled = true
			
		btn.pressed.connect(func(): _on_slot_clicked(i))
		slots_container.add_child(btn)

func _on_slot_clicked(slot_index: int) -> void:
	slot_selected.emit(slot_index)
