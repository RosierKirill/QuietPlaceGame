extends Node3D
## GAME-1204 — Le joueur marche sur le terrain généré (bac à sable Epic E12).
##
## Assemble le terrain procédural (GAME-1203) et le contrôleur FPS existant,
## avec une APPARITION SÛRE : le joueur est gelé au-dessus du sol jusqu'à ce que
## la collision du terrain soit générée sous lui, puis déposé dessus — pas de
## chute dans le vide pendant le chargement des chunks.

const ProceduralTerrainGenerator := preload("res://world/procedural_terrain_generator.gd")
const PlayerScene := preload("res://player/player.tscn")

const LOD_COUNT := 4
const LOD_DISTANCE := 48.0
const SPAWN_XZ := Vector2(0.0, 0.0)
const SPAWN_FREEZE_HEIGHT := 100.0  # où le joueur attend, gelé
const SPAWN_SCAN_HEIGHT := 200.0    # hauteur de départ du rayon de détection du sol
const SPAWN_MARGIN := 1.0           # marge au-dessus du sol à l'apparition
const SPAWN_TIMEOUT := 8.0          # sécurité : réveille le joueur après ce délai

var _player: CharacterBody3D
var _grounded := false
var _elapsed := 0.0

func _ready() -> void:
	_build_environment()
	_build_terrain()
	_spawn_player()

func _physics_process(delta: float) -> void:
	if _grounded:
		return
	_elapsed += delta
	# Rayon vers le bas : trouve la surface dès que sa collision est générée.
	var space := get_world_3d().direct_space_state
	var from := Vector3(SPAWN_XZ.x, SPAWN_SCAN_HEIGHT, SPAWN_XZ.y)
	var to := Vector3(SPAWN_XZ.x, -SPAWN_SCAN_HEIGHT, SPAWN_XZ.y)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]  # ne pas toucher le joueur gelé lui-même
	var hit := space.intersect_ray(query)
	if hit:
		_drop_player(float(hit.position.y) + SPAWN_MARGIN)
	elif _elapsed >= SPAWN_TIMEOUT:
		_drop_player(_player.global_position.y)  # sécurité : il tombera sur le sol

func _drop_player(y: float) -> void:
	_grounded = true
	_player.global_position = Vector3(SPAWN_XZ.x, y, SPAWN_XZ.y)
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(true)
	print("[terrain_player] Joueur déposé à y=%.1f" % y)

func _spawn_player() -> void:
	_player = PlayerScene.instantiate()
	add_child(_player)
	_player.global_position = Vector3(SPAWN_XZ.x, SPAWN_FREEZE_HEIGHT, SPAWN_XZ.y)
	_player.set_physics_process(false)  # gelé tant que le sol n'est pas prêt
	# VoxelViewer sur le joueur : le terrain se génère autour de lui.
	var viewer := VoxelViewer.new()
	_player.add_child(viewer)

func _build_terrain() -> void:
	var terrain := VoxelLodTerrain.new()
	terrain.name = "VoxelLodTerrain"
	terrain.mesher = VoxelMesherTransvoxel.new()
	terrain.generator = ProceduralTerrainGenerator.build()
	terrain.generate_collisions = true
	terrain.lod_count = LOD_COUNT
	terrain.lod_distance = LOD_DISTANCE
	add_child(terrain)

func _build_environment() -> void:
	# Soleil avec ombres pour faire ressortir le relief.
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
