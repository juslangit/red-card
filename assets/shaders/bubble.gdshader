shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

// A speech bubble: a rounded plate with a little tail underneath, facing the camera.
// The quad is billboarded in the vertex shader (Godot's billboard flag lives on
// StandardMaterial3D, not on a shader material), and the rounded corners and the tail are
// drawn with distance fields so the same shader fits any width.

uniform vec4 fill : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge : source_color = vec4(0.05, 0.06, 0.08, 1.0);
uniform vec2 size = vec2(1.0, 0.46);
uniform float alpha = 1.0;

void vertex() {
	// Face the camera, keep the world position and the scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz) * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz) * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz) * length(MODEL_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]);
}

// Distance to a rounded box centred on the origin.
float rounded_box(vec2 p, vec2 half_size, float radius) {
	vec2 d = abs(p) - half_size + radius;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

// Distance to the tail: a triangle hanging below the middle of the plate.
float tail(vec2 p, vec2 half_size) {
	vec2 q = vec2(abs(p.x), p.y);
	float width = 0.075;
	float drop = 0.13;
	float top = -half_size.y + 0.02;
	if (q.y > top) return 1.0;
	float t = clamp((top - q.y) / drop, 0.0, 1.0);
	return q.x - mix(width, 0.0, t);
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	p.y = -p.y;
	float body = rounded_box(p, size * 0.5, 0.16);
	float spike = tail(p, size * 0.5);
	float d = min(body, spike);
	float aa = fwidth(d) * 1.2;
	float inside = 1.0 - smoothstep(-aa, aa, d);
	float outline = 1.0 - smoothstep(0.018 - aa, 0.018 + aa, abs(d));
	if (inside < 0.01 && outline < 0.01) {
		discard;
	}
	ALBEDO = mix(fill.rgb, edge.rgb, outline);
	ALPHA = max(inside, outline) * alpha;
}
