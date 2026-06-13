extends Control
class_name PaperDollModel

@onready var bg = $Background
@onready var arm_equip = $Layer_Arm_Equip

var layer_nodes: Dictionary = {}

func _ready() -> void:
	# Map EquipmentSlot enums to their specific TextureRect layer
	# Enum mapping from GameEnums.EquipmentSlot:
	# 1: INNER_TORSO, 2: OUTER_TORSO, 3: HANDS, 4: LEGS, 5: FEET, 6: BACKPACK
	# 7: SLING, 8: BELT, 9: VEST, 10: HEAD, 11: EYES, 12: FACE, 13: NECK, 14: ARMS
	for i in range(1, 15):
		var node_path = "Layer_" + str(i)
		if has_node(node_path):
			layer_nodes[i] = get_node(node_path)

func update_model(equipment_data: Array) -> void:
	# Clear all dynamic layers
	for layer in layer_nodes.values():
		layer.texture = null
		
	arm_equip.texture = null

	# Populate based on dictionary snapshot
	for item in equipment_data:
		var slot_id = item.get("equipment_slot", 0)
		
		# Set primary layer texture
		var tex_path = item.get("paperdoll_texture_path", "")
		if tex_path != "" and layer_nodes.has(slot_id):
			if ResourceLoader.exists(tex_path):
				layer_nodes[slot_id].texture = load(tex_path)
				
		# Handle secondary arm overlays (e.g., coat sleeves)
		var arm_path = item.get("arms_texture_path", "")
		if arm_path != "" and ResourceLoader.exists(arm_path):
			arm_equip.texture = load(arm_path)
