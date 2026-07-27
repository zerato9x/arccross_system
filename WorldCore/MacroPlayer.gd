extends Node2D
class_name MacroPlayer

const WALK_DURATION_SECONDS := 2.0

@export var definition: EntityDefinition

@onready var humanoid_core: HumanoidCore = $HumanoidCore
@onready var humanoid_token: HumanoidTokenView = $HumanoidTokenView

var current_hex_coords: Vector2i = Vector2i(0, 0)
var _movement_tween: Tween
var _movement_serial := 0
var _interaction_queued := false
var _ground_ring: Polygon2D

func _ready() -> void:
	if not humanoid_core:
		push_error("MacroPlayer requires a HumanoidCore child.")
		return

	definition = humanoid_core.definition
	if not definition:
		push_error("MacroPlayer's HumanoidCore requires an EntityDefinition.")
		return

	if definition.loadout and _inventory_is_empty():
		definition.loadout.apply_to(humanoid_core.inventory)
		print("[PLAYER] Persistent runtime state initialized with starting loadout.")
	_configure_humanoid_token()
	_ensure_player_readability()

func get_humanoid_core() -> HumanoidCore:
	return humanoid_core

func capture_runtime_record() -> Dictionary:
	return {
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"life_state": (
			GameEnums.EntityLifeState.DEAD
			if humanoid_core.is_dead
			else GameEnums.EntityLifeState.ALIVE
		),
		"coords": current_hex_coords,
		"definition": humanoid_core.definition.to_state(),
		"runtime": humanoid_core.capture_runtime_state().to_dict(),
	}


func initialize_new_definition(definition_state: Dictionary) -> bool:
	if definition_state.is_empty() or humanoid_core == null:
		return false
	humanoid_core.inventory.drain_all_items()
	definition = EntityDefinition.from_state(definition_state)
	humanoid_core.definition = definition
	humanoid_core.body.configure_structure(definition.fortitude)
	humanoid_core.inventory.base_max_capacity = 0
	if definition.loadout != null:
		definition.loadout.apply_to(humanoid_core.inventory)
	humanoid_core.inventory._recalculate_bounds()
	if humanoid_token != null:
		humanoid_token.refresh_from_record(capture_runtime_record())
		refresh_token_pose()
	return true

func restore_runtime_record(record) -> void:
	if record == null or (record is Dictionary and record.is_empty()):
		return

	var definition_state: Dictionary
	var runtime_state
	var coords_state: Vector2i

	if record is EntityRecord:
		definition_state = record.definition
		runtime_state = record.runtime
		coords_state = record.coords
	elif record is Dictionary:
		definition_state = record.get("definition", {})
		runtime_state = record.get("runtime", {})
		coords_state = record.get("coords", current_hex_coords)
	else:
		return
	if not definition_state.is_empty():
		definition = EntityDefinition.from_state(definition_state)
		humanoid_core.definition = definition
		humanoid_core.body.configure_structure(definition.fortitude)
		humanoid_core.inventory.base_max_capacity = 0
		humanoid_core.inventory._recalculate_bounds()

	humanoid_core.restore_runtime_state(runtime_state)
	current_hex_coords = coords_state
	if humanoid_token:
		humanoid_token.refresh_from_record(capture_runtime_record())
		refresh_token_pose()

func snap_to_hex(coords: Vector2i, pixel_position: Vector2) -> void:
	current_hex_coords = coords
	position = pixel_position
	_interaction_queued = false
	if humanoid_token:
		humanoid_token.play_animation(_idle_animation(), false)

func walk_to_hex(coords: Vector2i, pixel_position: Vector2) -> void:
	current_hex_coords = coords
	var movement_direction := pixel_position - position
	_movement_serial += 1
	var movement_id := _movement_serial
	if _movement_tween and _movement_tween.is_valid():
		_movement_tween.kill()
	if humanoid_token:
		humanoid_token.face_direction(movement_direction)
		humanoid_token.play_animation(_movement_animation())
	# Long enough to visibly advance through several walk frames.
	_movement_tween = create_tween()
	_movement_tween.tween_property(
		self,
		"position",
		pixel_position,
		WALK_DURATION_SECONDS
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_movement_tween.finished.connect(_finish_walk.bind(movement_id))

func _inventory_is_empty() -> bool:
	if humanoid_core.inventory.backpack_array.size() > 0:
		return false

	for item in humanoid_core.inventory.paper_doll.values():
		if item != null:
			return false

	return true

func _ensure_player_readability() -> void:
	# Always above fog overlays and map props.
	z_index = 8
	modulate = Color(1, 1, 1, 1)
	if _ground_ring != null:
		return
	_ground_ring = Polygon2D.new()
	_ground_ring.name = "PlayerGroundRing"
	_ground_ring.polygon = PackedVector2Array([
		Vector2(0.0, -28.0),
		Vector2(32.0, -14.0),
		Vector2(32.0, 14.0),
		Vector2(0.0, 28.0),
		Vector2(-32.0, 14.0),
		Vector2(-32.0, -14.0),
	])
	_ground_ring.color = Color(0.98, 0.82, 0.28, 0.16)
	_ground_ring.z_index = -1
	add_child(_ground_ring)


func _configure_humanoid_token() -> void:
	var placeholder := get_node_or_null("Sprite2D") as Sprite2D
	if placeholder:
		placeholder.visible = false

	if humanoid_token == null:
		push_error("MacroPlayer requires an authored HumanoidTokenView child.")
		return
	humanoid_token.set_display_scale(2.4)
	humanoid_token.modulate = Color(1, 1, 1, 1)
	humanoid_token.z_index = 1
	humanoid_token.bind_appearance_record(capture_runtime_record())
	if not humanoid_core.inventory.equipment_changed.is_connected(
		_on_inventory_appearance_changed
	):
		humanoid_core.inventory.equipment_changed.connect(
			_on_inventory_appearance_changed
		)
	if not humanoid_core.stance_changed.is_connected(_on_stance_changed):
		humanoid_core.stance_changed.connect(_on_stance_changed)
	if not humanoid_core.body.limb_destroyed.is_connected(
		_on_limb_destroyed
	):
		humanoid_core.body.limb_destroyed.connect(_on_limb_destroyed)
	if not humanoid_core.died.is_connected(_on_died):
		humanoid_core.died.connect(_on_died)
	
	if not humanoid_token.footstep_taken.is_connected(_on_token_footstep):
		humanoid_token.footstep_taken.connect(_on_token_footstep)
		
	refresh_token_pose()

func _on_inventory_appearance_changed(
	_slot: GameEnums.EquipmentSlot,
	_item: ItemData
) -> void:
	if humanoid_token:
		humanoid_token.refresh_from_record(capture_runtime_record())


func _on_token_footstep() -> void:
	var world_state := get_node_or_null("/root/WorldState") as RuntimeStateStore
	if not world_state:
		return
	var hex_data = world_state.get_hex_record(current_hex_coords)
	if hex_data == null:
		return
		
	var bg := "NONE"
	if hex_data.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW or hex_data.terrain_tile == GameEnums.MacroTerrainTile.SNOW_TRANSITION:
		bg = "MUD"
	elif hex_data.flora_layer == GameEnums.MacroFloraLayer.TREES or hex_data.terrain_tile == GameEnums.MacroTerrainTile.FOREST_SPARSE:
		bg = "TREES"
	else:
		bg = "DIRT"
		
	var bus = get_node_or_null("/root/GameEventBus")
	if bus:
		bus.emit_humanoid_footstep(self, bg)

func _finish_walk(movement_id: int) -> void:
	if movement_id != _movement_serial or not humanoid_token:
		return
	if _interaction_queued:
		_interaction_queued = false
		humanoid_token.play_one_shot("Taunt", _idle_animation())
	else:
		humanoid_token.play_animation(_idle_animation())

func play_interaction() -> void:
	if not humanoid_token:
		return
	if _movement_tween and _movement_tween.is_valid() \
	and _movement_tween.is_running():
		_interaction_queued = true
		return
	humanoid_token.play_one_shot("Taunt", _idle_animation())

func refresh_token_pose() -> void:
	if not humanoid_token:
		return
	if humanoid_core.is_dead:
		humanoid_token.play_animation("Die", false)
	elif _movement_tween and _movement_tween.is_valid() \
	and _movement_tween.is_running():
		humanoid_token.play_animation(_movement_animation(), false)
	elif humanoid_token.is_playing_one_shot():
		humanoid_token.set_return_animation(_idle_animation())
	else:
		humanoid_token.play_animation(_idle_animation(), false)

func _idle_animation() -> String:
	if humanoid_core.is_dead:
		return "Die"
	if _is_impaired():
		return "CrouchIdle"
	return "Idle"

func _movement_animation() -> String:
	return "CrouchRun" if _is_impaired() else "Walk"

func _is_impaired() -> bool:
	return (
		humanoid_core.stance_points <= 6
		or humanoid_core.body.are_both_legs_disabled()
	)

func _on_stance_changed(
	_state: GameEnums.StanceState,
	_points: int
) -> void:
	refresh_token_pose()

func _on_limb_destroyed(_limb: GameEnums.LimbRegion) -> void:
	refresh_token_pose()

func _on_died(_cause: String) -> void:
	refresh_token_pose()
