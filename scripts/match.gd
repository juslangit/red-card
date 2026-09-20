class_name Match
extends Node3D

## A football match, from the first whistle to the last.
##
## The match owns the pitch, the ball, the twenty-two players, the officials and the
## clock, and runs the phases of play. It is where the referee's decisions land: every
## whistle, point, card and flag comes in through the functions under "The referee's
## decisions", is attached to the incident it answers, and changes what the players do
## next. The players obey the referee — even when he is wrong, which is the point. The
## truth stays in `Laws`, and the verdicts are the `Assessor`'s.

enum Phase { PRE_MATCH, KICK_OFF, LIVE, STOPPED, SET_PIECE, GOAL, HALF_TIME, FULL_TIME, REVIEW }

signal phase_changed(phase: Phase)
signal decision_made(text: String, good: bool)
signal scored(team: Team)
signal card_shown(player: Footballer, colour: StringName)
signal half_ended(half: int)
signal message(text: String, seconds: float)

## Real seconds per half. 45 match minutes are squeezed into this. Luqman chose short
## halves; six real minutes is the default and the settings screen offers five to eight.
var half_seconds := 360.0
var level_id := "village"
var level: Dictionary
var spec: PitchSpec
var venue: Venue
var ball: Ball
var teams: Array[Team] = []
var players: Array = []
var referee: Node3D = null
var assistants: Array = []
var ai: MatchAI
var laws: Laws
var assessor: Assessor
var recorder: Recorder
var var_system = null

var phase := Phase.PRE_MATCH
var half := 1
## Seconds since the match began, running through stoppages the way a football clock does.
var clock := 0.0
var half_started_at := 0.0
var added_announced := -1
## Time lost this half, in match seconds, which is what added time is made of.
var lost_seconds := 0.0
var _phase_time := 0.0

## The restart the referee has given and the players are setting up for.
var restart: Dictionary = {}
var restart_needs_whistle := false
## The incident the current stoppage is answering, if any.
var stopped_for: Incident = null
var stop_time := 0.0
var advantage_for: Incident = null
var advantage_time := -100.0
var kick_off_team: Team

## Flags raised by assistants and not yet dealt with: {assistant, incident or null, kind}.
var flag: Dictionary = {}

## In training and scenarios every restart waits for the whistle, so there is always
## time to show a card before play goes on.
var whistle_every_restart := false
## True while VAR is checking: the restart waits.
var var_hold := false

## A team waiting to make a substitution: {team, off, on_name, asked_at, stoppages}.
var sub_request: Dictionary = {}
var _next_sub_check := 0.0

var captions: Captions
var sound: SoundBank
var paused := false
var headless := false


func setup(home: Team, away: Team, at_level: String, seconds_per_half: float) -> void:
	level_id = at_level
	half_seconds = seconds_per_half
	teams = [home, away]
	home.index = 0
	away.index = 1
	home.attack = 1
	away.attack = -1


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	venue = Venue.new()
	venue.name = "Venue"
	add_child(venue)
	venue.build(level_id)
	level = venue.level
	spec = venue.spec
	venue.stands.set_colours(teams[0].shirt, teams[0].shorts, teams[1].shirt, teams[1].shorts)

	ball = Ball.new()
	ball.name = "Ball"
	ball.spec = spec
	ball.woodwork = venue.woodwork
	add_child(ball)

	laws = Laws.new(self)
	ai = MatchAI.new(self)
	assessor = Assessor.new(self)
	recorder = Recorder.new(self)
	ball.touched.connect(_on_touch)
	ball.went_out.connect(_on_out)
	ball.hit_referee.connect(_on_hit_referee)
	laws.recorded.connect(_on_incident)

	for team in teams:
		_field_team(team)
	captions = Captions.new()
	captions.name = "Captions"
	add_child(captions)
	sound = SoundBank.new()
	sound.name = "Sound"
	add_child(sound)
	sound.start_bed(level)

	for side in [-1, 1]:
		var ar := Assistant.new()
		ar.setup(self, side, level.assistants)
		add_child(ar)
		assistants.append(ar)
	laws.offside_moment.connect(func(team, positions):
		for ar in assistants:
			ar.on_offside_moment(team, positions))
	laws.recorded.connect(func(inc):
		for ar in assistants:
			ar.on_incident(inc))
	if level.var:
		var_system = VarSystem.new(self)
	kick_off_team = teams[0]
	_line_up_for_kick_off(kick_off_team)


func _field_team(team: Team) -> void:
	var names := Names.squad(team.name, 11)
	for i in Team.FORMATION_442.size():
		var slot: Dictionary = Team.FORMATION_442[i]
		var p := Footballer.new()
		p.setup(team, slot.num, slot.role, names[i])
		p.slot = i
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(team.name) + slot.num * 31
		p.pace = rng.randf_range(6.9, 8.4) - (0.6 if slot.role == Footballer.Role.GK else 0.0)
		p.skill = clampf(rng.randf_range(0.45, 0.8) + team.get_meta("quality", 0.0), 0.2, 0.95)
		p.aggression = clampf(team.aggression + rng.randf_range(-0.25, 0.25), 0.05, 0.95)
		p.honesty = clampf(team.honesty + rng.randf_range(-0.25, 0.2), 0.05, 1.0)
		add_child(p)
		p.global_position = team.to_world(slot.u * 0.9, slot.v, spec)
		p.heading = Vector3(team.attack, 0, 0)
		players.append(p)
		team.players.append(p)


func attach_referee(ref: Node3D) -> void:
	referee = ref
	ball.referee = ref


# --- the clock --------------------------------------------------------------------------

## Match minutes per real second.
func clock_scale() -> float:
	return 45.0 * 60.0 / half_seconds


## The match minute, the way the watch shows it: 0 to 45 in the first half, 45 to 90 in
## the second, running on past 45 or 90 into added time.
func match_seconds() -> float:
	return (clock - half_started_at) * clock_scale() + (45.0 * 60.0 if half == 2 else 0.0)


func match_minute() -> int:
	return int(match_seconds() / 60.0)


## How far into its own half the match is, in match seconds.
func half_elapsed() -> float:
	return (clock - half_started_at) * clock_scale()


## The added time the truth calls for: every half-minute lost, rounded up to the minute.
## Law 7 lists what it covers — substitutions, injuries, wasting time, cards, goal
## celebrations, VAR — and the referee is expected to add it.
func added_minutes_owed() -> int:
	return maxi(1, int(ceil(lost_seconds / 60.0)))


func is_live() -> bool:
	return phase == Phase.LIVE


# --- the loop ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if paused or phase == Phase.REVIEW:
		return
	if phase in [Phase.LIVE, Phase.STOPPED, Phase.SET_PIECE, Phase.GOAL, Phase.KICK_OFF]:
		clock += delta
	ball.clock = clock
	_phase_time += delta
	match phase:
		Phase.LIVE:
			ai.step(delta)
			ball.step(delta)
			_watch_advantage()
			_watch_injuries(delta)
		Phase.STOPPED, Phase.GOAL:
			_idle_players(delta)
			ball.step(delta)
			if _phase_time > 25.0:
				lost_seconds += delta * clock_scale()
		Phase.SET_PIECE, Phase.KICK_OFF:
			var ready := ai.step_set_piece(delta)
			if phase == Phase.SET_PIECE and _phase_time > 30.0:
				lost_seconds += delta * clock_scale()
			if ready and not restart_needs_whistle and not var_hold:
				_take_restart()
			ai._separate()
		Phase.HALF_TIME, Phase.FULL_TIME, Phase.PRE_MATCH:
			_idle_players(delta)
	for p: Footballer in players:
		p.step(delta)
	for ar in assistants:
		ar.step(delta)
	recorder.step(delta)
	assessor.step(delta)
	if var_system != null:
		var_system.step(delta)
	_nag_about_time()
	_substitutions()


## From the 55th minute each side may want to change somebody — the most tired, as a
## manager would. The request waits at the halfway line until the referee allows it at a
## stoppage (Law 3: a substitution is made only when the ball is out of play, with the
## referee's permission).
func _substitutions() -> void:
	if not sub_request.is_empty() or match_seconds() < 55.0 * 60.0 or clock < _next_sub_check:
		return
	if phase in [Phase.HALF_TIME, Phase.FULL_TIME, Phase.PRE_MATCH]:
		return
	_next_sub_check = clock + half_seconds * 0.12
	for team in teams:
		if team.subs_used >= 3 or randf() > 0.5:
			continue
		var tired: Array = team.on_field().filter(func(p): return not p.is_keeper() and p.state == Footballer.State.PLAY)
		if tired.is_empty():
			continue
		tired.sort_custom(func(a, b): return a.stamina < b.stamina)
		var off: Footballer = tired[0]
		var bench := Names.squad(team.name + " bench", 5)
		sub_request = {"team": team, "off": off, "on_name": bench[team.subs_used], "asked_at": clock, "stoppages": 0}
		var board := "Fourth official's board: " if level.fourth_official else ""
		message.emit("%sSUBSTITUTION — %s #%d off. Allow it at a stoppage (U)" % [board, team.short, off.number], 6.0)
		return


## The referee waves the substitute on.
func allow_substitution() -> void:
	if sub_request.is_empty():
		return
	if phase not in [Phase.STOPPED, Phase.SET_PIECE, Phase.GOAL, Phase.KICK_OFF]:
		message.emit("Substitutions only when the ball is out of play", 2.5)
		return
	var team: Team = sub_request.team
	var off: Footballer = sub_request.off
	if not off.on_pitch:
		sub_request = {}
		return
	var slot := off.slot
	off.leave(Vector3(off.global_position.x * 0.2, 0, -spec.half_width() - 3.0))
	var on := Footballer.new()
	on.setup(team, 12 + team.subs_used, off.role, sub_request.on_name)
	on.slot = slot
	on.pace = off.pace + 0.3
	on.skill = off.skill
	on.aggression = off.aggression
	on.honesty = off.honesty
	add_child(on)
	on.global_position = Vector3(0, 0, -spec.half_width() - 0.5)
	on.heading = Vector3(0, 0, 1)
	players.append(on)
	team.players.append(on)
	team.subs_used += 1
	lost_seconds += 30.0
	assessor.note_substitution(clock - sub_request.asked_at, sub_request.stoppages)
	message.emit("%s #%d on for #%d" % [team.short, on.number, off.number], 3.0)
	sub_request = {}


func _idle_players(_delta: float) -> void:
	for p: Footballer in players:
		if not p.can_move():
			continue
		if p.state == Footballer.State.PROTESTING and referee != null:
			var to_ref: Vector3 = referee.global_position - p.global_position
			p.goal = referee.global_position - to_ref.normalized() * 1.6
			p.hurry = 0.7
			p.face_point = referee.global_position
			continue
		# Players drift, slow down and watch the referee.
		p.goal = p.global_position + p.velocity * 0.3
		p.hurry = 0.25
		if referee != null:
			p.face_point = referee.global_position
	ai._separate()


func _set_phase(new_phase: Phase) -> void:
	if new_phase == Phase.LIVE and phase in [Phase.SET_PIECE, Phase.KICK_OFF] and not sub_request.is_empty():
		sub_request.stoppages += 1
	phase = new_phase
	_phase_time = 0.0
	phase_changed.emit(new_phase)


# --- things happening -------------------------------------------------------------------

func _on_touch(by: Node, kind: StringName) -> void:
	laws.on_touch(by, kind)
	_settle_ref_touch(by, kind)
	recorder.mark(&"touch")


func _on_out(where: Vector3, over_goal_line: bool, in_goal: bool) -> void:
	if phase != Phase.LIVE:
		return
	ai.carrier = null
	var incident := laws.on_out(where, over_goal_line, in_goal)
	stopped_for = incident
	stop_time = clock
	if in_goal:
		_set_phase(Phase.GOAL)
		var scoring: Team = incident.details.scoring
		var disallowable: bool = incident.details.has("cancelled_by")
		for p: Footballer in scoring.on_field():
			if p.global_position.distance_to(ball.global_position) < 40.0:
				p.celebrate(6.0)
		sound.roar(scoring == teams[0])
		venue.stands.set_excitement(1.0 if scoring == teams[0] else 0.0, 1.0 if scoring == teams[1] else 0.0)
		message.emit("GOAL? — point to the centre circle to give it", 5.0)
	else:
		_set_phase(Phase.STOPPED)
		if var_system != null:
			var_system.on_stoppage()
	for ar in assistants:
		ar.on_out(incident)
	var said: Team = incident.details.get("assistant_said")
	var who = incident.details.get("assistant")
	if said != null and who != null:
		captions.say(who.body, "OUT · %s" % said.short, UiTheme.ACCENT)


func _on_hit_referee(speed: float) -> void:
	if phase != Phase.LIVE:
		return
	_ref_touch = laws.referee_touch(ball.global_position)
	sound.thud(ball.global_position)


## Law 9.2 asks what happened *next*: did the other team get the ball, did a team start a
## promising attack. So it is settled at the next player's controlled touch, not after a
## fixed wait — a rebound can take two seconds to reach anybody, and a fixed 1.6 s judged
## those "play on" before the ball had arrived.
var _ref_touch: Incident = null


func _settle_ref_touch(by: Node, kind: StringName) -> void:
	if _ref_touch == null or not by is Footballer:
		return
	if kind not in [&"control", &"hands"] and clock - _ref_touch.time < 5.0:
		return
	var team_now: int = (by as Footballer).team.index
	var promising := teams[team_now].to_team_space(ball.global_position, spec).x > 0.7
	laws.settle_referee_touch(_ref_touch, team_now, promising)
	_ref_touch = null


func _on_incident(incident: Incident) -> void:
	recorder.mark(incident.kind)
	if incident.kind in [&"foul", &"holding", &"handball"] and incident.victim != null:
		# The fouled side appeals: an arm up from the nearest teammate.
		var appealer: Footballer = incident.victim
		captions.say(appealer, "REF!", appealer.team.shirt)
		if appealer.state == Footballer.State.PLAY:
			appealer.arms.set_right(Vector3(0, 1, 0.2), Vector3.ZERO, 1.0)
			get_tree().create_timer(1.2).timeout.connect(func(): if is_instance_valid(appealer): appealer.arms.release_right())


## A player hurt badly enough to stay down: the truth is that play should stop.
func _watch_injuries(_delta: float) -> void:
	for p: Footballer in players:
		if p.on_pitch and p.injured and p.state == Footballer.State.FALLEN and not p.has_meta("injury_logged"):
			p.set_meta("injury_logged", true)
			laws.serious_injury(p, p.global_position)


## Advantage (Law 5.3): the advantage has to come "at that time or within a few seconds".
## Whether it did is judged two and a half seconds on — still with the ball, it came; a
## turnover later than that is the ordinary run of play, not a failed advantage (an
## earlier version checked at four seconds and marked a good advantage wrong because the
## attack broke down afterwards). Up to four seconds the referee may still go back.
func _watch_advantage() -> void:
	if advantage_for == null:
		return
	if clock - advantage_time > 2.5 and not advantage_for.details.has("advantage_realised"):
		advantage_for.details["advantage_realised"] = ai.possession == advantage_for.expected_team.index
	if clock - advantage_time > 4.0:
		advantage_for = null


func _nag_about_time() -> void:
	var elapsed := half_elapsed()
	if added_announced < 0 and elapsed >= 45.0 * 60.0 and phase != Phase.HALF_TIME and phase != Phase.FULL_TIME:
		added_announced = added_minutes_owed()
		if level.fourth_official:
			message.emit("Fourth official: added time? Press a number key (1–9)", 8.0)
	# A referee who never ends the half is ended for, badly, well after it should be over.
	if elapsed > (45.0 + added_minutes_owed() + 6.0) * 60.0 and phase in [Phase.LIVE, Phase.STOPPED, Phase.SET_PIECE]:
		assessor.note_timekeeping(elapsed / 60.0 - 45.0, added_minutes_owed(), true)
		_end_half()


# --- the referee's decisions ------------------------------------------------------------
#
# Everything here is something the referee does with their whistle, their arms or their
# cards. Each returns quickly and never checks whether the decision is right — that is
# not the match's job. The players do what they are told.

## A blast of the whistle. What it means depends on when: stopping play, starting a
## restart that needs it, or — held long after time — ending the half.
func whistle(long := false) -> void:
	sound.whistle(long)
	match phase:
		Phase.LIVE:
			if long and half_elapsed() >= 44.0 * 60.0:
				_end_half()
				return
			_stop_play()
		Phase.KICK_OFF, Phase.SET_PIECE:
			if var_hold:
				message.emit("Wait — VAR is checking", 1.5)
				return
			if restart_needs_whistle:
				restart_needs_whistle = false
				if ai.set_piece_ready or _phase_time > 2.0:
					_take_restart()
		Phase.STOPPED, Phase.GOAL:
			if long and half_elapsed() >= 44.0 * 60.0:
				_end_half()
			elif flag.has("offside") and phase == Phase.GOAL:
				accept_flag()
		_:
			pass


func _stop_play() -> void:
	# Coming back for a foul after advantage did not work out.
	var linked := _incident_for_whistle()
	stopped_for = linked
	stop_time = clock
	if linked != null:
		linked.whistled = true
		linked.whistle_time = clock
	ai.carrier = null
	_set_phase(Phase.STOPPED)
	# A flag up when the whistle goes is the flag being accepted.
	if flag.has("offside"):
		accept_flag()
	elif flag.has("foul"):
		_accept_foul_flag()
	elif var_system != null:
		var_system.on_stoppage()
	decision_made.emit("", true)


## The incident a whistle is answering: the most recent open offence still inside its
## window, preferring the most serious. Advantage that has not come back is included.
func _incident_for_whistle() -> Incident:
	var best: Incident = null
	for i in range(laws.incidents.size() - 1, -1, -1):
		var inc: Incident = laws.incidents[i]
		if clock - inc.time > maxf(inc.window, 6.0):
			break
		if inc.whistled or inc.resolved or inc.kind in [&"out", &"goal", &"dissent"]:
			continue
		if inc.advantage and clock - inc.advantage_time > 4.0:
			continue
		if clock - inc.time > inc.window and not inc.advantage:
			continue
		if best == null or inc.severity > best.severity or inc.key and not best.key:
			best = inc
	return best


## Both arms swept forward: play on, advantage (Law 5.3).
func signal_advantage() -> void:
	if phase != Phase.LIVE:
		return
	# Advantage over an assistant's foul flag acknowledges it: he lowers it.
	if flag.has("foul"):
		for ar in assistants:
			ar.lower()
		flag = {}
	for i in range(laws.incidents.size() - 1, -1, -1):
		var inc: Incident = laws.incidents[i]
		if clock - inc.time > 4.0:
			break
		if inc.kind in [&"foul", &"holding", &"handball"] and not inc.advantage:
			inc.advantage = true
			inc.advantage_time = clock
			advantage_for = inc
			advantage_time = clock
			assessor.note_advantage(inc)
			return
	assessor.note_advantage(null)


## The referee's restart. `type` is one of: free_kick, indirect_free_kick, penalty,
## throw_in, corner, goal_kick, kick_off (which awards a goal), dropped_ball.
func award(type: StringName, to: Team) -> void:
	if phase not in [Phase.STOPPED, Phase.GOAL]:
		return
	var linked := stopped_for
	var spot := _restart_spot(type, to, linked)
	if linked != null:
		linked.restart_given = type
		linked.restart_team = to
		linked.resolved = true
		linked.whistled = true
	# A goal given or taken away.
	if phase == Phase.GOAL:
		var goal_incident := linked
		if var_system != null:
			var_system.on_award(goal_incident, type, to, true)
		if type == &"kick_off":
			var scoring: Team = goal_incident.details.scoring
			scoring.goals += 1
			if goal_incident.offender != null:
				captions.say(goal_incident.offender, "GOAL!", scoring.shirt)
			scored.emit(scoring)
			lost_seconds += 45.0
			kick_off_team = to
			decision_made.emit("GOAL — %s" % scoring.name, true)
			_react_to(goal_incident)
			_line_up_for_kick_off(to)
			return
		else:
			sound.groan()
			venue.stands.set_excitement(0.0, 0.0)
			for p: Footballer in players:
				p.calm()
	_react_to(linked)
	if var_system != null and phase != Phase.GOAL:
		var_system.on_award(linked, type, to, false)
	restart = {"type": type, "team": to, "spot": spot}
	restart_needs_whistle = type in [&"penalty"] or restart.get("carded", false) or whistle_every_restart
	ai.begin_set_piece(restart)
	_set_phase(Phase.SET_PIECE)
	decision_made.emit(_restart_words(type, to), true)
	for ar in assistants:
		ar.lower()
	flag = {}


func _restart_spot(type: StringName, to: Team, linked: Incident) -> Vector3:
	var where := ball.global_position
	if linked != null:
		where = linked.position
		if linked.details.has("spot") and type == linked.expected_restart:
			return linked.details.spot
	match type:
		&"penalty":
			return spec.penalty_spot(to.attack)
		&"throw_in":
			return spec.throw_in_spot(ball.global_position if linked == null else linked.position)
		&"corner":
			var end := to.attack
			return spec.corner_for(ball.global_position, end)
		&"goal_kick":
			return spec.goal_kick_spot(ball.global_position, -to.attack)
		&"kick_off":
			return Vector3.ZERO
		&"indirect_free_kick", &"free_kick":
			# A free kick to the attacking team inside the goal area is taken from the
			# goal-area line (Law 13); one to the defenders anywhere in their goal area.
			var p := spec.clamp_to_field(where, 1.0)
			if spec.in_goal_area(p, to.attack):
				p.x = spec.goal_line_x(to.attack) - PitchSpec.GOAL_AREA_DEPTH * to.attack
			# A direct free kick given inside the offender's area is not a penalty unless
			# the referee says so; if he gives a free kick there, it goes on the edge.
			if type == &"free_kick" and spec.in_penalty_area(p, to.attack):
				p.x = spec.goal_line_x(to.attack) - (PitchSpec.PENALTY_AREA_DEPTH + 0.5) * to.attack
			return p
	return spec.clamp_to_field(where, 1.0)


func _restart_words(type: StringName, to: Team) -> String:
	var names := {
		&"free_kick": "Free kick", &"indirect_free_kick": "Indirect free kick",
		&"penalty": "PENALTY", &"throw_in": "Throw-in", &"corner": "Corner",
		&"goal_kick": "Goal kick", &"dropped_ball": "Dropped ball", &"kick_off": "Kick-off",
	}
	return "%s — %s" % [names.get(type, String(type)), to.name]


## A card, shown to the player the referee is looking at. Cards are only shown when the
## ball is out of play (Law 12.3 — after advantage, at the next stoppage).
func show_card(player: Footballer, colour: StringName) -> void:
	if phase not in [Phase.STOPPED, Phase.SET_PIECE, Phase.GOAL]:
		return
	if player == null or not player.on_pitch:
		return
	var actual := Laws.card_for(player, colour)
	if actual == &"yellow":
		player.yellow_cards += 1
	elif actual == &"second_yellow":
		player.yellow_cards += 1
		_send_off(player)
	else:
		_send_off(player)
	assessor.note_card(player, actual)
	captions.say(player, {&"yellow": "YELLOW", &"red": "RED", &"second_yellow": "SECOND YELLOW"}.get(actual, "CARD"),
		UiTheme.YELLOW if actual == &"yellow" else UiTheme.RED)
	card_shown.emit(player, actual)
	if var_system != null and not assessor.cards.is_empty():
		var_system.on_card(player, &"red" if actual in [&"red", &"second_yellow"] and colour == &"red" else actual, assessor.cards.back().incident)
	lost_seconds += 20.0
	# After a card the restart needs the whistle (Law 5).
	restart["carded"] = true
	restart_needs_whistle = phase == Phase.SET_PIECE or restart_needs_whistle
	if phase == Phase.SET_PIECE:
		restart_needs_whistle = true
	sound.crowd_reacts(0.6)


func _send_off(player: Footballer) -> void:
	player.sent_off = true
	var exit := Vector3(player.global_position.x * 0.3, 0, -spec.half_width() - 3.0)
	player.leave(exit)
	if ai.carrier == player:
		ai.carrier = null


## An assistant's flag is up for offside and the referee agrees.
func accept_flag() -> void:
	if not flag.has("offside"):
		return
	var inc: Incident = flag.get("incident")
	if phase == Phase.LIVE:
		stopped_for = inc
		stop_time = clock
		_set_phase(Phase.STOPPED)
	if inc != null:
		inc.whistled = true
		stopped_for = inc
	var offender: Footballer = flag.offender
	assessor.note_flag(flag, true)
	var to: Team = teams[1] if offender.team == teams[0] else teams[0]
	var goal_phase := phase == Phase.GOAL
	if goal_phase:
		phase = Phase.STOPPED
	stopped_for = inc if inc != null else stopped_for
	if inc == null:
		# A flag with no offside behind it: the assistant was wrong and the referee went
		# with him. The restart is still what the flag said.
		pass
	restart = {}
	_award_flag_restart(offender, to, inc)


func _award_flag_restart(offender: Footballer, to: Team, inc: Incident) -> void:
	var at: Vector3 = flag.get("where", offender.global_position)
	phase = Phase.STOPPED
	if inc != null:
		inc.restart_given = &"indirect_free_kick"
		inc.restart_team = to
		inc.resolved = true
	restart = {"type": &"indirect_free_kick", "team": to, "spot": spec.clamp_to_field(at, 1.0)}
	restart_needs_whistle = whistle_every_restart
	for ar in assistants:
		ar.lower()
	flag = {}
	ai.begin_set_piece(restart)
	_set_phase(Phase.SET_PIECE)
	decision_made.emit(_restart_words(&"indirect_free_kick", to) + " (offside)", true)


## A foul flag accepted: the stoppage is for the assistant's foul, and he points the way
## the free kick goes. The referee still gives the restart (and any card) himself.
func _accept_foul_flag() -> void:
	var inc: Incident = flag.get("incident")
	var ar = flag.get("assistant")
	assessor.note_flag(flag, true)
	if inc != null:
		inc.whistled = true
		inc.whistle_time = clock
		stopped_for = inc
		var to: Team = teams[1] if inc.offender.team == teams[0] else teams[0]
		for other in assistants:
			if other != ar:
				other.lower()
		ar.point_restart(to)
		message.emit("Assistant: foul by %s #%d — his flag points %s's way" % [inc.offender.team.short, inc.offender.number, to.name], 4.0)
	flag = {}


## The referee waves the flag down: play on. `ignored` is the assistant giving up on a
## flag nobody acknowledged, which leaves play going on but is not a decision.
func wave_flag(ignored := false) -> void:
	if flag.is_empty():
		return
	assessor.note_flag(flag, false, ignored)
	for ar in assistants:
		ar.lower()
	flag = {}


## Called by an assistant raising the flag.
func raise_flag(assistant, kind: StringName, offender: Footballer, inc: Incident) -> void:
	flag = {"assistant": assistant, "kind": kind, "offender": offender, "incident": inc,
		"where": offender.global_position, "time": clock}
	flag[String(kind)] = true
	captions.say(assistant.body, "OFFSIDE!" if kind == &"offside" else "FOUL!", UiTheme.ACCENT)
	sound.flag_beep()


func set_added_time(minutes: int) -> void:
	assessor.note_added_time(minutes, added_minutes_owed())
	added_announced = minutes
	message.emit("+%d" % minutes, 4.0)
	venue.stands.big_screens.map(func(s): s.text = "+%d" % minutes)


# --- restarts ---------------------------------------------------------------------------

func _take_restart() -> void:
	if phase == Phase.KICK_OFF and restart.is_empty():
		return
	if ai.set_piece.is_empty():
		return
	ai.take_set_piece()
	restart = {}
	stopped_for = null
	_set_phase(Phase.LIVE)
	for p: Footballer in players:
		p.calm()
		if p.injured:
			p.get_up()
	venue.stands.set_excitement(0.0, 0.0)


## Straight into open play with everybody where a scenario put them — no kick-off.
func begin_open_play() -> void:
	ai.set_piece = {}
	restart = {}
	restart_needs_whistle = false
	ball.held = false
	ball.in_play = true
	_set_phase(Phase.LIVE)


## Sets up a different restart after a VAR correction.
func redo_restart(type: StringName, to: Team, where: Vector3) -> void:
	for p in players:
		p.calm()
	if type == &"kick_off":
		_line_up_for_kick_off(to)
		return
	var spot := spec.clamp_to_field(where, 1.0)
	if type == &"penalty":
		spot = spec.penalty_spot(to.attack)
	elif type == &"free_kick" and spec.in_penalty_area(spot, to.attack):
		spot.x = spec.goal_line_x(to.attack) - (PitchSpec.PENALTY_AREA_DEPTH + 0.5) * to.attack
	restart = {"type": type, "team": to, "spot": spot}
	restart_needs_whistle = true
	ai.begin_set_piece(restart)
	_set_phase(Phase.SET_PIECE)
	decision_made.emit(_restart_words(type, to), true)


func _line_up_for_kick_off(team: Team) -> void:
	for p: Footballer in players:
		p.calm()
	restart = {"type": &"kick_off", "team": team, "spot": Vector3.ZERO}
	restart_needs_whistle = true
	ai.begin_set_piece(restart)
	ball.place(Vector3.ZERO)
	_set_phase(Phase.KICK_OFF)


func _end_half() -> void:
	var elapsed := half_elapsed() / 60.0 - 45.0
	assessor.note_timekeeping(elapsed, added_minutes_owed(), false)
	sound.whistle(true)
	half_ended.emit(half)
	if half == 1:
		_set_phase(Phase.HALF_TIME)
	else:
		_set_phase(Phase.FULL_TIME)
		assessor.finish()


## Out for the second half: change ends, the other team kicks off (Law 8).
func start_second_half() -> void:
	half = 2
	half_started_at = clock
	lost_seconds = 0.0
	added_announced = -1
	for team in teams:
		team.attack = -team.attack
	for p: Footballer in players:
		if p.on_pitch:
			p.global_position.x = -p.global_position.x
	kick_off_team = teams[1]
	_line_up_for_kick_off(kick_off_team)


# --- what the referee can see -----------------------------------------------------------

## How good the referee's view of a point is: 1 clear, lower when players stand in the
## line of sight, lower still from far away. Used for the report, never for the call.
func view_quality(where: Vector3) -> float:
	if referee == null:
		return 1.0
	var eye: Vector3 = referee.global_position
	var d := eye.distance_to(where)
	var blocked := 0
	for p: Footballer in players:
		if not p.on_pitch:
			continue
		var to_p: Vector3 = p.global_position - eye
		var along := to_p.dot((where - eye).normalized())
		if along <= 1.0 or along >= d - 1.0:
			continue
		var off := (to_p - (where - eye).normalized() * along).length()
		if off < 0.5:
			blocked += 1
	return clampf(1.0 - blocked * 0.3 - maxf(d - 25.0, 0.0) / 50.0, 0.0, 1.0)


# --- reactions --------------------------------------------------------------------------

## Players and the crowd respond to a decision. A decision the losing side can argue with
## draws a protest; a plainly wrong one draws a bigger one, and a hot head can go too far.
func _react_to(incident: Incident) -> void:
	var verdict := assessor.quick_verdict(incident)
	if verdict == 0:
		return
	var aggrieved: Team = null
	if incident != null and incident.restart_team != null:
		aggrieved = teams[1] if incident.restart_team == teams[0] else teams[0]
	if aggrieved == null:
		return
	var count := 1 if verdict > 0 else 3
	var protesters := aggrieved.on_field().filter(func(p): return not p.is_keeper() and p.state == Footballer.State.PLAY)
	if referee == null:
		return
	protesters.sort_custom(func(a, b): return a.global_position.distance_to(referee.global_position) < b.global_position.distance_to(referee.global_position))
	for i in mini(count, protesters.size()):
		var p: Footballer = protesters[i]
		p.protest(4.0 + i)
		if i == 0:
			captions.say(p, "REF!!" if verdict < 0 else "REF!", p.team.shirt)
		if verdict < 0 and p.aggression > 0.7 and i == 0 and randf() < 0.5:
			laws.dissent(p)
			p.set_meta("dissent", clock)
	if verdict < 0:
		sound.boo(aggrieved == teams[0])
	else:
		sound.crowd_reacts(0.3)


func sound_kick(where: Vector3, speed: float) -> void:
	if sound != null:
		sound.kick(where, speed)


func on_played(p: Footballer, kind: StringName) -> void:
	pass
