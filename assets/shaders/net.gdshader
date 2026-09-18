shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Goal netting: a square mesh of cord, cut out of a flat quad.
uniform float cell = 0.12;
uniform float cord = 0.012;
uniform vec3 colour : source_color = vec3(0.95, 0.95, 0.95);

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = world / cell;
	vec3 f = abs(fract(p) - 0.5) * cell;
	// Pick the two axes that lie in this face.
	vec3 n = abs(NORMAL);
	float a;
	float b;
	vec3 wn = abs((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (wn.x > wn.y && wn.x > wn.z) { a = f.y; b = f.z; }
	else if (wn.y > wn.z) { a = f.x; b = f.z; }
	else { a = f.x; b = f.y; }
	float edge = cell * 0.5 - cord;
	float c = max(step(edge, a), step(edge, b));
	if (c < 0.5) discard;
	ALBEDO = colour;
	ROUGHNESS = 0.9;
}
