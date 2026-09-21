extends Node3D

## Does the restart happen where the offence did?
##
##     Godot --headless --path . res://dev/checks/_restart_spot.tscn
##
## Luqman played a match on 2026-09-21 and said the free kick did not start where the foul
## was. It did not, for two reasons, and this measures both:
##
##   the ball rolls on   the restart is given when the referee points, which can be several
##                       seconds after the whistle, and the ball is still rolling. Anything
##                       worked out from where the ball *is* — a corner, a goal kick — was
##                       worked out from the wrong place.
##   the box             a free kick given inside the penalty area was quietly moved out to
##                       the edge of it, because a foul there ought to have been a penalty.
##                       That is the referee's mistake to make, and moving the ball twenty
##                       yards without telling him is not how to say so.
##
## Every case fouls somebody at a known spot, whistles, waits (so the ball can roll), then
## points, and checks where the ball ended up.

const CASES := [
	{"name": "midfield", "at": Vector3(-8.0, 0, 6.0)},
	{"name": "wing", "at": Vector3(14.0, 0, -26.0)},
	{"name": "edge of the box", "at": Vector3(33.0, 0, 4.0)},
	{"name": "inside the box", "at": Vector3(43.0, 0, -6.0)},
]

var m: Match
var ref: Referee
var at := 0
var step := 0
var wait := 0.0
var bad := 0
var _where := Vector3.ZERO


func _ready() -> void:
	m = Match.new()
	m.setup(Names.team_from(0), Names.team_from(1), "town", 360.0)
	add_child(m)
	ref = Referee.new()
	ref.setup(m, Game.settings)
	add_child(ref)
	ref.scripted = true
	m.attach_referee(ref)


func _process(delta: float) -> void:
	if at >= CASES.size():
		return
	wait += delta
	match step:
		0:
			if m.phase != Match.Phase.LIVE:
				m.whistle()
				return
			step = 1
			wait = 0.0
		1:
			if wait < 0.3:
				return
			# A foul on the attacker at the named spot, with the ball rolling away from it.
			var case: Dictionary = CASES[at]
			_where = case.at
			var attacker: Footballer = m.teams[0].players[9]
			var defender: Footballer = m.teams[1].players[5]
			attacker.global_position = _where
			defender.global_position = _where + Vector3(-0.9, 0, 0.2)
			m.ai.give_ball(attacker)
			m.ball.place(_where + Vector3(0, 0.3, 0))
			m.ai.carrier = null
			m.ball.carrier = null
			m.ball.kick(Vector3(-14.0, 0.2, 9.0), attacker, &"pass")
			m.ai.force_foul(defender, attacker, Laws.Severity.CARELESS, false, false, false)
			step = 2
			wait = 0.0
		2:
			# The referee whistles a moment later, and points a moment after that — all the
			# while the ball is rolling away.
			if wait > 0.6:
				m.whistle()
				step = 3
				wait = 0.0
		3:
			if wait > 1.2:
				m.award(&"free_kick", m.teams[0])
				step = 4
				wait = 0.0
		4:
			if wait < 0.2:
				return
			var ball_at: Vector3 = m.ball.global_position
			var off_by := Vector2(ball_at.x - _where.x, ball_at.z - _where.z).length()
			var rolled := Vector2(ball_at.x - m.stopped_ball_at.x, ball_at.z - m.stopped_ball_at.z).length()
			var right := off_by < 1.5
			if not right:
				bad += 1
			print("%s %-16s foul at (%.1f, %.1f), kick at (%.1f, %.1f) — %.1f m out"
				% ["    " if right else "BAD ", CASES[at].name, _where.x, _where.z,
				ball_at.x, ball_at.z, off_by])
			at += 1
			step = 0
			wait = 0.0
			if at >= CASES.size():
				print("%d restart(s) in the wrong place" % bad)
				get_tree().quit(1 if bad > 0 else 0)
