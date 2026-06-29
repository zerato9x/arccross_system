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
	preload("res://SoundCore/Sound/sfx/guns/pistols/9mm Single Isolated.wav")
]

const SOUNDS_SHOTGUN := [
	preload("res://SoundCore/Sound/sfx/guns/shotgun/20 Gauge Single Isolated.wav")
]

const SOUNDS_REVOLVER := [
	preload("res://SoundCore/Sound/sfx/guns/revolver/308 Single Isolated.wav")
]

const SOUNDS_RIFLE_CARBON := [
	preload("res://SoundCore/Sound/sfx/guns/rifle_carbon/556 Single Isolated WAV.wav")
]

const SOUNDS_RIFLE_SERVICE := [
	preload("res://SoundCore/Sound/sfx/guns/rifle_service/762x54r Single Isolated WAV.wav")
]

const SOUNDS_AK47 := [
	preload("res://SoundCore/Sound/sfx/guns/ak47/762x39 Single Isolated WAV.wav")
]

const SOUNDS_GUN_RELOAD := {
	"ak47": [
		preload("res://SoundCore/Sound/sfx/guns/ak47/AK Reload Full WAV.wav"),
	],
	"carbon_rifle": [
		preload("res://SoundCore/Sound/sfx/guns/rifle_carbon/AR Reload Full WAV.wav"),
	],
	"service_rifle": [
		preload("res://SoundCore/Sound/sfx/guns/rifle_service/Mosin Top Load.wav"),
	],
	"shotgun": [
		preload("res://SoundCore/Sound/sfx/Equipment/DesignedGunSoundReload1.wav"),
		preload("res://SoundCore/Sound/sfx/Equipment/DesignedGunSoundReload2.wav"),
	],
	"default": [
		preload("res://SoundCore/Sound/sfx/Equipment/DesignedGunSoundReload1.wav"),
		preload("res://SoundCore/Sound/sfx/Equipment/DesignedGunSoundReload2.wav"),
		preload("res://SoundCore/Sound/sfx/Equipment/DesignedGunSoundReload3.wav"),
		preload("res://SoundCore/Sound/sfx/Equipment/DesignedGunSoundReload4.wav"),
	],
}

const SOUNDS_GUN_CYCLE := {
	"ak47": [
		preload("res://SoundCore/Sound/sfx/guns/ak47/AK Rack WAV.wav"),
	],
	"carbon_rifle": [
		preload("res://SoundCore/Sound/sfx/guns/rifle_carbon/AR Charging Handle WAV.wav"),
		preload("res://SoundCore/Sound/sfx/guns/rifle_carbon/AR Bolt Release WAV.wav"),
	],
	"service_rifle": [
		preload("res://SoundCore/Sound/sfx/guns/rifle_service/Lever Cycle WAV.wav"),
	],
	"default": [
		preload("res://SoundCore/Sound/sfx/Equipment/DesignedGunSoundHandling1.wav"),
		preload("res://SoundCore/Sound/sfx/Equipment/DesignedGunSoundHandling2.wav"),
		preload("res://SoundCore/Sound/sfx/Equipment/DesignedGunSoundHandling3.wav"),
		preload("res://SoundCore/Sound/sfx/Equipment/DesignedGunSoundHandling4.wav"),
	],
}

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

# Footsteps
const SOUNDS_FOOTSTEP_CONCRETE := [
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsConcrete1.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsConcrete2.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsConcrete3.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsConcrete4.wav")
]
const SOUNDS_FOOTSTEP_MUD := [
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsWetGravelStones1.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsWetGravelStones2.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsWetGravelStones3.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsWetGravelStones4.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsSlushSnow1.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsSlushSnow2.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsSlushSnow3.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsSlushSnow4.wav")
]
const SOUNDS_FOOTSTEP_TREES := [
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsDryBeachTwigs1.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsDryBeachTwigs2.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsDryBeachTwigs3.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsDryBeachTwigs4.wav")
]
const SOUNDS_FOOTSTEP_DIRT := [
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsStoneDirt1.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsStoneDirt2.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsStoneDirt3.wav"),
	preload("res://SoundCore/Sound/sfx/Footsteps/FootstepsStoneDirt4.wav")
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
		bus.humanoid_footstep_taken.connect(_on_humanoid_footstep)

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

func _on_combat_action(
	_entity: Node,
	action: GameEnums.ActionType,
	weapon_class: GameEnums.WeaponClass,
	weapon_id: String
) -> void:
	if action == GameEnums.ActionType.SHOOT or action == GameEnums.ActionType.AIMED_SHOT:
		match weapon_class:
			GameEnums.WeaponClass.PISTOL:
				_play_sound(_gunshot_pool_for_id(weapon_id).pick_random())
			GameEnums.WeaponClass.RIFLE:
				_play_sound(_gunshot_pool_for_id(weapon_id).pick_random())
			GameEnums.WeaponClass.SHOTGUN:
				_play_sound(SOUNDS_SHOTGUN.pick_random())
			_:
				pass
	elif action == GameEnums.ActionType.RELOAD:
		_play_sound(_mapped_pool(SOUNDS_GUN_RELOAD, weapon_id).pick_random(), 0.04, -2.0)
	elif action == GameEnums.ActionType.CYCLE:
		_play_sound(_mapped_pool(SOUNDS_GUN_CYCLE, weapon_id).pick_random(), 0.04, -3.0)
	elif action == GameEnums.ActionType.STRIKE:
		_play_sound(SOUNDS_PUNCH.pick_random())

func _gunshot_pool_for_id(weapon_id: String) -> Array:
	match weapon_id:
		"revolver":
			return SOUNDS_REVOLVER
		"carbon_rifle":
			return SOUNDS_RIFLE_CARBON
		"service_rifle":
			return SOUNDS_RIFLE_SERVICE
		"ak47":
			return SOUNDS_AK47
	return SOUNDS_PISTOL

func _mapped_pool(mapping: Dictionary, weapon_id: String) -> Array:
	if mapping.has(weapon_id):
		return mapping[weapon_id]
	return mapping["default"]

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

func _on_humanoid_footstep(_entity: Node, background: String) -> void:
	match background:
		"MUD":
			_play_sound(SOUNDS_FOOTSTEP_MUD.pick_random(), 0.08, -6.0)
		"TREES":
			_play_sound(SOUNDS_FOOTSTEP_TREES.pick_random(), 0.08, -6.0)
		"DIRT":
			_play_sound(SOUNDS_FOOTSTEP_DIRT.pick_random(), 0.08, -6.0)
		_:
			_play_sound(SOUNDS_FOOTSTEP_CONCRETE.pick_random(), 0.08, -6.0)
