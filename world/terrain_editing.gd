class_name TerrainEditing
extends RefCounted
## Construction et minage, à la maille du BLOC (Epic E12 · Terrain voxel).
##
## Le monde est une grille de blocs de ProceduralTerrainGenerator.BLOCK_SIZE
## (0.75 unité = 3 voxels). On ne creuse plus des sphères : on casse ou on pose
## un bloc entier, aligné sur cette grille, comme dans Minecraft ou Terraria.
## Le mailleur lisse arrondit ensuite les arêtes, ce qui donne le biseau voulu.
##
## Tout se fait en COORDONNÉES VOXEL (l'espace local du terrain). Les scripts de
## scène convertissent avec ProceduralTerrainGenerator.to_voxel().
##
##   - break_block() : vide le bloc et renvoie le matériau ramassé.
##   - place_block() : remplit le bloc avec le matériau en main.
##
## Le VoxelTool est laissé sur le canal SDF en sortie.

const PTG := preload("res://world/procedural_terrain_generator.gd")

const SOLID := -1.0
const AIR := 1.0

## Coin (en voxels) du bloc qui contient cette position voxel.
static func block_origin(voxel_position: Vector3i) -> Vector3i:
	var n := PTG.BLOCK_VOXELS
	return Vector3i(
		int(floor(float(voxel_position.x) / n)) * n,
		int(floor(float(voxel_position.y) / n)) * n,
		int(floor(float(voxel_position.z) / n)) * n)

## Matériau (canal INDICES) au centre du bloc.
static func block_material(tool: VoxelTool, voxel_position: Vector3i) -> int:
	var origin := block_origin(voxel_position)
	var center := origin + Vector3i.ONE * (PTG.BLOCK_VOXELS / 2)
	tool.channel = VoxelBuffer.CHANNEL_INDICES
	var material := int(tool.get_voxel(center))
	tool.channel = VoxelBuffer.CHANNEL_SDF
	return material

## La zone est-elle chargée ? Hors de la zone chargée, les écritures seraient
## perdues en silence : mieux vaut le dire.
static func can_edit(tool: VoxelTool, voxel_position: Vector3i) -> bool:
	var origin := block_origin(voxel_position)
	var box := AABB(Vector3(origin) - Vector3.ONE, Vector3.ONE * (PTG.BLOCK_VOXELS + 2))
	if tool.is_area_editable(box):
		return true
	push_warning("[terrain] Zone pas encore chargée : édition ignorée en %s." % str(origin))
	return false

## Casse le bloc contenant cette position. Renvoie le matériau ramassé, ou -1
## si la zone n'est pas encore chargée.
static func break_block(tool: VoxelTool, voxel_position: Vector3i) -> int:
	if not can_edit(tool, voxel_position):
		return -1
	var material := block_material(tool, voxel_position)
	_fill(tool, block_origin(voxel_position), AIR, -1)
	return material

## Pose un bloc du matériau donné à cette position.
static func place_block(tool: VoxelTool, voxel_position: Vector3i, material: int) -> bool:
	if not can_edit(tool, voxel_position):
		return false
	_fill(tool, block_origin(voxel_position), SOLID, material)
	return true

## Le bloc est-il plein (matière) ?
static func is_block_solid(tool: VoxelTool, voxel_position: Vector3i) -> bool:
	var origin := block_origin(voxel_position)
	var center := origin + Vector3i.ONE * (PTG.BLOCK_VOXELS / 2)
	tool.channel = VoxelBuffer.CHANNEL_SDF
	return tool.get_voxel_f(center) < 0.0

## Écrit le SDF (et l'indice de matériau si >= 0) sur les voxels du bloc, et sur
## eux seuls : deux blocs voisins se soudent d'eux-mêmes (leurs sommets sont
## contigus), et casser un bloc ne grignote pas celui d'à côté.
static func _fill(tool: VoxelTool, origin: Vector3i, sdf: float, material: int) -> void:
	var n := PTG.BLOCK_VOXELS
	# MODE_SET : on écrit la valeur telle quelle (en MODE_ADD, poser de l'air
	# n'aurait aucun effet, l'outil ne gardant que la matière la plus proche).
	tool.mode = VoxelTool.MODE_SET
	if material >= 0:
		tool.channel = VoxelBuffer.CHANNEL_INDICES
		for x in range(origin.x, origin.x + n):
			for y in range(origin.y, origin.y + n):
				for z in range(origin.z, origin.z + n):
					tool.set_voxel(Vector3i(x, y, z), material)
	tool.channel = VoxelBuffer.CHANNEL_SDF
	for x in range(origin.x, origin.x + n):
		for y in range(origin.y, origin.y + n):
			for z in range(origin.z, origin.z + n):
				tool.set_voxel_f(Vector3i(x, y, z), sdf)
