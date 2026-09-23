class_name WorldGenerator
extends VoxelGeneratorScript
## Générateur du monde (GAME-1223, GAME-1225, GAME-1226).
##
## Le monde est une grille de BLOCS de 0.75 unité, chacun découpé en
## 3 x 3 x 3 sous-voxels de 0.25. Deux échelles cohabitent :
##
##   - la SURFACE est un champ de hauteur lu au pas de 0.25 dans les trois
##     directions : une passe de moyenne lisse le champ (smoothed_height), puis
##     chaque sous-colonne prend sa hauteur par interpolation bilinéaire entre
##     les colonnes voisines (sub_top). C'est ce qui donne des pentes, des
##     diagonales et des coins sans casser la lecture « en blocs ».
##   - les GROTTES restent raisonnées au bloc : un bloc est creusé ou non, et
##     les plafonds prennent une pente du catalogue BlockShapes.
##
## Le catalogue BlockShapes reste la référence des formes pour la construction.
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

# Noyau binomial 1-2-1 de la passe de lissage (somme = 16).
const KERNEL := [1, 2, 1, 2, 4, 2, 1, 2, 1]

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
		"h": h,                 # hauteur continue, en sous-voxels
		"hs": hs,               # hauteur du sol quantifiée, en sous-voxels
		"biome": biome,
		"snow": snow,           # dalle de neige d'un sous-voxel au-dessus
		"surface": PTG.MAT_PERMAFROST if snow else PTG.surface_material_of(biome),
	}


## Passe de lissage du champ de hauteur (GAME-1226), transposition du
## « Smooth World » de Terraria : la hauteur d'une colonne est moyennée avec
## celle de ses 8 voisines par un noyau binomial 1-2-1. Le bruit à l'échelle du
## bloc disparaît, les longues pentes deviennent régulières, et les montagnes ne
## bougent pas (leurs détails sont bien plus grands que 0.75 unité).
## PTG.SMOOTH_STRENGTH règle le dosage : 0 = pas de lissage, 1 = moyenne pleine.
func smoothed_height(bx: int, bz: int, heights: Dictionary) -> float:
	var raw: float = heights[Vector2i(bx, bz)]
	if PTG.SMOOTH_STRENGTH <= 0.0:
		return raw
	var total := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var weight := float(KERNEL[(dz + 1) * 3 + dx + 1])
			total += weight * float(heights.get(Vector2i(bx + dx, bz + dz), raw))
	return lerpf(raw, total / 16.0, PTG.SMOOTH_STRENGTH)


## Hauteur continue au centre d'une colonne de blocs. Séparée de column_data :
## les colonnes de bordure ne servent qu'au lissage, inutile d'y calculer le
## biome et les matériaux.
func column_height(bx: int, bz: int) -> float:
	return surface_voxels(float(bx * N + 1), float(bz * N + 1))


## Même hauteur lissée, mais autonome (spawn, requêtes ponctuelles).
func smoothed_surface(bx: int, bz: int) -> float:
	var heights := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			heights[Vector2i(bx + dx, bz + dz)] = column_height(bx + dx, bz + dz)
	return smoothed_height(bx, bz, heights)


## Bruit blanc reproductible dans [0, 1], lié à la graine du monde.
static func _hash01(a: int, b: int) -> float:
	var h: int = a * 374761393 + b * 668265263 + PTG.world_seed * 2246822519
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


## Amplitude du tramage pour ce bloc : maximale là où le terrain est plat (les
## paliers y sont larges), nulle dès que la pente les rend invisibles.
func dither_amount(bx: int, bz: int, smooth: Dictionary) -> float:
	if PTG.SURFACE_DITHER <= 0.0:
		return 0.0
	var h0: float = smooth[Vector2i(bx, bz)]
	var gx: float = absf(float(smooth.get(Vector2i(bx + 1, bz), h0))
		- float(smooth.get(Vector2i(bx - 1, bz), h0))) * 0.5
	var gz: float = absf(float(smooth.get(Vector2i(bx, bz + 1), h0))
		- float(smooth.get(Vector2i(bx, bz - 1), h0))) * 0.5
	var slope := maxf(gx, gz) / float(N)
	return PTG.SURFACE_DITHER * clampf(1.0 - slope, 0.0, 1.0)


## Hauteur du sol, en sous-voxels, sous la SOUS-COLONNE (lx, lz) du bloc :
## interpolation bilinéaire entre les hauteurs lissées des colonnes voisines.
## C'est ce qui donne les diagonales et les coins — la surface se lit comme une
## courbe et non comme une marche par bloc.
func sub_top(bx: int, bz: int, lx: int, lz: int, smooth: Dictionary, snow: bool,
		dither: float = 0.0) -> int:
	var sx := 0
	var tx := 0.0
	if lx == 0:
		sx = -1
		tx = 1.0 / float(N)
	elif lx == N - 1:
		sx = 1
		tx = 1.0 / float(N)
	var sz := 0
	var tz := 0.0
	if lz == 0:
		sz = -1
		tz = 1.0 / float(N)
	elif lz == N - 1:
		sz = 1
		tz = 1.0 / float(N)
	var h00: float = smooth[Vector2i(bx, bz)]
	var h10: float = smooth.get(Vector2i(bx + sx, bz), h00)
	var h01: float = smooth.get(Vector2i(bx, bz + sz), h00)
	var h11: float = smooth.get(Vector2i(bx + sx, bz + sz), h00)
	var h := lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
	# Tramage : sans lui, une pente très douce produit de larges paliers plats
	# dont le bord dessine une courbe de niveau bien nette. Un demi-sous-voxel
	# de bruit blanc suffit à rendre ce bord irrégulier, donc invisible.
	if dither > 0.0:
		h += (_hash01(bx * N + lx, bz * N + lz) - 0.5) * dither
	var top := int(floor(h + 0.5))
	if snow:
		# Toundra : permafrost arasé au bloc, la neige se pose dessus.
		top = int(floor(float(top) / N + 0.5)) * N
	return top


## Colonne mise en cache : les LOD lointains relisent souvent la même.
func _cached_column(bx: int, bz: int, cache: Dictionary) -> Dictionary:
	var key := Vector2i(bx, bz)
	var col: Dictionary = cache.get(key, {})
	if col.is_empty():
		col = column_data(bx, bz)
		cache[key] = col
	return col


## Hauteur, en sous-voxels, où le NIVEAU 0 pose vraiment la surface : la dalle
## de neige de la toundra ajoute un sous-voxel, et le champ du niveau 0 étant
## binaire, la surface tombe à mi-chemin entre le dernier sous-voxel plein et le
## premier vide (d'où le -0.5). Les LOD lointains s'alignent dessus : sans ce
## décalage le raccord laisse une fente de ciel. On part de la hauteur CONTINUE
## et non de la quantifiée : de loin la quantification n'est que du bruit, et
## la passe de lissage ne déplace la surface que d'une fraction de sous-voxel.
static func center_surface(col: Dictionary) -> float:
	return float(col["h"]) - 0.5 + (1.0 if col["snow"] else 0.0)


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


## LOD 0 : relief LISSÉ, avec une hauteur de sol par SOUS-COLONNE.
##
## Deux règles empruntées à Terraria :
##   - une passe de moyenne sur le champ de hauteur (voir smoothed_height) ;
##   - la hauteur est ensuite lue au pas de 0.25 EN HORIZONTAL aussi : chacune
##     des 9 sous-colonnes d'un bloc a sa propre hauteur, interpolée entre les
##     colonnes voisines (voir sub_top). Les diagonales et les coins sortent
##     tout seuls, et le mailleur lisse biseaute le reste.
##
## Les grottes restent raisonnées au bloc : leurs plafonds gardent les pentes du
## catalogue.
func _generate_near(out_buffer: VoxelBuffer, origin: Vector3i) -> void:
	var size := out_buffer.get_size()
	var bx0 := _block_of(origin.x)
	var bx1 := _block_of(origin.x + size.x - 1)
	var bz0 := _block_of(origin.z)
	var bz1 := _block_of(origin.z + size.z - 1)
	var by0 := _block_of(origin.y)
	var by1 := _block_of(origin.y + size.y - 1)

	# Bordure de 2 blocs : la bilinéaire lit un voisin, le lissage un de plus.
	# Seule la hauteur y est calculée ; le biome ne sert qu'aux blocs écrits.
	var heights := {}
	for bx in range(bx0 - 2, bx1 + 3):
		for bz in range(bz0 - 2, bz1 + 3):
			heights[Vector2i(bx, bz)] = column_height(bx, bz)

	# Hauteurs lissées, bordure de 1 bloc (ce que lit la bilinéaire).
	var smooth := {}
	for bx in range(bx0 - 1, bx1 + 2):
		for bz in range(bz0 - 1, bz1 + 2):
			smooth[Vector2i(bx, bz)] = smoothed_height(bx, bz, heights)

	# Grottes de la zone, plus une bordure : les plafonds regardent les voisins.
	var caves := {}
	for bx in range(bx0 - 1, bx1 + 2):
		for bz in range(bz0 - 1, bz1 + 2):
			var surface: float = smooth[Vector2i(bx, bz)]
			for by in range(by0 - 1, by1 + 2):
				caves[Vector3i(bx, by, bz)] = cave_at(bx, by, bz, surface)

	var tops := PackedInt32Array()
	tops.resize(N * N)
	for bx in range(bx0, bx1 + 1):
		for bz in range(bz0, bz1 + 1):
			var col: Dictionary = column_data(bx, bz)
			var snow: bool = col["snow"]
			var dither := dither_amount(bx, bz, smooth)
			for lx in N:
				for lz in N:
					tops[lx * N + lz] = sub_top(bx, bz, lx, lz, smooth, snow, dither)
			var center_top: int = tops[N + 1]
			for by in range(by0, by1 + 1):
				if caves.get(Vector3i(bx, by, bz), false):
					continue
				if by * N > center_top + N:
					continue
				var ceiling := _ceiling_state(bx, by, bz, caves)
				var material := _block_material(bx, by, bz, col, caves, center_top)
				_write_column_block(out_buffer, origin, bx, by, bz, tops, ceiling,
					material, snow)


## Pente de plafond quand le bloc du dessous est creusé, sinon VIDE (= pas de
## traitement particulier).
func _ceiling_state(bx: int, by: int, bz: int, caves: Dictionary) -> int:
	if not caves.get(Vector3i(bx, by - 1, bz), false):
		return Shapes.VIDE
	for d in 4:
		var offset := Shapes.direction_offset(d)
		if caves.get(Vector3i(bx + offset.x, by, bz + offset.y), false):
			return Shapes.ceiling_slope(d)
	return Shapes.VIDE


## Remplit un bloc sous-colonne par sous-colonne, jusqu'à la hauteur de chacune.
func _write_column_block(out_buffer: VoxelBuffer, origin: Vector3i,
		bx: int, by: int, bz: int, tops: PackedInt32Array, ceiling: int,
		material: int, snow: bool) -> void:
	var size := out_buffer.get_size()
	var base := by * N
	for lx in N:
		var vx := bx * N + lx - origin.x
		if vx < 0 or vx >= size.x:
			continue
		for lz in N:
			var vz := bz * N + lz - origin.z
			if vz < 0 or vz >= size.z:
				continue
			var top: int = tops[lx * N + lz]
			var start := 0
			if ceiling != Shapes.VIDE:
				var span := Shapes.column_range(ceiling, lx, lz)
				if span.y < span.x:
					continue
				start = span.x
			var y0 := base + start - origin.y
			var y1 := mini(base + N - 1, top - 1) - origin.y
			y0 = maxi(y0, 0)
			y1 = mini(y1, size.y - 1)
			if y1 >= y0:
				var lo := Vector3i(vx, y0, vz)
				var hi := Vector3i(vx + 1, y1 + 1, vz + 1)
				out_buffer.fill_area_f(SOLID, lo, hi, VoxelBuffer.CHANNEL_SDF)
				out_buffer.fill_area(material, lo, hi, VoxelBuffer.CHANNEL_INDICES)
			# Toundra : la dalle de neige, un sous-voxel posé sur le permafrost.
			if not snow or top < base or top > base + N - 1:
				continue
			var ys := top - origin.y
			if ys >= 0 and ys < size.y:
				out_buffer.set_voxel_f(SOLID, vx, ys, vz, VoxelBuffer.CHANNEL_SDF)
				out_buffer.set_voxel(PTG.MAT_SNOW, vx, ys, vz, VoxelBuffer.CHANNEL_INDICES)


## Matériau du bloc : biome en surface, terre, roche, minerai en profondeur.
func _block_material(bx: int, by: int, bz: int, col: Dictionary, caves: Dictionary,
		hs: int) -> int:
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


## LOD lointains : MÊME surface que le niveau 0, mais échantillonnée.
##
## ATTENTION : `origin_in_voxels` est TOUJOURS donné en voxels du niveau 0, y
## compris pour les LOD lointains ; seul le PAS entre deux voxels du tampon vaut
## 2^lod. C'était la cause des éclats : en prenant l'origine pour des voxels du
## niveau courant, les niveaux lointains décrivaient un terrain pris 2^lod fois
## trop loin, sans aucun rapport avec le niveau fin.
##
## Les deux niveaux partent de la même hauteur (voir center_surface). Le champ
## lointain est dégradé et non binaire : de loin les blocs ne se voient pas, et
## un champ dégradé se raccorde proprement aux cellules de transition.
func _generate_far(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var size := out_buffer.get_size()
	var step := 1 << lod
	var stepf := float(step)
	var columns := {}
	var caves := {}
	var sub_depth := PTG.SUB_DEPTH / PTG.VOXEL_SIZE

	for ix in size.x:
		var wx := origin.x + ix * step
		var bx := _block_of(wx)
		for iz in size.z:
			var wz := origin.z + iz * step
			var bz := _block_of(wz)
			var col := _cached_column(bx, bz, columns)
			var hs := center_surface(col)

			# Indice, dans ce tampon, du dernier voxel sous la surface.
			var top := int(floor((hs - float(origin.y)) / stepf))
			if top < 0:
				continue
			var solid_top := mini(top - 2, size.y - 1)
			if solid_top >= 0:
				out_buffer.fill_area_f(SOLID, Vector3i(ix, 0, iz),
					Vector3i(ix + 1, solid_top + 1, iz + 1), VoxelBuffer.CHANNEL_SDF)
			for y in range(maxi(top - 2, 0), mini(top + 2, size.y)):
				var wy := float(origin.y + y * step)
				out_buffer.set_voxel_f(clampf((wy - hs) / stepf, -1.0, 1.0),
					ix, y, iz, VoxelBuffer.CHANNEL_SDF)

			# Matériaux : roche en profondeur, matière du biome en surface.
			var hi := Vector3i(ix + 1, mini(top + 1, size.y), iz + 1)
			if hi.y > 0:
				out_buffer.fill_area(PTG.MAT_ROCK, Vector3i(ix, 0, iz), hi,
					VoxelBuffer.CHANNEL_INDICES)
				var skin := maxi(top - maxi(int(sub_depth / stepf), 1), 0)
				out_buffer.fill_area(col["surface"], Vector3i(ix, skin, iz), hi,
					VoxelBuffer.CHANNEL_INDICES)
				if col["snow"] and top < size.y:
					out_buffer.fill_area(PTG.MAT_SNOW, Vector3i(ix, top, iz), hi,
						VoxelBuffer.CHANNEL_INDICES)

			# Grottes : seulement au premier niveau lointain, où les entrées à
			# flanc de colline se voient encore.
			if lod > 1:
				continue
			for y in range(0, mini(top, size.y)):
				var cave_key := Vector3i(bx, _block_of(origin.y + y * step), bz)
				var carved = caves.get(cave_key)
				if carved == null:
					carved = cave_at(cave_key.x, cave_key.y, cave_key.z, float(col["hs"]))
					caves[cave_key] = carved
				if carved:
					out_buffer.set_voxel_f(AIR, ix, y, iz, VoxelBuffer.CHANNEL_SDF)


static func _block_of(voxel: int) -> int:
	return int(floor(float(voxel) / N))
