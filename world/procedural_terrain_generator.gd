extends RefCounted
class_name ProceduralTerrainGenerator
## GAME-1203 — Générateur procédural v1 (Epic E12 · Terrain voxel)
##
##   - Relief : bruit 2D (x,z) -> hauteur -> SDF (sdf = Y - hauteur)
##   - Grottes SPAGHETTI (façon Minecraft) : couloirs sinueux là où |bruit 3D| est
##     petit ( |bruit| < CAVE_WIDTH ). Retirés du terrain via SdfSmoothSubtract
##     (soustraction booléenne SDF) -> jamais d'ajout de matière, pas d'îlots.
##   - Graine reproductible.
##   - get_height(x,z) : hauteur analytique du sol (sert au spawn du joueur).
##
## Convention SDF : négatif = matière, positif = air.

const SEED := 1337
const HEIGHT_AMPLITUDE := 55.0
const HEIGHT_FREQUENCY := 0.0016
const HEIGHT_OCTAVES := 4
const CAVE_FREQUENCY := 0.02
const CAVE_WIDTH := 0.06        # demi-largeur des tunnels : |bruit| < width = creusé
const CAVE_SMOOTHNESS := 2.0

static func _make_height_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = SEED
	n.frequency = HEIGHT_FREQUENCY
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = HEIGHT_OCTAVES
	return n

## Hauteur du sol au point (x,z), en mètres. Ignore les grottes (surface pleine).
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

	# --- Relief ---
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

	# --- Grottes spaghetti : cave_b = |bruit3D| - width  (négatif dans le tunnel) ---
	var cave_noise := FastNoiseLite.new()
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cave_noise.seed = SEED + 1
	cave_noise.frequency = CAVE_FREQUENCY

	var n_cave := g.create_node(T.NODE_NOISE_3D, Vector2(240, 420))
	g.set_node_param(n_cave, 0, cave_noise)
	g.add_connection(in_x, 0, n_cave, 0)
	g.add_connection(in_y, 0, n_cave, 1)
	g.add_connection(in_z, 0, n_cave, 2)

	var n_abs := g.create_node(T.NODE_ABS, Vector2(460, 420))
	g.add_connection(n_cave, 0, n_abs, 0)

	var n_cave_b := g.create_node(T.NODE_SUBTRACT, Vector2(680, 420))
	g.add_connection(n_abs, 0, n_cave_b, 0)
	g.set_node_default_input(n_cave_b, 1, CAVE_WIDTH)

	var n_final := g.create_node(T.NODE_SDF_SMOOTH_SUBTRACT, Vector2(940, 240))
	g.set_node_param(n_final, 0, CAVE_SMOOTHNESS)
	g.add_connection(n_terrain, 0, n_final, 0)
	g.add_connection(n_cave_b, 0, n_final, 1)

	var out := g.create_node(T.NODE_OUTPUT_SDF, Vector2(1180, 240))
	g.add_connection(n_final, 0, out, 0)

	var result := graph.compile()
	if typeof(result) == TYPE_DICTIONARY and result.has("success") and not result["success"]:
		push_error("[terrain] Échec compilation du graphe : %s (noeud %s)" % [
			result.get("message", ""), str(result.get("node_id", -1))])
	else:
		print("[terrain] Graphe procédural compilé avec succès.")
	return graph
