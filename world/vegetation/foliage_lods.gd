class_name FoliageLods
extends RefCounted
## Lighter copies of a plant mesh for distant instances (Voxel Tools mesh LOD,
## see VoxelInstanceLibraryMultiMeshItem.mesh_lod1..3).
##
## Godot already simplifies solid parts on its own: the OBJ importer builds LOD
## index buffers with meshoptimizer (generate_lods), and Godot picks them by
## distance, MultiMesh included. Those are kept here for solid surfaces.
##
## Foliage is the part Godot cannot simplify: leaves are separate flat cards,
## there is no edge to collapse, so its LODs stay at full detail. Here a far
## copy keeps one card out of N, each card enlarged by sqrt(N) around its
## centre so the crown keeps about the same coverage from afar.

## Copy of `mesh` where each foliage surface keeps one card out of
## `keep_one_in`. Materials are carried over.
static func build(mesh: Mesh, foliage_surfaces: PackedInt32Array, keep_one_in: int) -> ArrayMesh:
	var out := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if surface in foliage_surfaces:
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _thin_cards(arrays, keep_one_in))
		else:
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], _godot_lods(mesh, surface))
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(surface))
	return out


## Keeps one card out of `keep_one_in`, enlarged. A card is a group of
## triangles joined by shared vertex positions.
static func _thin_cards(arrays: Array, keep_one_in: int) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array
	if arrays[Mesh.ARRAY_INDEX] == null:
		indices = PackedInt32Array(range(vertices.size()))
	else:
		indices = arrays[Mesh.ARRAY_INDEX]

	# Union-find of vertices, by position (the importer may split a card's
	# vertices when their normals or UVs differ).
	var parent := PackedInt32Array(range(vertices.size()))
	var by_position := {}
	for i in vertices.size():
		var key := vertices[i].snappedf(0.0001)
		if by_position.has(key):
			_union(parent, i, by_position[key])
		else:
			by_position[key] = i
	for t in range(0, indices.size(), 3):
		_union(parent, indices[t], indices[t + 1])
		_union(parent, indices[t], indices[t + 2])

	# Number the cards in index order, keep one out of N.
	var card_of := {}           # root vertex -> card number
	var kept_triangles := PackedInt32Array()
	for t in range(0, indices.size(), 3):
		var root := _find(parent, indices[t])
		if not card_of.has(root):
			card_of[root] = card_of.size()
		if card_of[root] % keep_one_in == 0:
			kept_triangles.append_array([indices[t], indices[t + 1], indices[t + 2]])

	# Enlarge the kept cards around their centre.
	var sums := {}              # root -> [sum of positions, count]
	for i in kept_triangles:
		var root := _find(parent, i)
		var entry: Array = sums.get(root, [Vector3.ZERO, 0])
		sums[root] = [entry[0] + vertices[i], entry[1] + 1]
	var grow := sqrt(float(keep_one_in))
	var new_vertices := vertices.duplicate()
	var done := {}
	for i in kept_triangles:
		if done.has(i):
			continue
		done[i] = true
		var entry: Array = sums[_find(parent, i)]
		var centre: Vector3 = entry[0] / float(entry[1])
		new_vertices[i] = centre + (vertices[i] - centre) * grow

	var result := arrays.duplicate()
	result[Mesh.ARRAY_VERTEX] = new_vertices
	result[Mesh.ARRAY_INDEX] = kept_triangles
	return result


## The LOD index buffers Godot generated at import for this surface, in the
## form add_surface_from_arrays() takes: { edge length: indices }.
static func _godot_lods(mesh: Mesh, surface: int) -> Dictionary:
	var data: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
	# Godot stores indices on 16 bits when the surface has few enough vertices.
	var wide: bool = int(data.get("vertex_count", 0)) > 65536
	var lods := {}
	for lod in data.get("lods", []):
		var bytes: PackedByteArray = lod["index_data"]
		var lod_indices := PackedInt32Array()
		if wide:
			lod_indices = bytes.to_int32_array()
		else:
			lod_indices.resize(bytes.size() / 2)
			for i in lod_indices.size():
				lod_indices[i] = bytes.decode_u16(i * 2)
		lods[float(lod["edge_length"])] = lod_indices
	return lods


static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb
