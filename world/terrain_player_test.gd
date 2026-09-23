extends Node3D
## Bac à sable du terrain voxel (Epic E12) — grille en blocs, biomes, grottes.
##
##   - Le terrain est à l'échelle de la grille : 1 voxel = 0.25 unité, 1 bloc
##     = 0.75 unité. Les coordonnées du VoxelTool sont donc LOCALES (voxels),
##     jamais celles du monde : on convertit avec ProceduralTerrainGenerator.
##   - SPAWN : le joueur reste hors-physique tant que la collision du chunk
##     sous lui n'est pas prête (GAME-1210). Le filet anti-chute ne sert que de
##     secours (GAME-1204), et une dépénétration remonte le joueur s'il se
##     retrouve dans la matière (GAME-1211).
##   - CONSTRUCTION : clic gauche = casser le bloc visé (on ramasse son
##     matériau), clic droit = poser un bloc du matériau en main, aligné sur la
##     grille. Touches 1 à 9 : choisir la matière à poser.
##   - GRAINE : tirée au hasard à chaque lancement et affichée dans la console
##     (GAME-1219). Mettre FIXED_SEED à une valeur positive pour rejouer un
##     monde précis.

const ProceduralTerrainGenerator := preload("res://world/procedural_terrain_generator.gd")
const TerrainEditing := preload("res://world/terrain_editing.gd")
const PlayerScene := preload("res://player/player.tscn")
const LoadingScreenScene := preload("res://ui/loading_screen.tscn")

const LOD_COUNT := 7
const LOD_DISTANCE := 128.0    # en voxels (= 32 unités de plein détail)
const VIEW_DISTANCE := 800     # en voxels (= 200 unités)
const COLLISION_LOD_COUNT := 1
const SPAWN_LIFT := 3.0
const DROP_MARGIN := 0.2
const SCAN_TOP := 400.0
const SCAN_BOTTOM := -400.0
const SPAWN_TIMEOUT := 20.0
const FALL_LIMIT := -120.0
## Graine fixe pour rejouer un monde ; -1 = graine tirée au hasard.
const FIXED_SEED := -1
## Le filet anti-chute ne vaut que pendant ces premières secondes au sol :
## après, être sous la surface veut simplement dire qu'on explore une grotte.
const SPAWN_GRACE := 6.0
## Tolérance (unités) entre la hauteur analytique et la collision trouvée.
const SURFACE_TOLERANCE := 3.0

const EDIT_DISTANCE := 6.0     # portée de construction, en unités de monde

# Dépénétration (GAME-1211) : sondes sur la hauteur du joueur.
const DEPEN_SAMPLE_HEIGHTS := [0.1, 0.9, 1.7]
const DEPEN_STEP := 0.15
const DEPEN_MAX_STEPS := 40

var _player: CharacterBody3D
var _camera: Camera3D
var _terrain: VoxelLodTerrain
var _voxel_tool: VoxelTool
var _grounded := false
var _elapsed := 0.0
var _reported := false
var _report_time := 0.0
## Matériau en main : celui du dernier bloc cassé (terre au départ).
var _held_material: int = ProceduralTerrainGenerator.MAT_DIRT
var _grace_left := 0.0
var _loading: CanvasLayer

func _ready() -> void:
	if FIXED_SEED >= 0:
		ProceduralTerrainGenerator.set_world_seed(FIXED_SEED)
	else:
		ProceduralTerrainGenerator.randomize_world_seed()
	print("[terrain] Graine du monde : %d" % ProceduralTerrainGenerator.world_seed)
	_loading = LoadingScreenScene.instantiate()
	add_child(_loading)
	_loading.show_seed(ProceduralTerrainGenerator.world_seed)
	_loading.set_status("Génération du terrain…")
	_build_environment()
	_build_terrain()
	_spawn_player()
	print("[terrain] Construction : clic gauche = casser, clic droit = poser, touches 1-9 = matière.")

func _unhandled_input(event: InputEvent) -> void:
	if not _grounded or _camera == null or _voxel_tool == null:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_break_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_place_block()
	elif event is InputEventKey and event.pressed and not event.echo:
		var slot: int = event.keycode - KEY_1
		if slot >= 0 and slot < ProceduralTerrainGenerator.MATERIAL_NAMES.size():
			_held_material = slot
			print("[terrain] Matière en main : %s" % _material_name(slot))

## Bloc visé par la caméra. Renvoie null si rien à portée.
func _aim() -> VoxelRaycastResult:
	var origin: Vector3 = ProceduralTerrainGenerator.to_voxel(_camera.global_position)
	var dir := -_camera.global_transform.basis.z
	var reach: float = EDIT_DISTANCE / ProceduralTerrainGenerator.VOXEL_SIZE
	return _voxel_tool.raycast(origin, dir, reach)

func _break_block() -> void:
	var hit := _aim()
	if hit == null:
		return
	var picked := TerrainEditing.break_block(_voxel_tool, hit.position)
	if picked >= 0 and picked != _held_material:
		_held_material = picked
		print("[terrain] Matière en main : %s" % _material_name(picked))

func _place_block() -> void:
	var hit := _aim()
	if hit == null:
		return
	if TerrainEditing.place_block(_voxel_tool, hit.previous_position, _held_material):
		# GAME-1211 : si le bloc posé enferme le joueur, on le remonte.
		_depenetrate_player()

func _material_name(index: int) -> String:
	var names: Array = ProceduralTerrainGenerator.MATERIAL_NAMES
	if index >= 0 and index < names.size():
		return names[index]
	return "matériau %d" % index

func _is_solid_at(world_position: Vector3) -> bool:
	if _voxel_tool == null:
		return false
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	return _voxel_tool.get_voxel_f_interpolated(
		ProceduralTerrainGenerator.to_voxel(world_position)) < 0.0

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
			push_warning("[terrain_player] Dépénétration : limite atteinte.")

func _physics_process(delta: float) -> void:
	if _grounded:
		var p0 := _player.global_position
		# Secours des premières secondes seulement : passé ce délai, être sous
		# la surface signifie simplement qu'on explore une grotte.
		_grace_left = maxf(_grace_left - delta, 0.0)
		var surf := ProceduralTerrainGenerator.get_height(p0.x, p0.z)
		if _grace_left > 0.0 and not _player.is_on_floor() and _player.velocity.y < 0.0 \
				and p0.y < surf - 2.0:
			_begin_settle()
			return
		if p0.y < FALL_LIMIT:
			_begin_settle()
			return
		if not _reported:
			_report_time += delta
			if _report_time >= 1.0:
				_reported = true
				var biome: int = ProceduralTerrainGenerator.get_biome(p0.x, p0.z)
				print("[terrain_player] DIAG 1s : au sol=%s, y=%.1f, biome=%s" % [
					str(_player.is_on_floor()), p0.y,
					ProceduralTerrainGenerator.BIOME_NAMES[biome]])
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
	# GAME-1210 : on attend que la collision existe vraiment SOUS LA SURFACE
	# avant de rendre la physique au joueur. Le rayon ne balaie qu'une fenêtre
	# autour de la hauteur analytique : sinon, un plafond de grotte chargé avant
	# le sol ferait apparaître le joueur sous terre.
	_elapsed += delta
	var p := _player.global_position
	var surf := ProceduralTerrainGenerator.get_height(p.x, p.z)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(p.x, surf + SPAWN_LIFT + 1.0, p.z),
		Vector3(p.x, surf - SURFACE_TOLERANCE, p.z))
	query.exclude = [_player.get_rid()]
	_update_loading(surf)
	var hit := space.intersect_ray(query)
	if hit:
		_drop_player(float(hit.position.y) + DROP_MARGIN)
	elif _elapsed >= SPAWN_TIMEOUT:
		push_warning("[terrain_player] Collision toujours absente : pose sur la hauteur calculée.")
		_drop_player(surf + DROP_MARGIN)

## Avancement affiché : les voxels d'abord, la collision ensuite.
func _update_loading(surf: float) -> void:
	if _loading == null or not is_instance_valid(_loading):
		return
	# La barre avance déjà avec le temps, pour ne jamais paraître figée.
	_loading.set_progress(minf(_elapsed / SPAWN_TIMEOUT, 0.85) * 0.5)
	var spawn_voxel := Vector3i(ProceduralTerrainGenerator.to_voxel(
		Vector3(_player.global_position.x, surf, _player.global_position.z)))
	if TerrainEditing.can_edit_quiet(_voxel_tool, spawn_voxel):
		_loading.set_progress(0.7)
		_loading.set_status("Mise en place de la collision…")
	else:
		_loading.set_status("Génération du terrain…")

func _drop_player(y: float) -> void:
	_grounded = true
	_grace_left = SPAWN_GRACE
	var p := _player.global_position
	_player.global_position = Vector3(p.x, y, p.z)
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(true)
	# Au cas où la collision le coince dans un versant, on le dégage tout de suite.
	_depenetrate_player()
	if _loading != null and is_instance_valid(_loading):
		_loading.finish()
	print("[terrain_player] Joueur posé au sol à y=%.1f (biome %s)" % [
		_player.global_position.y,
		ProceduralTerrainGenerator.BIOME_NAMES[ProceduralTerrainGenerator.get_biome(p.x, p.z)]])

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
	ProceduralTerrainGenerator.apply_scale(_terrain)
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
