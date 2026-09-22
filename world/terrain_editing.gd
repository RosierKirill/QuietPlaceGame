class_name TerrainEditing
extends RefCounted
## GAME-1212 — Édition du terrain qui respecte le matériau de chaque voxel.
##
## Point d'entrée unique pour creuser / poser : les scènes de test l'utilisent
## aujourd'hui, les futurs outils (pioche, pelle — Epic E15) s'y brancheront.
##
##   - dig()  : retire une boule de matière et renvoie le matériau du voxel visé
##              (ce que le joueur "ramasse").
##   - add()  : ajoute une boule de matière ET écrit son matériau, uniquement sur
##              les voxels qui étaient de l'air. La matière déjà en place garde
##              le sien : poser de la terre contre la roche ne repeint pas la roche.
##
## Le VoxelTool est laissé sur le canal SDF en sortie.

## Matériau (indice du canal INDICES) du voxel à cette position.
static func read_material(tool: VoxelTool, pos: Vector3i) -> int:
	tool.channel = VoxelBuffer.CHANNEL_INDICES
	var m := int(tool.get_voxel(pos))
	tool.channel = VoxelBuffer.CHANNEL_SDF
	return m

## Creuse une boule. Renvoie le matériau du voxel visé (avant de creuser).
static func dig(tool: VoxelTool, target: Vector3i, center: Vector3, radius: float) -> int:
	var material := read_material(tool, target)
	tool.channel = VoxelBuffer.CHANNEL_SDF
	tool.mode = VoxelTool.MODE_REMOVE
	tool.do_sphere(center, radius)
	return material

## Pose une boule de matière du matériau donné.
static func add(tool: VoxelTool, center: Vector3, radius: float, material: int) -> void:
	# 1) Repère les voxels encore vides dans la zone (marge d'1 voxel pour la
	#    surface lissée qui déborde un peu du rayon).
	var r := radius + 1.0
	var r2 := r * r
	var lo := Vector3i((center - Vector3.ONE * r).floor())
	var hi := Vector3i((center + Vector3.ONE * r).ceil())
	var was_air: Array[Vector3i] = []
	tool.channel = VoxelBuffer.CHANNEL_SDF
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var p := Vector3i(x, y, z)
				if Vector3(p).distance_squared_to(center) > r2:
					continue
				if tool.get_voxel_f(p) >= 0.0:
					was_air.append(p)

	# 2) Écrit d'abord le matériau sur ces voxels vides (invisible tant qu'ils
	#    sont de l'air) : pas d'image intermédiaire avec la mauvaise texture.
	tool.channel = VoxelBuffer.CHANNEL_INDICES
	for p in was_air:
		tool.set_voxel(p, material)

	# 3) Puis ajoute la matière (forme).
	tool.channel = VoxelBuffer.CHANNEL_SDF
	tool.mode = VoxelTool.MODE_ADD
	tool.do_sphere(center, radius)
