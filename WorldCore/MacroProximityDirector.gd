extends RefCounted
class_name MacroProximityDirector

## Proximity / enemy-token lifecycle extracted from MacroGameManager.
## Owns active token projections (coords -> MacroEnemy). Tokens are still
## parented under the host via add_child. Keep this WorldCore-only (no combat presentation/UI imports).

const _NpcSimulator := preload("res://WorldCore/MacroNpcSimulator.gd")

var host: MacroGameManager
var world_state: RuntimeStateStore
var world_generator: HexWorldGenerator
var map_visualizer: HexMapVisualizer
var player_token: MacroPlayer
var mob_spawner: MobSpawner
var enemy_token_scene: PackedScene
## Vector2i -> MacroEnemy projections currently in the scene.
var active_enemies: Dictionary = {}


func _init(host_manager: MacroGameManager = null) -> void:
	if host_manager != null:
		bind_host(host_manager)


func bind_host(host_manager: MacroGameManager) -> void:
	host = host_manager
	sync_host_refs()


func sync_host_refs() -> void:
	if host == null:
		return
	world_state = host._world_state
	world_generator = host.world_generator
	map_visualizer = host.map_visualizer
	player_token = host.player_token
	mob_spawner = host.mob_spawner
	enemy_token_scene = host.enemy_token_scene


func get_token(coords: Vector2i) -> MacroEnemy:
	return active_enemies.get(coords, null) as MacroEnemy


func unload_all() -> void:
	var coords_list: Array = active_enemies.keys()
	for coords in coords_list:
		unload_enemy_token(coords)


func unload_enemy_token(coords: Vector2i) -> void:
	if not active_enemies.has(coords):
		return
	var enemy: MacroEnemy = active_enemies[coords]
	active_enemies.erase(coords)
	_macro_log("Despawned token %s @%s." % [enemy.entity_id, str(coords)])
	enemy.queue_free()


func load_enemy_token(entity_id: String) -> MacroEnemy:
	sync_host_refs()
	if world_state == null:
		return null
	var record_snapshot := world_state.get_entity_snapshot(entity_id)
	var record := (
		EntityRecord.from_dict(record_snapshot)
		if not record_snapshot.is_empty()
		else null
	)
	if (
		record == null
		or not world_state.is_entity_alive(entity_id)
	):
		return null
	return spawn_from_record(record)


func spawn_procedural_enemy(
	coords: Vector2i,
	faction: GameEnums.Faction,
	difficulty: int = 0
) -> void:
	sync_host_refs()
	if not enemy_token_scene:
		push_error("Cannot spawn enemy. Assign the PackedScene in the Inspector.")
		return

	if not mob_spawner:
		push_error("Cannot spawn enemy. MobSpawner is not assigned.")
		return

	if world_state == null:
		return

	if world_state.has_entity_at(coords):
		var existing_snapshot := world_state.get_entity_snapshot_at(coords)
		var existing := (
			EntityRecord.from_dict(existing_snapshot)
			if not existing_snapshot.is_empty()
			else null
		)
		if existing != null and world_state.is_entity_alive(existing.entity_id):
			spawn_from_record(existing)
		return

	var deterministic_key := _NpcSimulator.encounter_key(
		world_state.world_seed,
		coords
	)
	var record := mob_spawner.generate_mob_record(
		coords,
		faction,
		difficulty,
		deterministic_key
	)
	host._initialize_npc_runtime(record)
	world_state.register_entity(record)
	_macro_log(
		"Procedural enemy %s (%s) requested @%s."
		% [record.entity_id, GameEnums.Faction.keys()[faction], str(coords)]
	)
	spawn_from_record(record)


func refresh_proximity(center_coords: Vector2i) -> void:
	sync_host_refs()
	var tokens_before := active_enemies.size()
	host._ensure_encounter_records(center_coords)

	# Hysteresis: tokens are projected within active_radius but only torn down
	# once they drift past the larger unload_radius. Using a single radius for
	# both made tokens thrash (despawn/respawn) whenever the player stepped back
	# and forth across the boundary.
	var unload_radius: int = host.unload_radius
	for coords in active_enemies.keys().duplicate():
		var token: MacroEnemy = active_enemies[coords]
		var distance := _NpcSimulator.hex_distance(center_coords, coords)
		var alive := world_state.is_entity_alive(token.entity_id)
		if distance > unload_radius or not alive:
			_macro_log(
				"Unload token %s @%s (dist %d, alive %s)."
				% [token.entity_id, str(coords), distance, str(alive)]
			)
			unload_enemy_token(coords)

	_trim_visible_npc_tokens(center_coords)

	var max_visible: int = host.max_visible_npc_tokens
	for record in _projection_candidates(center_coords):
		if active_enemies.size() >= max_visible:
			break
		spawn_from_record(record)

	_trim_visible_npc_tokens(center_coords)
	if active_enemies.size() != tokens_before:
		_macro_log(
			"Proximity @%s: tokens %d -> %d (cap %d)."
			% [
				str(center_coords),
				tokens_before,
				active_enemies.size(),
				max_visible,
			]
		)


func force_project_npc_token(record: EntityRecord) -> MacroEnemy:
	sync_host_refs()
	if record == null:
		return null
	if active_enemies.has(record.coords):
		return active_enemies[record.coords]
	var max_visible: int = host.max_visible_npc_tokens
	if active_enemies.size() >= max_visible:
		_trim_visible_npc_tokens(player_token.current_hex_coords)
	if active_enemies.size() >= max_visible:
		var farthest_coords := _farthest_visible_token_coords(
			player_token.current_hex_coords
		)
		if active_enemies.has(farthest_coords):
			unload_enemy_token(farthest_coords)
	return spawn_from_record(record)


func spawn_from_record(record: EntityRecord) -> MacroEnemy:
	sync_host_refs()
	if not enemy_token_scene:
		push_error("Cannot spawn enemy. Assign the PackedScene in the Inspector.")
		return null

	var entity_id: String = record.entity_id
	if world_state == null or not world_state.is_entity_alive(entity_id):
		return null

	var coords: Vector2i = record.coords
	if active_enemies.has(coords):
		var existing := active_enemies[coords] as MacroEnemy
		# Same entity already projected here: reuse it. A DIFFERENT entity sharing
		# the coord means the index desynced (e.g. a record relocated without its
		# token); tear the stale token down so we never render the wrong identity.
		if existing != null and existing.entity_id == entity_id:
			host._apply_enemy_visibility(existing, coords)
			return existing
		_macro_log(
			"Replacing stale token at %s (%s -> %s)."
			% [
				str(coords),
				str(existing.entity_id) if existing != null else "<null>",
				entity_id,
			]
		)
		unload_enemy_token(coords)

	var enemy := enemy_token_scene.instantiate() as MacroEnemy
	host.add_child(enemy)
	enemy.setup_from_record(record.to_dict())
	enemy.snap_to_hex(coords, map_visualizer.map_to_local(coords))
	active_enemies[coords] = enemy
	host._apply_enemy_visibility(enemy, coords)
	if host.has_method("_bind_enemy_inspect_signals"):
		host._bind_enemy_inspect_signals(enemy)

	var definition_state: Dictionary = record.definition
	_macro_log(
		"Spawned token %s (%s) at hex %s."
		% [
			entity_id,
			str(definition_state.get("archetype_name", "Unknown")),
			str(coords),
		]
	)
	return enemy


func _projection_candidates(center_coords: Vector2i) -> Array:
	return _NpcSimulator.projection_candidates(
		_detached_entity_records(),
		center_coords,
		host.active_radius,
		Callable(world_state, "is_entity_alive"),
	)


func _projection_score(record: EntityRecord, center_coords: Vector2i) -> float:
	return _NpcSimulator.projection_score(record, center_coords)


func _trim_visible_npc_tokens(center_coords: Vector2i) -> void:
	var visible_coords := active_enemies.keys()
	visible_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_record := _detached_entity_record(
			(active_enemies[a] as MacroEnemy).entity_id
		)
		var b_record := _detached_entity_record(
			(active_enemies[b] as MacroEnemy).entity_id
		)
		if a_record == null or b_record == null:
			return a_record != null
		return (
			_projection_score(a_record, center_coords)
			> _projection_score(b_record, center_coords)
		)
	)
	var max_visible: int = host.max_visible_npc_tokens
	while visible_coords.size() > max_visible:
		var coords_to_unload: Vector2i = visible_coords.pop_back()
		unload_enemy_token(coords_to_unload)


func _detached_entity_records() -> Array[EntityRecord]:
	var records: Array[EntityRecord] = []
	for snapshot in world_state.get_all_entity_snapshots():
		if snapshot is Dictionary:
			records.append(EntityRecord.from_dict(snapshot))
	return records


func _detached_entity_record(entity_id: String) -> EntityRecord:
	var snapshot := world_state.get_entity_snapshot(entity_id)
	return EntityRecord.from_dict(snapshot) if not snapshot.is_empty() else null


func _farthest_visible_token_coords(center_coords: Vector2i) -> Vector2i:
	return _NpcSimulator.farthest_token_coords(
		active_enemies.keys(),
		center_coords
	)


func _macro_log(message: String) -> void:
	if host != null:
		host._macro_log(message)
