extends Node3D

## Your own head, from your own eyes, while you run.
##
##   Godot --path . --resolution 1600x900 res://dev/looks/_head.tscn -- town
##
## Luqman saw the referee's head clip into the camera at a sprint on 2026-09-20. The head
## is cut out of his own view by the kit shader, so this walks him forward at a sprint and
## takes the view at eight points in the stride, level and looking down, which is where
## anything the cut misses will show.

var m: Match
var ref: Referee
var level := "town"
var shots := 0
var wait := 0.0
var settle := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	level = args[0] if args.size() > 0 else "town"
	m = Match.new()
	m.setup(Names.team_from(0), Names.team_from(1), level, 360.0)
	add_child(m)
	ref = Referee.new()
	ref.setup(m, Game.settings)
	add_child(ref)
	ref.global_position = Vector3(-20, 0, 18)
	ref.scripted = true
	m.attach_referee(ref)
	ref.yaw = 0.0


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://dev/shots/head_%s.png" % name)


func _process(delta: float) -> void:
	settle += delta
	if settle < 1.0:
		return
	# Sprinting up the touchline, which is the fastest the head ever moves.
	_travel(Vector3.FORWARD)
	ref.wish_sprint = true
	ref.stamina = 1.0
	wait += delta
	# Eight views a fifth of a second apart covers more than one full stride, so no part of
	# the cycle goes unseen; the first four look ahead and the last four look down at the
	# chest, where the chin and the brim of the head come into frame.
	if wait > 0.2:
		wait = 0.0
		# The first half runs straight, level then looking down at the chest. The second
		# half keeps running the same way while the head turns further and further off the
		# line of travel — a referee watching play as he runs to keep up, and the case where
		# the body, and the head on it, swings round in front of the camera.
		var turn := 0.0 if shots < 4 else deg_to_rad(60.0 + 30.0 * float(shots - 4))
		ref.yaw = turn
		ref.pitch = deg_to_rad(-2.0) if shots < 4 or shots >= 6 else deg_to_rad(-84.0)
		_travel(Vector3.FORWARD)
		var head := ref.body.head_position()
		var eye := ref.camera.global_position
		# How far in front of the eye the head's centre sits: past zero, the face is in the
		# picture, and past the camera's near plane you are looking at the inside of it.
		var ahead := -ref.camera.global_transform.basis.z.dot(head - eye)
		print("%02d  turn %3d deg   eye to head %.3f m   head %+.3f m ahead of the eye"
			% [shots, int(rad_to_deg(turn)), eye.distance_to(head), ahead])
		_shot("%02d" % shots)
		shots += 1
		if shots >= 8:
			get_tree().quit()


## Keeps him running the same way across the ground whichever way he is looking: the
## referee's own controls are relative to where he faces, so the wish has to be turned
## back by however far the head has turned.
func _travel(direction: Vector3) -> void:
	var forward := Vector3(-sin(ref.yaw), 0, -cos(ref.yaw))
	var right := Vector3(cos(ref.yaw), 0, -sin(ref.yaw))
	ref.wish = Vector2(direction.dot(right), -direction.dot(forward))
