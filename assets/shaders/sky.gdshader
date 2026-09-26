shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.30, 0.50, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.78, 0.83, 0.88);
uniform vec3 ground_color : source_color = vec3(0.42, 0.38, 0.33);
uniform vec3 sun_dir : source_color = vec3(0.45, 0.18, -0.87);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.86);
uniform float sun_intensity : hint_range(0.0, 4.0) = 1.2;
uniform float sun_disc_softness : hint_range(0.0001, 0.01) = 0.0004;
uniform vec3 cloud_albedo : source_color = vec3(1.0, 0.985, 0.95);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_density : hint_range(0.0, 2.0) = 0.55;
uniform float cloud_scale : hint_range(0.5, 6.0) = 2.2;
uniform float cloud_speed : hint_range(0.0, 0.2) = 0.02;
uniform float haze_strength : hint_range(0.0, 1.0) = 0.35;
uniform float haze_color_amount : hint_range(0.0, 1.0) = 0.55;
uniform float stars_amount : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p = p * 2.03 + vec2(11.7, 7.3);
		amp *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = clamp(dir.y, -1.0, 1.0);

	// Sky gradient
	vec3 sky = mix(horizon_color, zenith_color, smoothstep(0.0, 0.45, max(h, 0.0)));
	sky = mix(sky, horizon_color, pow(1.0 - max(h, 0.0), 2.0) * 0.45);

	// Ground
	vec3 gnd = mix(ground_color, horizon_color, smoothstep(0.0, -0.12, h) * 0.35);
	vec3 col = mix(gnd, sky, smoothstep(-0.02, 0.08, h));

	// Sun
	vec3 sd = normalize(sun_dir);
	float sdot = dot(dir, sd);
	float disc = smoothstep(0.9999 - sun_disc_softness, 0.9999 + sun_disc_softness, sdot);
	col += disc * sun_color * sun_intensity * 2.0;
	col += sun_color * pow(max(sdot, 0.0), 6.0) * sun_intensity * 0.10;
	col += sun_color * pow(max(sdot, 0.0), 64.0) * sun_intensity * 0.35;

	// Clouds (dome-projected fbm)
	if (h > 0.02) {
		vec2 cp = vec2(atan(dir.z, dir.x), asin(clamp(dir.y, -1.0, 1.0)));
		cp *= cloud_scale;
		cp.x += TIME * cloud_speed * 8.0;
		float n = fbm(cp + vec2(TIME * cloud_speed * 3.0, 0.0));
		float edge = 1.0 - cloud_coverage;
		float cld = smoothstep(edge, edge + cloud_density * 0.5, n);
		float light = 0.35 + 0.65 * pow(max(dot(dir, sd), 0.0), 3.0);
		float silver = smoothstep(0.25, 0.9, abs(dot(normalize(vec3(dir.x, 0.0, dir.z)), vec3(0.0, 0.0, 1.0))));
		col = mix(col, cloud_albedo * (0.15 + light) * (1.0 + silver * 0.25), cld * 0.85);
	}

	// Horizon haze (aerial perspective fake)
	float haze = pow(1.0 - clamp(abs(h) * 2.2, 0.0, 1.0), 1.5) * haze_strength;
	vec3 haze_col = mix(horizon_color, sun_color, 0.25) * haze_color_amount;
	col = mix(col, haze_col, haze);

	// Stars (only high up)
	if (stars_amount > 0.001 && h > 0.25) {
		float st = vnoise(dir.xz * 180.0 + vec2(dir.y * 140.0, 0.0));
		float tw = smoothstep(0.985, 1.0, st);
		col += vec3(1.0) * tw * stars_amount * (0.5 + 0.5 * sin(TIME * 1.7 + st * 90.0));
	}

	COLOR = col;
}
