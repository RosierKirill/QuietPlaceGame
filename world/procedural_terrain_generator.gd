extends RefCounted
class_name ProceduralTerrainGenerator
## World generation settings and entry points (Epic E12 · Voxel terrain).
##
## Generation runs in a VoxelGeneratorGraph (see TerrainGraph): the graph is
## compiled to native code by Voxel Tools, which keeps streaming fast enough to
## never leave holes around the player. The same formulas are mirrored in
## GDScript by TerrainShape for point queries (spawn, water, biomes).
##
## Both read the SAME noise resources, created here once per seed. This is what
## keeps the graph and the queries in agreement.
##
## CONVENTIONS
##   - The terrain is scaled by VOXEL_SIZE: the graph works in VOXELS.
##   - Constants below are in WORLD UNITS unless their name ends with _V.
##   - SDF: negative = matter.

# TerrainGraph and TerrainShape read the constants of this file: they are loaded
# lazily here, a preload in both directions would be circular.
const TERRAIN_GRAPH_PATH := "res://world/terrain_graph.gd"
const TERRAIN_SHAPE_PATH := "res://world/terrain_shape.gd"

## World seed. Set it BEFORE build() and before any query.
static var world_seed: int = 1337

# --- Grid ---
const VOXEL_SIZE := 0.25             # one voxel, in world units
const BLOCK_SIZE := 0.75             # one block = 3 voxels
const BLOCK_VOXELS := 3

# --- Relief (world units) ---
# Rolling grassy hills everywhere, and separate rocky massifs rising from them
# (reference pictures: alpine meadow with rocky peaks, anime valley with lakes).
const BASE_HEIGHT := 12.0            # mean ground height of the plains
const HILLS_AMPLITUDE := 12.0        # plains range from 0 to 24 units
const HILLS_PERIOD := 380.0          # width of a hill
const HILLS_OCTAVES := 4
const MASK_PERIOD := 1400.0          # size of mountain regions
const MASK_LOW := 0.35               # raw mask value where mountains start
const MASK_HIGH := 0.65              # raw mask value where they reach full height
const MOUNTAIN_AMPLITUDE := 130.0    # extra height of a full massif
const MOUNTAIN_PERIOD := 260.0       # width of a peak
const MOUNTAIN_OCTAVES := 5

# --- Sea ---
const SEA_LEVEL := 8.0

# --- Caves (world units) ---
const CAVE_PERIOD := 55.0            # size of tunnels
const CAVE_WIDTH := 0.11             # half width of the crossing noise bands
# Cave field -> SDF (voxels). The field changes by about 1/35 per voxel (noise
# period of about 200 voxels), so this turns it into a distance in voxels.
const CAVE_SDF_SCALE := 35.0
const ROOM_PERIOD := 50.0            # size of rooms
const ROOM_THRESHOLD := 0.70         # higher = rarer rooms
const SURFACE_CRUST := 8.0           # solid ground kept above caves
const ENTRANCE_PERIOD := 50.0        # size of the spots where caves open
const ENTRANCE_LOW := 0.56           # raw noise value where the crust thins
const ENTRANCE_HIGH := 0.72          # raw noise value where it is gone
# How fast caves are closed off inside the crust, per voxel of missing depth.
const CRUST_TAPER := 0.05
# Near the surface of an entrance, tunnels are widened by this much so they
# open cleanly instead of leaving thin floating lips.
const ENTRANCE_WIDEN := 0.12
const ENTRANCE_ROOF_V := 6.0         # depth (voxels) over which widening fades
# Voxels closer than this to a cave (in cave-field units, about 2 voxels) are
# cave walls: they are always rock, never grass or dirt.
const CAVE_WALL_BAND := 0.06

# --- Biomes ---
const TEMPERATURE_PERIOD := 2500.0
const HUMIDITY_PERIOD := 2000.0
const COLD_ALTITUDE_START := 60.0    # above this, it gets colder
const COLD_ALTITUDE_RANGE := 300.0   # altitude that removes 1.0 of temperature

# --- Layers (vertical rule: top block, then dirt, then stone) ---
const TOP_LAYER_V := 3               # the top block: 3 voxels = 0.75
const SUB_DEPTH := 4.0               # stone starts this deep
const ROCK_ALTITUDE := 110.0         # summits above this are bare rock
const ROCK_ALTITUDE_JITTER := 25.0
const ROCK_NOISE_PERIOD := 250.0
const SLOPE_ROCK := 1.6              # slope (tangent) above which rock shows
const SLOPE_SAMPLE_V := 2.0          # distance used to measure the slope

# --- Plants (see TerrainGraph.build_plant_filter) ---
# Surface plants grow where the ground is at most this deep under them, in
# voxels. Instances sit on the mesh, so this only absorbs placement error.
const PLANT_SURFACE_BAND_V := 6.0
# Weight of one voxel in the plant filter, next to climate rates in [0, 1].
const PLANT_FILTER_VOXEL := 0.1

# --- Materials (index written in the INDICES channel) ---
const MAT_GRASS := 0                 # temperate grass
const MAT_GRASS_DRY := 1             # dry grass (savanna, prairie)
const MAT_GRASS_COLD := 2            # cold grass (taiga)
const MAT_DIRT := 3
const MAT_ROCK := 4
const MAT_SAND := 5
const MAT_SNOW := 6
# Ores are no longer generated in the ground (ore rocks are, see Vegetation).
# Their indices stay: blocks can still be placed, and they name the ore tints.
const MAT_COAL := 7
const MAT_IRON := 8
const MAT_COPPER := 9
const MAT_PERMAFROST := 10
const MATERIAL_NAMES := [
	"herbe", "herbe sèche", "herbe froide", "terre", "roche",
	"sable", "neige", "charbon", "fer", "cuivre", "permafrost",
]

# --- Biomes (values returned by get_biome) ---
const BIOME_TUNDRA := 0
const BIOME_TAIGA := 1
const BIOME_TEMPERATE_FOREST := 2
const BIOME_TEMPERATE_PRAIRIE := 3
const BIOME_DESERT := 4
const BIOME_RAINFOREST := 5
const BIOME_SAVANNA := 6
const BIOME_NAMES := [
	"toundra", "taïga", "forêt tempérée", "prairie tempérée",
	"désert", "forêt humide", "savane",
]

# Biome thresholds of the temperature x humidity pyramid. Each seed draws its
# own inside these ranges, so one world can be mostly desert and another cold.
const RANGE_T_TUNDRA := Vector2(0.10, 0.28)
const RANGE_T_TAIGA := Vector2(0.10, 0.26)
const RANGE_T_HOT := Vector2(0.20, 0.38)
const RANGE_H_DESERT := Vector2(0.14, 0.36)
const RANGE_H_FOREST := Vector2(0.14, 0.30)
const RANGE_H_RAIN := Vector2(0.05, 0.20)

static var t_tundra := 0.20
static var t_taiga := 0.40
static var t_hot := 0.70
static var h_desert := 0.25
static var h_forest := 0.50
static var h_rain := 0.60

## Noise resources of the current seed, shared by the graph and the queries.
static var _noises: Dictionary = {}
static var _shape = null


# --- Seed --------------------------------------------------------------------

## Sets the world seed. Call it before build() and before any query.
static func set_world_seed(value: int) -> void:
	world_seed = value
	_roll_biome_thresholds()
	_noises.clear()
	_shape = null

## Draws a random seed, sets it and returns it.
static func randomize_world_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	set_world_seed(int(rng.randi() % 1000000))
	return world_seed

## Draws this world's biome thresholds from the seed.
static func _roll_biome_thresholds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 31 + 7
	t_tundra = rng.randf_range(RANGE_T_TUNDRA.x, RANGE_T_TUNDRA.y)
	t_taiga = t_tundra + rng.randf_range(RANGE_T_TAIGA.x, RANGE_T_TAIGA.y)
	t_hot = minf(t_taiga + rng.randf_range(RANGE_T_HOT.x, RANGE_T_HOT.y), 0.95)
	h_desert = rng.randf_range(RANGE_H_DESERT.x, RANGE_H_DESERT.y)
	h_forest = h_desert + rng.randf_range(RANGE_H_FOREST.x, RANGE_H_FOREST.y)
	h_rain = minf(h_forest + rng.randf_range(RANGE_H_RAIN.x, RANGE_H_RAIN.y), 0.95)

## Readable summary of this world's thresholds (console, loading screen).
static func biome_thresholds_text() -> String:
	return "toundra<%.2f, taïga<%.2f, chaud>%.2f | désert<%.2f, prairie<%.2f, savane<%.2f" % [
		t_tundra, t_taiga, t_hot, h_desert, h_forest, h_rain]


# --- Noises --------------------------------------------------------------------

## The noise resources of the current seed, created on first use.
## Keys: hills, mask, mountain, temperature, humidity, rock,
## cave_a, cave_b, room, entrance.
static func noises() -> Dictionary:
	if _noises.is_empty():
		_noises = {
			"hills": _noise(1, HILLS_PERIOD, HILLS_OCTAVES),
			"mask": _noise(2, MASK_PERIOD, 2),
			"mountain": _noise(3, MOUNTAIN_PERIOD, MOUNTAIN_OCTAVES),
			"temperature": _noise(10, TEMPERATURE_PERIOD, 1),
			"humidity": _noise(11, HUMIDITY_PERIOD, 1),
			"rock": _noise(12, ROCK_NOISE_PERIOD, 1),
			"cave_a": _noise(20, CAVE_PERIOD, 1),
			"cave_b": _noise(21, CAVE_PERIOD, 1),
			"room": _noise(30, ROOM_PERIOD, 1),
			"entrance": _noise(31, ENTRANCE_PERIOD, 1),
		}
	return _noises

## Noise with a period given in world units.
static func _noise(seed_offset: int, period: float, octaves: int) -> ZN_FastNoiseLite:
	return _noise_voxels(seed_offset, period / VOXEL_SIZE, octaves)

## Noise with a period given in voxels (the graph works in voxels).
static func _noise_voxels(seed_offset: int, period_v: float, octaves: int) -> ZN_FastNoiseLite:
	var n := ZN_FastNoiseLite.new()
	n.noise_type = ZN_FastNoiseLite.TYPE_OPEN_SIMPLEX_2S
	n.seed = world_seed + seed_offset
	n.period = period_v
	if octaves > 1:
		n.fractal_type = ZN_FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
	else:
		n.fractal_type = ZN_FastNoiseLite.FRACTAL_NONE
	return n


# --- Terrain setup (shared by scenes) -----------------------------------------

## Transvoxel mesher that passes the material index to the shader (CUSTOM1).
static func make_mesher() -> VoxelMesherTransvoxel:
	var m := VoxelMesherTransvoxel.new()
	m.texturing_mode = VoxelMesherTransvoxel.TEXTURES_SINGLE_S4
	m.textures_ignore_air_voxels = true
	return m

## Voxel format: "Single texture" mode needs an 8-bit INDICES channel.
static func make_format() -> VoxelFormat:
	var f := VoxelFormat.new()
	f.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_8_BIT)
	return f

## Applies the grid scale: 1 voxel = VOXEL_SIZE world units.
static func apply_scale(terrain: VoxelLodTerrain) -> void:
	terrain.scale = Vector3.ONE * VOXEL_SIZE

## World -> voxels (terrain local coordinates).
static func to_voxel(world_position: Vector3) -> Vector3:
	return world_position / VOXEL_SIZE

## Voxels -> world.
static func to_world(voxel_position: Vector3) -> Vector3:
	return voxel_position * VOXEL_SIZE

## Generator to put on the terrain.
static func build() -> VoxelGenerator:
	print("[terrain] Graine %d, seuils : %s" % [world_seed, biome_thresholds_text()])
	return load(TERRAIN_GRAPH_PATH).build(noises())


# --- Queries (same formulas as the graph) -------------------------------------

static func shape():
	if _shape == null:
		_shape = load(TERRAIN_SHAPE_PATH).new(noises())
	return _shape

## Height of the rendered ground at (x, z), in WORLD UNITS.
static func get_height(x: float, z: float) -> float:
	return shape().height_voxels(x / VOXEL_SIZE, z / VOXEL_SIZE) * VOXEL_SIZE

## Ground height of a block column, in voxels (used by the water).
static func block_ground_voxels(bx: int, bz: int) -> float:
	# Measured at the centre of the block.
	var vx := (float(bx) + 0.5) * BLOCK_VOXELS
	var vz := (float(bz) + 0.5) * BLOCK_VOXELS
	return shape().height_voxels(vx, vz)

## How open the crust is at (x, z): 0 = full crust, 1 = cave entrance.
static func get_entrance_openness(x: float, z: float) -> float:
	return shape().entrance_openness(x / VOXEL_SIZE, z / VOXEL_SIZE)

## Temperature [0, 1] at (x, z).
static func get_temperature(x: float, z: float) -> float:
	return shape().temperature(x / VOXEL_SIZE, z / VOXEL_SIZE)

## Humidity [0, 1] at (x, z).
static func get_humidity(x: float, z: float) -> float:
	return shape().humidity(x / VOXEL_SIZE, z / VOXEL_SIZE)

## Biome at (x, z) — see BIOME_NAMES.
static func get_biome(x: float, z: float) -> int:
	return biome_from(get_temperature(x, z), get_humidity(x, z))

## Biome from both rates (pyramid of the Notion note).
static func biome_from(temperature: float, humidity: float) -> int:
	if temperature < t_tundra:
		return BIOME_TUNDRA
	if temperature < t_taiga:
		return BIOME_TAIGA
	if temperature < t_hot:
		if humidity < h_desert:
			return BIOME_DESERT
		if humidity < h_forest:
			return BIOME_TEMPERATE_PRAIRIE
		return BIOME_TEMPERATE_FOREST
	if humidity < h_desert:
		return BIOME_DESERT
	if humidity < h_rain:
		return BIOME_SAVANNA
	return BIOME_RAINFOREST
