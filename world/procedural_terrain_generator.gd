extends RefCounted
class_name ProceduralTerrainGenerator
## GAME-1203 — Générateur procédural v1 (Epic E12 · Terrain voxel)
##
## VoxelGeneratorGraph construit par code.
##   - Relief : bruit 2D (x,z) -> hauteur -> SDF (sdf = Y - hauteur)
##   - Grottes "cheese" (méthode Minecraft) : on marque à creuser toute zone où
##     un bruit 3D dépasse un seuil, puis on RETIRE ce volume avec SdfSmoothSubtract
##     (soustraction booléenne SDF = max(terrain, -grotte)). Cette opération ne
##     peut JAMAIS changer de l'air en roche -> aucun îlot flottant ; elle ne fait
##     que creuser à l'intérieur du sol.
##   - Graine reproductible.
##
## Convention SDF : négatif = matière, positif = air.

const SEED := 1337
const HEIGHT_AMPLITUDE := 55.0
const HEIGHT_FREQUENCY := 0.0016
const HEIGHT_OCTAVES := 4
const CAVE_FREQUENCY := 0.02
const CAVE_THRESHOLD := 0.55   # ne creuse que là où le bruit 3D dépasse ce seuil
const CAVE_SMOOTHNESS := 2.0   # arrondi des parois de grotte

static func build() -> VoxelGeneratorGraph:
	var graph := VoxelGeneratorGraph.new()
	graph.clear()
	var g := graph.get_main_function()
	var T := VoxelGraphFunction

	var in_x := g.create_node(T.NODE_INPUT_X, Vector2(0, 0))
	var in_y := g.create_node(T.NODE_INPUT_Y, Vector2(0, 140))
	var in_z := g.create_node(T.NODE_INPUT_Z, Vector2(0, 280))

	# --- Relief : hauteur = noise2D(x, z) * amplitude ---
	var height_noise := FastNoiseLite.new()
	height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	height_noise.seed = SEED
	height_noise.frequency = HEIGHT_FREQUENCY
	height_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	height_noise.fractal_octaves = HEIGHT_OCTAVES

	var n_height := g.create_node(T.NODE_NOISE_2D, Vector2(240, 60))
	g.set_node_param(n_height, 0, height_noise)
	g.add_connection(in_x, 0, n_height, 0)
	g.add_connection(in_z, 0, n_height, 1)

	var n_height_amp := g.create_node(T.NODE_MULTIPLY, Vector2(460, 60))
	g.add_connection(n_height, 0, n_height_amp, 0)
	g.set_node_default_input(n_height_amp, 1, HEIGHT_AMPLITUDE)

	# sdf_terrain = Y - hauteur  (négatif sous la surface = matière)
	var n_terrain := g.create_node(T.NODE_SUBTRACT, Vector2(700, 140))
	g.add_connection(in_y, 0, n_terrain, 0)
	g.add_connection(n_height_amp, 0, n_terrain, 1)

	# --- Grottes "cheese" ---
	var cave_noise := FastNoiseLite.new()
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cave_noise.seed = SEED + 1
	cave_noise.frequency = CAVE_FREQUENCY

	var n_cave := g.create_node(T.NODE_NOISE_3D, Vector2(240, 360))
	g.set_node_param(n_cave, 0, cave_noise)
	g.add_connection(in_x, 0, n_cave, 0)
	g.add_connection(in_y, 0, n_cave, 1)
	g.add_connection(in_z, 0, n_cave, 2)

	# Forme de grotte (SDF) : cave_b = seuil - bruit3D
	#   -> négatif là où bruit3D > seuil = volume à creuser
	var n_cave_b := g.create_node(T.NODE_SUBTRACT, Vector2(460, 360))
	g.set_node_default_input(n_cave_b, 0, CAVE_THRESHOLD)
	g.add_connection(n_cave, 0, n_cave_b, 1)

	# Soustraction booléenne SDF : retire la grotte du terrain (jamais d'ajout).
	var n_final := g.create_node(T.NODE_SDF_SMOOTH_SUBTRACT, Vector2(900, 200))
	g.set_node_param(n_final, 0, CAVE_SMOOTHNESS)
	g.add_connection(n_terrain, 0, n_final, 0)
	g.add_connection(n_cave_b, 0, n_final, 1)

	var out := g.create_node(T.NODE_OUTPUT_SDF, Vector2(1140, 200))
	g.add_connection(n_final, 0, out, 0)

	var result := graph.compile()
	if typeof(result) == TYPE_DICTIONARY and result.has("success") and not result["success"]:
		push_error("[terrain] Échec compilation du graphe : %s (noeud %s)" % [
			result.get("message", ""), str(result.get("node_id", -1))])
	else:
		print("[terrain] Graphe procédural compilé avec succès.")
	return graph
