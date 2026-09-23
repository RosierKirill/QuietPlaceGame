class_name WaterMaterial
extends RefCounted
## Fabrique du matériau de l'eau (GAME-1233). Même rôle que TerrainMaterial :
## un seul endroit qui connaît le shader et sa texture.

const WATER_SHADER := preload("res://world/shaders/water.gdshader")
const WATER_TEX := "res://assets/textures/terrain/water_albedo.jpg"


static func build() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	if ResourceLoader.exists(WATER_TEX):
		material.set_shader_parameter("water_tex", load(WATER_TEX))
	else:
		push_warning("[eau] Texture introuvable : %s" % WATER_TEX)
	# L'eau se dessine après le terrain opaque.
	material.render_priority = 1
	return material
