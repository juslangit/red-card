class_name BotReferee
extends Node

## A referee for the checks: it reads the truth and does what the Laws say, a moment
## later, from a sensible position. It exists to drive whole matches headless so the
## football and the flow of the Laws can be tested without a person. It cheats — it is
## the one thing in the project allowed to read `Laws` during play.

var m: Match
var ref: Referee
var _think := 0.0
var _seen := {}
var accuracy := 1.0
var log_decisions := false
var _rng := RandomNumberGenerator.new()


func setup(match_node: Match, referee: Referee) -> void:
	m = match_node
	ref = referee
	ref.scripted = true
	_rng.seed = 7


func _physics_process(delta: float) -> void:
	if m == null:
		return
	_position()
	_think -= delta
	if _think > 0.0:
		return
	_think = 0.35
	match m.phase:
		Match.Phase.KICK_OFF:
			if m.ai.set_piece_ready:
				m.whistle()
		Match.Phase.SET_PIECE:
			if m.restart_needs_whistle and m.ai.set_piece_ready:
				m.whistle()
		Match.Phase.LIVE:
			if m.half_elapsed() >= (45.0 + m.added_minutes_owed()) * 60.0:
				m.whistle(true)
				return
			if not m.flag.is_empty():
				if m.flag.get("incident") != null:
					m.whistle()
				else:
					m.wave_flag()
				return
			for inc in m.laws.incidents:
				if _seen.has(inc) or inc.kind in [&"out", &"goal", &"dissent"]:
					continue
				if m.clock - inc.time < 0.6:
					continue
				_seen[inc] = true
				if inc.must_stop and m.clock - inc.time < inc.window:
					m.whistle()
					return
		Match.Phase.STOPPED, Match.Phase.GOAL:
			if m.half_elapsed() >= (45.0 + m.added_minutes_owed()) * 60.0:
				m.whistle(true)
				return
			var inc: Incident = m.stopped_for
			if inc == null:
				m.award(&"dropped_ball", m.laws.last_player.team if m.laws.last_player else m.teams[0])
				return
			if inc.expected_card != &"" and inc.offender != null and inc.offender.on_pitch and inc.cards_given.is_empty():
				m.show_card(inc.offender, inc.expected_card)
			var type := inc.expected_restart
			if type == &"play_on" or type == &"":
				type = &"dropped_ball"
			var team: Team = inc.expected_team if inc.expected_team != null else m.teams[0]
			if log_decisions:
				print("%5.1f  %-12s -> %s %s" % [m.match_seconds() / 60.0, inc.kind, type, team.name])
			m.award(type, team)
		Match.Phase.HALF_TIME:
			m.start_second_half()


## Runs the left diagonal, staying 15-20 m from the ball on the side away from the
## nearer assistant.
func _position() -> void:
	var b := m.ball.global_position
	var target := b + Vector3(-8.0, 0, 14.0 if b.x < 0.0 else -14.0) * Vector3(signf(b.x) if b.x != 0.0 else 1.0, 1, 1)
	target = m.spec.clamp_to_field(target, 2.0)
	var to := target - ref.global_position
	to.y = 0.0
	var look := (b - ref.global_position)
	ref.yaw = atan2(-look.x, -look.z)
	var forward := Vector3(-sin(ref.yaw), 0, -cos(ref.yaw))
	var right := Vector3(cos(ref.yaw), 0, -sin(ref.yaw))
	var local := Vector2(to.dot(right), -to.dot(forward))
	ref.wish = local.limit_length(1.0) if to.length() > 1.0 else Vector2.ZERO
	ref.wish_sprint = to.length() > 12.0
