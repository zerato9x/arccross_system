@tool
extends Resource
class_name WorldWorkTaskCatalog

## Authoring catalog for manual work.  Resources are duplicated at lookup so
## a method adjustment never mutates the shared authored asset.

@export var profiles: Array[WorldWorkTaskProfile] = []
@export var methods: Array[WorldWorkMethodDefinition] = []

var _profile_index: Dictionary = {}
var _method_index: Dictionary = {}
var _index_ready: bool = false


func _ensure_index() -> void:
	if _index_ready:
		return
	_profile_index.clear()
	for profile in profiles:
		if profile != null and not profile.profile_id.is_empty():
			_profile_index[profile.profile_id] = profile
	_method_index.clear()
	for method in methods:
		if method != null and not method.method_id.is_empty():
			_method_index[method.method_id] = method
	_index_ready = true


func profile_for_id(profile_id: String) -> WorldWorkTaskProfile:
	_ensure_index()
	var source := _profile_index.get(profile_id) as WorldWorkTaskProfile
	return source.duplicate(true) as WorldWorkTaskProfile if source != null else null


func apply_method_profile(profile: WorldWorkTaskProfile, method_id: String) -> bool:
	_ensure_index()
	var method := _method_index.get(method_id) as WorldWorkMethodDefinition
	if method == null:
		return false
	method.apply_to(profile)
	return true


func profile_ids() -> PackedStringArray:
	_ensure_index()
	return PackedStringArray(_profile_index.keys())


func method_ids() -> PackedStringArray:
	_ensure_index()
	return PackedStringArray(_method_index.keys())
