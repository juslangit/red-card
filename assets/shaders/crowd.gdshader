shader_type spatial;

// The crowd, thousands of people in one draw call.
//
// Each spectator model is merged into one mesh whose vertex colours are its own
// materials' colours, with the shirt marked by alpha = 0. The shirt takes a colour from
// the palette below, so one mesh wears every colour in the ground.
//
// INSTANCE_CUSTOM carries: x a phase, y which end they support (0 home, 1 away, 0.5
// neutral), z the palette index of their shirt. The two excitement uniforms make each
// set of supporters jump when their side scores. (Godot multiplies a MultiMesh's own
// instance colour into COLOR before the shader sees it, which would lose the shirt
// marker — hence the palette.)

uniform float excite_home = 0.0;
uniform float excite_away = 0.0;
uniform float sway = 1.0;
uniform vec3 palette[8] : source_color;

varying vec3 tint;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float side = INSTANCE_CUSTOM.y;
	float excite = mix(excite_home, excite_away, side);
	float jump = excite * max(sin(TIME * 7.0 + phase), 0.0) * 0.28;
	float idle = sin(TIME * 1.3 + phase) * 0.012 * sway;
	VERTEX.y += (jump + idle) * step(0.05, VERTEX.y);
	int index = clamp(int(INSTANCE_CUSTOM.z + 0.5), 0, 7);
	tint = mix(COLOR.rgb, palette[index], 1.0 - step(0.5, COLOR.a));
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.9;
}
