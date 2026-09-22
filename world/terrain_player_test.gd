extends Node3D
## GAME-1204 + GAME-1205 — Terrain généré marchable + édition à la visée
## (bac à sable Epic E12).
##
##   - Collision réelle (collision_lod_count = 1), spawn qui ATTEND que la
##     collision du chunk soit prête avant de rendre le joueur physique
##     (GAME-1210) ; le filet de sécurité anti-chute ne sert plus que de
##     secours pour les tout premiers instants.
##   - ÉDITION : clic gauche = creuser, clic droit = ajouter de la matière
##     (VoxelTool sur le canal SDF). Permet d'explorer/creuser les grottes.
##     Après un ajout, le joueur est dépénétré si jamais il se retrouve dans
##     la matière fraîchement posée (GAME-1211 — vrai fix, pas seulement une
##     distance minimale).
##   - MATÉRIAU PAR VOXEL (GAME-1212) : creuser "ramasse" le matériau du bloc
##     visé (herbe / terre / roche) ; poser remet CE matériau. La texture suit
##     le bloc, plus la forme du terrain.

const ProceduralTerrainGenerator := preload("res://world/procedural_terrain_generator.gd")
const TerrainEditing := preload("res://world/terrain_editing.gd")
const PlayerScene := preload("res://player/player.tscn")

const LOD_COUNT := 4
const LOD_DISTANCE := 48.0
const VIEW_DISTANCE := 256
const COLLISION_LOD_COUNT := 1
const SPAWN_LIFT := 3.0
const DROP_MARGIN := 0.2
const SCAN_TOP := 300.0
const SCAN_BOTTOM := -300.0
const SPAWN_TIMEOUT := 8.0
const FALL_LIMIT := -90.0

const EDIT_DISTANCE := 8.0   # portée du creusement (m)
const EDIT_RADIUS := 2.5     # rayon de la boule creusée/ajoutée (m)

# GAME-1211 — dépénétration après un ajout de matière : on sonde le volume du
# joueur (pieds/bassin/tête) et on le remonte tant qu'un point est "dans" la
# matière (SDF < 0), jusqu'à une limite de sécurité.
const DEPEN_SAMPLE_HEIGHTS := [0.1, 0.9, 1.7]
const DEPEN_STEP := 0.15
const DEPEN_MAX_STEPS := 40  # 6 m de remontée max

var _player: CharacterBody3D
var _camera: Camera3D
var _terrain: VoxelLodTerrain
var _voxel_tool: VoxelTool
var _grounded := false
var _elapsed := 0.0
var _reported := false
var _report_time := 0.0
## Matériau "en main" : celui du dernier bloc creusé (terre au départ).
var _held_material: int = ProceduralTerrainGenerator.MAT_DIRT

func _ready() -> void:
	_build_environment()
	_build_terrain()
	_spawn_player()
	print("[terrain] Édition : clic gauche = creuser (ramasse le matériau), clic droit = poser le matériau ramassé.")

func _unhandled_input(event: InputEvent) -> void:
	if not _grounded or _camera == null or _voxel_tool == null:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_edit(true)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_edit(false)

func _edit(dig: bool) -> void:
	var origin := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var hit := _voxel_tool.raycast(origin, dir, EDIT_DISTANCE)
	if hit == null:
		return
	var center: Vector3 = Vector3(hit.position if dig else hit.previous_position)
	if not dig:
		# Garde-fou UX : évite de se murer instantanément à bout portant.
		var head := _player.global_position + Vector3.UP * 0.9
		if center.distance_to(head) < EDIT_RADIUS + 1.2:
			return
	if dig:
		# GAME-1212 — on garde en main le matériau du bloc creusé.
		var picked := TerrainEditing.dig(_voxel_tool, hit.position, center, EDIT_RADIUS)
		if picked != _held_material:
			_held_material = picked
			print("[terrain] Matériau en main : %s" % _material_name(_held_material))
	else:
		# GAME-1212 — la matière posée porte le matériau en main.
		TerrainEditing.add(_voxel_tool, center, EDIT_RADIUS, _held_material)
		# GAME-1211 — vrai fix : que le garde-fou ci-dessus ait suffi ou non,
		# on vérifie l'état réel des voxels et on dépénètre si besoin.
		_depenetrate_player()

func _material_name(index: int) -> String:
	var names: Array = ProceduralTerrainGenerator.MATERIAL_NAMES
	if index >= 0 and index < names.size():
		return names[index]
	return "matériau %d" % index

func _is_solid_at(pos: Vector3) -> bool:
	if _voxel_tool == null:
		return false
	return _voxel_tool.get_voxel_f_interpolated(pos) < 0.0

func _player_is_stuck() -> bool:
	var base := _player.global_position
	for h in DEPEN_SAMPLE_HEIGHTS:
		if _is_solid_at(base + Vector3.UP * h):
			return true
	return false

func _depenetrate_player() -> void:
	if _player == null:
		return
	var steps := 0
	while _player_is_stuck() and steps < DEPEN_MAX_STEPS:
		_player.global_position += Vector3.UP * DEPEN_STEP
		steps += 1
	if steps > 0:
		_player.velocity = Vector3.ZERO
		if steps >= DEPEN_MAX_STEPS:
			push_warning("[terrain_player] Dépénétration : limite atteinte, le joueur est peut-être encore coincé.")

func _physics_process(delta: float) -> void:
	if _grounded:
		var p0 := _player.global_position
		# GAME-1204 fix, secours GAME-1210 : la croute (SURFACE_CRUST) est
		# toujours pleine ; s'y trouver sans toucher le sol = on a traversé.
		# Ce filet ne sert plus qu'aux tout premiers instants — le spawn
		# normal attend déjà que la collision soit prête (cf. _settle_step).
		var surf := ProceduralTerrainGenerator.get_height(p0.x, p0.z)
		if not _player.is_on_floor() and _player.velocity.y < 0.0 \
				and p0.y < surf - 3.0 and p0.y > surf - (ProceduralTerrainGenerator.SURFACE_CRUST - 1.0):
			_begin_settle()
			return
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
	# GAME-1210 — le joueur reste hors-physique (flottant, invisible pour la
	# marche) tant que la collision du chunk sous lui n'est pas confirmée par
	# ce raycast. On ne le rend "au sol" qu'une fois une collision réelle
	# trouvée : ce n'est donc pas "spawner puis rattraper" mais "attendre
	# avant de lâcher".
	_elapsed += delta
	var p := _player.global_position
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(p.x, SCAN_TOP, p.z), Vector3(p.x, SCAN_BOTTOM, p.z))
	query.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit:
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
	_camera = _player.get_node("CameraPivot/Camera3D")
	_player.global_position = _surface_wait_pos(0.0, 0.0)
	_player.set_physics_process(false)
	var viewer := VoxelViewer.new()
	viewer.requires_collisions = true
	viewer.view_distance = VIEW_DISTANCE
	_player.add_child(viewer)

func _build_terrain() -> void:
	_terrain = VoxelLodTerrain.new()
	_terrain.name = "VoxelLodTerrain"
	_terrain.mesher = ProceduralTerrainGenerator.make_mesher()
	_terrain.format = ProceduralTerrainGenerator.make_format()
	_terrain.generator = ProceduralTerrainGenerator.build()
	_terrain.generate_collisions = true
	_terrain.collision_lod_count = COLLISION_LOD_COUNT
	_terrain.lod_count = LOD_COUNT
	_terrain.lod_distance = LOD_DISTANCE
	add_child(_terrain)
	_terrain.material = TerrainMaterial.build()
	_voxel_tool = _terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF

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
