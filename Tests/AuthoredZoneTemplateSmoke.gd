extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://WorldCore/plains_zone_template.tscn") as PackedScene
	if packed == null:
		_fail("Could not load the plains authoring template.")
		return
	var template := packed.instantiate()
	root.add_child(template)
	var terrain := template.get_node_or_null("TerrainLayer") as TileMapLayer
	var water := template.get_node_or_null("WaterLayer") as TileMapLayer
	var baker := template.get_node_or_null("AuthoredWorldMapBaker") as AuthoredWorldMapBaker
	if terrain == null or water == null or baker == null:
		_fail("Template is missing TerrainLayer, WaterLayer, or its baker.")
		return
	if terrain.get_used_cells().size() != GameEnums.MACRO_ZONE_CELL_COUNT:
		_fail("Template does not contain exactly 469 terrain cells.")
		return
	for coords in terrain.get_used_cells():
		if not HexCoordUtils.is_in_radius(coords, GameEnums.MACRO_ZONE_RADIUS):
			_fail("Terrain escaped radius 12 at %s." % str(coords))
			return
	if water.get_used_cells().size() != 3:
		_fail("Expected the three-cell manual water example.")
		return

	var baked := baker.bake_to_resource(false) as AuthoredWorldMap
	if baked == null or baked.entries.size() != GameEnums.MACRO_ZONE_CELL_COUNT:
		_fail("Baker did not emit 469 authored entries.")
		return
	if baked.decorations.size() != 3:
		_fail("Expected the three-prop manual decoration example.")
		return
	var arrivals := baked.get_sockets(HexMapSocket.SocketKind.ARRIVAL)
	var exits := baked.get_sockets(HexMapSocket.SocketKind.EXIT)
	if arrivals.size() != 8 or exits.size() != 8:
		_fail("Expected eight arrival and eight exit sockets.")
		return
	for socket in arrivals + exits:
		var direction := int(socket.get("direction", GameEnums.MacroTravelDirection.NONE))
		var expected := HexCoordUtils.rim_anchor(direction, GameEnums.MACRO_ZONE_RADIUS)
		if socket.get("coords", Vector2i.ZERO) != expected:
			_fail("Socket %s is not at %s." % [socket.get("socket_id", "?"), expected])
			return
	if baked.get_sockets(HexMapSocket.SocketKind.POI).size() != 1:
		_fail("Variable POI socket example missing.")
		return
	if baked.get_sockets(HexMapSocket.SocketKind.ENCOUNTER).size() != 1:
		_fail("Encounter socket example missing.")
		return
	if baked.get_sockets(HexMapSocket.SocketKind.QUEST_ITEM).size() != 1:
		_fail("Quest-object socket example missing.")
		return
	for coords in water.get_used_cells():
		var hex := baked.build_hex_data(coords)
		if (
			hex.water_layer != GameEnums.MacroWaterLayer.SHALLOW_RIVER
			or hex.water_sprite_path.is_empty()
		):
			_fail("Water paint did not survive baking at %s." % str(coords))
			return
	print("[TEST PASS] Authored plains template: 469 cells, manual layers, props, and sockets.")
	quit(0)


func _fail(message: String) -> void:
	push_error("[TEST FAIL] %s" % message)
	quit(1)
