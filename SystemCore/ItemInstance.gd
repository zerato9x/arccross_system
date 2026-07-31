extends Resource
class_name ItemInstance

## Neutral physical-item contract. ItemCore owns behavioral projections, while
## persistence and combat receipts exchange only this stable identity record.

@export var instance_id: String = ""
@export var definition_id: String = ""
@export_range(0.0, 12.0) var condition: float = 12.0
@export var quantity: int = 1
@export var charges: int = 0
@export var owner_id: String = ""
@export var physical_location: String = "unassigned"
@export var container_instance_id: String = ""
@export var fitted_magazine_instance_id: String = ""
@export var fitted_attachment_instance_ids: Array[String] = []
@export var state: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"definition_id": definition_id,
		"condition": condition,
		"quantity": quantity,
		"charges": charges,
		"owner_id": owner_id,
		"physical_location": physical_location,
		"container_instance_id": container_instance_id,
		"fitted_magazine_instance_id": fitted_magazine_instance_id,
		"fitted_attachment_instance_ids": fitted_attachment_instance_ids.duplicate(),
		"state": state.duplicate(true),
	}


static func from_dict(data: Dictionary) -> ItemInstance:
	var item := ItemInstance.new()
	item.instance_id = str(data.get("instance_id", ""))
	item.definition_id = str(data.get("definition_id", ""))
	item.condition = clampf(float(data.get("condition", 12.0)), 0.0, 12.0)
	item.quantity = maxi(1, int(data.get("quantity", 1)))
	item.charges = maxi(0, int(data.get("charges", 0)))
	item.owner_id = str(data.get("owner_id", ""))
	item.physical_location = str(data.get("physical_location", "unassigned"))
	item.container_instance_id = str(data.get("container_instance_id", ""))
	item.fitted_magazine_instance_id = str(data.get("fitted_magazine_instance_id", ""))
	for attachment_id in data.get("fitted_attachment_instance_ids", []):
		item.fitted_attachment_instance_ids.append(str(attachment_id))
	item.state = data.get("state", {}).duplicate(true)
	return item
