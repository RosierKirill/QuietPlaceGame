shader_type sky;

// Ciel, nuages et soleil (GAME-1235).
//
// Les nuages sont peints DANS le ciel : on projette la direction du regard sur
// un plan à `cloud_height` et on y lit un bruit fractal qui dérive avec le
// vent. Coût quasi nul et joli de loin, mais c'est un décor : on ne peut pas
// voler dedans. Le jour où il faudra les traverser, il faudra passer à des
// volumes (brouillard volumétrique) — le reste du ciel ne bougera pas.
//
// Le script SkyEnvironment fournit la direction du soleil et les couleurs :
// le shader ne décide de rien, il dessine.

group_uniforms Soleil;
// Direction de la LUMIÈRE (du ciel vers le sol), normalisée.
uniform vec3 sun_direction = vec3(0.0, -1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
// 0 = nuit noire, 1 = plein jour. Pilote tout le mélange.
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;

group_uniforms Couleurs;
uniform vec3 zenith_day : source_color = vec3(0.19, 0.42, 0.78);
uniform vec3 horizon_day : source_color = vec3(0.72, 0.84, 0.96);
uniform vec3 zenith_night : source_color = vec3(0.016, 0.026, 0.06);
uniform vec3 horizon_night : source_color = vec3(0.05, 0.07, 0.12);
uniform vec3 ground_color : source_color = vec3(0.24, 0.26, 0.28);

group_uniforms Nuages;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.92;
uniform float cloud_scale = 1.1;
uniform float cloud_height = 700.0;
uniform vec2 cloud_wind = vec2(0.004, 0.0015);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.99, 0.96);
uniform vec3 cloud_shade : source_color = vec3(0.55, 0.58, 0.66);

group_uniforms Etoiles;
uniform float star_density : hint_range(0.0, 1.0) = 0.6;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Hachage 3D : les étoiles se répartissent sur la sphère du ciel. Une version
// 2D projetée les étirerait en traits près de l'horizon.
float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Bruit fractal : cinq octaves, c'est le grain d'un cumulus.
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amplitude * value_noise(p);
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;

	// Dégradé zénith / horizon, teinté par l'heure.
	vec3 zenith = mix(zenith_night, zenith_day, day_factor);
	vec3 horizon = mix(horizon_night, horizon_day, day_factor);
	vec3 col = mix(horizon, zenith, pow(clamp(up, 0.0, 1.0), 0.45));
	if (up < 0.0) {
		col = mix(horizon, ground_color, pow(clamp(-up, 0.0, 1.0), 0.5));
	}

	// Étoiles : seulement quand le jour s'efface, et jamais sous l'horizon.
	float night = 1.0 - day_factor;
	if (night > 0.01 && up > 0.0) {
		float star = hash31(floor(dir * 170.0));
		float spark = smoothstep(0.9982 - star_density * 0.002, 1.0, star);
		col += vec3(spark) * night * smoothstep(0.02, 0.3, up);
	}

	// Soleil : un disque net et un halo large.
	float sun = dot(dir, -sun_direction);
	col += sun_color * pow(max(sun, 0.0), 1400.0) * 12.0;
	col += sun_color * pow(max(sun, 0.0), 8.0) * 0.22 * day_factor;

	// Nuages : plan à cloud_height, vus en perspective.
	if (up > 0.015) {
		vec2 uv = dir.xz / up * (cloud_height * 0.0016 * cloud_scale) + cloud_wind * TIME;
		float n = fbm(uv);
		float density = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.22, n);
		// Relief : on compare au voisin situé vers le soleil. Plus le nuage
		// monte de ce côté, plus il est éclairé.
		vec2 towards_sun = normalize(-sun_direction.xz + vec2(0.001, 0.0));
		float lit_sample = fbm(uv + towards_sun * 0.28);
		float lit = clamp((n - lit_sample) * 2.5 + 0.5, 0.0, 1.0);
		vec3 cloud = mix(cloud_shade, cloud_lit, lit);
		// Au lever et au coucher, les nuages prennent la couleur du soleil.
		cloud = mix(cloud * vec3(0.18, 0.2, 0.28), cloud * mix(sun_color, vec3(1.0), 0.5),
			day_factor);
		// Ils s'effacent près de l'horizon, où la projection s'étire à l'infini.
		float fade = smoothstep(0.015, 0.22, up);
		col = mix(col, cloud, density * fade * cloud_opacity);
	}

	COLOR = col;
}
