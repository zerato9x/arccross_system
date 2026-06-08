extends Node2D
class_name MacroGameManager

# Broadcasts to the overarching Game Director when a fight breaks out
signal combat_interception(player_def: EntityDefinition, enemy_def: EntityDefinition, enemy_coords: Vector2i)

@export_group("The Strings")
@export var world_generator: HexWorldGenerator
@export var map_visualizer: HexMapVisualizer
@export var player_token: MacroPlayer
@export var enemy_token_scene: PackedScene
@export var mob_spawner: MobSpawner

var active_enemies: Dictionary = {} # Stores Vector2i -> MacroEnemy
var active_map_remnants: Dictionary = {} # Stores Vector2i -> Array[ItemData]

const HEX_NEIGHBORS = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), 
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]

func _ready() -> void:
	if not world_generator or not map_visualizer or not player_token:
		push_error("The Puppet Master is missing its strings. Check the inspector.")
		return
		
	_initialize_demo()

func _initialize_demo() -> void:
	world_generator.master_seed = "DEMO_WASTELAND_01"
	
	# Spawn Player
	var start_coords = Vector2i(0, 0)
	var start_pixel_pos = map_visualizer.map_to_local(start_coords)
	player_token.snap_to_hex(start_coords, start_pixel_pos)
	map_visualizer.render_radius(start_coords, 3)
	
	# Spawn a procedural scavenger 2 hexes to the right
	spawn_procedural_enemy(Vector2i(2, 0), GameEnums.Faction.SCAVENGER_CELL)
	
	# Spawn a craven further out
	spawn_procedural_enemy(Vector2i(-2, 1), GameEnums.Faction.CRAVEN_HIVE)

## Spawn a procedurally generated enemy at the given hex coordinates.
func spawn_procedural_enemy(coords: Vector2i, faction: GameEnums.Faction, difficulty: int = 0) -> void:
	if not enemy_token_scene:
		push_error("Cannot spawn enemy. Assign the PackedScene in the Inspector.")
		return
	
	if not mob_spawner:
		push_error("Cannot spawn enemy. MobSpawner is not assigned.")
		return
	
	var enemy = enemy_token_scene.instantiate()
	add_child(enemy)
	
	# Generate a fully procedural entity definition with gear
	var def: EntityDefinition = mob_spawner.generate_mob(faction, difficulty)
	enemy.setup_from_definition(def)
	
	var pixel_pos = map_visualizer.map_to_local(coords)
	enemy.snap_to_hex(coords, pixel_pos)
	
	active_enemies[coords] = enemy
	print("[MACRO] Spawned ", def.archetype_name, " at hex ", coords)

## Legacy: spawn from a pre-built definition .tres (still works).
func spawn_macro_enemy(coords: Vector2i) -> void:
	if not enemy_token_scene:
		push_error("Cannot spawn enemy. Assign the PackedScene in the Inspector.")
		return
		
	var enemy = enemy_token_scene.instantiate()
	add_child(enemy)
	
	var pixel_pos = map_visualizer.map_to_local(coords)
	enemy.snap_to_hex(coords, pixel_pos)
	
	active_enemies[coords] = enemy

# ---------------------------------------------------------
# INPUT & MOVEMENT LOGIC
# ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_attempt_move_to_mouse()

func _attempt_move_to_mouse() -> void:
	var mouse_pos = map_visualizer.get_local_mouse_position()
	var clicked_hex_coords = map_visualizer.local_to_map(mouse_pos)
	
	var distance_vector = clicked_hex_coords - player_token.current_hex_coords
	if not HEX_NEIGHBORS.has(distance_vector):
		return # Ignored. Too far away.
		
	_execute_player_step(clicked_hex_coords)

func _execute_player_step(target_coords: Vector2i) -> void:
	var pixel_pos = map_visualizer.map_to_local(target_coords)
	player_token.walk_to_hex(target_coords, pixel_pos)
	map_visualizer.render_radius(target_coords, 3)
	
	# --- THE INTERCEPTION TRIGGER ---
	if active_enemies.has(target_coords):
		var enemy = active_enemies[target_coords]
		print("\n[MACRO] Interception! Freezing map and calling the Director...")
		set_process_unhandled_input(false)
		combat_interception.emit(player_token.definition, enemy.definition, target_coords)
		return
		
	# --- POI TRIGGER ---
	var hex_data = world_generator.get_hex_at(target_coords) # Declared ONCE here
	if hex_data.is_poi:
		print(">>> ENTERED POI: ", hex_data.poi_name, " <<<")
		
	# Pick up map remnants if any exist on the target hex
	if active_map_remnants.has(target_coords):
		print(">>> You stumbled upon dropped items on this hex! <<<")
		# In a full game, this would open a looting UI.
		
	# --- METABOLIC SURVIVAL TICK ---
	var exertion: float = 1.0
	if hex_data.biome == GameEnums.GridBiome.SWAMP or hex_data.biome == GameEnums.GridBiome.MUD:
		exertion = 2.0 
		
	var current_player_core = player_token.get_node_or_null("HumanoidCore") # Adjust pointer if your Core is a sub-node
	if current_player_core and current_player_core.has_method("get_insulation_rating"):
		var insulation = current_player_core.get_insulation_rating()
		current_player_core.body.process_biological_tick(15.0, insulation, exertion)
