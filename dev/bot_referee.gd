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
## A referee who does nothing at all, for checking that doing nothing fails.
var idle := false
## Stand where you were put.
var stay := false
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
	if idle:
		ref.wish = Vector2.ZERO
		return
	if not stay:
		_position()
	else:
		ref.wish = Vector2.ZERO
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
				# A foul where the fouled team is still going: play advantage.
				if inc.kind == &"foul" and inc.victim != null and inc.victim.state != Footballer.State.FALLEN \
						and m.ai.possession == inc.victim.team.index:
					m.signal_advantage()
					continue
				if inc.must_stop and m.clock - inc.time < inc.window:
					m.whistle()
					return
			# The ball hit the referee and it mattered: stop for a dropped ball.
			for inc in m.laws.incidents:
				if inc.kind == &"hit_referee" and inc.must_stop and not inc.whistled and m.clock - inc.time < 6.0:
					m.whistle()
					return
		Match.Phase.STOPPED, Match.Phase.GOAL:
			if not m.sub_request.is_empty():
				m.allow_substitution()
			if m.half_elapsed() >= (45.0 + m.added_minutes_owed()) * 60.0:
				m.whistle(true)
				return
			# Cards still owed from earlier — after advantage, or for dissent.
			for owed in m.laws.incidents:
				if m.clock - owed.time > 90.0 or owed.offender == null or not owed.offender.on_pitch:
					continue
				var due := owed.expected_card
				if owed.advantage and owed.spa and not owed.dogso and owed.severity < Laws.Severity.RECKLESS:
					due = &""
				if due != &"" and owed.cards_given.is_empty() and owed != m.stopped_for:
					m.show_card(owed.offender, due)
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
