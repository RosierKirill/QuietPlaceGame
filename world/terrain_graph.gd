class_name TerrainGraph
extends RefCounted
## Builds the world generator as a VoxelGeneratorGraph.
##
## Why a graph: Voxel Tools compiles it and runs each node on whole buffers of
## voxels, in native code, on its worker threads. The previous GDScript
## generator looped voxel by voxel and could not keep up with the player, which
## left holes without collision around him.
##
## Every formula here is mirrored in TerrainShape (point queries). Change both
## together. Positions are in VOXELS.
##
## What the graph produces:
##   - SURFACE: rolling hills + separate rocky massifs. The SDF is the plain
##     height field "y - height" (in voxels), continuous: the Transvoxel mesher
##     turns it into a smooth surface. No quantization, no clamping: a
##     continuous SDF is what the smooth mesher is designed for, and the mesh,
##     its collider and the point queries all agree on the same surface.
##   - LAYERS: the top block (3 voxels) is grass (or the biome's surface), then
##     dirt, then stone. Steep slopes and high summits are bare rock.
##   - CAVES: crossing noise bands (tunnels) + rooms, kept under a solid crust
##     except at entrance spots, where tunnels widen to open cleanly.
##   - CAVE WALLS are always stone. Ores are not in the ground: they are ore
##     rocks placed in caves by Vegetation (PlantSpecies with a tint_material).

const PTG := preload("res://world/procedural_terrain_generator.gd")

var _g: VoxelGraphFunction
var _n: Dictionary
var _x: Dictionary
var _y: Dictionary
var _z: Dictionary
var _column := 0     # only used to lay nodes out in the graph editor


## Returns a compiled generator, or null if compilation failed.
static func build(noise_set: Dictionary) -> VoxelGeneratorGraph:
	var graph := VoxelGeneratorGraph.new()
	graph.clear()
	# Materials are written as one 8-bit index per voxel (see make_format()).
	graph.texture_mode = VoxelGeneratorGraph.TEXTURE_MODE_SINGLE
	# SDF clipping skips blocks that are fully underground or fully in the air,
	# but then it also skips their texture outputs: dug underground blocks would
	# come out with material 0 (grass). Correct materials matter more here, so
	# clipping is turned off with a threshold the SDF never reaches.
	graph.sdf_clip_threshold = 10000.0

	var builder := TerrainGraph.new()
	builder._g = graph.get_main_function()
	builder._n = noise_set
	builder._build()

	var result: Dictionary = graph.compile()
	if not result.get("success", false):
		push_error("[terrain] Graph compilation failed: %s (node %s)" % [
			result.get("message", "?"), str(result.get("node_id", -1))])
		return null
	return graph


## Filter graph for VoxelInstancer (plants and rocks): X, Y, Z in, one value
## out, positive where the species may grow. VoxelInstanceGenerator evaluates
## it at every candidate position (terrain local space = voxels) and drops the
## candidates where it is <= 0. See VoxelInstanceGenerator.noise_graph.
##
## Reuses the height and temperature formulas of the terrain, so plants follow
## exactly the same climate as the ground materials.
static func build_plant_filter(noise_set: Dictionary, species: PlantSpecies) -> VoxelGraphFunction:
	var builder := TerrainGraph.new()
	builder._g = VoxelGraphFunction.new()
	builder._n = noise_set
	builder._build_plant_filter(species)
	return builder._g


# --- Graph -------------------------------------------------------------------

func _build() -> void:
	_x = _ref(_g.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0)))
	_y = _ref(_g.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 200)))
	_z = _ref(_g.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(0, 400)))

	# --- Surface ---
	var height := _height(_x, _z)
	# Depth of this voxel under the surface, in voxels (negative in the air).
	var depth := _op(VoxelGraphFunction.NODE_SUBTRACT, [height, _y])
	# Height field SDF: negative under the surface.
	var surface_sdf := _op(VoxelGraphFunction.NODE_SUBTRACT, [_y, height])

	# --- Caves ---
	var cave := _cave_field()
	var cave_open := _cave_opening(cave, depth)

	# Air if the surface OR the cave says air (union of the two air volumes).
	# The cave field is scaled to about one unit per voxel so both terms of the
	# max() have the same slope and the cave walls come out as smooth as the
	# ground.
	var carved := _op(VoxelGraphFunction.NODE_MULTIPLY, [cave_open, PTG.CAVE_SDF_SCALE])
	var sdf := _op(VoxelGraphFunction.NODE_MAX, [surface_sdf, carved])
	_op(VoxelGraphFunction.NODE_OUTPUT_SDF, [sdf])

	# --- Materials ---
	_op(VoxelGraphFunction.NODE_OUTPUT_SINGLE_TEXTURE, [_material(height, depth, cave, cave_open)])


func _build_plant_filter(species: PlantSpecies) -> void:
	_x = _ref(_g.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0)))
	_y = _ref(_g.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 200)))
	_z = _ref(_g.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(0, 400)))

	var height := _height(_x, _z)
	var t := _temperature(height)
	var hu := _op(VoxelGraphFunction.NODE_CLAMP, [_unit_raw(_noise_2d("humidity", _x, _z)), 0.0, 1.0])

	# Inside the climate ranges: every term is positive.
	var terms: Array[Dictionary] = [
		_op(VoxelGraphFunction.NODE_SUBTRACT, [t, species.temperature_min]),
		_op(VoxelGraphFunction.NODE_SUBTRACT, [species.temperature_max, t]),
		_op(VoxelGraphFunction.NODE_SUBTRACT, [hu, species.humidity_min]),
		_op(VoxelGraphFunction.NODE_SUBTRACT, [species.humidity_max, hu]),
	]

	# Where: on the ground outside (and above the sea), or deep in a cave.
	# These terms are in voxels, scaled down to the size of the climate terms.
	var depth := _op(VoxelGraphFunction.NODE_SUBTRACT, [height, _y])
	if species.location == PlantSpecies.Location.SURFACE:
		terms.append(_op(VoxelGraphFunction.NODE_MULTIPLY, [
			_op(VoxelGraphFunction.NODE_SUBTRACT, [PTG.PLANT_SURFACE_BAND_V, depth]), PTG.PLANT_FILTER_VOXEL]))
		terms.append(_op(VoxelGraphFunction.NODE_MULTIPLY, [
			_op(VoxelGraphFunction.NODE_SUBTRACT, [_y, PTG.SEA_LEVEL / PTG.VOXEL_SIZE]), PTG.PLANT_FILTER_VOXEL]))
	else:
		terms.append(_op(VoxelGraphFunction.NODE_MULTIPLY, [
			_op(VoxelGraphFunction.NODE_SUBTRACT, [depth, species.min_depth / PTG.VOXEL_SIZE]),
			PTG.PLANT_FILTER_VOXEL]))

	var value: Dictionary = terms[0]
	for i in range(1, terms.size()):
		value = _op(VoxelGraphFunction.NODE_MIN, [value, terms[i]])
	_op(VoxelGraphFunction.NODE_OUTPUT_SDF, [value])


## Ground height in voxels at (x, z). Mirrored by TerrainShape.height_voxels().
func _height(x: Dictionary, z: Dictionary) -> Dictionary:
	var hills := _noise_2d("hills", x, z)
	var mask := _op(VoxelGraphFunction.NODE_SMOOTHSTEP, [_noise_2d("mask", x, z)],
		{"edge0": PTG.MASK_LOW, "edge1": PTG.MASK_HIGH})
	var m := _unit(_noise_2d("mountain", x, z))
	var mountains := _op(VoxelGraphFunction.NODE_MULTIPLY, [
		_op(VoxelGraphFunction.NODE_MULTIPLY, [_op(VoxelGraphFunction.NODE_MULTIPLY, [m, m]), mask]),
		PTG.MOUNTAIN_AMPLITUDE / PTG.VOXEL_SIZE])
	var plains := _op(VoxelGraphFunction.NODE_ADD, [
		_op(VoxelGraphFunction.NODE_MULTIPLY, [hills, PTG.HILLS_AMPLITUDE / PTG.VOXEL_SIZE]),
		PTG.BASE_HEIGHT / PTG.VOXEL_SIZE])
	return _op(VoxelGraphFunction.NODE_ADD, [plains, mountains])


## Raw cave field: positive inside a tunnel or a room.
func _cave_field() -> Dictionary:
	var a := _op(VoxelGraphFunction.NODE_ABS, [_noise_3d("cave_a")])
	var b := _op(VoxelGraphFunction.NODE_ABS, [_noise_3d("cave_b")])
	# Two bands |noise| < width cross along a TUBE.
	var tube := _op(VoxelGraphFunction.NODE_SUBTRACT, [PTG.CAVE_WIDTH, _op(VoxelGraphFunction.NODE_MAX, [a, b])])
	var room := _op(VoxelGraphFunction.NODE_SUBTRACT, [_noise_3d("room"), PTG.ROOM_THRESHOLD])
	return _op(VoxelGraphFunction.NODE_MAX, [tube, room])


## Cave field once the crust is applied: positive = carved.
##
## Under a full crust, caves are closed off progressively as they get closer to
## the surface. At entrance spots the crust is gone, and tunnels near the
## surface are widened a little: they cut a clean opening instead of leaving a
## thin roof or floating bits at the lip.
func _cave_opening(cave: Dictionary, depth: Dictionary) -> Dictionary:
	var entrance := _op(VoxelGraphFunction.NODE_SMOOTHSTEP, [_noise_2d("entrance", _x, _z)],
		{"edge0": PTG.ENTRANCE_LOW, "edge1": PTG.ENTRANCE_HIGH})
	var crust := _op(VoxelGraphFunction.NODE_MULTIPLY, [
		_op(VoxelGraphFunction.NODE_SUBTRACT, [1.0, entrance]), PTG.SURFACE_CRUST / PTG.VOXEL_SIZE])
	var missing := _op(VoxelGraphFunction.NODE_MAX, [_op(VoxelGraphFunction.NODE_SUBTRACT, [crust, depth]), 0.0])
	var taper := _op(VoxelGraphFunction.NODE_MULTIPLY, [missing, PTG.CRUST_TAPER])
	var near_surface := _op(VoxelGraphFunction.NODE_MAX, [
		_op(VoxelGraphFunction.NODE_SUBTRACT, [1.0, _op(VoxelGraphFunction.NODE_MULTIPLY, [depth, 1.0 / PTG.ENTRANCE_ROOF_V])]),
		0.0])
	var widen := _op(VoxelGraphFunction.NODE_MULTIPLY, [
		_op(VoxelGraphFunction.NODE_MULTIPLY, [entrance, near_surface]), PTG.ENTRANCE_WIDEN])
	return _op(VoxelGraphFunction.NODE_ADD, [_op(VoxelGraphFunction.NODE_SUBTRACT, [cave, taper]), widen])


## Material index of the voxel.
func _material(top: Dictionary, depth: Dictionary, cave: Dictionary,
		cave_open: Dictionary) -> Dictionary:
	var t := _temperature(top)
	var hu := _op(VoxelGraphFunction.NODE_CLAMP, [_unit_raw(_noise_2d("humidity", _x, _z)), 0.0, 1.0])

	# Surface block of each biome (the pyramid of the Notion note).
	var temperate := _select(PTG.MAT_SAND,
		_select(PTG.MAT_GRASS_DRY, PTG.MAT_GRASS, hu, PTG.h_forest), hu, PTG.h_desert)
	var hot := _select(PTG.MAT_SAND,
		_select(PTG.MAT_GRASS_DRY, PTG.MAT_GRASS, hu, PTG.h_rain), hu, PTG.h_desert)
	var warm := _select(temperate, hot, t, PTG.t_hot)
	var skin := _select(PTG.MAT_SNOW, _select(PTG.MAT_GRASS_COLD, warm, t, PTG.t_taiga),
		t, PTG.t_tundra)
	# What lies under it, down to the stone.
	var warm_sub := _select(PTG.MAT_SAND, PTG.MAT_DIRT, hu, PTG.h_desert)
	var sub := _select(PTG.MAT_PERMAFROST, _select(PTG.MAT_DIRT, warm_sub, t, PTG.t_taiga),
		t, PTG.t_tundra)

	# Bare rock on steep slopes and high summits.
	var rockness := _rockness(top)
	skin = _select(skin, PTG.MAT_ROCK, rockness, 0.0)
	sub = _select(sub, PTG.MAT_ROCK, rockness, 0.0)

	# Vertical rule: top block, then the sub layer, then stone.
	var upper := _select(skin, sub, depth, float(PTG.TOP_LAYER_V))
	var layered := _select(upper, PTG.MAT_ROCK, depth, PTG.SUB_DEPTH / PTG.VOXEL_SIZE)

	# Cave walls are stone: no grass or dirt inside caves. The top block is kept,
	# so the lip of an entrance stays grassy like the ground around it.
	var wall := _op(VoxelGraphFunction.NODE_MIN, [
		_op(VoxelGraphFunction.NODE_ADD, [cave_open, PTG.CAVE_WALL_BAND]),
		_op(VoxelGraphFunction.NODE_SUBTRACT, [depth, float(PTG.TOP_LAYER_V)])])
	return _select(layered, PTG.MAT_ROCK, wall, 0.0)


## Temperature [0, 1], colder with altitude. Mirrored by TerrainShape.
func _temperature(top: Dictionary) -> Dictionary:
	var base := _unit_raw(_noise_2d("temperature", _x, _z))
	var above := _op(VoxelGraphFunction.NODE_MAX, [
		_op(VoxelGraphFunction.NODE_SUBTRACT, [top, PTG.COLD_ALTITUDE_START / PTG.VOXEL_SIZE]), 0.0])
	var cold := _op(VoxelGraphFunction.NODE_MULTIPLY, [above, PTG.VOXEL_SIZE / PTG.COLD_ALTITUDE_RANGE])
	return _op(VoxelGraphFunction.NODE_CLAMP, [_op(VoxelGraphFunction.NODE_SUBTRACT, [base, cold]), 0.0, 1.0])


## Positive where the surface is bare rock (too steep, or too high).
func _rockness(top: Dictionary) -> Dictionary:
	var s := PTG.SLOPE_SAMPLE_V
	var h0 := _height(_x, _z)
	var hx := _height(_op(VoxelGraphFunction.NODE_ADD, [_x, s]), _z)
	var hz := _height(_x, _op(VoxelGraphFunction.NODE_ADD, [_z, s]))
	var gx := _op(VoxelGraphFunction.NODE_MULTIPLY, [_op(VoxelGraphFunction.NODE_SUBTRACT, [hx, h0]), 1.0 / s])
	var gz := _op(VoxelGraphFunction.NODE_MULTIPLY, [_op(VoxelGraphFunction.NODE_SUBTRACT, [hz, h0]), 1.0 / s])
	var slope2 := _op(VoxelGraphFunction.NODE_ADD, [_op(VoxelGraphFunction.NODE_MULTIPLY, [gx, gx]), _op(VoxelGraphFunction.NODE_MULTIPLY, [gz, gz])])
	var steep := _op(VoxelGraphFunction.NODE_SUBTRACT, [slope2, PTG.SLOPE_ROCK * PTG.SLOPE_ROCK])

	var limit := _op(VoxelGraphFunction.NODE_ADD, [
		_op(VoxelGraphFunction.NODE_MULTIPLY, [_noise_2d("rock", _x, _z), PTG.ROCK_ALTITUDE_JITTER / PTG.VOXEL_SIZE]),
		PTG.ROCK_ALTITUDE / PTG.VOXEL_SIZE])
	var high := _op(VoxelGraphFunction.NODE_SUBTRACT, [top, limit])
	return _op(VoxelGraphFunction.NODE_MAX, [steep, high])



# --- Helpers -------------------------------------------------------------------

## A reference to a node output, to tell it apart from a constant.
static func _ref(node_id: int) -> Dictionary:
	return {"id": node_id}


## Creates a node. Each input is either a node reference (connected) or a
## number (set as the input's default value). Inputs follow the documented
## order of the node (a, b / x, min, max / a, b, t ...).
func _op(type: int, inputs: Array, params: Dictionary = {}) -> Dictionary:
	_column += 1
	var id := _g.create_node(type, Vector2(200 * (_column % 40), 200 * int(_column / 40.0)))
	for i in inputs.size():
		var value = inputs[i]
		if value is Dictionary:
			_g.add_connection(value["id"], 0, id, i)
		else:
			_g.set_node_default_input(id, i, float(value))
	for param_name in params:
		_g.set_node_param_by_name(id, param_name, params[param_name])
	return _ref(id)


## Select: returns `a` if `t` < threshold, `b` otherwise.
func _select(a, b, t: Dictionary, threshold: float) -> Dictionary:
	return _op(VoxelGraphFunction.NODE_SELECT, [a, b, t], {"threshold": threshold})


func _noise_2d(key: String, x: Dictionary, z: Dictionary) -> Dictionary:
	return _op(VoxelGraphFunction.NODE_FAST_NOISE_2D, [x, z], {"noise": _n[key]})


func _noise_3d(key: String) -> Dictionary:
	return _op(VoxelGraphFunction.NODE_FAST_NOISE_3D, [_x, _y, _z], {"noise": _n[key]})


## Noise [-1, 1] -> [0, 1], not clamped.
func _unit_raw(value: Dictionary) -> Dictionary:
	return _op(VoxelGraphFunction.NODE_ADD, [_op(VoxelGraphFunction.NODE_MULTIPLY, [value, 0.5]), 0.5])


## Noise [-1, 1] -> [0, 1], clamped.
func _unit(value: Dictionary) -> Dictionary:
	return _op(VoxelGraphFunction.NODE_CLAMP, [_unit_raw(value), 0.0, 1.0])
