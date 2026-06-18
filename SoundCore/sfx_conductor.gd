extends Node
class_name SfxConductor

# ---------------------------------------------------------
# SFX CONDUCTOR: Ephemeral Audio Event Handler
# ---------------------------------------------------------
# Listens to the global GameEventBus and plays SFX using a
# pool of AudioStreamPlayers to prevent voice stealing.
# ---------------------------------------------------------

const POOL_SIZE: int = 16
var _players: Array[AudioStreamPlayer] = []
var _next_player_idx: int = 0

# --- SFX Mappings ---

# Guns (using only sfx/guns)
const SOUNDS_PISTOL := [
	preload("res://SoundCore/Sound/sfx/guns/pistols/9mm Single Isolated.wav"),
	preload("res://SoundCore/Sound/sfx/guns/pistols/9mm Double Tap Isolated.wav")
]

const SOUNDS_SHOTGUN := [
	preload("res://SoundCore/Sound/sfx/guns/shotgun/20 Gauge Single Isolated.wav")
]

# (Future placeholders for Rifle, Revolver, AK47, etc. - currently no mapping since we only map what's available)

# Injuries
const SOUNDS_INJURED := [
	preload("res://SoundCore/Sound/sfx/Human/HumanInjured1.wav"),
	preload("res://SoundCore/Sound/sfx/Human/HumanInjured2.wav"),
	preload("res://SoundCore/Sound/sfx/Human/HumanInjured3.wav"),
	preload("res://SoundCore/Sound/sfx/Human/HumanInjured4.wav"),
	preload("res://SoundCore/Sound/sfx/Human/HumanInjured5.wav")
]

# Exhaustion
const SOUNDS_EXHAUSTED := [
	preload("res://SoundCore/Sound/sfx/Human/HumanExhausted1.wav"),
	preload("res://SoundCore/Sound/sfx/Human/HumanBreathingOut1.wav"),
	preload("res://SoundCore/Sound/sfx/Human/HumanBreathingOut2.wav"),
	preload("res://SoundCore/Sound/sfx/Human/HumanBreathingOut3.wav")
]

# Medicine
const SOUNDS_PILLS := [
	preload("res://SoundCore/Sound/sfx/Medicine/PillsBox1.wav"),
	preload("res://SoundCore/Sound/sfx/Medicine/PillsBox2.wav")
]

# Melee (Placeholder since user wants guns from guns folder, but punch sounds are available in Human/Combat)
const SOUNDS_PUNCH := [
	preload("res://SoundCore/Sound/sfx/Combat/DesignedPunch1.wav"),
	preload("res://SoundCore/Sound/sfx/Combat/DesignedPunch2.wav"),
	preload("res://SoundCore/Sound/sfx/Combat/DesignedPunch3.wav"),
	preload("res://SoundCore/Sound/sfx/Combat/DesignedPunch4.wav")
]


func _ready() -> void:
	_init_pool()
	_connect_to_bus()

func _init_pool() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master" # We can route this to an SFX bus later if needed
		add_child(p)
		_players.append(p)

func _connect_to_bus() -> void:
	var bus = get_node_or_null("/root/GameEventBus")
	if bus:
		bus.combat_action_executed.connect(_on_combat_action)
		bus.humanoid_injured.connect(_on_humanoid_injured)
		bus.humanoid_exhausted.connect(_on_humanoid_exhausted)
		bus.item_used.connect(_on_item_used)

func _play_sound(stream: AudioStream, pitch_variance: float = 0.05, volume_db: float = 0.0) -> void:
	if not stream:
		return
	var p: AudioStreamPlayer = _players[_next_player_idx]
	_next_player_idx = (_next_player_idx + 1) % POOL_SIZE
	
	p.stream = stream
	p.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	p.volume_db = volume_db
	p.play()

# ---------------------------------------------------------
# EVENT HANDLERS
# ---------------------------------------------------------

func _on_combat_action(_entity: Node, action: GameEnums.ActionType, weapon_class: GameEnums.WeaponClass) -> void:
	if action == GameEnums.ActionType.SHOOT or action == GameEnums.ActionType.AIMED_SHOT:
		match weapon_class:
			GameEnums.WeaponClass.PISTOL:
				_play_sound(SOUNDS_PISTOL.pick_random())
			GameEnums.WeaponClass.SHOTGUN:
				_play_sound(SOUNDS_SHOTGUN.pick_random())
			_:
				pass # Future hook for rifles, revolvers, etc.
	elif action == GameEnums.ActionType.STRIKE:
		_play_sound(SOUNDS_PUNCH.pick_random())

func _on_humanoid_injured(_entity: Node, _trauma: GameEnums.TraumaType) -> void:
	# Right now all traumas play generic injury grunts. 
	# Can expand this later to differentiate burns, breaks, bleeding.
	_play_sound(SOUNDS_INJURED.pick_random())

func _on_humanoid_exhausted(_entity: Node) -> void:
	_play_sound(SOUNDS_EXHAUSTED.pick_random())

func _on_item_used(_entity: Node, category: GameEnums.ItemCategory) -> void:
	match category:
		GameEnums.ItemCategory.MEDICINE:
			_play_sound(SOUNDS_PILLS.pick_random())
		_:
			pass # Hook for future item categories
