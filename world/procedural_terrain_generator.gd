extends RefCounted
class_name ProceduralTerrainGenerator
## GAME-1203 — Générateur procédural v1 (Epic E12 · Terrain voxel)
##
##   - Relief : bruit 2D (x,z) -> hauteur -> SDF (sdf = Y - hauteur)
##   - Grottes SPAGHETTI enterrées :
##       * tunnels là où |bruit 3D| < CAVE_WIDTH
##       * CROÛTE de surface : on ne creuse que sous SURFACE_CRUST mètres de sol,
##         donc la surface reste pleine et marchable (pas de trous, pas de chute).
##     Retrait via SdfSmoothSubtract (soustraction booléenne SDF) -> aucun ajout
##     de matière, aucun îlot flottant.
##   - Graine reproductible ; get_height(x,z) pour le spawn.
##
## Convention SDF : négatif = matière, positif = air.

const SEED := 1337
const HEIGHT_AMPLITUDE := 55.0
const HEIGHT_FREQUENCY := 0.0016
const HEIGHT_OCTAVES := 4
const CAVE_FREQUENCY := 0.02
const CAVE_WIDTH := 0.06        # demi-largeur des tunnels
const CAVE_SMOOTHNESS := 2.0
const SURFACE_CRUST := 10.0     # épaisseur (m) de sol plein sous la surface (0 grotte)

static func _make_height_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = SEED
	n.frequency = HEIGHT_FREQUENCY
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = HEIGHT_OCTAVES
	return n

## Hauteur du sol au point (x,z), en mètres (surface pleine, hors grottes).
static func get_height(x: float, z: float) -> float:
	return _make_height_noise().get_noise_2d(x, z) * HEIGHT_AMPLITUDE

static func build() -> VoxelGeneratorGraph:
	var graph := VoxelGeneratorGraph.new()
	graph.clear()
	var g := graph.get_main_function()
	var T := VoxelGraphFunction

	var in_x := g.create_node(T.NODE_INPUT_X, Vector2(0, 0))
	var in_y := g.create_node(T.NODE_INPUT_Y, Vector2(0, 160))
	var in_z := g.create_node(T.NODE_INPUT_Z, Vector2(0, 320))

	# --- Relief : sdf_terrain = Y - hauteur ---
	var n_height := g.create_node(T.NODE_NOISE_2D, Vector2(240, 60))
	g.set_node_param(n_height, 0, _make_height_noise())
	g.add_connection(in_x, 0, n_height, 0)
	g.add_connection(in_z, 0, n_height, 1)

	var n_hamp := g.create_node(T.NODE_MULTIPLY, Vector2(460, 60))
	g.add_connection(n_height, 0, n_hamp, 0)
	g.set_node_default_input(n_hamp, 1, HEIGHT_AMPLITUDE)

	var n_terrain := g.create_node(T.NODE_SUBTRACT, Vector2(700, 120))
	g.add_connection(in_y, 0, n_terrain, 0)
	g.add_connection(n_hamp, 0, n_terrain, 1)

	# --- Tunnels : cave_b = |bruit3D| - width  (négatif dans le tunnel) ---
	var cave_noise := FastNoiseLite.new()
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cave_noise.seed = SEED + 1
	cave_noise.frequency = CAVE_FREQUENCY

	var n_cave := g.create_node(T.NODE_NOISE_3D, Vector2(240, 440))
	g.set_node_param(n_cave, 0, cave_noise)
	g.add_connection(in_x, 0, n_cave, 0)
	g.add_connection(in_y, 0, n_cave, 1)
	g.add_connection(in_z, 0, n_cave, 2)

	var n_abs := g.create_node(T.NODE_ABS, Vector2(460, 440))
	g.add_connection(n_cave, 0, n_abs, 0)

	var n_cave_b := g.create_node(T.NODE_SUBTRACT, Vector2(680, 440))
	g.add_connection(n_abs, 0, n_cave_b, 0)
	g.set_node_default_input(n_cave_b, 1, CAVE_WIDTH)

	# --- Croûte de surface : garde = terrain_sdf + SURFACE_CRUST ---
	# >= 0 près de la surface (bloque le creusement), < 0 en profondeur.
	var n_guard := g.create_node(T.NODE_ADD, Vector2(680, 260))
	g.add_connection(n_terrain, 0, n_guard, 0)
	g.set_node_default_input(n_guard, 1, SURFACE_CRUST)

	# On ne creuse que DANS le tunnel ET assez profond : gated = max(cave_b, garde)
	var n_gated := g.create_node(T.NODE_MAX, Vector2(900, 360))
	g.add_connection(n_cave_b, 0, n_gated, 0)
	g.add_connection(n_guard, 0, n_gated, 1)

	# Retrait booléen des grottes du terrain.
	var n_final := g.create_node(T.NODE_SDF_SMOOTH_SUBTRACT, Vector2(1120, 200))
	g.set_node_param(n_final, 0, CAVE_SMOOTHNESS)
	g.add_connection(n_terrain, 0, n_final, 0)
	g.add_connection(n_gated, 0, n_final, 1)

	var out := g.create_node(T.NODE_OUTPUT_SDF, Vector2(1360, 200))
	g.add_connection(n_final, 0, out, 0)

	var result := graph.compile()
	if typeof(result) == TYPE_DICTIONARY and result.has("success") and not result["success"]:
		push_error("[terrain] Échec compilation du graphe : %s (noeud %s)" % [
			result.get("message", ""), str(result.get("node_id", -1))])
	else:
		print("[terrain] Graphe procédural compilé avec succès.")
	return graph
