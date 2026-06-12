extends SceneTree

const ITEM_DIRECTORY := "res://ItemCore/Items"
const REQUIRED_CORE_IDS := [
	"water_bottle",
	"mre",
	"blood_bag",
	"sleeping_bag",
	"tentkit",
	"multitool",
	"trap_makeshift",
	"coat_leather",
	"pants_cargo",
	"boot_service",
	"shirt_thermo",
	"backpack_service_big",
	"service_pistol",
	"carbon_pistol",
	"revolver",
	"service_rifle",
	"carbon_rifle",
	"ak47",
	"shotgun",
	"pistol_round",
	"rifle_round",
	"shotgun_shell",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var paths := _resource_paths(ITEM_DIRECTORY)
	if paths.size() < 120:
		_fail("The static catalog is unexpectedly small: %d definitions." % paths.size())
		return

	for required_id in REQUIRED_CORE_IDS:
		var item_path := ITEM_DIRECTORY.path_join(required_id + ".tres")
		var core_item := load(item_path) as ItemData
		if not core_item:
			_fail("Required core item could not be loaded: " + required_id)
			return
		if core_item.id != required_id:
			_fail("Core item ID does not match its resource: " + required_id)
			return
		if (
			core_item.inventory_sprite_path.is_empty()
			or core_item.inventory_sprite_path.contains("/DuelScene/")
			or not ResourceLoader.exists(core_item.inventory_sprite_path)
		):
			_fail("Core item has invalid static presentation: " + required_id)
			return

	print(
		"[TEST PASS] Static item catalog loaded %d unique definitions with "
		% paths.size()
		+ "valid non-DuelScene presentation assets."
	)
	quit(0)

func _resource_paths(root_path: String) -> Array[String]:
	var paths: Array[String] = []
	var directory := DirAccess.open(root_path)
	if not directory:
		return paths
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		var path := root_path.path_join(file_name)
		if directory.current_is_dir():
			if not file_name.begins_with("."):
				paths.append_array(_resource_paths(path))
		elif file_name.ends_with(".tres"):
			paths.append(path)
		file_name = directory.get_next()
	directory.list_dir_end()
	paths.sort()
	return paths

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
