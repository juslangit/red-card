extends Node3D

## The referee's own view at the moments that matter, as screenshots:
##   Godot --path . --resolution 1600x900 res://dev/looks/_fp.tscn -- town

var m: Match
var ref: Referee
var hud: Hud
var step := 0
var wait := 0.0
var level := "town"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	level = args[0] if args.size() > 0 else "town"
	m = Match.new()
	m.setup(Names.team_from(0), Names.team_from(1), level, 360.0)
	add_child(m)
	ref = Referee.new()
	ref.setup(m, Game.settings)
	add_child(ref)
	ref.global_position = Vector3(-4, 0, 12)
	ref.scripted = true
	m.attach_referee(ref)
	hud = Hud.new()
	hud.setup(m, ref, Game.settings)
	add_child(hud)
	ref.yaw = atan2(4.0, 12.0) + PI


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://dev/shots/fp_%s_%s.png" % [level, name])


func _process(delta: float) -> void:
	wait += delta
	match step:
		0:
			if wait > 2.5:
				_shot("kickoff")
				ref.pitch = deg_to_rad(-58.0); ref.wish = Vector2(0, -0.7)
				step = 1
				wait = 0.0
		1:
			if wait > 0.6:
				_shot("down"); ref.wish = Vector2.ZERO
				ref.pitch = deg_to_rad(-6.0)
				m.whistle()
				step = 2
				wait = 0.0
		2:
			# Follow the ball for a while.
			var to := m.ball.global_position - ref.global_position
			ref.yaw = atan2(-to.x, -to.z)
			ref.wish = Vector2(0, -0.6) if to.length() > 18.0 else Vector2.ZERO
			if wait > 7.0:
				_shot("live")
				# Force a foul right in front of us and blow for it.
				var att: Footballer = m.teams[0].players[9]
				var dfn: Footballer = m.teams[1].players[5]
				att.global_position = ref.global_position + Vector3(9, 0, -4)
				dfn.global_position = att.global_position + Vector3(-0.9, 0, 0.2)
				m.ai.give_ball(att)
				m.ai.force_foul(dfn, att, Laws.Severity.RECKLESS, true, true, false)
				step = 3
				wait = 0.0
		3:
			if wait > 1.0:
				m.whistle()
				ref.yaw = -PI * 0.5
				ref.pitch = deg_to_rad(-4.0)
				step = 4
				wait = 0.0
		4:
			if wait > 0.8:
				_shot("point")
				ref.point()
				step = 5
				wait = 0.0
		5:
			if wait > 0.8:
				var dfn: Footballer = m.teams[1].players[5]
				var to := dfn.global_position + Vector3(0, 1.2, 0) - ref.camera.global_position
				ref.yaw = atan2(-to.x, -to.z)
				ref.pitch = asin(to.normalized().y)
				step = 6
				wait = 0.0
		6:
			if wait > 0.5:
				_shot("target")
				ref.card(&"yellow")
				step = 7
				wait = 0.0
		7:
			if wait > 0.5:
				_shot("card")
				ref.force_watch = true
				step = 8
				wait = 0.0
		8:
			if wait > 1.2:
				_shot("watch")
				get_tree().quit()
