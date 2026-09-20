extends Node3D

## A keeper going for a shot.
##
##   Godot --path . --resolution 1600x900 res://dev/looks/_keeper.tscn
##
## Until 2026-09-20 a keeper who could not reach a shot standing up called `fall()` — he
## toppled over where he stood, arms by his sides, while the ball went past him. The dive
## is written now (`fb_keeper_dive`, and its mirror for the other side), and this fires a
## shot into each corner in turn to watch him go.

const SHOTS := [
	{"name": "left", "at": Vector3(0, 1.1, 2.6)},
	{"name": "right", "at": Vector3(0, 1.2, -2.6)},
	{"name": "high", "at": Vector3(0, 2.2, 2.2)},
]

var m: Match
var camera: Camera3D
var keeper: Footballer
var striker: Footballer
var at := 0
var shot := 0
var wait := 0.0
var _fired := false


func _ready() -> void:
	m = Match.new()
	m.setup(Names.team_from(0), Names.team_from(1), "town", 360.0)
	add_child(m)
	camera = Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	camera.current = true


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://dev/shots/keeper_%s_%d.png" % [name, shot])


func _process(delta: float) -> void:
	if at >= SHOTS.size():
		return
	if keeper == null:
		# The keepers only think while the ball is in play, so the kick-off has to be
		# whistled away first.
		if m.phase != Match.Phase.LIVE:
			m.whistle()
			return
		keeper = m.teams[1].keeper()
		striker = m.teams[0].players[9]
		if keeper == null:
			return
	var goal_x := m.spec.goal_line_x(-keeper.team.attack)
	var target: Vector3 = SHOTS[at].at
	target.x = goal_x
	# Behind and to the side of the keeper, where a television camera would be.
	camera.global_position = Vector3(goal_x + keeper.team.attack * 13.0, 2.6, 9.0)
	camera.look_at(Vector3(goal_x, 1.0, 0))

	if not _fired:
		_fired = true
		keeper.global_position = Vector3(goal_x + keeper.team.attack * 0.6, 0, 0)
		keeper.velocity = Vector3.ZERO
		keeper.state = Footballer.State.PLAY
		keeper.face_point = Vector3(goal_x + keeper.team.attack * 16.0, 0, 0)
		striker.global_position = Vector3(goal_x + keeper.team.attack * 16.0, 0, 0)
		m.ball.place(striker.global_position + Vector3(0, 0.3, 0))
		var flight := target - m.ball.global_position
		var time := flight.length() / 24.0
		var speed := flight / time + Vector3(0, 0.5 * Ball.GRAVITY * time, 0)
		# Struck, not carried: leaving anybody holding it means the AI takes it back and
		# dribbles away with what was supposed to be a shot.
		m.ai.carrier = null
		m.ball.carrier = null
		m.ball.kick(speed, striker, &"shot")
		striker.one_shot("kick", 0.5)
	wait += delta
	if wait > 0.13:
		wait = 0.0
		_shot(SHOTS[at].name)
		shot += 1
		if shot == 1:
			print("   phase %s, ball %.1f m out at %.1f m/s, last touch %s"
				% [Match.Phase.keys()[m.phase], absf(m.ball.global_position.x - goal_x),
				m.ball.speed(), m.ball.last_touch_kind])
		if shot >= 5:
			print("%s: keeper at %.1f m across the goal" % [SHOTS[at].name, keeper.global_position.z])
			at += 1
			shot = 0
			_fired = false
			if at >= SHOTS.size():
				get_tree().quit()
