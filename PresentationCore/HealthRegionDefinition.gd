extends Resource
class_name HealthRegionDefinition

@export var snapshot_region: StringName
@export var display_name: String
@export var limb_region: GameEnums.LimbRegion = GameEnums.LimbRegion.HEAD
@export_file("*.png") var icon_path: String

