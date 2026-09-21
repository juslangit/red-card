extends Node3D

## The footwork, gait by gait, from the side.
##
##   Godot --path . --resolution 1600x900 res://dev/looks/_gait.tscn
##
## A player is driven across the camera at the speed each gait is meant for, and four
## frames of the stride are saved for each. Side on is the view that shows footwork: a foot
## that slides, a stride too short for the speed, or a leg that never leaves the ground all
## read here and nowhere else.

const GAITS := [
	{"name": "walk", "speed": 1.6, "face": Vector3.FORWARD},
	{"name": "jog", "speed": 4.3, "face": Vector3.FORWARD, "shots": 8, "every": 0.085},
	# Head-on, because a sideways tilt is invisible from the side.
	{"name": "jog_front", "speed": 4.3, "face": Vector3.FORWARD, "shots": 4, "every": 0.1, "front": true},
	{"name": "sprint", "speed": 7.2, "face": Vector3.FORWARD, "shots": 8, "every": 0.075},
	{"name": "backpedal", "speed": 3.0, "face": Vector3.BACK},
	{"name": "sidestep", "speed": 2.8, "face": Vector3.LEFT},
	# Running a bend: he should lean into it rather than pivot on the spot.
	{"name": "turning", "speed": 6.0, "face": Vector3.FORWARD, "turn": 1.5},
	# The two ways of going in for the ball, played as they are in a match: a one-shot over
	# a body that is still moving. Six frames each rather than four, because what matters
	# in a tackle is the whole movement.
	{"name": "tackle", "speed": 3.4, "face": Vector3.FORWARD, "one_shot": "tackle", "shots": 6},
	{"name": "slide", "speed": 4.6, "face": Vector3.FORWARD, "one_shot": "slide", "shots": 6},
]
const SHOTS := 4

var player: Footballer
var camera: Camera3D
var at := 0
var shot := 0
var wait := 0.0
var _marks: Array[MeshInstance3D] = []
var _fired := false
var _turned := 0.0


func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, 35, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.55, 0.38)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.66, 0.7)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.30, 0.52, 0.24)
	ground.material_override = grass
	add_child(ground)
	# Stripes on the ground that scroll past at the speed he is travelling. He stays put
	# and the world moves, which is the only way to see a foot slip: a planted foot should
	# hold still against a stripe, and a sliding one will not.
	for i in 25:
		var mark := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.06, 0.01, 1.0)
		mark.mesh = box
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.92, 0.94, 0.9)
		mark.material_override = white
		mark.mesh.size = Vector3(1.2, 0.01, 0.07)
		mark.position = Vector3(0, 0.005, -12.0 + i)
		add_child(mark)
		_marks.append(mark)

	player = Footballer.new()
	player.setup(Names.team_from(0), 9, Footballer.Role.MF, "Test")
	add_child(player)

	camera = Camera3D.new()
	camera.fov = 38.0
	camera.position = Vector3(6.4, 1.05, 0)
	add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.current = true


func _process(delta: float) -> void:
	if at >= GAITS.size():
		return
	var gait: Dictionary = GAITS[at]
	# Head-on for the gaits that ask for it: a sideways tilt is invisible from the side.
	if gait.get("front", false):
		camera.global_position = player.global_position + Vector3(0, 1.15, -7.0)
		camera.look_at(player.global_position + Vector3(0, 0.95, 0))
	# He travels along -Z, past a camera off to his side. The ground scrolls the other way.
	var going: Vector3 = Vector3.FORWARD * float(gait.speed)
	for mark: MeshInstance3D in _marks:
		mark.position.z += float(gait.speed) * delta
		if mark.position.z > 12.0:
			mark.position.z -= 24.0
	if gait.has("one_shot") and not _fired:
		_fired = true
		player.state = Footballer.State.PLAY
		player.one_shot(gait.one_shot as String, 1.6)
	if gait.has("turn"):
		# Steered round a bend instead of driven straight, so `_face` has a turn to make.
		_turned += float(gait.turn) * delta
		var way := Vector3.FORWARD.rotated(Vector3.UP, _turned)
		# Steered rather than driven, so `_face` has a real turn to make. He is sent to a
		# point ahead on the bend and told to hurry, and then put back where he started so
		# he stays in front of the camera.
		player.goal = player.global_position + way * 10.0
		player.hurry = 1.0
		player.face_point = player.global_position + way * 8.0
		var was := player.global_position
		player.step(delta)
		player.global_position = was
		going = way * float(gait.speed)
	else:
		player.face_point = null
		player.puppet(going, gait.face as Vector3)
	wait += delta
	if wait > float(gait.get("every", 0.12)):
		wait = 0.0
		get_viewport().get_texture().get_image().save_png(
			"res://dev/shots/gait_%s_%d.png" % [gait.name, shot])
		shot += 1
		if gait.has("turn"):
			print("   leaning %.1f deg into a %.1f rad/s turn at %.1f m/s"
				% [rad_to_deg(player._pivot.rotation.z), float(gait.turn),
				Vector3(player.velocity.x, 0, player.velocity.z).length()])
		if shot >= int(gait.get("shots", SHOTS)):
			print("%-10s at %.1f m/s" % [gait.name, gait.speed])
			at += 1
			shot = 0
			_fired = false
			if at >= GAITS.size():
				get_tree().quit()
