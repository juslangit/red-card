class_name Venue
extends Node3D

## The ground: the pitch, the goals, the flags, the light, and whatever surrounds it.
##
## Four grounds, one per rung of the career, from a village recreation field with a
## handful of people along a rail to a national stadium under floodlights. What changes
## between them is not only how they look — each level brings its own officiating team,
## the way real football does:
##
##   village   club assistants, one from each side: they flag offside and fouls too, but
##             less sharply than qualified ones, and not neutrally.
##   town      two neutral assistant referees.
##   league    assistants and a fourth official, who holds up the added-time board.
##   final     all of that, and VAR.

const LEVELS := [
	{
		"id": "village", "name": "Riverside Recreation Ground", "short": "Riverside Rec",
		"length": 100.0, "width": 64.0, "wear": 0.75,
		"crowd": 60, "stands": "rail", "floodlights": false, "time": "afternoon",
		"assistants": "club", "fourth_official": false, "var": false,
		"grass_light": Color(0.36, 0.54, 0.22), "grass_dark": Color(0.33, 0.50, 0.20),
	},
	{
		"id": "town", "name": "Station Road", "short": "Station Road",
		"length": 102.0, "width": 66.0, "wear": 0.4,
		"crowd": 700, "stands": "one", "floodlights": false, "time": "evening",
		"assistants": "neutral", "fourth_official": false, "var": false,
		"grass_light": Color(0.31, 0.53, 0.21), "grass_dark": Color(0.27, 0.47, 0.18),
	},
	{
		"id": "league", "name": "Kestrel Park", "short": "Kestrel Park",
		"length": 105.0, "width": 68.0, "wear": 0.15,
		"crowd": 5000, "stands": "four", "floodlights": true, "time": "dusk",
		"assistants": "neutral", "fourth_official": true, "var": false,
		"grass_light": Color(0.28, 0.55, 0.21), "grass_dark": Color(0.23, 0.47, 0.17),
	},
	{
		"id": "final", "name": "National Stadium", "short": "National Stadium",
		"length": 105.0, "width": 68.0, "wear": 0.0,
		"crowd": 12000, "stands": "bowl", "floodlights": true, "time": "night",
		"assistants": "neutral", "fourth_official": true, "var": true,
		"grass_light": Color(0.26, 0.56, 0.22), "grass_dark": Color(0.2, 0.47, 0.17),
	},
]

var level: Dictionary
var spec: PitchSpec
var woodwork: Array = []
var stands: Stands
var sun: DirectionalLight3D
var environment: WorldEnvironment


static func level_by_id(id: String) -> Dictionary:
	for l in LEVELS:
		if l.id == id:
			return l
	return LEVELS[0]


func build(level_id: String) -> void:
	level = level_by_id(level_id)
	spec = PitchSpec.of_size(level.length, level.width)
	_ground()
	for end in [-1, 1]:
		_goal(end)
	_corner_flags()
	_sky_and_light()
	stands = Stands.new()
	stands.name = "Stands"
	add_child(stands)
	stands.build(level, spec)


func _ground() -> void:
	var plane := PlaneMesh.new()
	# The surround runs well past the pitch so the stands sit on grass, not the void.
	plane.size = Vector2(spec.length + 60.0, spec.width + 60.0)
	plane.subdivide_depth = 1
	plane.subdivide_width = 1
	var ground := MeshInstance3D.new()
	ground.name = "Pitch"
	ground.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/pitch.gdshader")
	material.set_shader_parameter("pitch_length", spec.length)
	material.set_shader_parameter("pitch_width", spec.width)
	material.set_shader_parameter("line_width", PitchSpec.LINE_WIDTH)
	material.set_shader_parameter("goal_width", PitchSpec.GOAL_WIDTH)
	material.set_shader_parameter("goal_area_depth", PitchSpec.GOAL_AREA_DEPTH)
	material.set_shader_parameter("penalty_area_depth", PitchSpec.PENALTY_AREA_DEPTH)
	material.set_shader_parameter("area_reach_goal", PitchSpec.GOAL_AREA_REACH)
	material.set_shader_parameter("area_reach_penalty", PitchSpec.PENALTY_AREA_REACH)
	material.set_shader_parameter("penalty_spot", PitchSpec.PENALTY_SPOT)
	material.set_shader_parameter("circle", PitchSpec.CENTRE_CIRCLE)
	material.set_shader_parameter("corner_arc", PitchSpec.CORNER_ARC)
	material.set_shader_parameter("stripe", spec.length / 20.0)
	material.set_shader_parameter("wear", level.wear)
	material.set_shader_parameter("grass_light", level.grass_light)
	material.set_shader_parameter("grass_dark", level.grass_dark)
	material.set_shader_parameter("surround", (level.grass_dark as Color).darkened(0.12))
	ground.material_override = material
	add_child(ground)


## A goal: two posts, a crossbar and a net, all 12 cm, white. The posts stand on the goal
## line with their inside edges 7.32 m apart, so their centres are a half-width further
## out; the crossbar's underside is 2.44 m up.
func _goal(end: int) -> void:
	var x := spec.goal_line_x(end)
	var half := PitchSpec.GOAL_WIDTH * 0.5 + PitchSpec.POST_WIDTH * 0.5
	var top := PitchSpec.GOAL_HEIGHT + PitchSpec.POST_WIDTH * 0.5
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.97, 0.97, 0.97)
	white.roughness = 0.4
	var frame := Node3D.new()
	frame.name = "Goal%s" % ("East" if end > 0 else "West")
	add_child(frame)
	# The posts sit behind the paint: the goal line is the outer edge of the line, and
	# the posts are the same width as it, so their centres are on the line's centre.
	var line_centre := x - PitchSpec.LINE_WIDTH * 0.5 * end
	for side in [-1.0, 1.0]:
		var post := _cylinder(PitchSpec.POST_WIDTH * 0.5, top, white)
		post.position = Vector3(line_centre, top * 0.5, half * side)
		frame.add_child(post)
		woodwork.append({"a": Vector3(line_centre, 0.0, half * side),
			"b": Vector3(line_centre, top, half * side)})
	var bar := _cylinder(PitchSpec.POST_WIDTH * 0.5, half * 2.0, white)
	bar.rotation.x = PI * 0.5
	bar.position = Vector3(line_centre, top, 0.0)
	frame.add_child(bar)
	woodwork.append({"a": Vector3(line_centre, top, -half), "b": Vector3(line_centre, top, half)})

	# The net: a back, two sides and a roof.
	var net_material := ShaderMaterial.new()
	net_material.shader = load("res://assets/shaders/net.gdshader")
	var depth := PitchSpec.GOAL_DEPTH
	var back_x := line_centre + depth * end
	_net_quad(frame, net_material, Vector3(back_x, top * 0.5, 0.0), Vector2(half * 2.0, top), Vector3(0, PI * 0.5, 0))
	for side in [-1.0, 1.0]:
		_net_quad(frame, net_material, Vector3(line_centre + depth * 0.5 * end, top * 0.5, half * side), Vector2(depth, top), Vector3.ZERO)
	_net_quad(frame, net_material, Vector3(line_centre + depth * 0.5 * end, top, 0.0), Vector2(depth, half * 2.0), Vector3(PI * 0.5, 0, 0))
	# Supports at the back.
	for side in [-1.0, 1.0]:
		var stay := _cylinder(0.03, top, white)
		stay.position = Vector3(back_x, top * 0.5, half * side)
		frame.add_child(stay)


func _net_quad(parent: Node3D, material: Material, at: Vector3, size: Vector2, turn: Vector3) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.material_override = material
	mesh.position = at
	mesh.rotation = turn
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)


func _cylinder(radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	return node


## Law 1: a flag on a post at least 1.5 m high at each corner. Not pointed at the top.
func _corner_flags() -> void:
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.95, 0.95, 0.9)
	var flag_material := StandardMaterial3D.new()
	flag_material.albedo_color = Color(1.0, 0.82, 0.1) if level.id != "village" else Color(0.9, 0.2, 0.15)
	flag_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var pole := _cylinder(0.018, 1.6, pole_material)
			pole.position = Vector3(spec.half_length() * sx, 0.8, spec.half_width() * sz)
			add_child(pole)
			var flag := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(0.45, 0.35)
			flag.mesh = quad
			flag.material_override = flag_material
			flag.position = pole.position + Vector3(0.23 * -sx, 0.6, 0)
			add_child(flag)


func _sky_and_light() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.fog_enabled = true
	env.fog_density = 0.0005

	match level.time:
		"afternoon":
			sun.rotation_degrees = Vector3(-52, -35, 0)
			sun.light_energy = 1.25
			sky_material.sky_top_color = Color(0.32, 0.52, 0.82)
			sky_material.sky_horizon_color = Color(0.72, 0.8, 0.88)
			env.fog_light_color = Color(0.72, 0.8, 0.88)
		"evening":
			sun.rotation_degrees = Vector3(-24, -60, 0)
			sun.light_energy = 1.05
			sun.light_color = Color(1.0, 0.88, 0.72)
			sky_material.sky_top_color = Color(0.3, 0.44, 0.7)
			sky_material.sky_horizon_color = Color(0.92, 0.72, 0.52)
			env.fog_light_color = Color(0.85, 0.7, 0.55)
		"dusk":
			sun.rotation_degrees = Vector3(-60, 20, 0)
			sun.light_energy = 0.95
			sun.light_color = Color(0.95, 0.95, 1.0)
			sky_material.sky_top_color = Color(0.08, 0.1, 0.22)
			sky_material.sky_horizon_color = Color(0.55, 0.38, 0.42)
			sky_material.ground_bottom_color = Color(0.05, 0.05, 0.06)
			env.fog_light_color = Color(0.3, 0.26, 0.32)
		_:
			# Night: the floodlights are the sun, high and white, and the sky is black.
			sun.rotation_degrees = Vector3(-65, 30, 0)
			sun.light_energy = 1.1
			sun.light_color = Color(0.96, 0.97, 1.0)
			sky_material.sky_top_color = Color(0.01, 0.012, 0.03)
			sky_material.sky_horizon_color = Color(0.06, 0.07, 0.1)
			sky_material.ground_bottom_color = Color(0.02, 0.02, 0.02)
			sky_material.ground_horizon_color = Color(0.06, 0.07, 0.1)
			env.ambient_light_energy = 0.7
			env.fog_light_color = Color(0.08, 0.09, 0.12)
	add_child(sun)
	environment = WorldEnvironment.new()
	environment.environment = env
	add_child(environment)
