extends RefCounted
class_name ProceduralTerrainGenerator
## GAME-1203 — Générateur procédural v1 (Epic E12 · Terrain voxel)
##
## Construit PAR CODE un VoxelGeneratorGraph (Voxel Tools / godot_voxel).
## Recette reproduite de la doc open-source de Zylann :
##   - Relief : bruit 2D (x,z) -> hauteur, converti en SDF (sdf = Y - hauteur)
##   - Grottes : bruit 3D soustrait de la matière ("map inversée"), BRIDÉ sous la
##     surface pour garder un terrain de surface propre (les entrées de grottes
##     visibles viendront dans la tâche dédiée "Grottes dans le générateur")
##   - Graine reproductible (SEED)
##
## Convention SDF : négatif = matière, positif = air.

const SEED := 1337
const HEIGHT_AMPLITUDE := 60.0     # hauteur max du relief (m)
const HEIGHT_FREQUENCY := 0.0016   # + petit = montagnes/plaines plus larges
const HEIGHT_OCTAVES := 5
const CAVE_STRENGTH := 22.0        # ampleur du creusement des grottes
const CAVE_FREQUENCY := 0.02       # + grand = cavités plus petites/nombreuses
const CAVE_DEPTH_SLOPE := 0.15     # vitesse d'apparition des grottes sous la surface

static func build() -> VoxelGeneratorGraph:
	var graph := VoxelGeneratorGraph.new()
	graph.clear()
	var g := graph.get_main_function()
	var T := VoxelGraphFunction

	# --- Entrées de coordonnées ---
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

	# --- Grottes : bruit 3D ---
	var cave_noise := FastNoiseLite.new()
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cave_noise.seed = SEED + 1
	cave_noise.frequency = CAVE_FREQUENCY

	var n_cave := g.create_node(T.NODE_NOISE_3D, Vector2(240, 360))
	g.set_node_param(n_cave, 0, cave_noise)
	g.add_connection(in_x, 0, n_cave, 0)
	g.add_connection(in_y, 0, n_cave, 1)
	g.add_connection(in_z, 0, n_cave, 2)

	var n_cave_amp := g.create_node(T.NODE_MULTIPLY, Vector2(460, 360))
	g.add_connection(n_cave, 0, n_cave_amp, 0)
	g.set_node_default_input(n_cave_amp, 1, CAVE_STRENGTH)

	# Bride de profondeur : gate = clamp(-terrain_sdf * pente, 0..1)
	# -> 0 en surface (pas de grottes qui trouent le sol), 1 en profondeur.
	var n_depth := g.create_node(T.NODE_MULTIPLY, Vector2(940, 260))
	g.add_connection(n_terrain, 0, n_depth, 0)
	g.set_node_default_input(n_depth, 1, -CAVE_DEPTH_SLOPE)

	var n_gate := g.create_node(T.NODE_CLAMP, Vector2(1140, 260))
	g.add_connection(n_depth, 0, n_gate, 0)
	g.set_node_default_input(n_gate, 1, 0.0)
	g.set_node_default_input(n_gate, 2, 1.0)

	var n_cave_gated := g.create_node(T.NODE_MULTIPLY, Vector2(1140, 380))
	g.add_connection(n_cave_amp, 0, n_cave_gated, 0)
	g.add_connection(n_gate, 0, n_cave_gated, 1)

	# sdf_final = sdf_terrain - grottes_bridées
	var n_final := g.create_node(T.NODE_SUBTRACT, Vector2(1360, 200))
	g.add_connection(n_terrain, 0, n_final, 0)
	g.add_connection(n_cave_gated, 0, n_final, 1)

	var out := g.create_node(T.NODE_OUTPUT_SDF, Vector2(1560, 200))
	g.add_connection(n_final, 0, out, 0)

	var result := graph.compile()
	if typeof(result) == TYPE_DICTIONARY and result.has("success") and not result["success"]:
		push_error("[terrain] Échec compilation du graphe : %s (noeud %s)" % [
			result.get("message", ""), str(result.get("node_id", -1))])
	else:
		print("[terrain] Graphe procédural compilé avec succès.")
	return graph
