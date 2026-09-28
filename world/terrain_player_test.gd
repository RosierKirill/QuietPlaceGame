extends Node3D
## Bac à sable du terrain voxel (Epic E12) — grille en blocs, biomes, grottes.
##
##   - Le terrain est à l'échelle de la grille : 1 voxel = 0.25 unité, 1 bloc
##     = 0.75 unité. Les coordonnées du VoxelTool sont donc LOCALES (voxels),
##     jamais celles du monde : on convertit avec ProceduralTerrainGenerator.
##   - SPAWN: the player appears in a COMPLETE world. The loading screen stays
##     until the whole full-detail area around the spawn is meshed and the
##     ground under the player has its collider. No timeout: the player is
##     never dropped into an unfinished world.
##   - STREAMING GUARD: while playing, if the player reaches ground whose data
##     or collider is not built yet, he is held in place until it is. He can
##     neither fall through nor walk into a hole.
##   - A dépénétration remonte le joueur s'il se retrouve dans la matière
##     (GAME-1211).
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
const WaterFieldScript := preload("res://world/water_field.gd")
const WaterSurfaceScript := preload("res://world/water_surface.gd")
const SkyEnvironmentScript := preload("res://world/sky_environment.gd")
const UnderwaterEffectScript := preload("res://world/underwater_effect.gd")

const LOD_COUNT := 7
const LOD_DISTANCE := 128.0    # en voxels (= 32 unités de plein détail)
const VIEW_DISTANCE := 800     # en voxels (= 200 unités)
const COLLISION_LOD_COUNT := 1
const SPAWN_LIFT := 3.0
const DROP_MARGIN := 0.2
const FALL_LIMIT := -120.0
## Graine fixe pour rejouer un monde ; -1 = graine tirée au hasard.
const FIXED_SEED := -1
## Tolérance (unités) entre la hauteur analytique et la collision trouvée.
const SURFACE_TOLERANCE := 3.0

# Spawn area that must be meshed at full detail before the player appears, in
# voxels (half sizes): 16 units around him, 8 up and down. It must fit inside
# the full-detail sphere (LOD_DISTANCE = 128 voxels), otherwise its corners
# would be meshed at a lower level and never reported as done at level 0:
# sqrt(64² + 64² + 32²) = 96 < 128.
const SPAWN_AREA_V := 64.0
const SPAWN_AREA_HEIGHT_V := 32.0
# The area is checked as SPAWN_AREA_CELLS x SPAWN_AREA_CELLS boxes, which also
# gives the progress shown on the loading screen.
const SPAWN_AREA_CELLS := 4
# Spawn search: spiral of candidate columns around the origin, in units.
const SPAWN_SEARCH_STEP := 24.0
const SPAWN_SEARCH_RADIUS := 2000.0
const SPAWN_MAX_SLOPE := 0.6        # tangent
# Streaming guard: how far under the feet the ground is checked, in units.
const GUARD_PROBE_DEPTH := 0.6

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
var _reported := false
var _report_time := 0.0
## True while the streaming guard holds the player.
var _held := false
## Largest number of pending voxel tasks seen while loading (progress bar).
var _max_pending := 0
## Matériau en main : celui du dernier bloc cassé (terre au départ).
var _held_material: int = ProceduralTerrainGenerator.MAT_DIRT
var _loading: CanvasLayer
## Nappe d'eau du monde et son maillage de surface.
var _water_field
var _water: Node3D

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
	_water_ground_changed(hit.position)
	if picked >= 0 and picked != _held_material:
		_held_material = picked
		print("[terrain] Matière en main : %s" % _material_name(picked))

func _place_block() -> void:
	var hit := _aim()
	if hit == null:
		return
	if TerrainEditing.place_block(_voxel_tool, hit.previous_position, _held_material):
		_water_ground_changed(hit.previous_position)
		# GAME-1211 : si le bloc posé enferme le joueur, on le remonte.
		_depenetrate_player()

## Prévient la nappe qu'une colonne a changé de sol. Le générateur ignore les
## modifications du joueur : on mesure donc le nouveau sol sur le terrain réel.
func _water_ground_changed(voxel_position: Vector3i) -> void:
	if _water_field == null:
		return
	var n: int = ProceduralTerrainGenerator.BLOCK_VOXELS
	var bx := int(floor(float(voxel_position.x) / float(n)))
	var bz := int(floor(float(voxel_position.z) / float(n)))
	_water_field.ground_changed(bx, bz, _column_ground(bx, bz))


## Sous-voxel plein le plus haut de la colonne, en partant au-dessus du sol
## connu et en descendant. Retourne une hauteur en sous-voxels.
func _column_ground(bx: int, bz: int) -> float:
	var n: int = ProceduralTerrainGenerator.BLOCK_VOXELS
	var vx := bx * n + 1
	var vz := bz * n + 1
	var top := int(_water_field.ground_at(bx, bz)) + 8
	var bottom := top - 96
	for y in range(top, bottom, -1):
		if _voxel_tool.get_voxel_f(Vector3i(vx, y, vz)) < 0.0:
			return float(y + 1)
	return float(bottom)


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
	if not _grounded:
		_settle_step()
		return
	_guard_streaming()
	var p0 := _player.global_position
	if p0.y < FALL_LIMIT:
		push_warning("[terrain_player] Joueur sous la limite du monde : retour à la surface.")
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


func _exit_tree() -> void:
	# Leaving the world by any path: the clock must not keep running.
	TimeOfDay.stop_clock()


func _surface_wait_pos(x: float, z: float) -> Vector3:
	return Vector3(x, ProceduralTerrainGenerator.get_height(x, z) + SPAWN_LIFT, z)


## Holds the player above the ground of his column until it is ready again.
func _begin_settle() -> void:
	_grounded = false
	_reported = false
	_report_time = 0.0
	var p := _player.global_position
	_player.global_position = _surface_wait_pos(p.x, p.z)
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(false)


## Waits for a complete world around the spawn, then drops the player.
##
## Three conditions, all required, no timeout:
##   1. every box of the spawn area has been meshed at full detail
##      (VoxelLodTerrain.is_area_meshed);
##   2. the voxel engine has no work left: generation, meshing, streaming, and
##      main-thread tasks (which include building colliders) — the whole view,
##      every level of detail, is done (VoxelEngine.get_stats);
##   3. a ray finds the collider of the ground under the player.
func _settle_step() -> void:
	var p := _player.global_position
	var surf := ProceduralTerrainGenerator.get_height(p.x, p.z)
	var meshed := _spawn_area_meshed_ratio(Vector3(p.x, surf, p.z))
	if meshed < 1.0:
		_show_loading(meshed * 0.6, "Génération du terrain…")
		return

	var pending := _pending_voxel_tasks()
	_max_pending = maxi(_max_pending, pending)
	if pending > 0:
		var done := 1.0 - float(pending) / float(maxi(_max_pending, 1))
		_show_loading(0.6 + 0.35 * done, "Chargement des alentours…")
		return

	_show_loading(0.97, "Mise en place de la collision…")
	var hit := _ground_ray(Vector3(p.x, surf + SPAWN_LIFT + 1.0, p.z),
		Vector3(p.x, surf - SURFACE_TOLERANCE, p.z))
	if not hit.is_empty():
		_drop_player(float(hit.position.y) + DROP_MARGIN)


## Tasks still queued in the voxel engine (all terrains).
func _pending_voxel_tasks() -> int:
	var tasks: Dictionary = VoxelEngine.get_stats().get("tasks", {})
	return int(tasks.get("streaming", 0)) + int(tasks.get("generation", 0)) \
		+ int(tasks.get("meshing", 0)) + int(tasks.get("main_thread", 0))


## Share of the spawn area already meshed at full detail, from 0 to 1.
func _spawn_area_meshed_ratio(center_world: Vector3) -> float:
	var center := ProceduralTerrainGenerator.to_voxel(center_world)
	var cell := SPAWN_AREA_V * 2.0 / float(SPAWN_AREA_CELLS)
	var origin := center - Vector3(SPAWN_AREA_V, SPAWN_AREA_HEIGHT_V, SPAWN_AREA_V)
	var size := Vector3(cell, SPAWN_AREA_HEIGHT_V * 2.0, cell)
	var done := 0
	for ix in SPAWN_AREA_CELLS:
		for iz in SPAWN_AREA_CELLS:
			var box := AABB(origin + Vector3(ix * cell, 0.0, iz * cell), size)
			if _terrain.is_area_meshed(box, 0):
				done += 1
	return float(done) / float(SPAWN_AREA_CELLS * SPAWN_AREA_CELLS)


func _show_loading(progress: float, status: String) -> void:
	if _loading == null or not is_instance_valid(_loading):
		return
	_loading.set_progress(progress)
	_loading.set_status(status)


## Physics ray against the terrain, ignoring the player. Empty if nothing.
func _ground_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func _drop_player(y: float) -> void:
	_grounded = true
	var p := _player.global_position
	_player.global_position = Vector3(p.x, y, p.z)
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(true)
	# Au cas où la collision le coince dans un versant, on le dégage tout de suite.
	_depenetrate_player()
	if _loading != null and is_instance_valid(_loading):
		_loading.finish()
		_loading = null
		# First time on the ground: the world is ready, time can run.
		TimeOfDay.start_clock()
	print("[terrain_player] Joueur posé au sol à y=%.1f (biome %s)" % [
		_player.global_position.y,
		ProceduralTerrainGenerator.BIOME_NAMES[ProceduralTerrainGenerator.get_biome(p.x, p.z)]])


## Streaming guard, every physics frame while playing.
##
## The player is held (no physics) when the ground around him is not ready:
##   - its voxel data is not loaded yet (the area is not editable), or
##   - the voxels say there is ground right under his feet but no collider has
##     been built for it yet (he would fall through).
## He is released as soon as both are ready.
func _guard_streaming() -> void:
	var ground_ready := _ground_ready_around_player()
	if ground_ready == not _held:
		return
	_held = not ground_ready
	if _held:
		_player.velocity = Vector3.ZERO
	_player.set_physics_process(ground_ready)


func _ground_ready_around_player() -> bool:
	var feet := _player.global_position
	var feet_voxel := Vector3i(ProceduralTerrainGenerator.to_voxel(feet).floor())
	if not TerrainEditing.can_edit_quiet(_voxel_tool, feet_voxel):
		return false
	if _player.is_on_floor():
		return true
	# Falling or jumping: only a problem if there is ground just under the feet
	# that the physics does not know about.
	var below := feet + Vector3.DOWN * GUARD_PROBE_DEPTH
	if not _is_solid_at(below):
		return true
	var hit := _ground_ray(feet + Vector3.UP * 0.5, below)
	return not hit.is_empty()


## Dry, flat enough, not over a cave entrance: the first such column on a
## spiral around the origin. The same seed always gives the same spawn.
func _find_spawn_column() -> Vector2:
	var sea := ProceduralTerrainGenerator.SEA_LEVEL
	var radius := 0.0
	while radius <= SPAWN_SEARCH_RADIUS:
		var steps := maxi(1, int(TAU * radius / SPAWN_SEARCH_STEP))
		for i in steps:
			var angle := TAU * float(i) / float(steps)
			var x := cos(angle) * radius
			var z := sin(angle) * radius
			if _is_good_spawn(x, z, sea):
				return Vector2(x, z)
		radius += SPAWN_SEARCH_STEP
	push_warning("[terrain_player] Aucune colonne de spawn idéale trouvée : origine.")
	return Vector2.ZERO


func _is_good_spawn(x: float, z: float, sea: float) -> bool:
	var h := ProceduralTerrainGenerator.get_height(x, z)
	if h < sea + 1.0:
		return false
	if ProceduralTerrainGenerator.get_entrance_openness(x, z) > 0.0:
		return false
	var dx := ProceduralTerrainGenerator.get_height(x + 1.0, z) - h
	var dz := ProceduralTerrainGenerator.get_height(x, z + 1.0) - h
	return sqrt(dx * dx + dz * dz) <= SPAWN_MAX_SLOPE


func _spawn_player() -> void:
	_player = PlayerScene.instantiate()
	add_child(_player)
	_camera = _player.get_node("CameraPivot/Camera3D")
	var spawn := _find_spawn_column()
	_player.global_position = _surface_wait_pos(spawn.x, spawn.y)
	_player.set_physics_process(false)
	var viewer := VoxelViewer.new()
	viewer.requires_collisions = true
	viewer.view_distance = VIEW_DISTANCE
	_player.add_child(viewer)

	if _water != null:
		_water.setup(_water_field, _player, WaterMaterial.build())
		var swimmer = _player.get_node_or_null("Swimmer")
		if swimmer != null:
			swimmer.set_water(_water)
		var underwater := UnderwaterEffectScript.new()
		underwater.name = "UnderwaterEffect"
		_camera.add_child(underwater)
		underwater.setup(_camera, _water)

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

	# The water reads the same ground as the terrain graph (same seed).
	_water_field = WaterFieldScript.new()
	_water = WaterSurfaceScript.new()
	_water.name = "WaterSurface"
	add_child(_water)

## Ciel et soleil : tout est dans SkyEnvironment, qui suit l'horloge du monde.
func _build_environment() -> void:
	var sky := SkyEnvironmentScript.new()
	sky.name = "SkyEnvironment"
	add_child(sky)
