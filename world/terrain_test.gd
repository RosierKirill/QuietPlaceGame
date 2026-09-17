extends Node3D
## Terrain de test — GAME-1202 (Epic E12 · Terrain voxel)
## Génère un terrain voxel LISSE (mesher Transvoxel) avec Voxel Tools (GDExtension).
##
## Scène de bac à sable pour valider la génération : terrain + collisions + LOD,
## avec une caméra de survol, une lumière directionnelle et un ciel procédural bleu.

# --- Paramètres réglables -----------------------------------------------------
const NOISE_FREQUENCY := 0.005      # + petit = collines + larges
const HEIGHT_START := -50.0         # altitude où commence la matière (SDF)
const HEIGHT_RANGE := 120.0         # amplitude verticale du terrain
const LOD_COUNT := 4                # niveaux de détail
const LOD_DISTANCE := 48.0          # distance (m) avant de passer au LOD suivant
const CAMERA_HEIGHT := 80.0         # hauteur de la caméra de test
# ------------------------------------------------------------------------------

func _ready() -> void:
	print("[terrain_test] _ready — le script tourne bien.")
	_build_environment()
	_build_terrain()
	print("[terrain_test] Terrain construit et ajouté à la scène.")

func _build_environment() -> void:
	# Caméra de test, surélevée et légèrement plongeante.
	var cam := Camera3D.new()
	cam.name = "TestCamera"
	cam.position = Vector3(0.0, CAMERA_HEIGHT, 0.0)
	cam.rotation_degrees = Vector3(-30.0, 0.0, 0.0)
	add_child(cam)

	# VoxelViewer : dit au moteur OÙ générer les voxels (suit la caméra).
	var viewer := VoxelViewer.new()
	cam.add_child(viewer)

	# Lumière directionnelle : sert aussi de soleil pour le ciel.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, -45.0, 0.0)
	add_child(light)

	# Ciel procédural bleu (les couleurs par défaut rendaient gris).
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

	# Mesher lisse : surfaces continues façon terrain naturel (overhangs possibles).
	terrain.mesher = VoxelMesherTransvoxel.new()

	# Générateur : bruit 3D interprété en SDF (le channel SDF est la valeur par défaut).
	var generator := VoxelGeneratorNoise.new()
	generator.height_start = HEIGHT_START
	generator.height_range = HEIGHT_RANGE

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = NOISE_FREQUENCY
	generator.noise = noise

	terrain.generator = generator

	# Collisions : indispensable pour que le joueur tienne debout dessus.
	terrain.generate_collisions = true

	# LOD : le moteur allège le maillage au loin.
	terrain.lod_count = LOD_COUNT
	terrain.lod_distance = LOD_DISTANCE

	add_child(terrain)
