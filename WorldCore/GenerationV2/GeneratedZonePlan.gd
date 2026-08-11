extends RefCounted
class_name GeneratedZonePlan

const VERSION := 3

var profile_id: String = ""
var zone_seed: String = ""
var radius: int = 0
var has_settlement: bool = false
var settlement_coords: Vector2i = Vector2i.ZERO
var gameplay_anchor_coords: Vector2i = Vector2i.ZERO
var road_cells: Dictionary = {} # Vector2i -> six-bit connection mask
var cell_roles: Dictionary = {} # Vector2i -> String
var stamp_cells: Dictionary = {} # Vector2i -> Dictionary
var rubble_search_cells: Array[Vector2i] = []
var visual_rubble_cells: Array[Vector2i] = []
var trace_records: Array[Dictionary] = []
var validation_errors: PackedStringArray = []
var seam_violations: Array[Dictionary] = []
var road_socket_violations: Array[Dictionary] = []
var unreachable_cells: Array[Vector2i] = []
var overflow_violations: Array[Dictionary] = []
var terrain_asset_usage: Dictionary = {}


func role_at(coords: Vector2i) -> String:
	return str(cell_roles.get(coords, "quiet_plains"))


func road_mask_at(coords: Vector2i) -> int:
	return int(road_cells.get(coords, 0))


func is_valid() -> bool:
	return validation_errors.is_empty()


func diagnostic_report() -> Dictionary:
	var role_counts: Dictionary = {}
	var road_mask_usage: Dictionary = {}
	for role in cell_roles.values():
		role_counts[str(role)] = int(role_counts.get(str(role), 0)) + 1
	for mask in road_cells.values():
		road_mask_usage["%02d" % int(mask)] = int(road_mask_usage.get("%02d" % int(mask), 0)) + 1
	return {
		"world_generation_version": VERSION,
		"profile_id": profile_id,
		"zone_seed": zone_seed,
		"radius": radius,
		"has_settlement": has_settlement,
		"cell_count": cell_roles.size(),
		"settlement_coords": [settlement_coords.x, settlement_coords.y],
		"road_cell_count": road_cells.size(),
		"rubble_search_count": rubble_search_cells.size(),
		"visual_rubble_count": visual_rubble_cells.size(),
		"trace_count": trace_records.size(),
		"truth_view_cell_count": 37,
		"role_counts": role_counts,
		"asset_usage": {
			"terrain": terrain_asset_usage.duplicate(true),
			"road_masks": road_mask_usage,
		},
		"seam_violations": seam_violations.duplicate(true),
		"road_socket_violations": road_socket_violations.duplicate(true),
		"unreachable_cells": unreachable_cells.duplicate(),
		"overflow_violations": overflow_violations.duplicate(true),
		"validation_errors": Array(validation_errors),
	}
