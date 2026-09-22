shader_type spatial;
render_mode cull_back;

// Terrain triplanaire, TEXTURÉ PAR VOXEL (GAME-1212) et TEINTÉ PAR BIOME.
//
// Les mailles Transvoxel n'ont pas d'UV : on projette les textures en
// triplanaire depuis la position monde. Le mesher (mode « Single texture »)
// fournit dans CUSTOM1 les 4 indices de matériau du triangle (x) et leurs
// poids (y), en 8 bits chacun.
//
// Matériaux : 0 herbe, 1 herbe sèche, 2 herbe froide, 3 terre, 4 roche,
//             5 sable, 6 neige, 7 charbon, 8 fer, 9 cuivre.
//
// Comme dans Minecraft, les matières végétales sont désaturées puis teintées :
// une seule texture d'herbe sert aux trois herbes (tempérée, sèche, froide).
// Le sable et la neige ont maintenant leur propre texture ; les minerais sont
// la roche, teintée.
//
// Chaque matière s'affiche sur TOUTES les faces du bloc : l'herbe peut pousser
// sur le côté d'un bloc, ce n'est plus réservé au dessus.

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap, repeat_enable;

// Taille des textures en mètres (plus petit = motif plus grand).
uniform float texture_scale = 0.15;

// Teintes par matériau (voir la liste ci-dessus).
uniform vec3 tint_grass : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 tint_grass_dry : source_color = vec3(0.85, 0.78, 0.42);
uniform vec3 tint_grass_cold : source_color = vec3(0.52, 0.66, 0.52);
uniform vec3 tint_coal : source_color = vec3(0.24, 0.24, 0.27);
uniform vec3 tint_iron : source_color = vec3(0.85, 0.66, 0.50);
uniform vec3 tint_copper : source_color = vec3(0.42, 0.76, 0.62);

// Secours géométrique si le maillage ne porte aucun matériau.
uniform float rock_to_dirt_low = 0.55;
uniform float rock_to_dirt_high = 0.72;
uniform float dirt_to_grass_low = 0.80;
uniform float dirt_to_grass_high = 0.92;

uniform float terrain_roughness = 0.95;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
// Les 4 indices sont constants sur un triangle : pas d'interpolation.
varying flat vec4 v_indices;
varying vec4 v_weights;

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

// Échantillonnage triplanaire : 3 plans mélangés par la normale.
vec3 triplanar(sampler2D tex, vec3 pos, vec3 n) {
	vec3 w = abs(n);
	w = w / max(w.x + w.y + w.z, 0.0001);
	vec3 cx = texture(tex, pos.yz).rgb;
	vec3 cy = texture(tex, pos.xz).rgb;
	vec3 cz = texture(tex, pos.xy).rgb;
	return cx * w.x + cy * w.y + cz * w.z;
}

// Désature une couleur puis la teinte (principe de Minecraft).
vec3 tinted(vec3 base, vec3 tint) {
	float grey = dot(base, vec3(0.299, 0.587, 0.114));
	return mix(base, vec3(grey), 0.75) * tint;
}

// Couleur d'un matériau à ce fragment.
vec3 material_color(float index, vec3 p, vec3 n) {
	vec3 c_grass = triplanar(grass_tex, p, n);
	vec3 c_dirt = triplanar(dirt_tex, p, n);
	vec3 c_rock = triplanar(rock_tex, p, n);

	if (index < 0.5) {                       // herbe tempérée
		return c_grass * tint_grass;
	} else if (index < 1.5) {                // herbe sèche
		return tinted(c_grass, tint_grass_dry);
	} else if (index < 2.5) {                // herbe froide
		return tinted(c_grass, tint_grass_cold);
	} else if (index < 3.5) {                // terre
		return c_dirt;
	} else if (index < 4.5) {                // roche
		return c_rock;
	} else if (index < 5.5) {                // sable
		return triplanar(sand_tex, p, n);
	} else if (index < 6.5) {                // neige
		return triplanar(snow_tex, p, n);
	} else if (index < 7.5) {                // charbon
		return tinted(c_rock, tint_coal);
	} else if (index < 8.5) {                // fer
		return tinted(c_rock, tint_iron);
	}
	return tinted(c_rock, tint_copper);      // cuivre
}

// Ancien choix purement géométrique (secours).
vec3 geometric_color(vec3 p, vec3 n, float upness) {
	vec3 col = triplanar(rock_tex, p, n);
	col = mix(col, triplanar(dirt_tex, p, n), smoothstep(rock_to_dirt_low, rock_to_dirt_high, upness));
	return mix(col, triplanar(grass_tex, p, n), smoothstep(dirt_to_grass_low, dirt_to_grass_high, upness));
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
			col += material_color(v_indices[i], p, n) * w;
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
