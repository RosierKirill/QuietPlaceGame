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
const MAT_PERMAFROST := 10
const MATERIAL_NAMES := [
	"herbe", "herbe sèche", "herbe froide", "terre", "roche",
	"sable", "neige", "charbon", "fer", "cuivre", "permafrost",
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
# Ils ne sont PAS constants : chaque graine tire les siens dans ces plages, donc
# un monde peut être très désertique et un autre très froid. Les plages
# ci-dessous sont les seules valeurs réglées à la main — à ajuster librement.
const RANGE_T_TUNDRA := Vector2(0.10, 0.28)      # fin de la toundra
const RANGE_T_TAIGA := Vector2(0.10, 0.26)       # largeur de la taïga
const RANGE_T_HOT := Vector2(0.20, 0.38)         # largeur des terres tempérées
const RANGE_H_DESERT := Vector2(0.14, 0.36)      # fin du désert
const RANGE_H_FOREST := Vector2(0.14, 0.30)      # largeur des prairies
const RANGE_H_RAIN := Vector2(0.05, 0.20)        # largeur de la savane

static var t_tundra := 0.20
static var t_taiga := 0.40
static var t_hot := 0.70
static var h_desert := 0.25
static var h_forest := 0.50
static var h_rain := 0.60


# --- Graine (GAME-1219) -------------------------------------------------------

## Fixe la graine du monde. À appeler avant build() et avant tout get_height().
static func set_world_seed(value: int) -> void:
	world_seed = value
	_roll_biome_thresholds()
	_refresh_query()

## Tire une graine au hasard, la fixe, et la renvoie (pour l'afficher/sauver).
static func randomize_world_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	world_seed = int(rng.randi() % 1000000)
	_roll_biome_thresholds()
	_refresh_query()
	return world_seed

## Les bruits du générateur de requête suivent la graine.
static func _refresh_query() -> void:
	if _query != null:
		_query.rebuild_noises()

## Tire les seuils de biome de cette graine : chaque monde a ses proportions.
static func _roll_biome_thresholds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 31 + 7
	t_tundra = rng.randf_range(RANGE_T_TUNDRA.x, RANGE_T_TUNDRA.y)
	t_taiga = t_tundra + rng.randf_range(RANGE_T_TAIGA.x, RANGE_T_TAIGA.y)
	t_hot = minf(t_taiga + rng.randf_range(RANGE_T_HOT.x, RANGE_T_HOT.y), 0.95)
	h_desert = rng.randf_range(RANGE_H_DESERT.x, RANGE_H_DESERT.y)
	h_forest = h_desert + rng.randf_range(RANGE_H_FOREST.x, RANGE_H_FOREST.y)
	h_rain = minf(h_forest + rng.randf_range(RANGE_H_RAIN.x, RANGE_H_RAIN.y), 0.95)

## Résumé lisible des seuils de ce monde (console, écran de chargement).
static func biome_thresholds_text() -> String:
	return "toundra<%.2f, taïga<%.2f, chaud>%.2f | désert<%.2f, prairie<%.2f, savane<%.2f" % [
		t_tundra, t_taiga, t_hot, h_desert, h_forest, h_rain]


# --- Bruits (partagés graphe / GDScript) --------------------------------------
# Les fréquences sont données en unités de monde puis converties en voxels.

static func _freq(world_frequency: float) -> float:
	return world_frequency * VOXEL_SIZE

static func make_height_noise() -> FastNoiseLite:
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

static func make_mask_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 2
	n.frequency = _freq(MASK_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

static func make_ridge_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 3
	n.frequency = _freq(RIDGE_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	return n

static func make_temperature_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 10
	n.frequency = _freq(TEMPERATURE_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

static func make_humidity_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 11
	n.frequency = _freq(HUMIDITY_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

static func make_cave_noise(index: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 20 + index
	n.frequency = _freq(CAVE_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 1
	return n

static func make_room_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 30
	n.frequency = _freq(ROOM_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

static func make_ore_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 40
	n.frequency = _freq(ORE_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

static func make_ore_type_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = world_seed + 41
	n.frequency = _freq(ORE_TYPE_FREQUENCY)
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

## Silhouette du terrain : X = bruit normalisé 0..1, Y = profil de hauteur.
static func make_height_curve() -> Curve:
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
static func make_mask_curve() -> Curve:
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


# --- Requêtes de terrain (mêmes formules que la génération) -------------------
#
# Le monde n'est plus décrit par un graphe voxel mais par WorldGenerator, qui
# raisonne en BLOCS. Pour que le spawn, la faune et les futurs outils lisent
# exactement le même monde, tout passe par une instance de requête partagée.

# Chargé paresseusement : WorldGenerator dépend déjà de ce fichier, un preload
# dans les deux sens serait circulaire.
static var _query = null

## Générateur de requête (ses bruits suivent la graine).
static func query():
	if _query == null:
		_query = load("res://world/world_generator.gd").new()
	return _query

## Générateur à poser sur le terrain.
static func build() -> VoxelGenerator:
	var generator = load("res://world/world_generator.gd").new()
	print("[terrain] Monde en blocs — graine %d, seuils : %s" % [
		world_seed, biome_thresholds_text()])
	return generator

## Hauteur du sol au point (x,z), EN UNITÉS DE MONDE, quantifiée comme la
## génération (blocs de BLOCK_SIZE, dalle de neige comprise).
static func get_height(x: float, z: float) -> float:
	var generator = query()
	var bx := int(floor(x / VOXEL_SIZE / BLOCK_VOXELS))
	var bz := int(floor(z / VOXEL_SIZE / BLOCK_VOXELS))
	var column: Dictionary = generator.column_data(bx, bz)
	var hs: int = column["hs"]
	if column["snow"]:
		hs += 1
	return float(hs) * VOXEL_SIZE

## Température [0,1] au point (x,z) : bruit basse fréquence, corrigé par l'altitude.
static func get_temperature(x: float, z: float) -> float:
	var generator = query()
	var vx := x / VOXEL_SIZE
	var vz := z / VOXEL_SIZE
	return generator.temperature_at(vx, vz, generator.surface_voxels(vx, vz))

## Humidité [0,1] au point (x,z).
static func get_humidity(x: float, z: float) -> float:
	return query().humidity_at(x / VOXEL_SIZE, z / VOXEL_SIZE)

## Biome au point (x,z) — voir BIOME_NAMES. Sert aussi à la faune et à la flore.
static func get_biome(x: float, z: float) -> int:
	return biome_from(get_temperature(x, z), get_humidity(x, z))

## Biome à partir des deux taux (pyramide de la note Notion).
static func biome_from(temperature: float, humidity: float) -> int:
	if temperature < t_tundra:
		return BIOME_TUNDRA
	if temperature < t_taiga:
		return BIOME_TAIGA
	if temperature < t_hot:
		if humidity < h_desert:
			return BIOME_DESERT
		if humidity < h_forest:
			return BIOME_TEMPERATE_PRAIRIE
		return BIOME_TEMPERATE_FOREST
	if humidity < h_desert:
		return BIOME_DESERT
	if humidity < h_rain:
		return BIOME_SAVANNA
	return BIOME_RAINFOREST

## Matériau de surface d'un biome.
static func surface_material_of(biome: int) -> int:
	match biome:
		BIOME_TUNDRA:
			# Toundra : permafrost, trop froid pour l'herbe ; la neige est une
			# dalle posée par-dessus par le générateur.
			return MAT_PERMAFROST
		BIOME_TAIGA:
			return MAT_GRASS_COLD
		BIOME_DESERT:
			return MAT_SAND
		BIOME_SAVANNA, BIOME_TEMPERATE_PRAIRIE:
			return MAT_GRASS_DRY
		_:
			return MAT_GRASS
