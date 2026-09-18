class_name Laws
extends RefCounted

## The truth, and the Laws of the Game applied to it.
##
## This is the referee the player is being compared with: one who sees everything and
## knows the book. It watches every touch of the ball and every challenge the AI makes,
## and writes each thing the Laws have an answer for down as an `Incident` with the right
## answer attached — before the player has had a chance to react.
##
## The same rule as Referee For Fun: **nothing drawn to the player's screen during the
## match may read this.** The player sees the pitch and nothing else, and finds out what
## was true in the assessor's report.
##
## Law references are to the IFAB Laws of the Game.

enum Severity { NONE, CARELESS, RECKLESS, EXCESSIVE }

signal recorded(incident: Incident)
## Every time the ball is played by a team, and who in the other team's half was in an
## offside position at that moment, with how far (metres, positive = offside). The
## assistant referees read this to decide whether to flag.
signal offside_moment(team: Team, positions: Dictionary)

var m  # the Match
var incidents: Array[Incident] = []

## Offside (Law 11): who was in an offside position when the ball was last played by
## their team, and which team that was. Cleared when an opponent deliberately plays it.
var _offside_team: Team = null
var _offside_positions := {}
## The last *player* to touch the ball, which decides restarts. The referee touching it
## does not change who put it out (Law 9 treats the ball hitting an official separately).
var last_player: Footballer = null
var _possession_before_ref := -1


func _init(match_node) -> void:
	m = match_node


func spec() -> PitchSpec:
	return m.spec


func _new(kind: StringName, where: Vector3) -> Incident:
	var incident := Incident.new()
	incident.kind = kind
	incident.time = m.clock
	incident.minute = m.match_minute()
	incident.position = where
	var ref: Node3D = m.referee
	if ref != null:
		incident.ref_distance = ref.global_position.distance_to(where)
		incident.ref_view = m.view_quality(where)
	return incident


func _commit(incident: Incident) -> Incident:
	incidents.append(incident)
	recorded.emit(incident)
	return incident


# --- touches: offside and who played it last --------------------------------------------

func on_touch(by: Node, kind: StringName) -> void:
	if not by is Footballer:
		if by == m.referee:
			_possession_before_ref = m.ai.possession
		return
	var p: Footballer = by
	# An offside player becoming involved: the first touch by a teammate who was in an
	# offside position when the ball was last played.
	if _offside_team != null and p.team == _offside_team and _offside_positions.has(p) \
			and _offside_positions[p] > 0.0 and kind != &"kick_off":
		_offside(p, _offside_positions[p])
	# An opponent deliberately playing the ball resets offside. A deflection or a save does
	# not (Law 11.2).
	if _offside_team != null and p.team != _offside_team and kind not in [&"block", &"save", &"handball"]:
		_offside_team = null
		_offside_positions.clear()
	last_player = p
	# A new moment of play: note who is where.
	if kind in [&"pass", &"shot", &"header", &"clearance", &"free_kick", &"kick_off", &"throw", &"dropped_ball", &"tackle"]:
		_snapshot(p.team)
	elif kind in [&"throw_in", &"corner", &"goal_kick"]:
		# No offence directly from these restarts (Law 11.3).
		_offside_team = null
		_offside_positions.clear()


## Who in `team` is in an offside position right now, and by how much. Law 11.1: in the
## opponents' half, and nearer the opponents' goal line than both the ball and the
## second-last opponent. Level is onside.
func _snapshot(team: Team) -> void:
	var s := team.attack
	var ball_x: float = m.ball.global_position.x * s
	var theirs: Array = []
	for q: Footballer in m.players:
		if q.on_pitch and q.team != team:
			theirs.append(q.global_position.x * s)
	theirs.sort()
	var second_last: float = theirs[theirs.size() - 2] if theirs.size() >= 2 else spec().half_length()
	var line := maxf(second_last, ball_x)
	var positions := {}
	for p: Footballer in m.players:
		if not p.on_pitch or p.team != team:
			continue
		var x: float = p.global_position.x * s
		if x <= 0.0:
			continue  # own half, or on the halfway line
		positions[p] = x - line
	_offside_team = team
	_offside_positions = positions
	offside_moment.emit(team, positions)


func _offside(p: Footballer, margin: float) -> void:
	var incident := _new(&"offside", p.global_position)
	incident.offender = p
	incident.details = {"margin": margin}
	incident.expected_restart = &"indirect_free_kick"
	incident.expected_team = _other(p.team)
	incident.window = 4.0
	incident.key = margin < 0.4
	_offside_team = null
	_offside_positions.clear()
	_commit(incident)


# --- the ball leaving the field ---------------------------------------------------------

func on_out(where: Vector3, over_goal_line: bool, in_goal: bool) -> Incident:
	var by := last_player
	if in_goal:
		return _goal(where)
	var incident := _new(&"out", where)
	incident.offender = by
	incident.window = 999.0
	incident.details = {"goal_line": over_goal_line}
	if not over_goal_line:
		incident.expected_restart = &"throw_in"
		incident.expected_team = _other(by.team) if by != null else m.teams[0]
		incident.details["spot"] = spec().throw_in_spot(where)
	else:
		var end := 1 if where.x > 0.0 else -1
		# Whose goal line it is: the team defending that end.
		var defending: Team = m.teams[0] if m.teams[0].attack == -end else m.teams[1]
		if by != null and by.team == defending:
			incident.expected_restart = &"corner"
			incident.expected_team = _other(defending)
			incident.details["spot"] = spec().corner_for(where, end)
		else:
			incident.expected_restart = &"goal_kick"
			incident.expected_team = defending
			incident.details["spot"] = spec().goal_kick_spot(where, end)
	return _commit(incident)


## Law 10. A goal stands unless the scoring team committed an offence in the move that
## has not been dealt with — an offside, a foul, a handball — in which case the right
## answer is that offence's restart instead.
func _goal(where: Vector3) -> Incident:
	var end := 1 if where.x > 0.0 else -1
	var conceding: Team = m.teams[0] if m.teams[0].attack == -end else m.teams[1]
	var scoring := _other(conceding)
	var incident := _new(&"goal", where)
	incident.offender = last_player
	incident.details = {"scoring": scoring, "own_goal": last_player != null and last_player.team == conceding}
	incident.window = 999.0
	incident.key = true
	incident.expected_restart = &"kick_off"
	incident.expected_team = conceding
	var cancel := _cancelling_offence(scoring)
	if cancel != null:
		incident.details["cancelled_by"] = cancel
		incident.expected_restart = cancel.expected_restart
		incident.expected_team = cancel.expected_team
		cancel.key = true
	return _commit(incident)


## An offence by the attacking team in the last few seconds that nobody has stopped play
## for — offside, a foul or a handball in the build-up.
func _cancelling_offence(scoring: Team) -> Incident:
	for i in range(incidents.size() - 1, -1, -1):
		var inc: Incident = incidents[i]
		if m.clock - inc.time > 12.0:
			break
		if inc.whistled or inc.resolved:
			continue
		if inc.offender != null and inc.offender.team == scoring and inc.kind in [&"offside", &"foul", &"holding", &"handball"]:
			return inc
	return null


# --- offences ---------------------------------------------------------------------------

## A foul (Law 12.1): careless, reckless, or using excessive force. `kind` is how it was
## committed — a tackle, holding. Works out the restart, whether it denied an obvious
## goal-scoring opportunity or stopped a promising attack, and the card.
func foul(offender: Footballer, victim: Footballer, kind: StringName, severity: Severity,
		where: Vector3, extra := {}) -> Incident:
	var incident := _new(&"foul" if kind != &"holding" else &"holding", where)
	incident.offender = offender
	incident.victim = victim
	incident.severity = severity
	incident.details = extra.duplicate()
	incident.details["how"] = kind
	_direct_restart(incident, offender, victim.team, where)
	_opportunity(incident, victim, offender, where)
	var card := &""
	var reasons := []
	if severity == Severity.RECKLESS:
		card = &"yellow"
		reasons.append("a reckless challenge")
	elif severity == Severity.EXCESSIVE:
		card = &"red"
		reasons.append("serious foul play")
	if incident.dogso:
		# Law 12.3: inside the area, an attempt to play the ball is only a caution;
		# holding, pulling or pushing is still a sending-off.
		var in_area := incident.expected_restart == &"penalty"
		var red := not in_area or kind == &"holding"
		if red:
			card = &"red"
			reasons.append("denying an obvious goal-scoring opportunity")
		elif card == &"":
			card = &"yellow"
			reasons.append("denying a goal-scoring opportunity with an attempt to play the ball")
	elif incident.spa and card == &"":
		# Law 12.3: stopping a promising attack is a caution — "except where the referee
		# awards a penalty kick for an offence which was an attempt to play the ball".
		var penalty_attempt := incident.expected_restart == &"penalty" and kind != &"holding"
		if not penalty_attempt:
			card = &"yellow"
			reasons.append("stopping a promising attack")
	incident.expected_card = card
	incident.card_reason = ", ".join(reasons)
	incident.key = incident.expected_restart == &"penalty" or card == &"red"
	# Advantage is available if the fouled team still has the ball in a useful place.
	return _commit(incident)


func handball(offender: Footballer, from_player: Footballer, where: Vector3, extra := {}) -> Incident:
	var incident := _new(&"handball", where)
	incident.offender = offender
	incident.victim = from_player
	incident.details = extra.duplicate()
	incident.severity = Severity.CARELESS
	_direct_restart(incident, offender, from_player.team, where)
	var goal := spec().goal_centre(from_player.team.attack)
	# A shot blocked with the arm close to goal denied a goal.
	if extra.get("blocked") == &"shot" and where.distance_to(goal) < 20.0:
		incident.dogso = true
		incident.expected_card = &"red"
		incident.card_reason = "denying a goal by handling the ball"
	elif extra.get("blocked") in [&"pass", &"free_kick", &"corner"] and _promising(from_player.team, where):
		incident.spa = true
		incident.expected_card = &"yellow"
		incident.card_reason = "stopping a promising attack by handling the ball"
	incident.key = incident.expected_restart == &"penalty" or incident.expected_card == &"red"
	return _commit(incident)


## Law 12.3: attempting to deceive the referee by feigning injury or pretending to have
## been fouled is a caution. The restart, if play is stopped for it, is an indirect free
## kick. Letting play go on is not wrong; giving the free kick or the penalty is.
func simulation(offender: Footballer, where: Vector3) -> Incident:
	var incident := _new(&"simulation", where)
	incident.offender = offender
	incident.expected_restart = &"indirect_free_kick"
	incident.expected_team = _other(offender.team)
	incident.expected_card = &"yellow"
	incident.card_reason = "simulation"
	incident.must_stop = false
	incident.key = spec().in_penalty_area(where, offender.team.attack)
	return _commit(incident)


## Law 12.2: the keeper handles a ball deliberately kicked to him by a teammate.
## An indirect free kick, taken from the goal-area line if it happened inside it.
func back_pass(keeper: Footballer, passer: Footballer, where: Vector3) -> Incident:
	var incident := _new(&"back_pass", where)
	incident.offender = keeper
	incident.victim = null
	incident.expected_restart = &"indirect_free_kick"
	incident.expected_team = _other(keeper.team)
	incident.details = {"passer": passer}
	return _commit(incident)


## Law 9.2: the ball touches the referee and a team starts a promising attack, or it goes
## directly into the goal, or the team in possession changes. Then it is a dropped ball;
## otherwise play goes on. Which of those happened is only known a moment later, so the
## match calls `settle_referee_touch` once the ball has gone somewhere.
func referee_touch(where: Vector3) -> Incident:
	var incident := _new(&"hit_referee", where)
	incident.expected_restart = &"play_on"
	incident.must_stop = false
	incident.window = 5.0
	incident.details = {"possession_before": _possession_before_ref}
	return _commit(incident)


func settle_referee_touch(incident: Incident, possession_after: int, promising: bool) -> void:
	var before: int = incident.details.get("possession_before", -1)
	if (before >= 0 and possession_after >= 0 and before != possession_after) or promising:
		incident.expected_restart = &"dropped_ball"
		incident.must_stop = true
		incident.expected_team = m.teams[before] if before >= 0 else null


## A player down and not getting up. Play should be stopped for it (Law 5).
func serious_injury(victim: Footballer, where: Vector3) -> Incident:
	var incident := _new(&"serious_injury", where)
	incident.victim = victim
	incident.expected_restart = &"dropped_ball"
	incident.window = 12.0
	return _commit(incident)


## Dissent by word or action (Law 12.3): a caution.
func dissent(offender: Footballer) -> Incident:
	var incident := _new(&"dissent", offender.global_position)
	incident.offender = offender
	incident.expected_card = &"yellow"
	incident.card_reason = "dissent"
	incident.must_stop = false
	incident.window = 999.0
	return _commit(incident)


# --- helpers ----------------------------------------------------------------------------

func _other(team: Team) -> Team:
	return m.teams[1] if team == m.teams[0] else m.teams[0]


## A direct free kick where it happened, or a penalty if it was in the offender's own
## penalty area.
func _direct_restart(incident: Incident, offender: Footballer, to: Team, where: Vector3) -> void:
	var own_end := -offender.team.attack
	incident.expected_team = to
	if spec().in_penalty_area(where, own_end):
		incident.expected_restart = &"penalty"
	else:
		incident.expected_restart = &"free_kick"


## DOGSO and SPA. The four considerations of Law 12.3 for DOGSO — distance to goal,
## general direction of play, likelihood of keeping or gaining control of the ball, and
## the location and number of defenders — each reduced to something measurable.
func _opportunity(incident: Incident, victim: Footballer, offender: Footballer, where: Vector3) -> void:
	var end := victim.team.attack
	var goal := spec().goal_centre(end)
	var distance := where.distance_to(goal)
	var ball_close: bool = m.ball.global_position.distance_to(victim.global_position) < 3.0
	var heading: Vector3 = victim.velocity if victim.velocity.length() > 1.0 else victim.heading
	var toward := heading.normalized().dot((goal - where).normalized()) > 0.2
	var between := 0
	for q: Footballer in m.players:
		if not q.on_pitch or q.team == victim.team or q == offender or q.is_keeper():
			continue
		var ahead: float = (q.global_position.x - where.x) * end
		if ahead > 0.0 and absf(q.global_position.z - where.z) < maxf(distance * 0.5, 6.0):
			between += 1
	incident.dogso = distance < 26.0 and toward and ball_close and between == 0
	incident.spa = not incident.dogso and ball_close and toward and between <= 2 \
		and (where.x * end) > -5.0 and _promising(victim.team, where)
	if incident.dogso:
		incident.details["dogso"] = {"distance": distance, "defenders": between}


func _promising(team: Team, where: Vector3) -> bool:
	var u := team.to_team_space(where, spec()).x
	return u > 0.5


## Which card a player has coming, counting what he already has: a second caution is a
## sending-off.
static func card_for(player: Footballer, colour: StringName) -> StringName:
	if colour == &"yellow" and player.yellow_cards >= 1:
		return &"second_yellow"
	return colour
