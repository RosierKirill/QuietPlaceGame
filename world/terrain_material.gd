class_name TerrainMaterial
extends RefCounted
## GAME-1250 + GAME-1256 — Fabrique du matériau de terrain.
## Un seul endroit pour le shader triplanaire et ses textures, partagé par toutes
## les scènes de terrain. Réglages fins exposés dans le shader (inspecteur).

const TERRAIN_SHADER := preload("res://world/shaders/terrain_triplanar.gdshader")

const GRASS_TEX := "res://assets/textures/terrain/grass_albedo.jpg"
const DIRT_TEX := "res://assets/textures/terrain/dirt_albedo.jpg"
const ROCK_TEX := "res://assets/textures/terrain/rock_albedo.jpg"
const SAND_TEX := "res://assets/textures/terrain/sand_albedo.jpg"
const SNOW_TEX := "res://assets/textures/terrain/snow_albedo.jpg"

const PTG := preload("res://world/procedural_terrain_generator.gd")

## Tint of each grass material: [colour, desaturation]. The terrain shader and
## the plants (Vegetation) both read it, so foliage matches the ground.
const GRASS_TINTS := {
	PTG.MAT_GRASS: [Color(1.0, 1.0, 1.0), 0.0],
	PTG.MAT_GRASS_DRY: [Color(0.85, 0.78, 0.42), 0.75],
	PTG.MAT_GRASS_COLD: [Color(0.52, 0.66, 0.52), 0.75],
}

## Tint of the ore rocks, on the rock texture: [colour, desaturation].
const ORE_TINTS := {
	PTG.MAT_COAL: [Color(0.24, 0.24, 0.27), 0.75],
	PTG.MAT_IRON: [Color(0.85, 0.66, 0.50), 0.75],
	PTG.MAT_COPPER: [Color(0.42, 0.76, 0.62), 0.75],
}

## Tint of a material, or null if it has none.
static func tint_of(material: int):
	if GRASS_TINTS.has(material):
		return GRASS_TINTS[material]
	return ORE_TINTS.get(material)

## Retourne un ShaderMaterial prêt à poser sur VoxelLodTerrain.material.
static func build() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("grass_tex", _load_tex(GRASS_TEX))
	material.set_shader_parameter("dirt_tex", _load_tex(DIRT_TEX))
	material.set_shader_parameter("rock_tex", _load_tex(ROCK_TEX))
	material.set_shader_parameter("sand_tex", _load_tex(SAND_TEX))
	material.set_shader_parameter("snow_tex", _load_tex(SNOW_TEX))
	material.set_shader_parameter("tint_grass", GRASS_TINTS[PTG.MAT_GRASS][0])
	material.set_shader_parameter("tint_grass_dry", GRASS_TINTS[PTG.MAT_GRASS_DRY][0])
	material.set_shader_parameter("tint_grass_cold", GRASS_TINTS[PTG.MAT_GRASS_COLD][0])
	material.set_shader_parameter("tint_coal", ORE_TINTS[PTG.MAT_COAL][0])
	material.set_shader_parameter("tint_iron", ORE_TINTS[PTG.MAT_IRON][0])
	material.set_shader_parameter("tint_copper", ORE_TINTS[PTG.MAT_COPPER][0])
	return material

static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("[terrain] Texture introuvable : %s" % path)
	return null
