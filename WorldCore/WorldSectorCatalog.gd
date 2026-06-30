extends RefCounted
class_name WorldSectorCatalog

## Wedge and hub sector definitions for Phase 2 macro layout.

const WEDGE_IDS := [
	"wedge_n",
	"wedge_ne",
	"wedge_e",
	"wedge_se",
	"wedge_s",
	"wedge_sw",
	"wedge_w",
	"wedge_nw",
]

const LANDMARK_POOL := [
	{
		"landmark_id": "homestead_b",
		"poi_id": "plains_homestead",
		"poi_name": "Abandoned Homestead",
		"sleep_anchor": "ground",
	},
	{
		"landmark_id": "shed_a",
		"poi_id": "plains_shed",
		"poi_name": "Locked Tool Shed",
		"sleep_anchor": "ground",
	},
	{
		"landmark_id": "warehouse_b",
		"poi_id": "plains_warehouse",
		"poi_name": "Collapsed Warehouse",
		"sleep_anchor": "bench",
	},
	{
		"landmark_id": "homestead_d",
		"poi_id": "plains_homestead_d",
		"poi_name": "Ruined Homestead",
		"sleep_anchor": "bed",
	},
]

static func wedge_id_for_coords(coords: Vector2i) -> String:
	if coords == Vector2i.ZERO:
		return "hub_core"
	var angle := atan2(float(coords.y), float(coords.x))
	var octant := int(floor((angle + PI) / (TAU / 8.0))) % 8
	if octant < 0:
		octant += 8
	return WEDGE_IDS[octant]

static func wedge_display_name(wedge_id: String) -> String:
	match wedge_id:
		"hub_core":
			return "Alpha Core"
		"hub_border":
			return "Hub Perimeter"
		"wedge_n":
			return "North Wastes"
		"wedge_ne":
			return "Northeast Fringe"
		"wedge_e":
			return "East Plains"
		"wedge_se":
			return "Southeast Fringe"
		"wedge_s":
			return "South Wastes"
		"wedge_sw":
			return "Southwest Fringe"
		"wedge_w":
			return "West Plains"
		"wedge_nw":
			return "Northwest Fringe"
		_:
			return wedge_id.capitalize()

static func wedge_definition(wedge_id: String) -> Dictionary:
	var hazard := 3.0
	var poi_density := 0.06
	match wedge_id:
		"hub_core", "hub_border":
			hazard = 0.0
			poi_density = 0.0
		"wedge_n", "wedge_s":
			poi_density = 0.05
		"wedge_e", "wedge_w":
			poi_density = 0.07
		_:
			poi_density = 0.06
	return {
		"zone_id": wedge_id,
		"display_name": wedge_display_name(wedge_id),
		"hazard_bias": hazard,
		"poi_density": poi_density,
		"loot_profile_id": "loot_plains",
	}

static func pick_landmark(
	world_seed: String,
	coords: Vector2i,
	wedge_id: String
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		world_seed
		+ ":landmark:"
		+ wedge_id
		+ ":"
		+ str(coords.x)
		+ ":"
		+ str(coords.y)
	).hash()
	var index := rng.randi_range(0, LANDMARK_POOL.size() - 1)
	return LANDMARK_POOL[index].duplicate(true)
