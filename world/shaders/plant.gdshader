shader_type spatial;
// Both sides are drawn: grass and leaves are single planes.
render_mode cull_disabled;

// Plants and rocks placed by Vegetation (VoxelInstancer).
//
// Foliage is tinted like the grass of the ground it grows on: desaturated, then
// multiplied by the tint (same formula as tinted() in terrain_triplanar).
// Vegetation sets tint and desaturation from TerrainMaterial.GRASS_TINTS.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(1.0);
uniform vec3 tint : source_color = vec3(1.0);
uniform float desaturation = 0.0;
uniform float roughness_value = 0.9;

void fragment() {
	vec4 c = texture(albedo_tex, UV * uv_scale);
	float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(c.rgb, vec3(grey), desaturation) * tint;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = roughness_value;

	// Back side of a plane: light it as seen from that side.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
