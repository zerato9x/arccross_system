extends Node
class_name MetaProgressionStore

## Cross-run profile. No character, inventory, fog, ordinary loot, ground-item,
## or procedural NPC state belongs here.

signal profile_saved(path: String)
signal meta_event_completed(event_id: String)
signal gateway_state_changed(gateway_id: String, unsealed: bool)
signal core_state_changed(core_id: String, state: Dictionary)
signal campaign_milestone_completed(milestone_id: String)
signal codex_entry_recorded(entry_id: String)

const SAVE_PATH := "user://arccross_meta_progression.json"
const LEGACY_WORLD_PROFILE_PATH := "user://arccross_world_profile.json"
const SAVE_VERSION := 3
const VARIANT_TYPE_KEY := "__arccross_type"
const _MetaCodec := preload("res://SystemCore/MetaProfileCodec.gd")
const _MetaMutations := preload("res://SystemCore/MetaMutationService.gd")
const _Milestones := preload("res://SystemCore/CampaignMilestoneEvaluator.gd")
const STRUCTURAL_FIELDS := [
	"biome",
	"terrain_tile",
	"flora_layer",
	"rock_layer",
	"water_layer",
	"structure_layer",
	"region",
	"arm_direction",
	"zone_id",
	"biome_pack",
	"landmark_id",
	"impassable",
	"terrain_sprite_path",
	"flora_sprite_path",
	"rock_sprite_path",
	"water_sprite_path",
	"structure_sprite_path",
	"sleep_anchor",
	"is_poi",
	"poi_id",
	"poi_name",
	"search_site_id",
	"hazard_level",
	"world_objects",
]

var completed_events: Dictionary = {} # event_id -> true
var gateway_states: Dictionary = {} # gateway_id -> bool
var core_states: Dictionary = {} # core_id -> neutral Dictionary
var node_profile_patches: Dictionary = {} # node_id -> neutral Dictionary
var permanent_node_hex_patches: Dictionary = {} # node_id -> Vector2i -> patch
## Small explicit hub summary used by UI and migration. Detailed condition and
## service mutations still live on the permanent node's world objects.
var shelter_states: Dictionary = {} # node_id -> state descriptor
var codex_entries: Dictionary = {} # knowledge_id -> true
## After eviction, Central Core refuses re-entry until endgame unlock.
## Defaults true so Route 1 guards diegetically hold the lock.
var central_locked: bool = true

var _last_save_error := ""
var profile_path := SAVE_PATH


func _ready() -> void:
	if Engine.is_editor_hint() or OS.get_cmdline_args().has("--script"):
		return
	load_profile()
	evaluate_campaign_milestones(false)


func get_meta_flags() -> Dictionary:
	var flags := gateway_states.duplicate(true)
	for event_id in completed_events.keys():
		flags[str(event_id)] = bool(completed_events[event_id])
	flags["central_locked"] = central_locked
	return flags


func is_central_locked() -> bool:
	return central_locked


func has_codex_entry(entry_id: String) -> bool:
	return bool(codex_entries.get(entry_id, false))


func get_codex_entry_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for entry_id in codex_entries.keys():
		if bool(codex_entries[entry_id]):
			ids.append(str(entry_id))
	ids.sort()
	return ids


func record_codex_entry(entry_id: String, save_after: bool = true) -> bool:
	if entry_id.is_empty() or has_codex_entry(entry_id):
		return false
	codex_entries[entry_id] = true
	codex_entry_recorded.emit(entry_id)
	if save_after:
		save_profile()
	return true


func set_central_locked(locked: bool, save_after: bool = true) -> void:
	if central_locked == locked:
		return
	central_locked = locked
	if save_after:
		save_profile()


func is_event_completed(event_id: String) -> bool:
	return bool(completed_events.get(event_id, false))


func complete_event(event_id: String, effects: Array = []) -> bool:
	if event_id.is_empty():
		return false
	var was_completed := is_event_completed(event_id)
	completed_events[event_id] = true
	apply_effects(effects, false)
	if not was_completed:
		meta_event_completed.emit(event_id)
	save_profile()
	return not was_completed


func apply_effects(effects: Array, save_after: bool = true) -> void:
	for effect in effects:
		if not effect is Dictionary:
			continue
		match str(effect.get("type", "")):
			"set_gateway":
				set_gateway_unsealed(
					str(effect.get("gateway_id", "")),
					bool(effect.get("unsealed", true)),
					false
				)
			"patch_node_profile":
				var node_id := str(effect.get("node_id", ""))
				var patch: Dictionary = effect.get("patch", {})
				if not node_id.is_empty() and not patch.is_empty():
					node_profile_patches[node_id] = _MetaMutations.merged_patch(
					 node_profile_patches.get(node_id, {}),
					 patch
				)
			"set_core_state":
				var core_id := str(effect.get("core_id", ""))
				if not core_id.is_empty():
					set_core_state(core_id, effect.get("state", {}), false)
	if save_after:
		save_profile()


func set_gateway_unsealed(
	gateway_id: String,
	unsealed: bool = true,
	save_after: bool = true
) -> void:
	if gateway_id.is_empty():
		return
	var flag_id := gateway_id
	if not flag_id.begins_with("gateway_"):
		flag_id = "gateway_%s_unsealed" % gateway_id
	elif not flag_id.ends_with("_unsealed"):
		flag_id += "_unsealed"
	if bool(gateway_states.get(flag_id, false)) == unsealed:
		return
	gateway_states[flag_id] = unsealed
	gateway_state_changed.emit(flag_id, unsealed)
	if save_after:
		save_profile()


func is_gateway_unsealed(gateway_id: String) -> bool:
	var flag_id := gateway_id
	if not flag_id.begins_with("gateway_"):
		flag_id = "gateway_%s_unsealed" % gateway_id
	elif not flag_id.ends_with("_unsealed"):
		flag_id += "_unsealed"
	return bool(gateway_states.get(flag_id, false))


func get_node_profile_patch(node_id: String) -> Dictionary:
	return node_profile_patches.get(node_id, {}).duplicate(true)


func get_shelter_state(node_id: String) -> Dictionary:
	return shelter_states.get(node_id, {"state": "ruined"}).duplicate(true)


func set_shelter_state(node_id: String, state: Dictionary, save_after: bool = true) -> void:
	if node_id.is_empty():
		return
	var next := state.duplicate(true)
	if shelter_states.get(node_id, {}) == next:
		return
	shelter_states[node_id] = next
	if save_after:
		save_profile()


func get_core_state(core_id: String) -> Dictionary:
	return core_states.get(core_id, {}).duplicate(true)


func set_core_state(core_id: String, state: Dictionary, save_after: bool = true) -> void:
	if core_id.is_empty():
		return
	var next_state := state.duplicate(true)
	if core_states.get(core_id, {}) == next_state:
		return
	core_states[core_id] = next_state
	core_state_changed.emit(core_id, next_state.duplicate(true))
	evaluate_campaign_milestones(false)
	if save_after:
		save_profile()


func evaluate_campaign_milestones(save_after: bool = true) -> bool:
	var milestone := _Milestones.evaluate(core_states)
	if milestone == null:
		return false
	var newly_completed := not bool(completed_events.get(milestone.completion_event_id, false))
	central_locked = false
	if not milestone.completion_event_id.is_empty():
		completed_events[milestone.completion_event_id] = true
	if newly_completed:
		campaign_milestone_completed.emit(milestone.id)
		meta_event_completed.emit(milestone.completion_event_id)
	if save_after:
		save_profile()
	return newly_completed


func apply_eviction_lock() -> void:
	central_locked = _Milestones.evaluate(core_states) == null
	save_profile()


func apply_patch_to_record(node_id: String, coords: Vector2i, record: HexRecord) -> void:
	if node_id.is_empty() or record == null:
		return
	var node_patches: Dictionary = permanent_node_hex_patches.get(node_id, {})
	var patch: Dictionary = node_patches.get(coords, {})
	for field_name in STRUCTURAL_FIELDS:
		if patch.has(field_name):
			record.set(field_name, patch[field_name])


func capture_node_mutations(
	node_id: String,
	baseline_records: Dictionary,
	hex_records: Dictionary
) -> void:
	if node_id.is_empty():
		return
	var node_patches: Dictionary = permanent_node_hex_patches.get(node_id, {}).duplicate(true)
	for patched_coords in node_patches.keys():
		if not baseline_records.has(patched_coords):
			node_patches.erase(patched_coords)
	# A permanent node can mutate only coordinates in its stable authored
	# baseline. Runtime boundary probes and procedural spillover are never Meta.
	for coords in baseline_records.keys():
		if not coords is Vector2i:
			continue
		var record: HexRecord = hex_records.get(coords)
		if record == null:
			continue
		var baseline: HexRecord = baseline_records.get(coords)
		if baseline == null:
			continue
		var patch: Dictionary = {}
		for field_name in STRUCTURAL_FIELDS:
			var baseline_value: Variant = baseline.get(field_name)
			var current_value: Variant = record.get(field_name)
			if baseline_value != current_value:
				patch[field_name] = current_value
		if patch.is_empty():
			node_patches.erase(coords)
		else:
			node_patches[coords] = patch
	permanent_node_hex_patches[node_id] = node_patches
	save_profile()


func reset_profile() -> void:
	completed_events.clear()
	gateway_states.clear()
	core_states.clear()
	node_profile_patches.clear()
	permanent_node_hex_patches.clear()
	shelter_states.clear()
	codex_entries.clear()
	central_locked = true
	save_profile()


func save_profile(path: String = "") -> bool:
	if path.is_empty():
		path = profile_path
	_last_save_error = ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_last_save_error = "Could not open %s for writing. Error %d." % [
			path, FileAccess.get_open_error()
		]
		push_error("[MetaProgressionStore] " + _last_save_error)
		return false
	var state := MetaProfileState.new()
	state.completed_events = completed_events
	state.gateway_states = gateway_states
	state.core_states = core_states
	state.node_profile_patches = node_profile_patches
	state.permanent_node_hex_patches = permanent_node_hex_patches
	state.shelter_states = shelter_states
	state.codex_entries = codex_entries
	state.central_locked = central_locked
	file.store_string(JSON.stringify(_MetaCodec.encode_state(state, SAVE_VERSION), "\t"))
	file.close()
	profile_saved.emit(path)
	return true


func load_profile(path: String = "") -> bool:
	if path.is_empty():
		path = profile_path
	_last_save_error = ""
	completed_events.clear()
	gateway_states.clear()
	core_states.clear()
	node_profile_patches.clear()
	permanent_node_hex_patches.clear()
	shelter_states.clear()
	codex_entries.clear()
	central_locked = true
	if not FileAccess.file_exists(path):
		_migrate_legacy_profile()
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_last_save_error = "Could not open %s for reading." % path
		return false
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		_last_save_error = "Invalid Meta Progress JSON."
		return false
	var data: Dictionary = _MetaCodec.decode_variant(json.data)
	if int(data.get("version", -1)) != SAVE_VERSION:
		_backup_incompatible_profile(path, int(data.get("version", -1)))
		_last_save_error = "Older Meta Progress was backed up and reset."
		return save_profile(path)
	var profile_state := MetaProfileState.from_dict(data)
	completed_events = profile_state.completed_events
	gateway_states = profile_state.gateway_states
	core_states = profile_state.core_states
	node_profile_patches = profile_state.node_profile_patches
	permanent_node_hex_patches = profile_state.permanent_node_hex_patches
	shelter_states = profile_state.shelter_states
	codex_entries = profile_state.codex_entries
	central_locked = profile_state.central_locked
	evaluate_campaign_milestones(false)
	return true


func _backup_incompatible_profile(path: String, old_version: int) -> void:
	if not FileAccess.file_exists(path):
		return
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return
	var contents := source.get_as_text()
	source.close()
	var absolute := ProjectSettings.globalize_path(path)
	var backup_path := "%s.v%d.bak" % [absolute, old_version]
	var backup := FileAccess.open(backup_path, FileAccess.WRITE)
	if backup != null:
		backup.store_string(contents)
		backup.close()


func get_last_save_error() -> String:
	return _last_save_error


func _migrate_legacy_profile() -> void:
	## Preserve the only safely mappable legacy Meta flag. The old coordinate-only
	## patches stay in their original file rather than leaking into every node.
	if not FileAccess.file_exists(LEGACY_WORLD_PROFILE_PATH):
		return
	var file := FileAccess.open(LEGACY_WORLD_PROFILE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		return
	if bool(json.data.get("core_activated", false)):
		completed_events["legacy_core_activated"] = true
	save_profile()


func _encode_variant(value: Variant) -> Variant:
	return _MetaCodec.encode_variant(value)


func _decode_variant(value: Variant) -> Variant:
	return _MetaCodec.decode_variant(value)
