class_name WaterSurface
extends Node3D
## Surface de l'eau (GAME-1233).
##
## The SEA is one flat disc at sea level that follows the player. The terrain
## is drawn first and hides it wherever the ground is above the sea, so the
## shoreline is exactly the terrain contour. (Before, the sea was made of
## 0.75-unit quads per block column: at the shore they overhung the slope and
## looked like plates floating above the ground.)
##
## Water that is NOT at sea level (a column the flow has filled or drained) is
## still meshed in tiles around the player, merged into maximal rectangles
## (greedy meshing).

const PTG := preload("res://world/procedural_terrain_generator.gd")
const Field := preload("res://world/water_field.gd")

## Côté d'une tuile, en colonnes de blocs (16 x 0.75 = 12 unités).
const TILE := 16
## Rayon maillé, en tuiles (8 x 12 = 96 unités).
const TILE_RADIUS := 8
## Radius of the sea disc, in units, and its number of segments.
const SEA_RADIUS := 1500.0
const SEA_SEGMENTS := 48
## Below this gap (voxels) a water column is at sea level: the disc draws it.
const SEA_TOLERANCE := 0.05

## Nombre de colonnes que l'écoulement traite par image.
const FLOW_BUDGET := 400
## Nombre de tuiles remaillées par image : au-delà, l'image saccade.
const TILES_PER_FRAME := 3

var field                            # WaterField

var _target: Node3D
var _material: ShaderMaterial
var _tiles: Dictionary = {}          # Vector2i -> MeshInstance3D
var _pending: Dictionary = {}        # Vector2i -> true : tuiles à reconstruire
var _ring: MeshInstance3D
var _center := Vector2i(999999, 0)


func setup(water_field, target: Node3D, material: ShaderMaterial) -> void:
	field = water_field
	_target = target
	_material = material
	_build_ring()


func _process(_delta: float) -> void:
	if field == null or _target == null:
		return

	field.step(FLOW_BUDGET)
	for key in field.take_dirty():
		_pending[_tile_of(key.x, key.y)] = true

	var position := _target.global_position
	var center := _tile_of(
		int(floor(position.x / PTG.BLOCK_SIZE)),
		int(floor(position.z / PTG.BLOCK_SIZE)))
	if center != _center:
		_center = center
		_refresh_tiles()
	_rebuild_pending()

	if _ring != null:
		# Also visible from below: it is the surface seen while swimming.
		_ring.global_position = Vector3(position.x, field.sea_level() * PTG.VOXEL_SIZE,
			position.z)


## Altitude de la surface de l'eau à cette position du monde, ou NAN s'il n'y a
## pas d'eau. C'est le point d'entrée du joueur (nage, souffle, boisson).
func surface_y(world_position: Vector3) -> float:
	if field == null:
		return NAN
	var bx := int(floor(world_position.x / PTG.BLOCK_SIZE))
	var bz := int(floor(world_position.z / PTG.BLOCK_SIZE))
	var s: float = field.surface_at(bx, bz)
	if s == Field.DRY:
		return NAN
	return s * PTG.VOXEL_SIZE


func _tile_of(bx: int, bz: int) -> Vector2i:
	return Vector2i(int(floor(float(bx) / float(TILE))), int(floor(float(bz) / float(TILE))))


## Crée les tuiles entrées dans le rayon, libère celles qui en sont sorties.
func _refresh_tiles() -> void:
	for key in _tiles.keys():
		var d: Vector2i = key - _center
		if absi(d.x) > TILE_RADIUS or absi(d.y) > TILE_RADIUS:
			var node: MeshInstance3D = _tiles[key]
			_tiles.erase(key)
			_pending.erase(key)
			node.queue_free()
	for dx in range(-TILE_RADIUS, TILE_RADIUS + 1):
		for dz in range(-TILE_RADIUS, TILE_RADIUS + 1):
			var key := _center + Vector2i(dx, dz)
			if not _tiles.has(key):
				_pending[key] = true


## Reconstruit les tuiles en attente. Le budget évite un à-coup quand le joueur
## traverse une grande étendue d'eau.
func _rebuild_pending() -> void:
	if _pending.is_empty():
		return
	var built := 0
	for key in _pending.keys():
		if built >= TILES_PER_FRAME:
			break
		_pending.erase(key)
		var d: Vector2i = key - _center
		if absi(d.x) > TILE_RADIUS or absi(d.y) > TILE_RADIUS:
			continue
		built += 1
		_build_tile(key)


func _build_tile(tile: Vector2i) -> void:
	var mesh := _tile_mesh(tile)
	var node: MeshInstance3D = _tiles.get(tile)
	if mesh == null:
		if node != null:
			_tiles.erase(tile)
			node.queue_free()
		return
	if node == null:
		node = MeshInstance3D.new()
		node.material_override = _material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_tiles[tile] = node
	node.mesh = mesh


## Maillage glouton d'une tuile : on regroupe les colonnes de même niveau en
## rectangles maximaux. Retourne null si la tuile est entièrement sèche.
func _tile_mesh(tile: Vector2i) -> ArrayMesh:
	var base_x := tile.x * TILE
	var base_z := tile.y * TILE
	var levels := PackedFloat32Array()
	levels.resize(TILE * TILE)
	var any := false
	for ix in TILE:
		for iz in TILE:
			var s: float = field.surface_at(base_x + ix, base_z + iz)
			# Dry, or at sea level: the sea disc already draws it.
			if s == Field.DRY or absf(s - field.sea_level()) < SEA_TOLERANCE:
				levels[ix * TILE + iz] = NAN
			else:
				levels[ix * TILE + iz] = s
				any = true
	if not any:
		return null

	var used := PackedByteArray()
	used.resize(TILE * TILE)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()

	for ix in TILE:
		for iz in TILE:
			var index := ix * TILE + iz
			if used[index] == 1:
				continue
			var level := levels[index]
			if is_nan(level):
				continue
			# Extension en x tant que le niveau est le même.
			var width := 1
			while ix + width < TILE and used[(ix + width) * TILE + iz] == 0 \
					and _same(levels[(ix + width) * TILE + iz], level):
				width += 1
			# Puis extension en z, ligne entière par ligne entière.
			var depth := 1
			while iz + depth < TILE:
				var ok := true
				for k in width:
					var other := (ix + k) * TILE + iz + depth
					if used[other] == 1 or not _same(levels[other], level):
						ok = false
						break
				if not ok:
					break
				depth += 1
			for k in width:
				for m in depth:
					used[(ix + k) * TILE + iz + m] = 1
			_add_quad(verts, normals, uvs, base_x + ix, base_z + iz, width, depth, level)

	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _same(a: float, b: float) -> bool:
	return not is_nan(a) and absf(a - b) < 0.05


func _add_quad(verts: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, bx: int, bz: int, width: int, depth: int,
		level: float) -> void:
	var x0 := float(bx) * PTG.BLOCK_SIZE
	var z0 := float(bz) * PTG.BLOCK_SIZE
	var x1 := x0 + float(width) * PTG.BLOCK_SIZE
	var z1 := z0 + float(depth) * PTG.BLOCK_SIZE
	var y := level * PTG.VOXEL_SIZE
	var a := Vector3(x0, y, z0)
	var b := Vector3(x1, y, z0)
	var c := Vector3(x1, y, z1)
	var d := Vector3(x0, y, z1)
	for v in [a, c, b, a, d, c]:
		verts.push_back(v)
		normals.push_back(Vector3.UP)
		uvs.push_back(Vector2(v.x, v.z))


## Anneau plat qui ferme l'horizon au-delà des tuiles.
func _build_ring() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	# A fan of triangles around the centre: a flat disc.
	for i in SEA_SEGMENTS:
		var a0 := TAU * float(i) / float(SEA_SEGMENTS)
		var a1 := TAU * float(i + 1) / float(SEA_SEGMENTS)
		var outer0 := Vector3(cos(a0) * SEA_RADIUS, 0.0, sin(a0) * SEA_RADIUS)
		var outer1 := Vector3(cos(a1) * SEA_RADIUS, 0.0, sin(a1) * SEA_RADIUS)
		for v in [Vector3.ZERO, outer0, outer1]:
			verts.push_back(v)
			normals.push_back(Vector3.UP)
			uvs.push_back(Vector2(v.x, v.z))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ring = MeshInstance3D.new()
	_ring.mesh = mesh
	_ring.material_override = _material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.extra_cull_margin = SEA_RADIUS
	add_child(_ring)
