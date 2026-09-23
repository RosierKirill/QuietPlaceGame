shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;

// Surface de l'eau (GAME-1233).
//
// La géométrie est plate : tout le relief vient du shader. Deux copies de la
// texture d'eau défilent en sens contraires et servent de normales ; la
// transparence suit la PROFONDEUR lue dans le tampon de profondeur, si bien
// qu'un haut-fond laisse voir le sable et qu'une fosse vire au bleu sombre.
//
// depth_draw_never : l'eau ne s'écrit pas dans le tampon de profondeur, deux
// nappes qui se recouvrent ne clignotent donc pas.

uniform sampler2D water_tex : source_color, filter_linear_mipmap, repeat_enable;
// Depuis Godot 4.4, le tampon de profondeur se déclare explicitement.
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

uniform vec3 shallow_color : source_color = vec3(0.24, 0.52, 0.55);
uniform vec3 deep_color : source_color = vec3(0.03, 0.12, 0.24);
// Profondeur (en unités) à laquelle la couleur profonde est atteinte.
uniform float depth_fade = 7.0;
// Transparence au bord et au large.
uniform float shallow_alpha = 0.45;
uniform float deep_alpha = 0.92;

uniform float wave_scale = 0.35;
uniform float wave_speed = 0.035;
uniform float wave_strength = 0.35;
uniform float water_roughness = 0.14;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_world_pos.xz * wave_scale;
	float t = TIME * wave_speed;
	// Deux couches qui dérivent en sens contraires : le motif ne se répète pas.
	vec3 a = texture(water_tex, uv + vec2(t, t * 0.6)).rgb;
	vec3 b = texture(water_tex, uv * -0.7 + vec2(-t * 0.8, t * 0.45)).rgb;
	float ripple = (a.r + b.r) * 0.5;

	// Normale perturbée à partir du gradient des deux couches.
	vec2 slope = vec2(a.r - b.r, a.g - b.g) * wave_strength;
	vec3 n = normalize(vec3(slope.x, 1.0, slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// Profondeur d'eau sous ce fragment, lue dans le tampon de profondeur.
	float raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw * 2.0 - 1.0, 1.0);
	view.xyz /= view.w;
	float floor_distance = -view.z;
	float surface_distance = -(VIEW_MATRIX * vec4(v_world_pos, 1.0)).z;
	float thickness = max(floor_distance - surface_distance, 0.0);
	float k = clamp(thickness / depth_fade, 0.0, 1.0);

	ALBEDO = mix(shallow_color, deep_color, k) * (0.85 + 0.3 * ripple);
	ALPHA = mix(shallow_alpha, deep_alpha, k);
	ROUGHNESS = water_roughness;
	METALLIC = 0.0;
	SPECULAR = 0.4;
}
