extends Node3D

## A close look at one footballer: standing from the front and the back, and the run cycle
## across a row, so the kit and the number can be judged.
##   Godot --path . --resolution 1600x900 res://dev/looks/_player.tscn

var cam: Camera3D
var shots := ["front", "back", "side", "sprint1", "sprint2", "sprint3", "parts_back", "parts_front"]
var step := 0
var t := 0.0
var p: Footballer
var mate_node: Footballer
var team: Team


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.18, 0.2, 0.23)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.63, 0.68)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.6
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.45, 0.2)
	floor_mesh.material_override = mat
	add_child(floor_mesh)

	team = Names.team_from(0)
	p = Footballer.new()
	p.setup(team, 9, Footballer.Role.MF, "Player")
	add_child(p)
	p.global_position = Vector3.ZERO
	# A second player, to see a two-digit number.
	var mate := Footballer.new()
	mate.setup(team, 11, Footballer.Role.MF, "Mate")
	add_child(mate)
	mate.global_position = Vector3(1.1, 0, 0)
	mate_node = mate
	mate.heading = Vector3(0, 0, -1)
	mate.transform.basis = Basis.looking_at(mate.heading, Vector3.UP)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	_aim()


func _aim() -> void:
	match shots[step]:
		"front":
			cam.global_position = Vector3(0, 1.1, 3.4)
			p.heading = Vector3(0, 0, 1)
		"back":
			cam.global_position = Vector3(0, 1.1, 3.4)
			p.heading = Vector3(0, 0, -1)
		"side":
			cam.global_position = Vector3(3.2, 1.1, 0.6)
			p.heading = Vector3(0, 0, -1)
		"sprint1", "sprint2", "sprint3":
			# One player, side on, at three moments of the stride.
			mate_node.visible = false
			cam.global_position = Vector3(3.6, 1.0, 0.0)
			p.heading = Vector3(0, 0, -1)
		"parts_back":
			cam.global_position = Vector3(0, 1.1, 3.4)
			p.heading = Vector3(0, 0, -1)
			_debug(1.0)
		"parts_front":
			cam.global_position = Vector3(0, 1.1, 3.4)
			p.heading = Vector3(0, 0, 1)
			_debug(2.0)
	p.transform.basis = Basis.looking_at(p.heading, Vector3.UP)
	cam.look_at(Vector3(0.0 if shots[step].begins_with("sprint") else 0.55, 0.95, 0), Vector3.UP)


func _debug(mode: float) -> void:
	var mesh: MeshInstance3D = p.find_child("char1", true, false)
	(mesh.material_override as ShaderMaterial).set_shader_parameter("debug_parts", mode)


func _process(delta: float) -> void:
	t += delta
	if not shots[step].begins_with("parts"):
		_debug(0.0)
	if shots[step].begins_with("parts"):
		p.play("idle", 0.1)
	elif shots[step] == "side":
		p.play("run", 0.1, 1.0)
	elif shots[step].begins_with("sprint"):
		var moment: float = {"sprint1": 0.08, "sprint2": 0.24, "sprint3": 0.40}[shots[step]]
		p.play("sprint", 0.0, 0.0)
		var anim: AnimationPlayer = p.find_child("AnimationPlayer", true, false)
		anim.seek(moment, true)
	else:
		p.play("idle", 0.1)
	if t > 1.2:
		t = 0.0
		get_viewport().get_texture().get_image().save_png("res://dev/shots/player_%s.png" % shots[step])
		step += 1
		if step >= shots.size():
			get_tree().quit()
			return
		_aim()
