shader_type spatial;
render_mode cull_back;

// GAME-1250 + GAME-1256 — Terrain triplanaire TEXTURÉ, piloté par la géométrie.
// Les mailles Transvoxel n'ont pas d'UV : on projette les textures en triplanaire
// depuis la position monde. Choix herbe / terre / roche par pente (normal.y) et
// hauteur — aucune donnée stockée dans les voxels.
//
// Empilement MONOTONE (du plus raide au plus plat) :
//   base    = roche          (pentes raides)
//   + terre  quand ça s'aplatit
//   + herbe  sur le plat
//   + roche  forcée sur les sommets (altitude)

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;

// Taille des textures en mètres (plus petit = motif plus grand).
uniform float texture_scale = 0.15;

// Seuils de pente, exprimés en n.y (1 = plat, 0 = falaise verticale).
uniform float rock_to_dirt_low = 0.55;    // n.y sous ce seuil = roche
uniform float rock_to_dirt_high = 0.72;   // au-dessus, la terre prend le dessus
uniform float dirt_to_grass_low = 0.80;   // début de l'herbe
uniform float dirt_to_grass_high = 0.92;  // plat franc = herbe pleine

// Altitude : au-delà, roche forcée (sommets).
uniform float height_rock_start = 120.0;
uniform float height_rock_end = 170.0;

uniform float terrain_roughness = 0.95;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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

void fragment() {
	vec3 n = normalize(v_world_normal);
	float upness = clamp(n.y, 0.0, 1.0);
	vec3 p = v_world_pos * texture_scale;

	vec3 c_grass = triplanar(grass_tex, p, n);
	vec3 c_dirt = triplanar(dirt_tex, p, n);
	vec3 c_rock = triplanar(rock_tex, p, n);

	// Empilement monotone selon la planéité.
	vec3 col = c_rock;
	col = mix(col, c_dirt, smoothstep(rock_to_dirt_low, rock_to_dirt_high, upness));
	col = mix(col, c_grass, smoothstep(dirt_to_grass_low, dirt_to_grass_high, upness));

	// Sommets : retour à la roche.
	float high = smoothstep(height_rock_start, height_rock_end, v_world_pos.y);
	col = mix(col, c_rock, high);

	ALBEDO = col;
	ROUGHNESS = terrain_roughness;
	METALLIC = 0.0;
}
