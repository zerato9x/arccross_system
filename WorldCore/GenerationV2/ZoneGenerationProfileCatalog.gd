@tool
extends Resource
class_name ZoneGenerationProfileCatalog

@export var profiles: Array[ZoneGenerationProfile] = []
var _index: Dictionary = {}
var _index_ready := false


func _ensure_index() -> void:
	if _index_ready:
		return
	_index.clear()
	for profile in profiles:
		if profile != null and not profile.profile_id.is_empty():
			_index[profile.profile_id] = profile
	_index_ready = true


func profile_for_arm(
	arm_key: String,
	include_settlement: bool = false
) -> ZoneGenerationProfile:
	_ensure_index()
	var profile := _index.get("starter_node_%s_v3" % arm_key) as ZoneGenerationProfile
	if profile == null:
		return ZoneGenerationProfile.starter_node(arm_key, include_settlement)
	var result := profile.duplicate(true) as ZoneGenerationProfile
	if include_settlement:
		result.simulated_resident_count = maxi(1, result.simulated_resident_count)
	else:
		result.required_stamp_ids = PackedStringArray()
		result.simulated_resident_count = 0
	return result


func validate_ids() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for profile in profiles:
		if profile == null:
			errors.append("null zone profile")
			continue
		if profile.profile_id.is_empty():
			errors.append("zone profile with empty ID")
		elif seen.has(profile.profile_id):
			errors.append("duplicate zone profile ID: %s" % profile.profile_id)
		else:
			seen[profile.profile_id] = true
	return errors
