extends Node3D
## GAME-1204 — Le joueur marche sur le terrain généré (bac à sable Epic E12).
##
##   - Collision réellement générée (collision_lod_count = 1).
##   - Spawn ANALYTIQUE : on calcule la hauteur du sol et on dépose le joueur juste
##     au-dessus -> pas de flottement en altitude, pas de chute (donc pas de dégâts).
##   - On attend quand même la collision (rayon) avant de rendre la main.
##   - Filet de sécurité : sous FALL_LIMIT, on remonte le joueur au-dessus du sol
##     local et on recommence le dépôt.

const ProceduralTerrainGenerator := preload("res://world/procedural_terrain_generator.gd")
const PlayerScene := preload("res://player/player.tscn")

const LOD_COUNT := 4
const LOD_DISTANCE := 48.0
const VIEW_DISTANCE := 256
const COLLISION_LOD_COUNT := 1
const SPAWN_LIFT := 3.0          # marge au-dessus du sol calculé, à l'attente
const DROP_MARGIN := 0.2         # dépôt final quasi au ras du sol (pas de chute)
const SCAN_TOP := 300.0
const SCAN_BOTTOM := -300.0
const SPAWN_TIMEOUT := 8.0
const FALL_LIMIT := -90.0

var _player: CharacterBody3D
var _grounded := false
var _elapsed := 0.0
var _reported := false
var _report_time := 0.0

func _ready() -> void:
	_build_environment()
	_build_terrain()
	_spawn_player()

func _physics_process(delta: float) -> void:
	if _grounded:
		if _player.global_position.y < FALL_LIMIT:
			_begin_settle()
			return
		if not _reported:
			_report_time += delta
			if _report_time >= 1.0:
				_reported = true
				print("[terrain_player] DIAG 1s : is_on_floor=%s, y=%.1f" % [
					str(_player.is_on_floor()), _player.global_position.y])
		return
	_settle_step(delta)

func _surface_wait_pos(x: float, z: float) -> Vector3:
	return Vector3(x, ProceduralTerrainGenerator.get_height(x, z) + SPAWN_LIFT, z)

func _begin_settle() -> void:
	_grounded = false
	_elapsed = 0.0
	_reported = false
	_report_time = 0.0
	var p := _player.global_position
	_player.global_position = _surface_wait_pos(p.x, p.z)
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
		print("[terrain_player] Sol détecté (collision présente) à y=%.1f" % float(hit.position.y))
		_drop_player(float(hit.position.y) + DROP_MARGIN)
	elif _elapsed >= SPAWN_TIMEOUT:
		push_warning("[terrain_player] Timeout : collision non trouvée sous le joueur.")
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
	_player.global_position = _surface_wait_pos(0.0, 0.0)
	_player.set_physics_process(false)
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
	terrain.collision_lod_count = COLLISION_LOD_COUNT
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
