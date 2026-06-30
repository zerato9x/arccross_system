extends SceneTree

const FORBIDDEN_DOMAIN_IMPORTS := {
	"WorldCore": ["CombatCore/", "res://UI/"],
	"CombatCore": ["WorldCore/", "res://UI/"],
	"ItemCore": [
		"WorldCore/",
		"CombatCore/",
		"BiologicalCore/",
		"SystemCore/",
		"SoundCore/",
		"PresentationCore/",
	],
}


func _init() -> void:
	var violations: Array[String] = []
	for domain in FORBIDDEN_DOMAIN_IMPORTS.keys():
		var patterns: Array = FORBIDDEN_DOMAIN_IMPORTS[domain]
		for file_path in _list_gd_files("res://%s" % domain):
			var source := FileAccess.get_file_as_string(file_path)
			for pattern in patterns:
				if source.find(pattern) != -1:
					violations.append("%s imports %s" % [file_path, pattern])

	if not violations.is_empty():
		for violation in violations:
			push_error(violation)
		_fail("Domain boundary violations detected.")
		return

	print("[PASS] Domain boundary imports are clean.")
	quit()


func _list_gd_files(root_path: String) -> Array[String]:
	var results: Array[String] = []
	var stack: Array[String] = [root_path]
	while not stack.is_empty():
		var current: String = stack.pop_back()
		var directory := DirAccess.open(current)
		if directory == null:
			continue
		directory.list_dir_begin()
		var entry: String = directory.get_next()
		while entry != "":
			if entry == "." or entry == "..":
				entry = directory.get_next()
				continue
			var full_path: String = current.path_join(entry)
			if directory.current_is_dir():
				stack.append(full_path)
			elif entry.ends_with(".gd"):
				results.append(full_path)
			entry = directory.get_next()
		directory.list_dir_end()
	return results


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
