shader_type spatial;

// One footballer mesh, every team's kit — a football kit, not a repainted badminton one.
//
// Two textures do the work. Meshy's own painting carries the face, the hair, the skin and
// every fold and seam in the fabric. Beside it, `parts_tex` (baked by
// tools/meshy/bake_kit_map.py) says what part of the body each texel belongs to:
//
//     R   the part      hand 20, torso 40, arm 80, hips and thigh 120, shin 160,
//                       foot 200, head 240
//     G   along         on a limb, 0 at the top of it to 1 at the bottom; elsewhere, the
//                       height up the body, 0 at the boots to 1 at the top of the head
//     B   backness      0 facing the front, 1 facing the back
//     A   across        0 at the player's right, 1 at his left
//
// The kit is cut from that map rather than from Meshy's colours, so the shirt, the shorts
// and the sleeves land in the same place on every player whatever the original texture is
// painted like — the colour-matching version put white shorts on the front of the legs and
// left navy ones on the back, because those are different islands in the texture. The
// texture now supplies only light and shade: each part divides its own pixel by the
// brightness that part was painted at, which keeps the creases and loses the colour.
//
// Every player gets his own colours through instance uniforms, so twenty-two players and
// a referee share one mesh and one material.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D parts_tex : filter_linear_mipmap, repeat_disable;
// 0 the kit, 1 each part in a flat colour, 2 the raw map. For looking at, not for play.
uniform float debug_parts = 0.0;
// Ten digits in a strip, printed on the back of the shirt.
uniform sampler2D digits_tex : source_color, filter_linear_mipmap, repeat_disable;

instance uniform vec4 shirt_color : source_color = vec4(0.73, 0.24, 0.24, 1.0);
instance uniform vec4 shorts_color : source_color = vec4(0.23, 0.24, 0.27, 1.0);
instance uniform vec4 socks_color : source_color = vec4(0.73, 0.24, 0.24, 1.0);
instance uniform vec4 trim_color : source_color = vec4(0.95, 0.95, 0.95, 1.0);
instance uniform float skin_tone = 1.0;
instance uniform float highlight = 0.0;
// For the referee's own body: everything within this radius of this point is cut away,
// except in the shadow pass, so the camera at his eyes never sees the inside of his head.
instance uniform vec4 hide_sphere = vec4(0.0, -1000.0, 0.0, 0.0);
// The shirt number: x the tens digit (-1 when there is none), y the units, z 1 for a dark
// number on a light shirt. Packed into one parameter because a shader may only carry so
// many per instance.
instance uniform vec3 number = vec3(-1.0, -1.0, 0.0);

const float HAND = 20.0;
const float TORSO = 40.0;
const float ARM = 80.0;
const float HIPS = 120.0;
const float SHIN = 160.0;
const float FOOT = 200.0;
const float HEAD = 240.0;

// Where the kit ends: heights up the body, and distances down a limb. Measured off the
// part map — the shirt covers the hips to a little over halfway up, the shorts reach
// mid-thigh, and the sleeve ends a third of the way down the upper arm.
const float SHIRT_HEM = 0.575;
const float SHORTS_HEM = 0.335;
const float SLEEVE_END = 0.34;
const float COLLAR = 0.795;

varying vec3 world_pos;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// 1 when the part id is this one. The map is filtered, so a texel on a seam arrives as
// something in between; half a part either way picks the nearer of the two.
float is_part(float id, float want) {
	return 1.0 - smoothstep(14.0, 22.0, abs(id - want));
}

// The folds, without the colour: how bright this texel is against the brightness the part
// was painted at, held near 1 so that a white kit does not come out a dirty one.
float folds(float value, float painted_at) {
	return mix(1.0, clamp(value / painted_at, 0.55, 1.35), 0.75);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (!IN_SHADOW_PASS && distance(world_pos, hide_sphere.xyz) < hide_sphere.w) {
		discard;
	}
	vec3 src = texture(albedo_tex, UV).rgb;
	vec4 parts = texture(parts_tex, UV);
	float id = parts.r * 255.0;
	float along = parts.g;
	vec3 hsv = rgb2hsv(src);

	// Skin keeps Meshy's painting, darkened or lightened per player. The hands lose their
	// badminton gloves: a footballer's hands are bare.
	vec3 col = src * skin_tone;
	// Bare skin is painted rather than taken from the texture wherever Meshy's own kit ran:
	// its sleeves reach further down the arm than a football sleeve does, and its gloves
	// cover the hands. Both would otherwise show through as red bands and black mitts.
	// Bare skin takes only a little of the texture's shading: Meshy's gloves and sleeves are
	// dark, and following their shading closely left grey hands.
	vec3 bare = vec3(0.80, 0.62, 0.52) * skin_tone * mix(1.0, folds(hsv.z, 0.62), 0.35);
	float hand = is_part(id, HAND);
	float lower_arm = is_part(id, ARM) * smoothstep(SLEEVE_END, SLEEVE_END + 0.04, along);
	col = mix(col, bare, clamp(hand + lower_arm, 0.0, 1.0));
	col = mix(col, src, is_part(id, HEAD));

	// Shirt: the whole torso, the top of each sleeve, and over the hips to the hem.
	float shirt = max(is_part(id, TORSO),
		max(is_part(id, ARM) * (1.0 - smoothstep(SLEEVE_END, SLEEVE_END + 0.05, along)),
			is_part(id, HIPS) * smoothstep(SHIRT_HEM - 0.02, SHIRT_HEM + 0.01, along)));
	col = mix(col, shirt_color.rgb * folds(hsv.z, 0.66), shirt);

	// Shorts: from the shirt's hem down to mid-thigh.
	float shorts = is_part(id, HIPS)
		* (1.0 - smoothstep(SHIRT_HEM, SHIRT_HEM + 0.02, along))
		* smoothstep(SHORTS_HEM - 0.02, SHORTS_HEM + 0.01, along);
	col = mix(col, shorts_color.rgb * folds(hsv.z, 0.45), shorts);

	// Socks: knee to ankle.
	float sock = is_part(id, SHIN) * smoothstep(0.02, 0.09, along);
	col = mix(col, socks_color.rgb * folds(hsv.z, 0.62), sock);

	// Boots.
	float boot = is_part(id, FOOT);
	col = mix(col, vec3(0.07, 0.07, 0.08) * folds(hsv.z, 0.5), boot);

	// The second colour: a collar, a band at the end of each sleeve, the sock turnover and
	// a flash along the boot.
	float collar = is_part(id, TORSO) * smoothstep(COLLAR, COLLAR + 0.02, along);
	float cuff = is_part(id, ARM) * smoothstep(SLEEVE_END - 0.07, SLEEVE_END - 0.04, along)
		* (1.0 - smoothstep(SLEEVE_END, SLEEVE_END + 0.02, along));
	float sock_band = sock * smoothstep(0.09, 0.13, along) * (1.0 - smoothstep(0.20, 0.25, along));
	float boot_flash = boot * smoothstep(0.62, 0.72, hsv.z) * 0.8;
	float trim = clamp(collar + cuff + sock_band + boot_flash, 0.0, 1.0);
	col = mix(col, trim_color.rgb * folds(hsv.z, 0.66), trim);

	// --- the number on the back of the shirt -------------------------------------------
	// Printed onto the shirt itself, using how far up and how far across the body each
	// texel is, so it creases and turns with the fabric. A Label3D floating behind the
	// player instead was half swallowed by his own back whenever he leaned.
	if (number.y >= 0.0) {
		float back = parts.b;
		float across = parts.a;
		float wide = number.x >= 0.0 ? 0.20 : 0.115;
		// Mirrored: "across" runs from the player's right to his left, which is right to
		// left again when you are stood behind him reading his number.
		float u = ((0.5 + wide * 0.5) - across) / wide;
		float v = 1.0 - (along - 0.665) / 0.125;
		if (u > 0.0 && u < 1.0 && v > 0.0 && v < 1.0 && back > 0.62) {
			float digit = number.y;
			float cell = u;
			if (number.x >= 0.0) {
				digit = u < 0.5 ? number.x : number.y;
				cell = fract(u * 2.0);
			}
			// A little inset from the edge of each cell, so digits do not touch.
			float ink = texture(digits_tex, vec2((digit + mix(0.08, 0.92, cell)) / 10.0, v)).a;
			ink = smoothstep(0.35, 0.62, ink);
			ink *= smoothstep(0.62, 0.72, back) * shirt;
			vec3 number_colour = mix(vec3(0.97, 0.97, 1.0), vec3(0.05, 0.05, 0.09), number.z);
			col = mix(col, number_colour * folds(hsv.z, 0.66), ink);
		}
	}

	vec3 shown = col;
	float rough = mix(0.85, 0.5, boot);
	if (debug_parts > 1.5) {
		shown = parts.rgb;
		rough = 1.0;
	} else if (debug_parts > 0.5) {
		vec3 key = vec3(0.35);
		key = mix(key, vec3(1.0, 0.1, 0.1), is_part(id, TORSO));
		key = mix(key, vec3(0.1, 1.0, 0.1), is_part(id, ARM));
		key = mix(key, vec3(0.1, 0.2, 1.0), is_part(id, HIPS));
		key = mix(key, vec3(1.0, 0.95, 0.1), is_part(id, SHIN));
		key = mix(key, vec3(1.0, 0.1, 0.9), is_part(id, FOOT));
		key = mix(key, vec3(0.1, 0.9, 1.0), is_part(id, HEAD));
		key = mix(key, vec3(1.0, 0.55, 0.1), is_part(id, HAND));
		shown = key * (0.45 + 0.55 * along);
		rough = 1.0;
	}
	ALBEDO = shown;
	ROUGHNESS = rough;
	EMISSION = vec3(highlight) * vec3(1.0, 0.85, 0.3);
}
