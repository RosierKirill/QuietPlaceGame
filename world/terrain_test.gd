extends Node3D
## Terrain de test — bac à sable de l'Epic E12 · Terrain voxel.
## Caméra de survol, sans joueur : sert à juger le relief, les biomes et les
## grottes d'un coup d'œil. Même générateur et même grille que la scène jouable.

const ProceduralTerrainGenerator := preload("res://world/procedural_terrain_generator.gd")

const LOD_COUNT := 7
const LOD_DISTANCE := 72.0     # en voxels
const VIEW_DISTANCE := 1200    # en voxels (= 300 unités)
const CAMERA_HEIGHT := 120.0   # en unités de monde

func _ready() -> void:
	_build_environment()
	_build_terrain()
	print("[terrain_test] Terrain construit (grille %.2f)." % ProceduralTerrainGenerator.VOXEL_SIZE)

func _build_environment() -> void:
	var cam := Camera3D.new()
	cam.name = "TestCamera"
	cam.position = Vector3(0.0, CAMERA_HEIGHT, 0.0)
	cam.rotation_degrees = Vector3(-30.0, 0.0, 0.0)
	cam.far = 2000.0
	add_child(cam)

	var viewer := VoxelViewer.new()
	viewer.view_distance = VIEW_DISTANCE
	cam.add_child(viewer)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, -45.0, 0.0)
	add_child(light)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.30, 0.55, 0.90)
	sky_material.sky_horizon_color = Color(0.72, 0.84, 0.96)
	sky_material.ground_horizon_color = Color(0.72, 0.84, 0.96)
	sky_material.ground_bottom_color = Color(0.55, 0.60, 0.62)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

func _build_terrain() -> void:
	var terrain := VoxelLodTerrain.new()
	terrain.name = "VoxelLodTerrain"
	terrain.mesher = ProceduralTerrainGenerator.make_mesher()
	terrain.format = ProceduralTerrainGenerator.make_format()
	terrain.generator = ProceduralTerrainGenerator.build()
	terrain.generate_collisions = true
	terrain.lod_count = LOD_COUNT
	terrain.lod_distance = LOD_DISTANCE
	ProceduralTerrainGenerator.apply_scale(terrain)
	add_child(terrain)
	terrain.material = TerrainMaterial.build()
