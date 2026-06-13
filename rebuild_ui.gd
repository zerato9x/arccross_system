@tool
extends EditorScript

func _run():
	print("Running Rebuild Script...")
	var scene_path = "res://UI/Inventory/InventoryUI.tscn"
	var packed_scene = ResourceLoader.load(scene_path)
	if not packed_scene:
		print("Failed to load scene")
		return
		
	var root = packed_scene.instantiate()
	var paper_doll = root.get_node("%PaperDollContainer")
	
	# Delete old buttons
	for child in paper_doll.get_children():
		if child.name.begins_with("Slot_"):
			paper_doll.remove_child(child)
			child.queue_free()

	# Create Containers
	var eq_container = Control.new()
	eq_container.name = "EquipmentSlots"
	eq_container.unique_name_in_owner = true
	paper_doll.add_child(eq_container)
	eq_container.owner = root
	
	var bp_container = Control.new()
	bp_container.name = "BackpackSlots"
	bp_container.unique_name_in_owner = true
	paper_doll.add_child(bp_container)
	bp_container.owner = root

	var slot_scene = load("res://UI/Inventory/InventorySlot.tscn")
	
	# Paper Doll Mapping
	# HEAD: 25, 105
	# EYES: 25, 25
	# FACE: 105, 25
	# NECK: 185, 25
	# OUTER: 25, 185
	# INNER: 25, 265
	# VEST: 280, 25
	# BACKPACK: 280, 105
	# ARMS: 265, 25
	# HANDS: 115, 555
	# BELT: 355, 500
	# SLING: 40, 435
	# LEGS: 25, 345
	# FEET: 265, 345
	
	var eq_data = [
		{"slot": 1, "pos": Vector2(25, 105), "tex": "head.png"}, # HEAD
		{"slot": 2, "pos": Vector2(25, 25), "tex": "eyes.png"}, # EYES
		{"slot": 3, "pos": Vector2(105, 25), "tex": "mask.png"}, # FACE
		{"slot": 4, "pos": Vector2(185, 25), "tex": ""}, # NECK
		{"slot": 5, "pos": Vector2(25, 185), "tex": "armor.png"}, # OUTER_TORSO
		{"slot": 6, "pos": Vector2(25, 265), "tex": "clothing.png"}, # INNER_TORSO
		{"slot": 7, "pos": Vector2(280, 25), "tex": "webbing.png"}, # VEST
		{"slot": 8, "pos": Vector2(280, 105), "tex": "backpack.png"}, # BACKPACK
		{"slot": 9, "pos": Vector2(265, 25), "tex": "sidepouch.png"}, # ARMS
		{"slot": 10, "pos": Vector2(115, 555), "tex": "pocket_front.png"}, # HANDS
		{"slot": 11, "pos": Vector2(355, 500), "tex": "belt.png"}, # BELT
		{"slot": 12, "pos": Vector2(40, 435), "tex": "weapon_2h.png"}, # SLING
		{"slot": 13, "pos": Vector2(25, 345), "tex": "pocket.png"}, # LEGS
		{"slot": 14, "pos": Vector2(265, 345), "tex": ""}, # FEET
	]
	
	for ed in eq_data:
		var s = slot_scene.instantiate()
		s.equipment_slot = ed.slot
		if ed.tex != "":
			s.empty_texture = load("res://Asset/UI/" + ed.tex)
		s.position = ed.pos
		s.name = "Slot_" + str(ed.slot)
		eq_container.add_child(s)
		s.owner = root
		# Also ensure children are owned (TextureRects inside the instance)
		# But since it's an instance, we only set owner of the root of the instance.
	
	# Backpack Array
	var backpack_positions = [
		Vector2(355, 25), Vector2(435, 25), Vector2(515, 25), Vector2(595, 25),
		Vector2(355, 105), Vector2(460, 105), Vector2(560, 105),
		Vector2(280, 185), Vector2(355, 185), Vector2(460, 185), Vector2(560, 185),
		Vector2(355, 265), Vector2(435, 265), Vector2(515, 265), Vector2(595, 265),
		Vector2(355, 345), Vector2(435, 345), Vector2(515, 345), Vector2(595, 345),
		Vector2(355, 425), Vector2(435, 425), Vector2(515, 425), Vector2(595, 425)
	]
	var bp_tex = load("res://Asset/UI/backpack_item_slot.png")
	for i in range(backpack_positions.size()):
		var s = slot_scene.instantiate()
		s.equipment_slot = 0 # NONE
		s.empty_texture = bp_tex
		s.position = backpack_positions[i]
		s.name = "BackpackSlot_" + str(i)
		bp_container.add_child(s)
		s.owner = root

	var packed = PackedScene.new()
	var result = packed.pack(root)
	if result == OK:
		ResourceSaver.save(packed, scene_path)
		print("Scene saved successfully.")
	else:
		print("Failed to pack scene: ", result)
