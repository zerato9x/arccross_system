extends RefCounted
class_name WorldAssetManifest

## Runtime contract for Hex World Generator V2 assets. The external S: library
## is an authoring source only; shipped paths always resolve inside res://.

const VERSION := 2
const MANIFEST_PATH := "res://Tools/world_asset_manifest.json"
const RUNTIME_MANIFEST_PATH := "res://Asset/HexTiles/world_asset_runtime_manifest.json"
const HEX_SIZE := Vector2i(512, 512)

const KIND_TERRAIN_HEX := "terrain_hex"
const KIND_OVERLAY_HEX := "overlay_hex"
const KIND_DECOR_SPRITE := "decor_sprite"


static func load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


static func approved_assets() -> Array:
	if not FileAccess.file_exists(RUNTIME_MANIFEST_PATH):
		return []
	var file := FileAccess.open(RUNTIME_MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed.get("assets", []) if parsed is Dictionary else []


static func approved_asset(asset_id: String) -> Dictionary:
	for entry in approved_assets():
		if entry is Dictionary and str(entry.get("asset_id", "")) == asset_id:
			return entry
	return {}


static func approved_hex_roots() -> PackedStringArray:
	var manifest := load_manifest()
	var output := PackedStringArray()
	for entry in manifest.get("approved_hex_roots", []):
		var path := str(entry).strip_edges()
		if not path.is_empty():
			output.append(path)
	return output


static func import_families() -> Array:
	return load_manifest().get("import_families", [])


static func excluded_hex_name_fragments() -> PackedStringArray:
	var output := PackedStringArray()
	for entry in load_manifest().get("excluded_hex_name_fragments", []):
		output.append(str(entry).to_lower())
	return output


static func is_runtime_hex_path(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	for root in approved_hex_roots():
		var normalized_root := str(root).replace("\\", "/").trim_suffix("/")
		if normalized.begins_with(normalized_root + "/"):
			return true
	return false


static func kind_for_runtime_path(path: String) -> String:
	var normalized := path.replace("\\", "/").to_lower()
	if "/_overlays/" in normalized:
		return KIND_OVERLAY_HEX
	if is_runtime_hex_path(path):
		return KIND_TERRAIN_HEX
	return KIND_DECOR_SPRITE


static func is_explicitly_excluded(path: String) -> bool:
	var lowered := path.replace("\\", "/").to_lower()
	for fragment in excluded_hex_name_fragments():
		if fragment in lowered:
			return true
	return false
