shader_type spatial;
render_mode cull_back;

// GAME-1250 + GAME-1256 + GAME-1212 — Terrain triplanaire TEXTURÉ PAR VOXEL.
// Les mailles Transvoxel n'ont pas d'UV : on projette les textures en triplanaire
// depuis la position monde.
//
// Matériau par voxel (GAME-1212) : le mesher (mode "Single texture") fournit
// dans CUSTOM1 les 4 indices de matériau du triangle (x, 4 x 8 bits) et leurs
// poids (y, 4 x 8 bits). Indices : 0 = herbe, 1 = terre, 2 = roche.
// Règle géométrique conservée EN PLUS : un bloc d'herbe montre l'herbe sur le
// dessus et la terre sur les flancs (comme un bloc Minecraft).
// Secours : si le maillage ne porte aucun poids, on retombe sur l'ancien
// choix par pente / altitude.

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;

// Taille des textures en mètres (plus petit = motif plus grand).
uniform float texture_scale = 0.15;

// Bloc d'herbe : herbe au-dessus, terre sur les flancs (n.y, 1 = plat).
uniform float grass_side_low = 0.55;
uniform float grass_side_high = 0.80;

// Secours géométrique (maillage sans matériau).
uniform float rock_to_dirt_low = 0.55;
uniform float rock_to_dirt_high = 0.72;
uniform float dirt_to_grass_low = 0.80;
uniform float dirt_to_grass_high = 0.92;
uniform float height_rock_start = 120.0;
uniform float height_rock_end = 170.0;

uniform float terrain_roughness = 0.95;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
// Indices identiques sur tout le triangle : pas d'interpolation.
varying flat vec4 v_indices;
varying vec4 v_weights;

// Décode un float (bits bruts) en 4 entiers 8 bits.
vec4 decode_8bit_vec4(float v) {
	uint i = floatBitsToUint(v);
	return vec4(
		float(i & 0xffu),
		float((i >> 8u) & 0xffu),
		float((i >> 16u) & 0xffu),
		float((i >> 24u) & 0xffu));
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_indices = decode_8bit_vec4(CUSTOM1.x);
	v_weights = decode_8bit_vec4(CUSTOM1.y) / 255.0;
}

// Échantillonnage triplanaire d'une texture : 3 plans mélangés par la normale.
vec3 triplanar(sampler2D tex, vec3 pos, vec3 n) {
	vec3 w = abs(n);
	w = w / max(w.x + w.y + w.z, 0.0001);
	vec3 cx = texture(tex, pos.yz).rgb;
	vec3 cy = texture(tex, pos.xz).rgb;
	vec3 cz = texture(tex, pos.xy).rgb;
	return cx * w.x + cy * w.y + cz * w.z;
}

// Couleur d'un matériau (indice voxel) à ce fragment.
vec3 material_color(float index, vec3 p, vec3 n, float upness) {
	if (index < 0.5) {
		vec3 top = triplanar(grass_tex, p, n);
		vec3 side = triplanar(dirt_tex, p, n);
		return mix(side, top, smoothstep(grass_side_low, grass_side_high, upness));
	} else if (index < 1.5) {
		return triplanar(dirt_tex, p, n);
	}
	return triplanar(rock_tex, p, n);
}

// Ancien choix purement géométrique (secours).
vec3 geometric_color(vec3 p, vec3 n, float upness) {
	vec3 c_grass = triplanar(grass_tex, p, n);
	vec3 c_dirt = triplanar(dirt_tex, p, n);
	vec3 c_rock = triplanar(rock_tex, p, n);
	vec3 col = c_rock;
	col = mix(col, c_dirt, smoothstep(rock_to_dirt_low, rock_to_dirt_high, upness));
	col = mix(col, c_grass, smoothstep(dirt_to_grass_low, dirt_to_grass_high, upness));
	float high = smoothstep(height_rock_start, height_rock_end, v_world_pos.y);
	return mix(col, c_rock, high);
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	float upness = clamp(n.y, 0.0, 1.0);
	vec3 p = v_world_pos * texture_scale;

	vec3 col = vec3(0.0);
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		float w = v_weights[i];
		if (w > 0.001) {
			col += material_color(v_indices[i], p, n, upness) * w;
			total += w;
		}
	}

	if (total > 0.001) {
		col /= total;
	} else {
		col = geometric_color(p, n, upness);
	}

	ALBEDO = col;
	ROUGHNESS = terrain_roughness;
	METALLIC = 0.0;
}
