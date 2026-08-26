extends RefCounted
class_name RuntimeSaveFileRepository

## Filesystem boundary for disposable run saves.
##
## Version policy and canonical-state validation remain in RuntimeStateStore.
## This repository only reads/writes JSON and performs recoverable replacement.


static func write_snapshot(path: String, snapshot: Dictionary) -> Dictionary:
	var encoded: Variant = RuntimePersistenceCodec.encode_variant(snapshot)
	var temporary_path := path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure(
			"Could not open %s for writing. Error %d."
			% [temporary_path, FileAccess.get_open_error()]
		)
	file.store_string(JSON.stringify(encoded, "\t"))
	file.close()
	if not _replace_file(temporary_path, path):
		return _failure("Could not atomically replace %s." % path)
	return {"ok": true}


static func read_snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("Save file does not exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure(
			"Could not open %s for reading. Error %d."
			% [path, FileAccess.get_open_error()]
		)
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return _failure(
			"Invalid save JSON at line %d: %s"
			% [json.get_error_line(), json.get_error_message()]
		)
	var decoded: Variant = RuntimePersistenceCodec.decode_variant(json.data)
	if not decoded is Dictionary:
		return _failure("Save root is not a Dictionary.")
	return {"ok": true, "snapshot": decoded}


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path)


static func delete(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true}
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if error != OK:
		return _failure("Could not delete %s. Error %d." % [path, error])
	return {"ok": true}


static func backup_incompatible(path: String, old_version: int) -> void:
	## Keep rejected user saves recoverable without polluting project fixtures.
	if not path.begins_with("user://") or not FileAccess.file_exists(path):
		return
	var contents := FileAccess.get_file_as_string(path)
	if contents.is_empty():
		return
	var absolute_path := ProjectSettings.globalize_path(path)
	var backup_path := "%s.v%s.bak" % [absolute_path, old_version]
	var backup := FileAccess.open(backup_path, FileAccess.WRITE)
	if backup != null:
		backup.store_string(contents)
		backup.close()


static func _replace_file(temporary_path: String, final_path: String) -> bool:
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var final_absolute := ProjectSettings.globalize_path(final_path)
	var backup_absolute := final_absolute + ".previous"
	if FileAccess.file_exists(backup_absolute):
		DirAccess.remove_absolute(backup_absolute)
	var had_final := FileAccess.file_exists(final_path)
	if had_final:
		if DirAccess.rename_absolute(final_absolute, backup_absolute) != OK:
			DirAccess.remove_absolute(temporary_absolute)
			return false
	if DirAccess.rename_absolute(temporary_absolute, final_absolute) != OK:
		if had_final and FileAccess.file_exists(backup_absolute):
			DirAccess.rename_absolute(backup_absolute, final_absolute)
		return false
	if FileAccess.file_exists(backup_absolute):
		DirAccess.remove_absolute(backup_absolute)
	return true


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
