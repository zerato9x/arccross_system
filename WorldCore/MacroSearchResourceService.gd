extends RefCounted
class_name MacroSearchResourceService

## Applies finite physical search-resource depletion and disturbance traces.
## Search outcome rules remain in MacroPoiController/MacroInteractionResolver;
## this service owns only the persistent world-object mutation.

var world_state: RuntimeStateStore
var world_generator: HexWorldGenerator


func configure(state: RuntimeStateStore, generator: HexWorldGenerator) -> void:
	world_state = state
	world_generator = generator


func deplete(
	coords: Vector2i,
	target_id: String,
	actor_id: String
) -> void:
	if world_state == null or world_generator == null:
		return
	var hex := world_generator.get_hex_at(coords)
	for index in range(hex.world_objects.size()):
		var value: Dictionary = hex.world_objects[index]
		if str(value.get("object_id", "")) != target_id:
			continue
		var target := WorldObjectRecord.from_dict(value)
		var resource_component := (
			"rubble" if target.has_component("rubble") else "debris"
		)
		if target.has_component(resource_component):
			var rubble := target.component(resource_component).duplicate(true)
			rubble["material_units"] = maxi(
				0,
				int(rubble.get("material_units", 1)) - 1
			)
			rubble["depleted"] = int(rubble.get("material_units", 0)) <= 0
			target.components[resource_component] = rubble
			if bool(rubble.get("depleted", false)) and target.has_component("container"):
				var container_after_rubble := target.component("container").duplicate(true)
				if bool(container_after_rubble.get("finite", false)):
					container_after_rubble["remaining_searches"] = 0
					container_after_rubble["depleted"] = true
					target.components["container"] = container_after_rubble
		elif target.has_component("container"):
			var container := target.component("container").duplicate(true)
			if bool(container.get("finite", false)):
				container["remaining_searches"] = maxi(
					0,
					int(container.get("remaining_searches", 1)) - 1
				)
				container["depleted"] = int(container.get("remaining_searches", 0)) <= 0
				target.components["container"] = container
			else:
				return
		else:
			return
		target.revision += 1
		hex.world_objects[index] = target.to_dict()
		hex.trace_records.append({
			"kind": "disturbed_rubble",
			"source_id": actor_id,
			"coords": coords,
			"created_minute": world_state.world_time_minutes,
			"expires_minute": world_state.world_time_minutes + 120,
			"age_minutes": 0,
			"direction": str(coords),
		})
		world_generator.commit_hex_projection(coords, hex)
		return


func build_depletion(
	coords: Vector2i,
	target_id: String,
	actor_id: String
) -> Dictionary:
	if world_state == null:
		return {}
	var hex := world_state.get_hex_record(coords)
	if hex == null:
		return {}
	for value in hex.world_objects:
		if not value is Dictionary or str(value.get("object_id", "")) != target_id:
			continue
		var target := WorldObjectRecord.from_dict(value)
		var resource_component := "rubble" if target.has_component("rubble") else "debris"
		if target.has_component(resource_component):
			var resource := target.component(resource_component).duplicate(true)
			resource["material_units"] = maxi(0, int(resource.get("material_units", 1)) - 1)
			resource["depleted"] = int(resource.get("material_units", 0)) <= 0
			target.components[resource_component] = resource
			if bool(resource.get("depleted", false)) and target.has_component("container"):
				var container := target.component("container").duplicate(true)
				if bool(container.get("finite", false)):
					container["remaining_searches"] = 0
					container["depleted"] = true
					target.components["container"] = container
		elif target.has_component("container"):
			var container := target.component("container").duplicate(true)
			if not bool(container.get("finite", false)):
				return {}
			container["remaining_searches"] = maxi(0, int(container.get("remaining_searches", 1)) - 1)
			container["depleted"] = int(container.get("remaining_searches", 0)) <= 0
			target.components["container"] = container
		else:
			return {}
		return {
			"target_state": target.to_dict(),
			"trace": {
				"kind": "disturbed_rubble",
				"source_id": actor_id,
				"coords": coords,
				"created_minute": world_state.world_time_minutes,
				"expires_minute": world_state.world_time_minutes + 120,
				"age_minutes": 0,
				"direction": str(coords),
			},
		}
	return {}
