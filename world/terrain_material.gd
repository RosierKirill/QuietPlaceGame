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

## Retourne un ShaderMaterial prêt à poser sur VoxelLodTerrain.material.
static func build() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("grass_tex", _load_tex(GRASS_TEX))
	material.set_shader_parameter("dirt_tex", _load_tex(DIRT_TEX))
	material.set_shader_parameter("rock_tex", _load_tex(ROCK_TEX))
	material.set_shader_parameter("sand_tex", _load_tex(SAND_TEX))
	material.set_shader_parameter("snow_tex", _load_tex(SNOW_TEX))
	return material

static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("[terrain] Texture introuvable : %s" % path)
	return null
