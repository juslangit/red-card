shader_type spatial;

// A classic football: twelve black pentagons on white, one centred on each vertex of an
// icosahedron. Drawn from the surface normal in the ball's own space, so it needs no
// texture and rolls with the mesh.

varying vec3 local_normal;

void vertex() {
	local_normal = NORMAL;
}

void fragment() {
	float phi = 1.61803398875;
	vec3 verts[12] = vec3[](
		vec3(-1.0, phi, 0.0), vec3(1.0, phi, 0.0), vec3(-1.0, -phi, 0.0), vec3(1.0, -phi, 0.0),
		vec3(0.0, -1.0, phi), vec3(0.0, 1.0, phi), vec3(0.0, -1.0, -phi), vec3(0.0, 1.0, -phi),
		vec3(phi, 0.0, -1.0), vec3(phi, 0.0, 1.0), vec3(-phi, 0.0, -1.0), vec3(-phi, 0.0, 1.0)
	);
	vec3 n = normalize(local_normal);
	float best = 0.0;
	for (int i = 0; i < 12; i++) {
		best = max(best, dot(n, normalize(verts[i])));
	}
	// cos(20 degrees) or so makes a patch about the size of a real panel.
	float spot = smoothstep(0.925, 0.935, best);
	ALBEDO = mix(vec3(0.95), vec3(0.06), spot);
	ROUGHNESS = 0.45;
	SPECULAR = 0.4;
}
