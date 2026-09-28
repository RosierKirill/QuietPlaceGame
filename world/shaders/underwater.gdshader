shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, cull_disabled;

// Underwater view: full-screen post-process, drawn only while the camera is
// under the water surface (UnderwaterEffect toggles it).
//
// Technique from the Godot docs ("Advanced post-processing"): a 2x2 QuadMesh
// under the camera, whose vertices are written straight to clip space, reads
// the screen and the depth buffer:
//   - the scene is read from a blurred mip level of the screen texture;
//   - it fades into the water colour with the distance to each pixel;
//   - the water colour darkens with the depth under the surface.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

uniform vec3 water_color : source_color = vec3(0.05, 0.24, 0.32);
// Light kept from the scene seen through the water.
uniform vec3 absorption : source_color = vec3(0.55, 0.80, 0.90);
// Fog density, per unit of distance.
uniform float fog_density = 0.12;
// Mip level of the screen read: higher = blurrier.
uniform float blur = 1.5;
// Darkening per unit of depth under the surface.
uniform float depth_darkening = 0.06;
// Set by UnderwaterEffect: depth of the camera under the surface, in units.
uniform float depth_below_surface = 0.0;

void vertex() {
	// Godot 4.3+ uses a reversed-Z depth buffer: 1.0 is the near plane.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).x;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float distance_to_pixel = length(view.xyz);

	vec3 scene = textureLod(screen_texture, SCREEN_UV, blur).rgb * absorption;
	float fog = 1.0 - exp(-distance_to_pixel * fog_density);
	vec3 deep = water_color * exp(-depth_below_surface * depth_darkening);
	ALBEDO = mix(scene, deep, fog);
}
