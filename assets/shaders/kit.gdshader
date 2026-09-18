shader_type spatial;

// One footballer texture, every team's kit.
//
// The Meshy footballer is painted in one 2048x2048 texture with a red shirt around
// rgb(186, 62, 61), navy shorts around rgb(59, 60, 70) and skin around rgb(239, 196, 170).
// Referee For Fun's recolour_kit.py repaints the shirt offline for one kit at a time;
// this does the same thing on the graphics card, per player, so twenty-two players and a
// referee share one mesh and one texture and still wear three different kits.
//
// The shirt is found by being far redder than it is green or blue — skin is only about
// 1.2x redder than green, the shirt about 3x — and it keeps its own shading: the new
// colour is scaled by how bright the fabric was at that pixel, so the folds survive.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;

instance uniform vec4 shirt_color : source_color = vec4(0.73, 0.24, 0.24, 1.0);
instance uniform vec4 shorts_color : source_color = vec4(0.23, 0.24, 0.27, 1.0);
instance uniform float skin_tone = 1.0;
instance uniform float highlight = 0.0;
// For the referee's own body: everything within this radius of this point is cut away,
// except in the shadow pass. The camera sits where the eyes are, so this removes the head
// and neck from the player's view and keeps them in the shadow on the grass — which is
// what having a head looks like from inside it.
instance uniform vec4 hide_sphere = vec4(0.0, -1000.0, 0.0, 0.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void fragment() {
	if (!IN_SHADOW_PASS && distance(world_pos, hide_sphere.xyz) < hide_sphere.w) {
		discard;
	}
	vec3 src = texture(albedo_tex, UV).rgb;
	vec3 hsv = rgb2hsv(src);
	vec3 col = src;

	// The shirt: strongly red, properly saturated.
	float redness = src.r / max(max(src.g, src.b), 0.02);
	float shirt = smoothstep(1.9, 2.4, redness) * smoothstep(0.30, 0.45, hsv.y);
	// 0.73 is the shirt's own brightness; anything brighter or darker is a fold.
	float shade = clamp(hsv.z / 0.73, 0.35, 1.35);
	col = mix(col, shirt_color.rgb * shade, shirt);

	// The shorts: dark, cool and unsaturated. Hair is dark too, but warm.
	float cool = step(src.r, src.b + 0.02);
	float shorts = (1.0 - smoothstep(0.26, 0.34, hsv.z)) * (1.0 - smoothstep(0.18, 0.30, hsv.y)) * cool;
	float short_shade = clamp(hsv.z / 0.25, 0.4, 1.4);
	col = mix(col, shorts_color.rgb * short_shade, shorts * (1.0 - shirt));

	// Skin: warm, lightly saturated, bright. Darkened or lightened per player.
	float skin_ratio = src.r / max(src.g, 0.02);
	float skin = step(1.08, skin_ratio) * (1.0 - step(1.5, skin_ratio))
		* smoothstep(0.12, 0.2, hsv.y) * (1.0 - smoothstep(0.45, 0.55, hsv.y))
		* smoothstep(0.45, 0.6, hsv.z);
	col = mix(col, col * skin_tone, skin * (1.0 - shirt));

	ALBEDO = col;
	ROUGHNESS = 0.85;
	EMISSION = vec3(highlight) * vec3(1.0, 0.85, 0.3);
}
