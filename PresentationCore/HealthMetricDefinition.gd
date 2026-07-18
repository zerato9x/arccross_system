extends Resource
class_name HealthMetricDefinition

enum ValueTransform {
	DIRECT,
	INVERTED_12,
	TEMPERATURE,
}

@export var snapshot_key: StringName
@export var display_name: String
@export_file("*.png") var icon_path: String
@export var fill_kind: StringName = &"health"
@export var value_transform: ValueTransform = ValueTransform.DIRECT
@export var compact_visible := true
@export var danger_below := -1.0
@export var danger_above := -1.0
@export var caution_below := -1.0
@export var caution_above := -1.0

