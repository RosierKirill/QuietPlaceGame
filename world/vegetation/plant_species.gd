class_name PlantSpecies
extends Resource
## One kind of plant or rock placed on the terrain (GAME-1222, GAME-2002).
##
## Pure data, like Item: each species is a .tres file in
## world/vegetation/species/. Vegetation turns them into VoxelInstancer items.
##
## Sizes and densities are in WORLD UNITS here. Vegetation converts them to the
## terrain's local space (voxels of VOXEL_SIZE).

enum Location {
	SURFACE,    ## on the ground outside, above the sea
	CAVE,       ## on cave floors
}

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Look")
@export var mesh: Mesh
## One texture per surface of the mesh, in the same order.
@export var textures: Array[Texture2D] = []
## Texture repeat per surface, in the same order (empty = 1 x 1 everywhere).
@export var uv_scales: PackedVector2Array = PackedVector2Array()
## Surfaces that are foliage: drawn from both sides, cut out by the texture's
## alpha, and tinted like the grass of the ground they grow on.
@export var foliage_surfaces: PackedInt32Array = PackedInt32Array()
## Solid surfaces are tinted like this terrain material (-1 = no tint). Ore
## rocks use the ore tints of the terrain (TerrainMaterial.ORE_TINTS).
@export var tint_material: int = -1
## Random size range (1 = size of the model).
@export var min_scale: float = 1.0
@export var max_scale: float = 1.0
## Stands upright (trees, grass) instead of following the ground's slope
## (rocks). Not upright + max_slope_degrees 180 = floors, walls and ceilings.
@export var upright: bool = true
## How deep the model is pushed into the ground, in units.
@export var sink: float = 0.0

@export_group("Where")
@export var location: Location = Location.SURFACE
## CAVE only: how deep under the surface, at least, in units.
@export var min_depth: float = 2.0
## Ground materials it grows on (ProceduralTerrainGenerator.MAT_*).
@export var ground_materials: PackedInt32Array = PackedInt32Array()
## Climate it grows in (rates from 0 to 1, see the "Température et humidité"
## note): 0 = very cold / very dry, 1 = very hot / very humid.
@export_range(0.0, 1.0) var temperature_min: float = 0.0
@export_range(0.0, 1.0) var temperature_max: float = 1.0
@export_range(0.0, 1.0) var humidity_min: float = 0.0
@export_range(0.0, 1.0) var humidity_max: float = 1.0
## Instances per square unit of ground, where the climate fits.
@export var density: float = 0.01
@export_range(0.0, 180.0) var max_slope_degrees: float = 35.0
## Terrain LOD it spawns on: 0 = only close to the player (grass), higher =
## seen from further away (trees).
@export_range(0, 6) var lod_index: int = 0

@export_group("Harvest")
## Hits needed to harvest it. 0 = cannot be harvested (and has no collider).
@export var hits: int = 0
## The player cannot walk through it (tree trunk, boulder).
@export var blocks_movement: bool = false
## Collider: a cylinder standing on the ground, at scale 1, in units.
@export var collider_radius: float = 0.3
@export var collider_height: float = 1.0
@export var loot: Item
@export var loot_min: int = 1
@export var loot_max: int = 1
