extends RefCounted
class_name ProceduralTerrainGenerator
## GAME-1203 + GAME-1209 — Générateur procédural (Epic E12 · Terrain voxel)
##
## Relief ART-DIRIGÉ (GAME-1209). Deux courbes de réglage :
##
##   - _make_height_curve() : profil vertical du terrain (bruit normalisé -> hauteur).
##     Aplatit les vallées, exagère les pics. C'est le réglage de la SILHOUETTE.
##   - _make_mask_curve()   : combien de terrain est montagneux (masque -> proportion
##     montagne). Monter cette courbe = MOINS de plaines et des FRONTS plus nets.
##
## Étapes :
##   1. COURBE de remap sur le bruit de base (silhouette).
##   2. MASQUE plaines/montagnes basse fréquence, re-façonné par _make_mask_curve()
##      pour des massifs francs (moins de plaine, transitions plus abruptes).
##   3. Crêtes RIDGED (1 - |bruit|)² dans les zones montagneuses.
##   4. DOMAIN WARP sur le bruit de base (formes organiques).
##
## IMPORTANT : le relief est calculé à l'IDENTIQUE dans build() (graphe) et dans
## get_height() (GDScript, pour le spawn). Toute modif de l'un va dans l'autre.
##
## NB : les Curve étant créées en code, les éditer dans l'inspecteur ne PERSISTE
## pas — ajuste les points ci-dessous. Convention SDF : négatif = matière.

const SEED := 1337

# Relief
const HEIGHT_FREQUENCY := 0.0016     # taille des grands reliefs
const HEIGHT_OCTAVES := 4
const WARP_AMPLITUDE := 40.0         # force du domain warp (formes organiques)
const BASE_AMPLITUDE := 30.0         # amplitude en plaine (gardée douce)
const MOUNTAIN_AMPLITUDE := 190.0    # amplitude en montagne (relevée -> pentes raides)
const MASK_FREQUENCY := 0.0007       # taille des régions plaine/montagne
const RIDGE_FREQUENCY := 0.010       # finesse des crêtes (relevée -> plus craggy)
const RIDGE_AMPLITUDE := 55.0        # hauteur des arêtes (relevée)

# Grottes
const CAVE_FREQUENCY := 0.02
const CAVE_WIDTH := 0.06             # demi-largeur des tunnels
const CAVE_SMOOTHNESS := 2.0
const SURFACE_CRUST := 10.0          # épaisseur (m) de sol plein sous la surface


# --- Ressources de bruit (partagées graphe / GDScript) ------------------------

static func _make_height_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = SEED
	n.frequency = HEIGHT_FREQUENCY
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = HEIGHT_OCTAVES
	n.domain_warp_enabled = true
	n.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	n.domain_warp_amplitude = WARP_AMPLITUDE
	n.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_NONE
	return n

static func _make_mask_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = SEED + 2
	n.frequency = MASK_FREQUENCY
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

static func _make_ridge_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = SEED + 3
	n.frequency = RIDGE_FREQUENCY
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	return n

## Silhouette du terrain : X = bruit normalisé 0..1, Y = profil de hauteur.
static func _make_height_curve() -> Curve:
	var c := Curve.new()
	c.min_value = 0.0
	c.max_value = 1.0
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.45, 0.10))   # large fond de vallée quasi plat
	c.add_point(Vector2(0.65, 0.26))   # contreforts vallonnés
	c.add_point(Vector2(0.82, 0.58))   # accélération
	c.add_point(Vector2(1.0, 1.0))     # pics
	c.bake()
	return c

## Répartition montagne : X = masque brut 0..1, Y = proportion de montagne.
## Montée franche -> moins de plaines et des fronts de montagne plus abrupts.
static func _make_mask_curve() -> Curve:
	var c := Curve.new()
	c.min_value = 0.0
	c.max_value = 1.0
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.30, 0.06))   # vraies basses terres (minoritaires)
	c.add_point(Vector2(0.45, 0.45))   # bascule rapide
	c.add_point(Vector2(0.60, 0.90))   # majoritairement montagneux au-dessus
	c.add_point(Vector2(1.0, 1.0))
	c.bake()
	return c


# --- Calcul de hauteur (partagé) ----------------------------------------------

## Hauteur du sol au point (x,z), en mètres. DOIT rester identique au graphe.
static func get_height(x: float, z: float) -> float:
	var height_noise := _make_height_noise()
	var mask_noise := _make_mask_noise()
	var ridge_noise := _make_ridge_noise()
	var height_curve := _make_height_curve()
	var mask_curve := _make_mask_curve()

	var base: float = height_noise.get_noise_2d(x, z)              # ~[-1,1]
	var t: float = clampf(base * 0.5 + 0.5, 0.0, 1.0)             # [0,1]
	var profile: float = height_curve.sample_baked(t)            # [0,1]

	var mask_raw: float = clampf(mask_noise.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var mask: float = mask_curve.sample_baked(mask_raw)          # [0,1] proportion montagne
	var amp: float = BASE_AMPLITUDE + mask * MOUNTAIN_AMPLITUDE

	var ridge: float = 1.0 - absf(ridge_noise.get_noise_2d(x, z))  # [0,1]
	var ridge_h: float = ridge * ridge * RIDGE_AMPLITUDE * mask

	return profile * amp + ridge_h


# --- Construction du graphe voxel ---------------------------------------------

static func build() -> VoxelGeneratorGraph:
	var graph := VoxelGeneratorGraph.new()
	graph.clear()
	var g := graph.get_main_function()
	var T := VoxelGraphFunction

	var in_x := g.create_node(T.NODE_INPUT_X, Vector2(0, 0))
	var in_y := g.create_node(T.NODE_INPUT_Y, Vector2(0, 200))
	var in_z := g.create_node(T.NODE_INPUT_Z, Vector2(0, 400))

	# 1) Bruit de base -> normalisé 0..1 -> courbe silhouette.
	var n_base := g.create_node(T.NODE_NOISE_2D, Vector2(240, 0))
	g.set_node_param(n_base, 0, _make_height_noise())
	g.add_connection(in_x, 0, n_base, 0)
	g.add_connection(in_z, 0, n_base, 1)

	var n_base_half := g.create_node(T.NODE_MULTIPLY, Vector2(440, 0))
	g.add_connection(n_base, 0, n_base_half, 0)
	g.set_node_default_input(n_base_half, 1, 0.5)

	var n_t := g.create_node(T.NODE_ADD, Vector2(620, 0))
	g.add_connection(n_base_half, 0, n_t, 0)
	g.set_node_default_input(n_t, 1, 0.5)

	var n_profile := g.create_node(T.NODE_CURVE, Vector2(800, 0))
	g.set_node_param(n_profile, 0, _make_height_curve())
	g.add_connection(n_t, 0, n_profile, 0)

	# 2) Masque plaines/montagnes -> courbe de masque -> amplitude locale.
	var n_mask := g.create_node(T.NODE_NOISE_2D, Vector2(240, 220))
	g.set_node_param(n_mask, 0, _make_mask_noise())
	g.add_connection(in_x, 0, n_mask, 0)
	g.add_connection(in_z, 0, n_mask, 1)

	var n_mask_half := g.create_node(T.NODE_MULTIPLY, Vector2(440, 220))
	g.add_connection(n_mask, 0, n_mask_half, 0)
	g.set_node_default_input(n_mask_half, 1, 0.5)

	var n_mask01 := g.create_node(T.NODE_ADD, Vector2(620, 220))
	g.add_connection(n_mask_half, 0, n_mask01, 0)
	g.set_node_default_input(n_mask01, 1, 0.5)

	var n_mask_c := g.create_node(T.NODE_CURVE, Vector2(800, 220))
	g.set_node_param(n_mask_c, 0, _make_mask_curve())
	g.add_connection(n_mask01, 0, n_mask_c, 0)

	var n_mtn := g.create_node(T.NODE_MULTIPLY, Vector2(980, 220))
	g.add_connection(n_mask_c, 0, n_mtn, 0)
	g.set_node_default_input(n_mtn, 1, MOUNTAIN_AMPLITUDE)

	var n_amp := g.create_node(T.NODE_ADD, Vector2(1160, 220))
	g.add_connection(n_mtn, 0, n_amp, 0)
	g.set_node_default_input(n_amp, 1, BASE_AMPLITUDE)

	var n_height_a := g.create_node(T.NODE_MULTIPLY, Vector2(1360, 60))
	g.add_connection(n_profile, 0, n_height_a, 0)
	g.add_connection(n_amp, 0, n_height_a, 1)

	# 3) Crêtes ridged : (1 - |bruit|)² * RIDGE_AMPLITUDE * masque façonné.
	var n_ridge := g.create_node(T.NODE_NOISE_2D, Vector2(240, 460))
	g.set_node_param(n_ridge, 0, _make_ridge_noise())
	g.add_connection(in_x, 0, n_ridge, 0)
	g.add_connection(in_z, 0, n_ridge, 1)

	var n_ridge_abs := g.create_node(T.NODE_ABS, Vector2(440, 460))
	g.add_connection(n_ridge, 0, n_ridge_abs, 0)

	var n_ridge_inv := g.create_node(T.NODE_SUBTRACT, Vector2(620, 460))
	g.set_node_default_input(n_ridge_inv, 0, 1.0)
	g.add_connection(n_ridge_abs, 0, n_ridge_inv, 1)

	var n_ridge_sq := g.create_node(T.NODE_MULTIPLY, Vector2(800, 460))
	g.add_connection(n_ridge_inv, 0, n_ridge_sq, 0)
	g.add_connection(n_ridge_inv, 0, n_ridge_sq, 1)

	var n_ridge_amp := g.create_node(T.NODE_MULTIPLY, Vector2(980, 460))
	g.add_connection(n_ridge_sq, 0, n_ridge_amp, 0)
	g.set_node_default_input(n_ridge_amp, 1, RIDGE_AMPLITUDE)

	var n_ridge_masked := g.create_node(T.NODE_MULTIPLY, Vector2(1160, 460))
	g.add_connection(n_ridge_amp, 0, n_ridge_masked, 0)
	g.add_connection(n_mask_c, 0, n_ridge_masked, 1)

	# height = height_a + ridge_masked
	var n_height := g.create_node(T.NODE_ADD, Vector2(1560, 200))
	g.add_connection(n_height_a, 0, n_height, 0)
	g.add_connection(n_ridge_masked, 0, n_height, 1)

	# sdf_terrain = Y - height
	var n_terrain := g.create_node(T.NODE_SUBTRACT, Vector2(1760, 200))
	g.add_connection(in_y, 0, n_terrain, 0)
	g.add_connection(n_height, 0, n_terrain, 1)

	# --- Grottes spaghetti (inchangé GAME-1203) ---
	var cave_noise := FastNoiseLite.new()
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cave_noise.seed = SEED + 1
	cave_noise.frequency = CAVE_FREQUENCY

	var n_cave := g.create_node(T.NODE_NOISE_3D, Vector2(240, 720))
	g.set_node_param(n_cave, 0, cave_noise)
	g.add_connection(in_x, 0, n_cave, 0)
	g.add_connection(in_y, 0, n_cave, 1)
	g.add_connection(in_z, 0, n_cave, 2)

	var n_abs := g.create_node(T.NODE_ABS, Vector2(460, 720))
	g.add_connection(n_cave, 0, n_abs, 0)

	var n_cave_b := g.create_node(T.NODE_SUBTRACT, Vector2(680, 720))
	g.add_connection(n_abs, 0, n_cave_b, 0)
	g.set_node_default_input(n_cave_b, 1, CAVE_WIDTH)

	var n_guard := g.create_node(T.NODE_ADD, Vector2(1960, 320))
	g.add_connection(n_terrain, 0, n_guard, 0)
	g.set_node_default_input(n_guard, 1, SURFACE_CRUST)

	var n_gated := g.create_node(T.NODE_MAX, Vector2(2160, 520))
	g.add_connection(n_cave_b, 0, n_gated, 0)
	g.add_connection(n_guard, 0, n_gated, 1)

	var n_final := g.create_node(T.NODE_SDF_SMOOTH_SUBTRACT, Vector2(2360, 260))
	g.set_node_param(n_final, 0, CAVE_SMOOTHNESS)
	g.add_connection(n_terrain, 0, n_final, 0)
	g.add_connection(n_gated, 0, n_final, 1)

	var out := g.create_node(T.NODE_OUTPUT_SDF, Vector2(2560, 260))
	g.add_connection(n_final, 0, out, 0)

	var result := graph.compile()
	if typeof(result) == TYPE_DICTIONARY and result.has("success") and not result["success"]:
		push_error("[terrain] Échec compilation du graphe : %s (noeud %s)" % [
			result.get("message", ""), str(result.get("node_id", -1))])
	else:
		print("[terrain] Graphe procédural compilé avec succès.")
	return graph
