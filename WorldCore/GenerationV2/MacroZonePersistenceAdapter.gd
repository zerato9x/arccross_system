extends RefCounted
class_name MacroZonePersistenceAdapter

## Zone-local persistence bridge. The RuntimeStateStore remains authoritative;
## this adapter only translates generator reads and writes.

var _world_state: RuntimeStateStore


func configure(world_state: RuntimeStateStore) -> void:
	_world_state = world_state


func record_for(coords: Vector2i) -> HexRecord:
	return _world_state.get_hex_record(coords) if _world_state != null else null


func write_hex(coords: Vector2i, hex: MacroHexData) -> void:
	if _world_state != null and hex != null:
		_world_state.set_hex_record(coords, hex.to_state())


func sync_hexes(world_hex_cache: Dictionary) -> void:
	if _world_state == null:
		return
	for coords in world_hex_cache.keys():
		var hex: MacroHexData = world_hex_cache[coords]
		_world_state.set_hex_record(coords, hex.to_state())
