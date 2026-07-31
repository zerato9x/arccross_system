extends RefCounted
class_name MacroNodeMapSnapshot

## Pure presentation builder for the fullscreen Node Map System window.
## Extracted from MacroGameManager so the graph -> UI dictionary construction
## stays free of node/token side effects. HUD and inventory data are injected
## as plain dictionaries by the caller (WorldCore -> ItemCore/SystemCore only).


static func build(
	campaign: MacroProgressController,
	pending_exit_direction: int,
	hud_snapshot: Dictionary = {},
	inventory_snapshot: Dictionary = {}
) -> Dictionary:
	var next_ids: Array[String] = []
	if pending_exit_direction != GameEnums.MacroTravelDirection.NONE:
		next_ids = campaign.get_directional_destinations(pending_exit_direction)
	var available := campaign.get_available_nodes()
	var newly_revealed := campaign.consume_newly_revealed_node_ids()
	var codex_entries: Array = hud_snapshot.get("codex_entries", [])
	var nodes: Array = []
	var edges: Array = []
	if campaign.graph != null:
		for node_id in campaign.graph.node_ids_in_order():
			var node := campaign.graph.get_node(node_id)
			if node == null:
				continue
			if not entry_visible(campaign, node_id):
				continue
			var entry := node.to_dict()
			var policy_locked := (
				node.role == GameEnums.MacroNodeRole.CENTRAL_CORE
				and campaign.is_central_locked()
			)
			var can_enter := campaign.can_enter_node(node_id, pending_exit_direction)
			var is_active := node_id == campaign.active_node_id
			var is_next := next_ids.has(node_id)
			var enter_reason := ""
			if pending_exit_direction == GameEnums.MacroTravelDirection.NONE:
				enter_reason = "Reach a zone rim and step outward to travel."
			elif not can_enter:
				enter_reason = "No unlocked connection in this exit direction."
			elif is_active:
				enter_reason = "Already present in this node's zone."
				can_enter = false
			entry["can_enter"] = can_enter
			entry["unlocked"] = node.unlocked and not policy_locked
			entry["enter_reason"] = enter_reason
			entry["is_active"] = is_active
			entry["is_next"] = is_next
			entry["detail_hidden"] = not node.details_revealed
			entry["just_revealed"] = newly_revealed.has(node_id)
			if not node.details_revealed:
				entry["display_name"] = "Unknown Route"
				entry["zone_profile_id"] = ""
			entry["zone_flavor"] = zone_flavor(node)
			entry["objective_text"] = objective_text(node)
			entry["intel_entries"] = intel_for_node(node, codex_entries)
			nodes.append(entry)
		for edge in campaign.graph.edges:
			if not (edge is Dictionary):
				continue
			var from_id := str(edge.get("from", ""))
			var to_id := str(edge.get("to", ""))
			if (
				bool(edge.get("visible", true))
				and bool(edge.get("revealed", edge.get("visible", true)))
				and entry_visible(campaign, from_id)
				and entry_visible(campaign, to_id)
			):
				var edge_entry: Dictionary = edge.duplicate(true)
				edge_entry["just_revealed"] = (
					newly_revealed.has(from_id) or newly_revealed.has(to_id)
				)
				edge_entry["eligible"] = (
					from_id == campaign.active_node_id
					and next_ids.has(to_id)
					and int(edge.get("from_direction", 0)) == int(pending_exit_direction)
				)
				edges.append(edge_entry)

	var snapshot := {
		"active_node_id": campaign.active_node_id if campaign != null else "",
		"travel_mode": pending_exit_direction != GameEnums.MacroTravelDirection.NONE,
		"pending_exit_direction": int(pending_exit_direction),
		"available_nodes": available,
		"next_nodes": next_ids,
		"advance_hint": (
			"Travel %s to an adjacent node." % GameEnums.MacroTravelDirection.keys()[pending_exit_direction]
			if not next_ids.is_empty()
			else "Inspect the web, or leave the local map through a connected rim."
		),
		"can_advance": false,
		"advance_reason": (
			"Select an eligible connected node directly."
		),
		"nodes": nodes,
		"edges": edges,
	}

	if not hud_snapshot.is_empty():
		snapshot["blood"] = hud_snapshot.get("blood", 0.0)
		snapshot["pain"] = hud_snapshot.get("pain", 0.0)
		snapshot["shock"] = hud_snapshot.get("shock", 0.0)
		snapshot["consciousness"] = hud_snapshot.get("consciousness", 0.0)
		snapshot["bleeding_rate"] = hud_snapshot.get("bleeding_rate", 0.0)
		snapshot["wound_count"] = hud_snapshot.get("wound_count", 0)
		snapshot["infection_risk"] = hud_snapshot.get("infection_risk", 0.0)
		snapshot["hunger"] = hud_snapshot.get("hunger", 0.0)
		snapshot["thirst"] = hud_snapshot.get("thirst", 0.0)
		snapshot["fatigue"] = hud_snapshot.get("fatigue", 0.0)
		snapshot["morale"] = hud_snapshot.get("morale", 0)
		snapshot["emergencies"] = hud_snapshot.get("emergencies", [])
		snapshot["codex_entries"] = codex_entries
		snapshot["equipment"] = inventory_snapshot.get("equipment", [])
		snapshot["current_capacity"] = inventory_snapshot.get("current_capacity", 0)
		snapshot["maximum_capacity"] = inventory_snapshot.get("maximum_capacity", 0)
		snapshot["loadout_stats"] = inventory_snapshot.get("loadout_stats", {})
	return snapshot


static func entry_visible(campaign: MacroProgressController, node_id: String) -> bool:
	if campaign == null or campaign.graph == null:
		return false
	var node := campaign.graph.get_node(node_id)
	if node == null:
		return false
	if node.hidden_until_discovered and not node.discovered:
		return false
	return true


static func zone_flavor(node: MacroNodeData) -> String:
	if not node.details_revealed:
		return "Unsurveyed route. Enter the zone to identify its properties."
	if node.persistence == GameEnums.MacroNodePersistence.PERMANENT_META:
		return "Permanent Meta node. Structural changes survive every character."
	match node.zone_kind:
		GameEnums.MacroZoneKind.UNIQUE_EVENT:
			return "Authored hex-event site. Resolve the encounter to progress."
		_:
			var biome_name := "unknown"
			var biome_keys := GameEnums.GridBiome.keys()
			if node.biome >= 0 and node.biome < biome_keys.size():
				biome_name = str(biome_keys[node.biome]).capitalize()
			return "Seeded %s zone. Leave through a connected directional rim." % biome_name


static func objective_text(node: MacroNodeData) -> String:
	if node.arm_tier == 1 and node.arm_direction != GameEnums.MacroArmDirection.NONE:
		if node.arm_direction == GameEnums.MacroArmDirection.NORTH:
			return "The North Fringe Relay is the Act 1 gate. Bring it the three relay relics recovered from the surrounding Route 1 arms."
		var landmarks := Route1LandmarkCatalog.data()
		var landmark := landmarks.for_arm(_arm_id(node.arm_direction)) if landmarks != null else null
		if landmark != null:
			return "Search %s and its roadside caches. Recover supplies, world evidence, and anything that points back to the North relay." % landmark.display_name
	if node.role == GameEnums.MacroNodeRole.GATEWAY and not node.unlocked:
		return "Sealed by Meta Progress."
	if node.role == GameEnums.MacroNodeRole.CENTRAL_CORE:
		return "Return recovered core components here."
	if node.role == GameEnums.MacroNodeRole.META_BRANCH:
		return "Recover the North Core Regulator."
	return "Traverse the zone through a graph-connected rim."


static func intel_for_node(node: MacroNodeData, codex_entries: Array) -> Array:
	var arm_id := _arm_id(node.arm_direction)
	var matches: Array = []
	for entry in codex_entries:
		if entry is Dictionary and str(entry.get("region_id", "")) == arm_id:
			matches.append(entry.duplicate(true))
	return matches


static func _arm_id(direction: int) -> String:
	match direction:
		GameEnums.MacroArmDirection.NORTH:
			return "north"
		GameEnums.MacroArmDirection.EAST:
			return "east"
		GameEnums.MacroArmDirection.SOUTH:
			return "south"
		GameEnums.MacroArmDirection.WEST:
			return "west"
		_:
			return ""
