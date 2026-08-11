extends RefCounted
class_name RunSlotRepository

const SLOT_PREFIX := "user://arccross_save_"


static func path_for(slot: int) -> String:
	return "%s%d.json" % [SLOT_PREFIX, slot]


static func metadata_for(slot: int, save_version: int, generation_version: int) -> Dictionary:
	var path := path_for(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary:
		return {}
	var data: Dictionary = json.data
	return {
		"slot": slot,
		"timestamp": Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(path)),
		"world_time_minutes": int(data.get("world_time_minutes", 0)),
		"world_seed": str(data.get("world_seed", "")),
		"version": int(data.get("version", -1)),
		"world_generation_version": int(data.get("world_generation_version", -1)),
		"compatible": (
			int(data.get("version", -1)) == save_version
			and int(data.get("world_generation_version", -1)) == generation_version
		),
	}
