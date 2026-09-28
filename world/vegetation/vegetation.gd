class_name Vegetation
extends VoxelInstancer
## Plants and rocks on the voxel terrain (GAME-1222, GAME-2002, GAME-1401,
## GAME-1603).
##
## Built on VoxelInstancer (Voxel Tools): it must be a child of the terrain, it
## spawns instances on the terrain meshes as they stream in, and removes them
## when the ground under them is dug. Everything is a MultiMesh item, the fast
## kind the Voxel Tools docs recommend for large numbers of instances.
##
## Each PlantSpecies (world/vegetation/species/*.tres) becomes one library item
## per grass material it can grow on, so its foliage gets the tint of that
## grass (see TerrainMaterial.GRASS_TINTS); non-grass ground shares one
## untinted item. Where it grows is decided by:
##   - voxel_texture_filter: the ground material under the instance;
##   - noise_graph: the climate and the location (TerrainGraph.build_plant_filter);
##   - slope, density and LOD from the species.
##
## HARVEST: species with hits > 0 get a collider. harvest_hit() casts a ray,
## counts hits on the collider, and on the last one drops the loot and frees
## the collider, which also removes the instance (VoxelInstancerRigidBody).
## Instances are not persistent yet: without a terrain stream (GAME-1207), a
## harvested plant grows back when its area is unloaded and loaded again.
##
## Positions, sizes and densities inside the instancer are in terrain local
## space, i.e. voxels: world values are converted with VOXEL_SIZE.

const PTG := preload("res://world/procedural_terrain_generator.gd")
const PLANT_SHADER := preload("res://world/shaders/plant.gdshader")
const WORLD_ITEM_SCENE: PackedScene = preload("res://entities/items/world_item.tscn")

const SPECIES_DIRECTORY := "res://world/vegetation/species/"

## Physics layer of plant colliders (layer 5), used by the harvest ray.
const PLANT_LAYER := 16
## Physics layer of the terrain and of everything the player bumps into.
const SOLID_LAYER := 1
## Colliders only exist this close to the player, in units.
const COLLIDER_DISTANCE := 32.0
## Width of the soft edge of a climate range (see noise_falloff).
const CLIMATE_FALLOFF := 0.05
## Hits already taken by a plant, stored on its collider.
const HITS_META := &"hits_taken"

const GRASS_MATERIALS := [PTG.MAT_GRASS, PTG.MAT_GRASS_DRY, PTG.MAT_GRASS_COLD]

## Library item id -> PlantSpecies.
var _species_by_item: Dictionary = {}
## Where loot is dropped.
var _loot_parent: Node


## Builds the library from every species file. Call before adding the node
## under the terrain, after the world seed is set (the filters read its noises).
func setup(loot_parent: Node) -> void:
	_loot_parent = loot_parent
	# No fading: it needs one shader instance uniform per MultiMesh node, and
	# with one node per item and per terrain block the renderer runs out of
	# them ("Too many instances using shader instance variables").
	fading_enabled = false
	library = VoxelInstanceLibrary.new()
	var noises: Dictionary = PTG.noises()
	for species in _load_species():
		_add_species(species, noises)
	print("[vegetation] %d espèces, %d éléments de bibliothèque." % [
		_count_species(), _species_by_item.size()])


## Hits the plant aimed at between `from` and `to` (world positions).
## Returns true if a plant was hit, so the caller does not also dig the ground.
func harvest_hit(from: Vector3, to: Vector3, exclude: Array[RID]) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, PLANT_LAYER | SOLID_LAYER)
	query.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var body := hit.collider as VoxelInstancerRigidBody
	if body == null:
		return false
	var species: PlantSpecies = _species_by_item.get(body.get_library_item_id())
	if species == null or species.hits <= 0:
		return false

	var taken := int(body.get_meta(HITS_META, 0)) + 1
	if taken < species.hits:
		body.set_meta(HITS_META, taken)
		return true
	_drop_loot(species, body.global_position)
	# Freeing the collider also removes the instance (VoxelInstancerRigidBody).
	body.queue_free()
	return true


# --- Library -----------------------------------------------------------------

func _load_species() -> Array[PlantSpecies]:
	var result: Array[PlantSpecies] = []
	var directory := DirAccess.open(SPECIES_DIRECTORY)
	if directory == null:
		push_warning("[vegetation] Dossier introuvable : %s" % SPECIES_DIRECTORY)
		return result
	for file_name in directory.get_files():
		# Exports rename .tres files to .remap: the resource path stays .tres.
		var clean_name := file_name.trim_suffix(".remap")
		if not clean_name.ends_with(".tres"):
			continue
		var species := load(SPECIES_DIRECTORY + clean_name) as PlantSpecies
		if species != null:
			result.append(species)
	return result


func _count_species() -> int:
	var ids := {}
	for species in _species_by_item.values():
		ids[species.id] = true
	return ids.size()


func _add_species(species: PlantSpecies, noises: Dictionary) -> void:
	if species.mesh == null or species.ground_materials.is_empty():
		push_warning("[vegetation] Espèce incomplète : %s" % species.id)
		return
	var filter := TerrainGraph.build_plant_filter(noises, species)

	# One item per grass material (tinted), one for the rest (untinted).
	var others := PackedInt32Array()
	for material in species.ground_materials:
		if material in GRASS_MATERIALS:
			_add_item(species, filter, PackedInt32Array([material]), material)
		else:
			others.append(material)
	if not others.is_empty():
		_add_item(species, filter, others, -1)


func _add_item(species: PlantSpecies, filter: VoxelGraphFunction,
		ground: PackedInt32Array, grass_material: int) -> void:
	var item := VoxelInstanceLibraryMultiMeshItem.new()
	item.name = "%s_%d" % [species.id, grass_material]
	item.lod_index = species.lod_index
	item.mesh = _build_mesh(species, grass_material)
	# Far copies with fewer leaf cards (see FoliageLods). Only for plants seen
	# from afar: close-range ones (grass) are never far enough to need it.
	if not species.foliage_surfaces.is_empty() and species.lod_index > 0:
		item.mesh_lod1 = FoliageLods.build(item.mesh, species.foliage_surfaces, 2)
		item.mesh_lod2 = FoliageLods.build(item.mesh, species.foliage_surfaces, 4)
		item.mesh_lod3 = FoliageLods.build(item.mesh, species.foliage_surfaces, 8)
	item.generator = _build_generator(species, filter, ground)
	if species.hits > 0:
		_add_collider(item, species)
	var id := _species_by_item.size() + 1
	library.add_item(id, item)
	_species_by_item[id] = species


func _build_generator(species: PlantSpecies, filter: VoxelGraphFunction,
		ground: PackedInt32Array) -> VoxelInstanceGenerator:
	var voxel := PTG.VOXEL_SIZE
	var gen := VoxelInstanceGenerator.new()
	# Random triangles. EMIT_FROM_FACES walks the triangles in mesh order and
	# drops its instances where an area counter overflows, which lines grass up
	# in visible rows on the regular Transvoxel grid.
	gen.emit_mode = VoxelInstanceGenerator.EMIT_FROM_FACES_FAST
	# In this mode density = instances per triangle. On flat ground a
	# Transvoxel triangle covers half a voxel at LOD 0, and 4 times more area
	# at each LOD above.
	var triangle_area := voxel * voxel * 0.5 * pow(4.0, species.lod_index)
	gen.density = species.density * triangle_area
	gen.min_scale = species.min_scale / voxel
	gen.max_scale = species.max_scale / voxel
	gen.random_rotation = true
	gen.vertical_alignment = 1.0 if species.upright else 0.0
	gen.offset_along_normal = -species.sink / voxel
	gen.max_slope_degrees = species.max_slope_degrees
	gen.voxel_texture_filter_enabled = true
	gen.voxel_texture_filter_array = ground
	gen.noise_dimension = VoxelInstanceGenerator.DIMENSION_3D
	gen.noise_falloff = CLIMATE_FALLOFF
	# Compiled when assigned: the graph must be complete at this point.
	gen.noise_graph = filter
	# Far LODs are placed on coarse meshes: snap them to the real ground.
	gen.snap_to_generator_sdf_enabled = species.lod_index > 0
	return gen


func _add_collider(item: VoxelInstanceLibraryMultiMeshItem, species: PlantSpecies) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = species.collider_radius
	shape.height = species.collider_height
	# Standing on the ground: the cylinder's centre is half its height up.
	var offset := Transform3D(Basis(), Vector3(0.0, species.collider_height * 0.5, 0.0))
	item.collision_shapes = [shape, offset]
	item.collision_layer = PLANT_LAYER | (SOLID_LAYER if species.blocks_movement else 0)
	item.collision_mask = 0
	item.collision_distance = COLLIDER_DISTANCE / PTG.VOXEL_SIZE


## Copy of the species mesh with one material per surface.
func _build_mesh(species: PlantSpecies, grass_material: int) -> Mesh:
	var mesh := species.mesh.duplicate() as Mesh
	for surface in mesh.get_surface_count():
		var material := ShaderMaterial.new()
		material.shader = PLANT_SHADER
		if surface < species.textures.size():
			material.set_shader_parameter("albedo_tex", species.textures[surface])
		if surface < species.uv_scales.size():
			material.set_shader_parameter("uv_scale", species.uv_scales[surface])
		# Foliage takes the tint of the grass under it, solid parts the tint of
		# their own material (ore rocks).
		var tint = null
		if surface in species.foliage_surfaces:
			if grass_material >= 0:
				tint = TerrainMaterial.tint_of(grass_material)
		elif species.tint_material >= 0:
			tint = TerrainMaterial.tint_of(species.tint_material)
		if tint != null:
			material.set_shader_parameter("tint", tint[0])
			material.set_shader_parameter("desaturation", tint[1])
		mesh.surface_set_material(surface, material)
	return mesh


# --- Loot ----------------------------------------------------------------------

func _drop_loot(species: PlantSpecies, origin: Vector3) -> void:
	_drop_item(species.loot, randi_range(species.loot_min, species.loot_max), origin)


func _drop_item(item: Item, quantity: int, origin: Vector3) -> void:
	if item == null or quantity <= 0 or _loot_parent == null:
		return
	var drop := WORLD_ITEM_SCENE.instantiate() as WorldItem
	drop.item = item
	drop.quantity = quantity
	_loot_parent.add_child(drop)
	var angle := randf() * TAU
	drop.global_position = origin + Vector3(cos(angle), 0.0, sin(angle)) * 0.4 + Vector3.UP * 0.3
