class_name UnderwaterEffect
extends MeshInstance3D
## Underwater view: blur, water colour and fog while the camera is submerged.
##
## Put it under the camera. It asks the water surface for the level at the
## camera position every frame and shows the post-process quad only below it.

const UNDERWATER_SHADER := preload("res://world/shaders/underwater.gdshader")

var _camera: Camera3D
var _water          # WaterSurface
var _material: ShaderMaterial


func setup(camera: Camera3D, water) -> void:
	_camera = camera
	_water = water

	# Full-screen quad (see the shader): 2x2, never culled.
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_material = ShaderMaterial.new()
	_material.shader = UNDERWATER_SHADER
	# Drawn after the water surface and the other transparent objects.
	_material.render_priority = 10
	material_override = _material
	visible = false


func _process(_delta: float) -> void:
	if _camera == null or _water == null:
		return
	var eye := _camera.global_position
	var level: float = _water.surface_y(eye)
	var submerged := not is_nan(level) and eye.y < level
	visible = submerged
	if submerged:
		_material.set_shader_parameter("depth_below_surface", level - eye.y)
