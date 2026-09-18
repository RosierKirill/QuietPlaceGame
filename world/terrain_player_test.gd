extends Node3D
## GAME-1204 — Le joueur marche sur le terrain généré (bac à sable Epic E12).
##
## Apparition sûre + FILET DE SÉCURITÉ anti-chute-à-travers-le-terrain :
##   - VoxelViewer sur le joueur avec une bonne portée -> la collision est
##     générée sur toute la colonne autour de lui, et devant lui quand il marche.
##   - Au spawn, le joueur est gelé au-dessus du sol puis déposé dessus dès que
##     la collision existe (rayon vers le bas).
##   - En jeu, s'il passe quand même sous le monde (y < FALL_LIMIT), il est
##     rattrapé et reposé sur le sol -> jamais de chute infinie.

const ProceduralTerrainGenerator := preload("res://world/procedural_terrain_generator.gd")
const PlayerScene := preload("res://player/player.tscn")

const LOD_COUNT := 4
const LOD_DISTANCE := 48.0
const VIEW_DISTANCE := 256          # portée du VoxelViewer (génération + collision)
const FREEZE_HEIGHT := 120.0        # hauteur d'attente, gelé, au-dessus du relief
const SCAN_TOP := 300.0
const SCAN_BOTTOM := -300.0
const SPAWN_MARGIN := 1.0
const SPAWN_TIMEOUT := 8.0
const FALL_LIMIT := -90.0           # sous ce Y : passé à travers -> rattrapage

var _player: CharacterBody3D
var _grounded := false
var _elapsed := 0.0

func _ready() -> void:
	_build_environment()
	_build_terrain()
	_spawn_player()

func _physics_process(delta: float) -> void:
	if _grounded:
		if _player.global_position.y < FALL_LIMIT:
			_begin_settle()  # filet de sécurité
		return
	_settle_step(delta)

# --- Apparition / rattrapage : gèle le joueur puis le dépose sur le sol ---

func _begin_settle() -> void:
	_grounded = false
	_elapsed = 0.0
	var p := _player.global_position
	_player.global_position = Vector3(p.x, FREEZE_HEIGHT, p.z)
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(false)
	push_warning("[terrain_player] Rattrapage anti-chute : le joueur était passé sous le terrain.")

func _settle_step(delta: float) -> void:
	_elapsed += delta
	var p := _player.global_position
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(p.x, SCAN_TOP, p.z), Vector3(p.x, SCAN_BOTTOM, p.z))
	query.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit:
		_drop_player(float(hit.position.y) + SPAWN_MARGIN)
	elif _elapsed >= SPAWN_TIMEOUT:
		_drop_player(p.y)

func _drop_player(y: float) -> void:
	_grounded = true
	var p := _player.global_position
	_player.global_position = Vector3(p.x, y, p.z)
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(true)
	print("[terrain_player] Joueur posé au sol à y=%.1f" % y)

func _spawn_player() -> void:
	_player = PlayerScene.instantiate()
	add_child(_player)
	_player.global_position = Vector3(0.0, FREEZE_HEIGHT, 0.0)
	_player.set_physics_process(false)  # gelé tant que le sol n'est pas prêt
	var viewer := VoxelViewer.new()
	viewer.requires_collisions = true
	viewer.view_distance = VIEW_DISTANCE
	_player.add_child(viewer)

func _build_terrain() -> void:
	var terrain := VoxelLodTerrain.new()
	terrain.name = "VoxelLodTerrain"
	terrain.mesher = VoxelMesherTransvoxel.new()
	terrain.generator = ProceduralTerrainGenerator.build()
	terrain.generate_collisions = true
	terrain.collision_lod_count = 0  # collision sur tous les LOD
	terrain.lod_count = LOD_COUNT
	terrain.lod_distance = LOD_DISTANCE
	add_child(terrain)

func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -50.0, 0.0)
	light.shadow_enabled = true
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
	env.ambient_light_energy = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
