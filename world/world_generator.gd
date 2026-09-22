class_name WorldGenerator
extends VoxelGeneratorScript
## Générateur du monde, raisonnant EN BLOCS (GAME-1223).
##
## Le graphe voxel précédent travaillait voxel par voxel : il ne savait pas
## dire « ce bloc est une pente ». Ici la génération est écrite en GDScript et
## travaille à la maille du BLOC (0.75 unité = 3 x 3 x 3 sous-voxels de 0.25) :
## pour chaque colonne de blocs on calcule la hauteur du sol, puis on choisit
## un ÉTAT dans le catalogue BlockShapes (plein, plats, pentes de sol, pentes
## de plafond). Les sous-voxels sont ensuite remplis par tranches verticales,
## ce qui reste rapide même en GDScript.
##
## Le champ est BINAIRE : un sous-voxel est plein (-1) ou vide (+1). Les
## sommets du maillage tombent donc toujours au même endroit de la grille, et
## le mailleur produit le biseau à 45° attendu.
##
## Les bruits, les biomes et les matériaux viennent de
## ProceduralTerrainGenerator, qui reste la source unique des réglages.

const PTG := preload("res://world/procedural_terrain_generator.gd")
const Shapes := preload("res://world/block_shapes.gd")

const SOLID := -1.0
const AIR := 1.0
const N := 3                      # sous-voxels par bloc et par axe

# Bruits instanciés une seule fois : les recréer à chaque appel coûterait cher.
var _height_noise: FastNoiseLite
var _mask_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _temperature_noise: FastNoiseLite
var _humidity_noise: FastNoiseLite
var _cave_a: FastNoiseLite
var _cave_b: FastNoiseLite
var _room_noise: FastNoiseLite
var _ore_noise: FastNoiseLite
var _ore_type_noise: FastNoiseLite
var _height_curve: Curve
var _mask_curve: Curve


func _init() -> void:
	rebuild_noises()


## À rappeler après un changement de graine.
func rebuild_noises() -> void:
	_height_noise = PTG.make_height_noise()
	_mask_noise = PTG.make_mask_noise()
	_ridge_noise = PTG.make_ridge_noise()
	_temperature_noise = PTG.make_temperature_noise()
	_humidity_noise = PTG.make_humidity_noise()
	_cave_a = PTG.make_cave_noise(0)
	_cave_b = PTG.make_cave_noise(1)
	_room_noise = PTG.make_room_noise()
	_ore_noise = PTG.make_ore_noise()
	_ore_type_noise = PTG.make_ore_type_noise()
	_height_curve = PTG.make_height_curve()
	_mask_curve = PTG.make_mask_curve()


func _get_used_channels_mask() -> int:
	return (1 << VoxelBuffer.CHANNEL_SDF) | (1 << VoxelBuffer.CHANNEL_INDICES)


# --- Champs continus (en VOXELS, l'espace local du terrain) -------------------

## Hauteur continue du sol, en voxels, avant toute quantification.
func surface_voxels(vx: float, vz: float) -> float:
	var t := clampf(_height_noise.get_noise_2d(vx, vz) * 0.5 + 0.5, 0.0, 1.0)
	var profile := _height_curve.sample_baked(t)
	var mask_raw := clampf(_mask_noise.get_noise_2d(vx, vz) * 0.5 + 0.5, 0.0, 1.0)
	var mask := _mask_curve.sample_baked(mask_raw)
	var amp := (PTG.BASE_AMPLITUDE + mask * PTG.MOUNTAIN_AMPLITUDE) / PTG.VOXEL_SIZE
	var ridge := 1.0 - absf(_ridge_noise.get_noise_2d(vx, vz))
	var ridge_h := ridge * ridge * (PTG.RIDGE_AMPLITUDE / PTG.VOXEL_SIZE) * mask
	return profile * amp + ridge_h


func temperature_at(vx: float, vz: float, height_v: float) -> float:
	var base := clampf(_temperature_noise.get_noise_2d(vx, vz) * 0.5 + 0.5, 0.0, 1.0)
	var altitude := maxf(height_v * PTG.VOXEL_SIZE - PTG.COLD_ALTITUDE_START, 0.0)
	return clampf(base - altitude / PTG.COLD_ALTITUDE_RANGE, 0.0, 1.0)


func humidity_at(vx: float, vz: float) -> float:
	return clampf(_humidity_noise.get_noise_2d(vx, vz) * 0.5 + 0.5, 0.0, 1.0)


## Le bloc est-il creusé par une grotte ? Les bruits sont lus au centre du bloc,
## donc constants sur tout le bloc : les grottes sont en blocs, comme la surface.
func cave_at(bx: int, by: int, bz: int, surface_v: float) -> bool:
	var cx := float(bx * N + 1)
	var cy := float(by * N + 1)
	var cz := float(bz * N + 1)
	# Croûte : rien n'est creusé trop près de la surface.
	if cy > surface_v - PTG.SURFACE_CRUST / PTG.VOXEL_SIZE:
		return false
	var a := absf(_cave_a.get_noise_3d(cx, cy, cz)) - PTG.CAVE_WIDTH
	var b := absf(_cave_b.get_noise_3d(cx, cy, cz)) - PTG.CAVE_WIDTH
	if maxf(a, b) < 0.0:
		return true
	return _room_noise.get_noise_3d(cx, cy, cz) > PTG.ROOM_THRESHOLD


## Minerai éventuel de ce bloc (sinon -1). Les veines suivent les parois.
func ore_at(bx: int, by: int, bz: int, depth_v: float, near_cave: bool) -> int:
	if not near_cave or depth_v < PTG.ORE_MIN_DEPTH / PTG.VOXEL_SIZE:
		return -1
	var cx := float(bx * N + 1)
	var cy := float(by * N + 1)
	var cz := float(bz * N + 1)
	if _ore_noise.get_noise_3d(cx, cy, cz) * 0.5 + 0.5 < PTG.ORE_THRESHOLD:
		return -1
	var kind := _ore_type_noise.get_noise_3d(cx, cy, cz) * 0.5 + 0.5
	if kind < 0.4:
		return PTG.MAT_COAL
	if kind < 0.62:
		return PTG.MAT_IRON
	return PTG.MAT_COPPER


# --- Colonne de blocs ---------------------------------------------------------

## Données d'une colonne de blocs : hauteur en sous-voxels, biome, matériaux.
## `snow` indique la dalle de neige posée sur le permafrost de la toundra.
func column_data(bx: int, bz: int) -> Dictionary:
	var cx := float(bx * N + 1)
	var cz := float(bz * N + 1)
	var h := surface_voxels(cx, cz)
	var temperature := temperature_at(cx, cz, h)
	var humidity := humidity_at(cx, cz)
	var biome: int = PTG.biome_from(temperature, humidity)
	var hs := int(floor(h + 0.5))
	var snow := biome == PTG.BIOME_TUNDRA
	if snow:
		# Toundra : sol de permafrost arasé au bloc, puis une dalle de neige.
		hs = int(floor(float(hs) / N + 0.5)) * N
	return {
		"hs": hs,               # hauteur du sol, en sous-voxels
		"biome": biome,
		"snow": snow,           # dalle de neige d'un sous-voxel au-dessus
		"surface": PTG.MAT_PERMAFROST if snow else PTG.surface_material_of(biome),
	}


## Index du bloc le plus haut qui contient de la matière (hors neige).
static func top_block(hs: int) -> int:
	return int(floor(float(hs - 1) / N)) if hs > 0 else -1


# --- Génération ---------------------------------------------------------------

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	out_buffer.fill_f(AIR, VoxelBuffer.CHANNEL_SDF)
	if lod > 0:
		_generate_far(out_buffer, origin_in_voxels, lod)
		return
	_generate_near(out_buffer, origin_in_voxels)
	out_buffer.compress_uniform_channels()


## LOD 0 : le vrai modèle en blocs, avec les états du catalogue.
func _generate_near(out_buffer: VoxelBuffer, origin: Vector3i) -> void:
	var size := out_buffer.get_size()
	var bx0 := _block_of(origin.x)
	var bx1 := _block_of(origin.x + size.x - 1)
	var bz0 := _block_of(origin.z)
	var bz1 := _block_of(origin.z + size.z - 1)
	var by0 := _block_of(origin.y)
	var by1 := _block_of(origin.y + size.y - 1)

	# Colonnes de la zone, plus une bordure : les pentes regardent les voisins.
	var columns := {}
	for bx in range(bx0 - 1, bx1 + 2):
		for bz in range(bz0 - 1, bz1 + 2):
			columns[Vector2i(bx, bz)] = column_data(bx, bz)

	# Grottes de la zone, plus une bordure : les plafonds regardent les voisins.
	var caves := {}
	for bx in range(bx0 - 1, bx1 + 2):
		for bz in range(bz0 - 1, bz1 + 2):
			var col: Dictionary = columns[Vector2i(bx, bz)]
			for by in range(by0 - 1, by1 + 2):
				caves[Vector3i(bx, by, bz)] = cave_at(bx, by, bz, col["hs"])

	for bx in range(bx0, bx1 + 1):
		for bz in range(bz0, bz1 + 1):
			var col: Dictionary = columns[Vector2i(bx, bz)]
			for by in range(by0, by1 + 1):
				var state := _block_state(bx, by, bz, columns, caves)
				if state == Shapes.VIDE:
					continue
				var material := _block_material(bx, by, bz, col, caves)
				_write_block(out_buffer, origin, bx, by, bz, state, material)


## État du bloc : plein, dalle, pente de sol, pente de plafond ou vide.
func _block_state(bx: int, by: int, bz: int, columns: Dictionary, caves: Dictionary) -> int:
	var col: Dictionary = columns[Vector2i(bx, bz)]
	var hs: int = col["hs"]
	var top: int = top_block(hs)

	# Dalle de neige de la toundra, juste au-dessus du sol.
	if col["snow"] and by == int(hs / N):
		return Shapes.PLAT_BAS if not caves.get(Vector3i(bx, by, bz), false) else Shapes.VIDE
	if by > top:
		return Shapes.VIDE
	if caves.get(Vector3i(bx, by, bz), false):
		return Shapes.VIDE

	var state := Shapes.PLEIN
	if by == top:
		# Bloc de surface : dalle si le sol s'arrête à un sous-voxel près.
		var rem := hs - top * N
		if rem == 1:
			state = Shapes.PLAT_BAS
		# Pente si le voisin le plus bas est exactement un bloc plus bas.
		if state == Shapes.PLEIN:
			var lowest := 99
			var direction := -1
			for d in 4:
				var offset := Shapes.direction_offset(d)
				var other: Dictionary = columns.get(Vector2i(bx + offset.x, bz + offset.y), col)
				var other_top: int = top_block(other["hs"])
				if other_top < lowest:
					lowest = other_top
					direction = d
			if direction >= 0 and lowest == top - 1:
				state = Shapes.floor_slope(direction)
	elif caves.get(Vector3i(bx, by - 1, bz), false):
		# Plafond de grotte : on adoucit vers le côté creusé.
		for d in 4:
			var offset := Shapes.direction_offset(d)
			if caves.get(Vector3i(bx + offset.x, by, bz + offset.y), false):
				state = Shapes.ceiling_slope(d)
				break
	return state


## Matériau du bloc : biome en surface, terre, roche, minerai en profondeur.
func _block_material(bx: int, by: int, bz: int, col: Dictionary, caves: Dictionary) -> int:
	var hs: int = col["hs"]
	if col["snow"] and by == int(hs / N):
		return PTG.MAT_SNOW
	var center := by * N + 1
	var depth := float(hs - center)
	if depth <= PTG.TOP_LAYER / PTG.VOXEL_SIZE:
		return col["surface"]
	if depth <= PTG.SUB_DEPTH / PTG.VOXEL_SIZE:
		if col["surface"] == PTG.MAT_SAND:
			return PTG.MAT_SAND
		if col["surface"] == PTG.MAT_ROCK:
			return PTG.MAT_ROCK
		return PTG.MAT_DIRT
	var near_cave := false
	for d in 4:
		var offset := Shapes.direction_offset(d)
		if caves.get(Vector3i(bx + offset.x, by, bz + offset.y), false):
			near_cave = true
			break
	if not near_cave:
		near_cave = caves.get(Vector3i(bx, by - 1, bz), false) \
			or caves.get(Vector3i(bx, by + 1, bz), false)
	var ore := ore_at(bx, by, bz, depth, near_cave)
	return ore if ore >= 0 else PTG.MAT_ROCK


## Écrit les sous-voxels pleins d'un bloc, colonne par colonne.
func _write_block(out_buffer: VoxelBuffer, origin: Vector3i,
		bx: int, by: int, bz: int, state: int, material: int) -> void:
	var size := out_buffer.get_size()
	for lx in N:
		var vx := bx * N + lx - origin.x
		if vx < 0 or vx >= size.x:
			continue
		for lz in N:
			var vz := bz * N + lz - origin.z
			if vz < 0 or vz >= size.z:
				continue
			var span := Shapes.column_range(state, lx, lz)
			if span.y < span.x:
				continue
			var y0 := by * N + span.x - origin.y
			var y1 := by * N + span.y - origin.y
			y0 = maxi(y0, 0)
			y1 = mini(y1, size.y - 1)
			if y1 < y0:
				continue
			var lo := Vector3i(vx, y0, vz)
			var hi := Vector3i(vx + 1, y1 + 1, vz + 1)
			out_buffer.fill_area_f(SOLID, lo, hi, VoxelBuffer.CHANNEL_SDF)
			out_buffer.fill_area(material, lo, hi, VoxelBuffer.CHANNEL_INDICES)


## LOD lointains : silhouette simple. Le champ y est LISSE (et non binaire) :
## de loin, les blocs ne se voient pas, et un champ lisse évite les éclats de
## maillage aux raccords entre niveaux de détail.
func _generate_far(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var size := out_buffer.get_size()
	var step := float(1 << lod)
	for ix in size.x:
		var vx := float(origin.x + ix) * step
		for iz in size.z:
			var vz := float(origin.z + iz) * step
			var h := surface_voxels(vx, vz) / step          # en voxels de ce LOD
			var temperature := temperature_at(vx, vz, surface_voxels(vx, vz))
			var humidity := humidity_at(vx, vz)
			var biome: int = PTG.biome_from(temperature, humidity)
			var surface: int = PTG.surface_material_of(biome)
			var top := int(floor(h)) - origin.y
			if top < 0:
				continue
			# Plein bien en dessous de la surface.
			var solid_top := mini(top - 2, size.y - 1)
			if solid_top >= 0:
				out_buffer.fill_area_f(SOLID, Vector3i(ix, 0, iz),
					Vector3i(ix + 1, solid_top + 1, iz + 1), VoxelBuffer.CHANNEL_SDF)
			# Dégradé sur les deux voxels qui encadrent la surface.
			for y in range(maxi(top - 2, 0), mini(top + 2, size.y)):
				var d := clampf(float(origin.y + y) - h, -1.0, 1.0)
				out_buffer.set_voxel_f(d, ix, y, iz, VoxelBuffer.CHANNEL_SDF)
			var hi := Vector3i(ix + 1, mini(top + 1, size.y), iz + 1)
			if hi.y > 0:
				out_buffer.fill_area(PTG.MAT_ROCK, Vector3i(ix, 0, iz), hi,
					VoxelBuffer.CHANNEL_INDICES)
				var skin := maxi(top - maxi(int(PTG.SUB_DEPTH / PTG.VOXEL_SIZE / step), 1), 0)
				out_buffer.fill_area(surface, Vector3i(ix, skin, iz), hi,
					VoxelBuffer.CHANNEL_INDICES)


static func _block_of(voxel: int) -> int:
	return int(floor(float(voxel) / N))
