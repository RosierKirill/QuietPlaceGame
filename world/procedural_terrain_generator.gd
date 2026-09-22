extends RefCounted
class_name ProceduralTerrainGenerator
## Générateur procédural du monde (Epic E12 · Terrain voxel) — version 3.
##
## TROIS IDÉES CLÉS (notes Notion du 22/09/2026) :
##
## 1. GRILLE EN BLOCS. Un voxel vaut VOXEL_SIZE (0.25 unité), un bloc vaut
##    BLOCK_SIZE (0.75 unité = 3 voxels). Le relief est quantifié par paliers
##    d'un bloc : on obtient des terrasses franches, et le mailleur lisse ne
##    produit plus que des faces à 0°, 45° et 90° — l'aspect « bloc arrondi »
##    façon Terraria, sans changer de moteur de rendu.
##
## 2. GROTTES EN COULOIRS + SALLES. L'ancienne formule (une seule bande de
##    bruit 3D) creusait des NAPPES, d'où l'effet gruyère. Ici deux bandes de
##    bruit se croisent : leur intersection est un TUBE. Des salles plus larges
##    s'ouvrent de loin en loin sur ces couloirs, et les minerais apparaissent
##    en veines sur leurs parois.
##
## 3. BIOMES PAR TEMPÉRATURE ET HUMIDITÉ. Deux champs de bruit basse fréquence,
##    la température baissant avec l'altitude, donnent les 7 biomes de la note :
##    toundra, taïga, forêt tempérée, prairie tempérée, désert, forêt humide,
##    savane. Le biome choisit le matériau de surface ; le shader teinte la
##    végétation selon ce matériau.
##
## CONVENTIONS
##   - Le GRAPHE travaille en VOXELS (le terrain est mis à l'échelle VOXEL_SIZE).
##   - Les constantes ci-dessous sont en UNITÉS DE MONDE, converties au besoin.
##   - SDF : négatif = matière.
##   - get_height() renvoie une hauteur en unités de monde et DOIT rester
##     identique au graphe (elle sert au spawn).

## Graine du monde. Ce n'est PLUS une constante : chaque partie peut avoir la
## sienne (GAME-1219). Toujours la fixer AVANT d'appeler build().
static var world_seed: int = 1337

# --- Grille ---
const VOXEL_SIZE := 0.25             # taille d'un voxel, en unités de monde
const BLOCK_SIZE := 0.75             # un bloc = 3 voxels
const BLOCK_VOXELS := 3

# --- Relief (unités de monde) ---
const HEIGHT_FREQUENCY := 0.0016
const HEIGHT_OCTAVES := 4
const WARP_AMPLITUDE := 40.0
const BASE_AMPLITUDE := 30.0
const MOUNTAIN_AMPLITUDE := 190.0
const MASK_FREQUENCY := 0.0007
const RIDGE_FREQUENCY := 0.010
const RIDGE_AMPLITUDE := 55.0

# --- Grottes (unités de monde) ---
const CAVE_FREQUENCY := 0.018        # finesse des couloirs
const CAVE_WIDTH := 0.11            # demi-largeur des bandes croisées
const ROOM_FREQUENCY := 0.02        # taille des salles
const ROOM_THRESHOLD := 0.70         # plus haut = salles plus rares
const CAVE_SMOOTHNESS := 1.5
const SURFACE_CRUST := 8.0           # épaisseur de sol plein sous la surface

# --- Minerais ---
const ORE_FREQUENCY := 0.05          # taille des veines
const ORE_TYPE_FREQUENCY := 0.004    # zones à charbon / fer / cuivre
const ORE_WALL_BAND := 2.0           # distance max à la paroi (unités)
const ORE_THRESHOLD := 0.55          # plus haut = minerais plus rares
const ORE_MIN_DEPTH := 10.0

# --- Biomes ---
const TEMPERATURE_FREQUENCY := 0.0004
const HUMIDITY_FREQUENCY := 0.0005
const COLD_ALTITUDE_START := 60.0    # au-dessus, il commence à faire plus froid
const COLD_ALTITUDE_RANGE := 300.0   # altitude qui retire 1.0 de température

# --- Couches ---
const TOP_LAYER := 0.75              # épaisseur de la couche de surface
const SUB_DEPTH := 4.0               # profondeur où commence la roche
const ROCK_ALTITUDE := 110.0         # au-delà, sommets rocheux
const ROCK_ALTITUDE_JITTER := 25.0   # irrégularité de cette limite (unités)
const SLOPE_STEP := 1.0              # pas (unités) de la mesure de pente
const SLOPE_DIRT := 1.5              # pente (tangente) au-delà : plus d'herbe
const SLOPE_ROCK := 3.0              # pente au-delà : roche à nu

# --- Matériaux (indice écrit dans le canal INDICES) ---
const MAT_GRASS := 0                 # herbe tempérée
const MAT_GRASS_DRY := 1             # herbe sèche (savane, prairie sèche)
const MAT_GRASS_COLD := 2            # herbe froide (taïga)
const MAT_DIRT := 3
const MAT_ROCK := 4
const MAT_SAND := 5
const MAT_SNOW := 6
const MAT_COAL := 7
const MAT_IRON := 8
const MAT_COPPER := 9
const MATERIAL_NAMES := [
	"herbe", "herbe sèche", "herbe froide", "terre", "roche",
	"sable", "neige", "charbon", "fer", "cuivre",
]

# --- Biomes (valeurs de retour de get_biome) ---
const BIOME_TUNDRA := 0
const BIOME_TAIGA := 1
const BIOME_TEMPERATE_FOREST := 2
const BIOME_TEMPERATE_PRAIRIE := 3
const BIOME_DESERT := 4
const BIOME_RAINFOREST := 5
const BIOME_SAVANNA := 6
const BIOME_NAMES := [
	"toundra", "taïga", "forêt tempérée", "prairie tempérée",
	"désert", "forêt humide", "savane",
]

# Seuils de la pyramide température × humidité (note Notion).
const T_TUNDRA := 0.20
const T_TAIGA := 0.40
const T_HOT := 0.70
const H_DESERT := 0.25
const H_TEMPERATE_FOREST := 0.50
const H_RAINFOREST := 0.60


# --- Graine (GAME-1219) -------------------------------------------------------

## Fixe la graine du monde. À appeler avant build() et avant tout get_height().
static func set_world_seed(value: int) -> void:
	world_seed = value

## Tire une graine au hasard, la fixe, et la renvoie (pour l'afficher/sauver).
static func randomize_world_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	world_seed = int(rng.randi() % 1000000)
	return world_seed


# --- Bruits (partagés graphe / GDScript) --------------------------------------
# Les fréquences sont données en unités de monde puis converties en voxels.

static func _freq(world_frequency: float) -> float:
	return world_frequency * VOXEL_SIZE

static func _make_height_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed
	n.frequency = _freq(HEIGHT_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = HEIGHT_OCTAVES
	n.domain_warp_enabled = true
	n.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	n.domain_warp_amplitude = WARP_AMPLITUDE / VOXEL_SIZE
	n.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_NONE
	return n

static func _make_mask_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 2
	n.frequency = _freq(MASK_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

static func _make_ridge_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 3
	n.frequency = _freq(RIDGE_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	return n

static func _make_temperature_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 10
	n.frequency = _freq(TEMPERATURE_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

static func _make_humidity_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 11
	n.frequency = _freq(HUMIDITY_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

static func _make_cave_noise(index: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 20 + index
	n.frequency = _freq(CAVE_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 1
	return n

static func _make_room_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 30
	n.frequency = _freq(ROOM_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

static func _make_ore_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 40
	n.frequency = _freq(ORE_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

static func _make_ore_type_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 41
	n.frequency = _freq(ORE_TYPE_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

## Silhouette du terrain : X = bruit normalisé 0..1, Y = profil de hauteur.
static func _make_height_curve() -> Curve:
	var c := Curve.new()
	c.min_value = 0.0
	c.max_value = 1.0
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.45, 0.10))
	c.add_point(Vector2(0.65, 0.26))
	c.add_point(Vector2(0.82, 0.58))
	c.add_point(Vector2(1.0, 1.0))
	c.bake()
	return c

## Répartition montagne : X = masque brut 0..1, Y = proportion de montagne.
static func _make_mask_curve() -> Curve:
	var c := Curve.new()
	c.min_value = 0.0
	c.max_value = 1.0
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.30, 0.06))
	c.add_point(Vector2(0.45, 0.45))
	c.add_point(Vector2(0.60, 0.90))
	c.add_point(Vector2(1.0, 1.0))
	c.bake()
	return c


# --- Configuration du terrain (partagée par les scènes) -----------------------

## Mesher Transvoxel qui transmet l'indice de matériau au shader (CUSTOM1).
static func make_mesher() -> VoxelMesherTransvoxel:
	var m := VoxelMesherTransvoxel.new()
	m.texturing_mode = VoxelMesherTransvoxel.TEXTURES_SINGLE_S4
	m.textures_ignore_air_voxels = true
	return m

## Format des voxels : le mode « Single texture » exige un canal INDICES 8 bits.
static func make_format() -> VoxelFormat:
	var f := VoxelFormat.new()
	f.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_8_BIT)
	return f

## Applique l'échelle de la grille : 1 voxel = VOXEL_SIZE unité de monde.
static func apply_scale(terrain: VoxelLodTerrain) -> void:
	terrain.scale = Vector3.ONE * VOXEL_SIZE

## Monde -> voxels (coordonnées locales du terrain).
static func to_voxel(world_position: Vector3) -> Vector3:
	return world_position / VOXEL_SIZE

## Voxels -> monde.
static func to_world(voxel_position: Vector3) -> Vector3:
	return voxel_position * VOXEL_SIZE


# --- Calculs partagés (mêmes formules que le graphe) --------------------------

static func _noise01(n: FastNoiseLite, x: float, z: float) -> float:
	return clampf(n.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)

## Hauteur du sol au point (x,z) EN UNITÉS DE MONDE, quantifiée par blocs.
static func get_height(x: float, z: float) -> float:
	var vx := x / VOXEL_SIZE
	var vz := z / VOXEL_SIZE

	var profile := _make_height_curve().sample_baked(_noise01(_make_height_noise(), vx, vz))
	var mask := _make_mask_curve().sample_baked(_noise01(_make_mask_noise(), vx, vz))
	var amp := BASE_AMPLITUDE + mask * MOUNTAIN_AMPLITUDE

	var ridge := 1.0 - absf(_make_ridge_noise().get_noise_2d(vx, vz))
	var ridge_h := ridge * ridge * RIDGE_AMPLITUDE * mask

	return snappedf(profile * amp + ridge_h, BLOCK_SIZE)

## Température [0,1] au point (x,z) : bruit basse fréquence, corrigé par l'altitude.
static func get_temperature(x: float, z: float) -> float:
	var base := _noise01(_make_temperature_noise(), x / VOXEL_SIZE, z / VOXEL_SIZE)
	var altitude := maxf(get_height(x, z) - COLD_ALTITUDE_START, 0.0)
	return clampf(base - altitude / COLD_ALTITUDE_RANGE, 0.0, 1.0)

## Humidité [0,1] au point (x,z).
static func get_humidity(x: float, z: float) -> float:
	return _noise01(_make_humidity_noise(), x / VOXEL_SIZE, z / VOXEL_SIZE)

## Biome au point (x,z) — voir BIOME_NAMES. Sert aussi à la faune et à la flore.
static func get_biome(x: float, z: float) -> int:
	return biome_from(get_temperature(x, z), get_humidity(x, z))

## Biome à partir des deux taux (pyramide de la note Notion).
static func biome_from(temperature: float, humidity: float) -> int:
	if temperature < T_TUNDRA:
		return BIOME_TUNDRA
	if temperature < T_TAIGA:
		return BIOME_TAIGA
	if temperature < T_HOT:
		if humidity < H_DESERT:
			return BIOME_DESERT
		if humidity < H_TEMPERATE_FOREST:
			return BIOME_TEMPERATE_PRAIRIE
		return BIOME_TEMPERATE_FOREST
	if humidity < H_DESERT:
		return BIOME_DESERT
	if humidity < H_RAINFOREST:
		return BIOME_SAVANNA
	return BIOME_RAINFOREST

## Matériau de surface d'un biome.
static func surface_material_of(biome: int) -> int:
	match biome:
		BIOME_TUNDRA:
			return MAT_SNOW
		BIOME_TAIGA:
			return MAT_GRASS_COLD
		BIOME_DESERT:
			return MAT_SAND
		BIOME_SAVANNA, BIOME_TEMPERATE_PRAIRIE:
			return MAT_GRASS_DRY
		_:
			return MAT_GRASS


# --- Construction du graphe ---------------------------------------------------

static func _constant(g: VoxelGraphFunction, value: float, pos: Vector2) -> int:
	var n := g.create_node(VoxelGraphFunction.NODE_CONSTANT, pos)
	g.set_node_param(n, 0, value)
	return n

## Select : t < seuil -> a, sinon b.
static func _select(g: VoxelGraphFunction, a: int, b: int, t: int, threshold: float, pos: Vector2) -> int:
	var n := g.create_node(VoxelGraphFunction.NODE_SELECT, pos)
	g.add_connection(a, 0, n, 0)
	g.add_connection(b, 0, n, 1)
	g.add_connection(t, 0, n, 2)
	g.set_node_param(n, 0, threshold)
	return n

## Expression mathématique avec des entrées nommées.
static func _expr(g: VoxelGraphFunction, expression: String, inputs: Array, sources: Array, pos: Vector2) -> int:
	var n := g.create_node(VoxelGraphFunction.NODE_EXPRESSION, pos)
	g.set_node_param(n, 0, expression)
	g.set_expression_node_inputs(n, PackedStringArray(inputs))
	for i in sources.size():
		g.add_connection(int(sources[i]), 0, n, i)
	return n

static func _noise_2d(g: VoxelGraphFunction, noise: FastNoiseLite, x: int, z: int, pos: Vector2) -> int:
	var n := g.create_node(VoxelGraphFunction.NODE_NOISE_2D, pos)
	g.set_node_param(n, 0, noise)
	g.add_connection(x, 0, n, 0)
	g.add_connection(z, 0, n, 1)
	return n

static func _noise_3d(g: VoxelGraphFunction, noise: FastNoiseLite, x: int, y: int, z: int, pos: Vector2) -> int:
	var n := g.create_node(VoxelGraphFunction.NODE_NOISE_3D, pos)
	g.set_node_param(n, 0, noise)
	g.add_connection(x, 0, n, 0)
	g.add_connection(y, 0, n, 1)
	g.add_connection(z, 0, n, 2)
	return n

static func _curve(g: VoxelGraphFunction, curve: Curve, src: int, pos: Vector2) -> int:
	var n := g.create_node(VoxelGraphFunction.NODE_CURVE, pos)
	g.set_node_param(n, 0, curve)
	g.add_connection(src, 0, n, 0)
	return n

## Sous-graphe de relief CONTINU (avant quantification) à partir d'entrées X/Z.
## Instancié trois fois : au point, puis décalé en X et en Z, pour mesurer la pente.
static func _add_height_nodes(g: VoxelGraphFunction, x_src: int, z_src: int, oy: float) -> Dictionary:
	var amp_base := BASE_AMPLITUDE / VOXEL_SIZE
	var amp_mtn := MOUNTAIN_AMPLITUDE / VOXEL_SIZE
	var amp_ridge := RIDGE_AMPLITUDE / VOXEL_SIZE

	var n_base := _noise_2d(g, _make_height_noise(), x_src, z_src, Vector2(240, oy))
	var n_t := _expr(g, "n * 0.5 + 0.5", ["n"], [n_base], Vector2(440, oy))
	var n_profile := _curve(g, _make_height_curve(), n_t, Vector2(640, oy))

	var n_mask_raw := _noise_2d(g, _make_mask_noise(), x_src, z_src, Vector2(240, oy + 200))
	var n_mask_t := _expr(g, "n * 0.5 + 0.5", ["n"], [n_mask_raw], Vector2(440, oy + 200))
	var n_mask := _curve(g, _make_mask_curve(), n_mask_t, Vector2(640, oy + 200))

	var n_ridge_raw := _noise_2d(g, _make_ridge_noise(), x_src, z_src, Vector2(240, oy + 400))

	var n_height_c := _expr(g,
		"p * %f + p * m * %f + (1.0 - abs(r)) * (1.0 - abs(r)) * %f * m" % [
			amp_base, amp_mtn, amp_ridge],
		["p", "m", "r"], [n_profile, n_mask, n_ridge_raw], Vector2(900, oy + 100))

	return {"height": n_height_c, "base": n_base}

## Arrondit une coordonnée au bloc : la valeur reste constante sur les 3 voxels
## d'un bloc. C'est ce qui rend les grottes « en blocs » comme la surface.
static func _block_quantize(g: VoxelGraphFunction, src: int, pos: Vector2) -> int:
	var n := g.create_node(VoxelGraphFunction.NODE_STEPIFY, pos)
	var shifted := _expr(g, "v - 1.0", ["v"], [src], pos - Vector2(120, 0))
	g.add_connection(shifted, 0, n, 0)
	g.set_node_default_input(n, 1, float(BLOCK_VOXELS))
	return _expr(g, "v + 1.0", ["v"], [n], pos + Vector2(120, 0))

static func build() -> VoxelGeneratorGraph:
	var graph := VoxelGeneratorGraph.new()
	graph.clear()
	graph.texture_mode = VoxelGeneratorGraph.TEXTURE_MODE_SINGLE
	var g := graph.get_main_function()
	var T := VoxelGraphFunction

	var vs := VOXEL_SIZE                 # unité de monde par voxel
	var step := SLOPE_STEP / vs          # pas de mesure de pente, en voxels

	var in_x := g.create_node(T.NODE_INPUT_X, Vector2(0, 0))
	var in_y := g.create_node(T.NODE_INPUT_Y, Vector2(0, 200))
	var in_z := g.create_node(T.NODE_INPUT_Z, Vector2(0, 400))

	# --- 1. Relief, quantifié par blocs ---
	var h0 := _add_height_nodes(g, in_x, in_z, 0.0)
	var n_height_c: int = h0["height"]

	var n_height := g.create_node(T.NODE_STEPIFY, Vector2(1100, 100))
	g.add_connection(n_height_c, 0, n_height, 0)
	g.set_node_default_input(n_height, 1, float(BLOCK_VOXELS))

	var n_terrain := _expr(g, "y - h", ["y", "h"], [in_y, n_height], Vector2(1300, 100))

	# --- 2. Pente : hauteur mesurée un pas plus loin en X puis en Z ---
	var x_step := _expr(g, "x + %f" % step, ["x"], [in_x], Vector2(0, 2600))
	var z_step := _expr(g, "z + %f" % step, ["z"], [in_z], Vector2(0, 3400))
	var hx: int = _add_height_nodes(g, x_step, in_z, 2600.0)["height"]
	var hz: int = _add_height_nodes(g, in_x, z_step, 3400.0)["height"]
	var n_slope := _expr(g, "sqrt((a - h) * (a - h) + (b - h) * (b - h)) / %f" % step,
		["a", "b", "h"], [hx, hz, n_height_c], Vector2(1300, 3000))

	# --- 3. Grottes EN BLOCS : les bruits sont lus au centre du bloc, donc
	#        constants sur tout le bloc — même logique que les terrasses. ---
	var qx := _block_quantize(g, in_x, Vector2(240, 620))
	var qy := _block_quantize(g, in_y, Vector2(240, 660))
	var qz := _block_quantize(g, in_z, Vector2(240, 700))

	var n_cave_a := _noise_3d(g, _make_cave_noise(0), qx, qy, qz, Vector2(520, 700))
	var n_cave_b := _noise_3d(g, _make_cave_noise(1), qx, qy, qz, Vector2(520, 900))
	var n_room := _noise_3d(g, _make_room_noise(), qx, qy, qz, Vector2(520, 1100))

	# Les valeurs de bruit ne sont pas des distances : on les convertit en voxels
	# (un bruit de fréquence f varie d'environ 2.5 * f par voxel).
	var cave_scale := 1.0 / (2.5 * _freq(CAVE_FREQUENCY))
	var room_scale := 1.0 / (2.5 * _freq(ROOM_FREQUENCY))

	# Couloirs : négatif seulement là où LES DEUX bandes sont proches de zéro.
	var n_tunnels := _expr(g, "max(abs(a) - %f, abs(b) - %f) * %f" % [
			CAVE_WIDTH, CAVE_WIDTH, cave_scale],
		["a", "b"], [n_cave_a, n_cave_b], Vector2(760, 800))
	# Salles : négatif dans les bulles de bruit les plus fortes.
	var n_rooms := _expr(g, "(%f - r) * %f" % [ROOM_THRESHOLD, room_scale],
		["r"], [n_room], Vector2(760, 1100))
	var n_caves := _expr(g, "min(t, s)", ["t", "s"], [n_tunnels, n_rooms], Vector2(1000, 950))

	# Croûte : rien n'est creusé trop près de la surface.
	var n_guard := _expr(g, "d + %f" % (SURFACE_CRUST / vs), ["d"], [n_terrain], Vector2(1000, 700))
	var n_gated := _expr(g, "max(c, g)", ["c", "g"], [n_caves, n_guard], Vector2(1240, 800))

	# Soustraction franche (pas de lissage) : les parois restent à angle droit,
	# le mailleur se charge du biseau.
	var n_final := _expr(g, "max(t, 0.0 - c)", ["t", "c"], [n_terrain, n_gated], Vector2(1500, 300))

	var out_sdf := g.create_node(T.NODE_OUTPUT_SDF, Vector2(1750, 300))
	g.add_connection(n_final, 0, out_sdf, 0)

	# --- 4. Biomes : température (avec altitude) et humidité ---
	var n_temp_raw := _noise_2d(g, _make_temperature_noise(), in_x, in_z, Vector2(240, 1400))
	var n_hum_raw := _noise_2d(g, _make_humidity_noise(), in_x, in_z, Vector2(240, 1600))

	var n_temp := _expr(g,
		"clamp(t * 0.5 + 0.5 - max(h * %f - %f, 0.0) / %f, 0.0, 1.0)" % [
			vs, COLD_ALTITUDE_START, COLD_ALTITUDE_RANGE],
		["t", "h"], [n_temp_raw, n_height], Vector2(520, 1400))
	var n_hum := _expr(g, "h * 0.5 + 0.5", ["h"], [n_hum_raw], Vector2(520, 1600))

	# --- 5. Matériaux ---
	var c_grass := _constant(g, MAT_GRASS, Vector2(760, 1300))
	var c_grass_dry := _constant(g, MAT_GRASS_DRY, Vector2(760, 1350))
	var c_grass_cold := _constant(g, MAT_GRASS_COLD, Vector2(760, 1400))
	var c_dirt := _constant(g, MAT_DIRT, Vector2(760, 1450))
	var c_rock := _constant(g, MAT_ROCK, Vector2(760, 1500))
	var c_sand := _constant(g, MAT_SAND, Vector2(760, 1550))
	var c_snow := _constant(g, MAT_SNOW, Vector2(760, 1600))
	var c_coal := _constant(g, MAT_COAL, Vector2(760, 1650))
	var c_iron := _constant(g, MAT_IRON, Vector2(760, 1700))
	var c_copper := _constant(g, MAT_COPPER, Vector2(760, 1750))

	# Surface chaude : désert / savane / forêt humide.
	var hot_a := _select(g, c_sand, c_grass_dry, n_hum, H_DESERT, Vector2(1000, 1500))
	var hot := _select(g, hot_a, c_grass, n_hum, H_RAINFOREST, Vector2(1180, 1500))
	# Surface tempérée : désert / prairie / forêt.
	var temperate_a := _select(g, c_sand, c_grass_dry, n_hum, H_DESERT, Vector2(1000, 1650))
	var temperate := _select(g, temperate_a, c_grass, n_hum, H_TEMPERATE_FOREST, Vector2(1180, 1650))
	# Froid : toundra (neige) puis taïga (herbe froide).
	var cold := _select(g, c_snow, c_grass_cold, n_temp, T_TUNDRA, Vector2(1180, 1350))

	var biome_a := _select(g, cold, temperate, n_temp, T_TAIGA, Vector2(1360, 1500))
	var biome_mat := _select(g, biome_a, hot, n_temp, T_HOT, Vector2(1540, 1500))

	# La PENTE prime sur le biome : l'herbe ne tient pas sur un versant raide.
	# Sous l'herbe il y a de la terre, sous le sable ou la neige de la roche.
	var steep_mat := _select(g, c_dirt, biome_mat, biome_mat, 2.5, Vector2(1720, 1420))
	var slope_a := _select(g, biome_mat, steep_mat, n_slope, SLOPE_DIRT, Vector2(1900, 1500))
	var slope_b := _select(g, slope_a, c_rock, n_slope, SLOPE_ROCK, Vector2(2080, 1500))

	# Altitude : sommets rocheux, avec une limite irrégulière.
	var n_alt := _expr(g, "h * %f - b * %f" % [vs, ROCK_ALTITUDE_JITTER],
		["h", "b"], [n_height, h0["base"]], Vector2(1900, 1300))
	var surface := _select(g, slope_b, c_rock, n_alt, ROCK_ALTITUDE, Vector2(2260, 1500))

	# Sous-couche : terre sous l'herbe, roche sous la roche, sable sous le sable,
	# terre sous la neige.
	var sub_a := _select(g, c_dirt, c_rock, surface, 3.5, Vector2(2260, 1700))
	var sub_b := _select(g, sub_a, c_sand, surface, 4.5, Vector2(2440, 1700))
	var sub := _select(g, sub_b, c_dirt, surface, 5.5, Vector2(2620, 1700))

	# Profondeur sous la surface, quantifiée par blocs elle aussi.
	var qy_mat := _block_quantize(g, in_y, Vector2(1300, 1900))
	var n_depth := _expr(g, "h - y", ["h", "y"], [n_height, qy_mat], Vector2(1700, 1900))
	# Sur un versant, la couche de surface doit être mesurée PERPENDICULAIREMENT
	# à la pente, sinon la montagne montre sa sous-couche de terre partout.
	var n_depth_n := _expr(g, "d / sqrt(1.0 + s * s)", ["d", "s"],
		[n_depth, n_slope], Vector2(1900, 1900))

	# Minerais : proches d'une paroi de grotte, assez profonds, dans une veine.
	var n_wallness := _expr(g, "1.0 - min(abs(c) / %f, 1.0)" % (ORE_WALL_BAND / vs),
		["c"], [n_gated], Vector2(1700, 2050))
	var n_ore_noise := _noise_3d(g, _make_ore_noise(), qx, qy, qz, Vector2(760, 2050))
	var n_ore_score := _expr(g, "(n * 0.5 + 0.5) * w * min(d / %f, 1.0)" % (ORE_MIN_DEPTH / vs),
		["n", "w", "d"], [n_ore_noise, n_wallness, n_depth], Vector2(1940, 2050))
	var n_ore_type := _noise_3d(g, _make_ore_type_noise(), qx, qy, qz, Vector2(760, 2250))
	var n_ore_type01 := _expr(g, "n * 0.5 + 0.5", ["n"], [n_ore_type], Vector2(1000, 2250))

	var ore_a := _select(g, c_coal, c_iron, n_ore_type01, 0.4, Vector2(1400, 2250))
	var ore := _select(g, ore_a, c_copper, n_ore_type01, 0.62, Vector2(1580, 2250))
	var deep := _select(g, c_rock, ore, n_ore_score, ORE_THRESHOLD, Vector2(2260, 2150))

	# Empilement final : surface / sous-couche / profondeur.
	var layered_a := _select(g, sub, deep, n_depth_n, SUB_DEPTH / vs, Vector2(2800, 1900))
	var material := _select(g, surface, layered_a, n_depth_n, TOP_LAYER / vs, Vector2(2980, 1700))

	var out_tex := g.create_node(T.NODE_OUTPUT_SINGLE_TEXTURE, Vector2(3160, 1700))
	g.add_connection(material, 0, out_tex, 0)

	var result := graph.compile()
	if typeof(result) == TYPE_DICTIONARY and result.has("success") and not result["success"]:
		push_error("[terrain] Échec compilation du graphe : %s (noeud %s)" % [
			result.get("message", ""), str(result.get("node_id", -1))])
	else:
		print("[terrain] Graphe procédural v3 compilé (grille %.2f, blocs %.2f)." % [
			VOXEL_SIZE, BLOCK_SIZE])
	return graph
