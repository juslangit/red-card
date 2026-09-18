shader_type spatial;

// The pitch: mown grass with every Law 1 marking, drawn from the same numbers
// PitchSpec judges with. The Venue passes them in as uniforms, so the paint and the
// judgement cannot disagree.

uniform float pitch_length = 105.0;
uniform float pitch_width = 68.0;
uniform float line_width = 0.12;
uniform float goal_width = 7.32;
uniform float goal_area_depth = 5.5;
uniform float penalty_area_depth = 16.5;
uniform float area_reach_goal = 5.5;
uniform float area_reach_penalty = 16.5;
uniform float penalty_spot = 11.0;
uniform float circle = 9.15;
uniform float corner_arc = 1.0;
uniform float stripe = 5.25;
uniform vec3 grass_light : source_color = vec3(0.30, 0.52, 0.20);
uniform vec3 grass_dark : source_color = vec3(0.25, 0.45, 0.17);
uniform vec3 surround : source_color = vec3(0.22, 0.40, 0.16);
// 0 a pristine stadium lawn, 1 a worn village field with bald goalmouths.
uniform float wear = 0.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// 1 on the paint of a line segment's band: |d| <= half line width.
float band(float d) {
	float aa = fwidth(d) * 0.75;
	return 1.0 - smoothstep(line_width * 0.5 - aa, line_width * 0.5 + aa, abs(d));
}

void fragment() {
	vec2 p = world.xz;
	float hl = pitch_length * 0.5;
	float hw = pitch_width * 0.5;
	// Lines are inside the boundary: the outer edge of the paint is the boundary figure.
	float inset = line_width * 0.5;
	float paint = 0.0;
	bool inside = abs(p.x) <= hl && abs(p.y) <= hw;

	// Boundary
	if (abs(p.x) <= hl && abs(p.y) <= hw) {
		paint = max(paint, band(abs(p.y) - (hw - inset)));
		paint = max(paint, band(abs(p.x) - (hl - inset)));
		// Halfway line
		paint = max(paint, band(p.x));
		// Centre circle and spot
		paint = max(paint, band(length(p) - (circle - inset)));
		paint = max(paint, 1.0 - smoothstep(0.1, 0.12, length(p)));
		// Both ends
		float ax = hl - abs(p.x);   // distance in from the goal line
		float az = abs(p.y);
		float half_goal = goal_width * 0.5;
		// Goal area
		float ga_z = half_goal + area_reach_goal;
		if (ax <= goal_area_depth + inset && az <= ga_z + inset) {
			paint = max(paint, band(ax - (goal_area_depth - inset)));
			paint = max(paint, band(az - (ga_z - inset)));
		}
		// Penalty area
		float pa_z = half_goal + area_reach_penalty;
		if (ax <= penalty_area_depth + inset && az <= pa_z + inset) {
			paint = max(paint, band(ax - (penalty_area_depth - inset)));
			paint = max(paint, band(az - (pa_z - inset)));
		}
		// Penalty spot and arc (the arc only outside the area)
		vec2 spot = vec2(hl - penalty_spot, 0.0);
		vec2 q = vec2(abs(p.x), p.y);
		paint = max(paint, 1.0 - smoothstep(0.1, 0.12, length(q - spot)));
		if (ax > penalty_area_depth) {
			paint = max(paint, band(length(q - spot) - (circle - inset)));
		}
		// Corner arcs
		vec2 corner = vec2(hl, hw);
		vec2 c = vec2(abs(p.x), abs(p.y));
		paint = max(paint, band(length(c - corner) - (corner_arc - inset)));
	}

	// Mowing stripes across the length, and a little noise so it is not a flat colour.
	float s = mod(floor((p.x + hl) / stripe), 2.0);
	vec3 grass = mix(grass_light, grass_dark, s);
	if (!inside) {
		grass = surround;
	}
	float n = noise(p * 1.7) * 0.5 + noise(p * 0.23) * 0.5;
	grass *= 0.9 + 0.2 * n;
	// Wear: bald patches in the goalmouths and down the middle.
	float goalmouth = exp(-pow((hl - abs(p.x)) / 6.0, 2.0) - pow(p.y / 5.0, 2.0));
	float spine = exp(-pow(p.y / 9.0, 2.0)) * 0.35;
	float bald = clamp((goalmouth + spine) * wear * (0.6 + 0.8 * noise(p * 0.6)), 0.0, 1.0);
	grass = mix(grass, vec3(0.42, 0.36, 0.25), bald * 0.8);

	ALBEDO = mix(grass, vec3(0.95), paint * (1.0 - bald * 0.5));
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
