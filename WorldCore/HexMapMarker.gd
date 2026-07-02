@tool
extends Node2D
class_name HexMapMarker

## Editor-only metadata marker for a painted hex. The baker merges these with
## TileMap layers when writing AuthoredWorldMap resources.

@export_group("Editor Helpers")
@export var coord_layer: TileMapLayer
@export var hex_coords: Vector2i = Vector2i.ZERO
@export var is_poi: bool = false
@export var poi_id: String = ""
@export var poi_name: String = ""
@export var landmark_id: String = ""
@export var sleep_anchor: String = "ground"
@export var impassable: bool = false
@export var region: GameEnums.MacroRegion = GameEnums.MacroRegion.WASTELAND
@export var arm_direction: GameEnums.MacroArmDirection = (
	GameEnums.MacroArmDirection.NONE
)
@export_range(1, 3) var arm_stage: int = 1
@export var zone_id: String = ""
@export_range(0.0, 12.0) var hazard_level: float = 0.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	if coord_layer == null:
		coord_layer = _guess_coord_layer()


func _guess_coord_layer() -> TileMapLayer:
	var root := get_tree().edited_scene_root
	if root == null:
		root = get_parent()
	while root != null:
		var candidate := root.get_node_or_null("TerrainLayer")
		if candidate is TileMapLayer:
			return candidate as TileMapLayer
		root = root.get_parent()
	return null


func sync_coords_from_position(layer: TileMapLayer = null, snap_to_center: bool = false) -> void:
	var resolved := layer if layer != null else coord_layer
	if resolved == null:
		resolved = _guess_coord_layer()
	if resolved == null:
		push_warning("[HexMapMarker] No coord layer set; cannot sync coords.")
		return
	var local_pos := resolved.to_local(global_position)
	hex_coords = resolved.local_to_map(local_pos)
	if snap_to_center:
		global_position = resolved.to_global(resolved.map_to_local(hex_coords))


func to_entry() -> Dictionary:
	var resolved_region := region
	if resolved_region == GameEnums.MacroRegion.WASTELAND and arm_stage > 0:
		match arm_stage:
			1:
				resolved_region = GameEnums.MacroRegion.ARM_STAGE_1
			2:
				resolved_region = GameEnums.MacroRegion.ARM_STAGE_2
			3:
				resolved_region = GameEnums.MacroRegion.ARM_STAGE_3

	return {
		"coords": hex_coords,
		"is_poi": is_poi,
		"poi_id": poi_id,
		"poi_name": poi_name,
		"landmark_id": landmark_id,
		"sleep_anchor": sleep_anchor,
		"impassable": impassable,
		"region": resolved_region,
		"arm_direction": arm_direction,
		"zone_id": zone_id,
		"hazard_level": hazard_level,
	}
