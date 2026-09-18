class_name VarSystem
extends RefCounted

## The video assistant referee — at the National Stadium only, as in real football, where
## only the top of the game has one.
##
## VAR follows the real protocol: it checks every goal, every penalty decision, every
## direct red card and mistaken identity, and it only intervenes for a *clear and obvious
## error* or a *serious missed incident*. Two kinds of intervention:
##
##   factual      offside, and whether a foul was inside or outside the area. VAR simply
##                tells the referee, and the decision changes.
##   subjective   everything else. VAR recommends an on-field review; the referee goes to
##                the monitor, watches the replay, and makes the decision again — which is
##                still theirs, and can still be wrong.
##
## A check holds the restart for a few seconds, which is what the player sees: the
## players set up, and nothing happens until "Check complete".

signal review_requested(incident: Incident, title: String, choices: Array, apply: Callable)

const CHECK_SECONDS := 2.5

var m
var checking := false
var _timer := 0.0
var _pending: Callable
var _message := ""


func _init(match_node) -> void:
	m = match_node


func step(delta: float) -> void:
	if not checking:
		return
	_timer -= delta
	if _timer <= 0.0:
		checking = false
		m.var_hold = false
		if _pending.is_valid():
			var action := _pending
			_pending = Callable()
			action.call()
		else:
			m.message.emit("VAR: check complete", 2.0)


func _check(then: Callable = Callable()) -> void:
	checking = true
	_timer = CHECK_SECONDS
	m.var_hold = true
	_pending = then
	m.message.emit("VAR: checking…", CHECK_SECONDS)
	m.lost_seconds += 30.0


## Called by the match whenever the referee gives a restart. Checks the ones VAR covers.
func on_award(inc: Incident, type: StringName, to: Team, was_goal: bool) -> void:
	# A goal given.
	if was_goal and type == &"kick_off":
		var cancel: Incident = inc.details.get("cancelled_by") if inc != null else null
		if cancel == null:
			_check()
		elif cancel.kind == &"offside":
			_check(func(): _overturn_goal(inc, cancel, "VAR: goal disallowed — offside"))
		else:
			_check(func(): _offer(inc, "Goal — %s?" % cancel.label(), ["Disallow the goal", "The goal stands"],
				func(choice): if choice == 0: _overturn_goal(inc, cancel, "Goal disallowed after review")))
		return
	# A goal disallowed.
	if was_goal and type != &"kick_off":
		if inc != null and inc.expected_restart == &"kick_off":
			_check(func(): _offer(inc, "Was it a goal?", ["Award the goal", "No goal"],
				func(choice): if choice == 0: _give_goal(inc)))
		else:
			_check()
		return
	if inc == null:
		if type == &"penalty":
			_check(func(): _offer(null, "Penalty — was there an offence?", ["No penalty — dropped ball", "The penalty stands"],
				func(choice): if choice == 0: _change_restart(null, &"dropped_ball", to)))
		return
	if type == &"penalty":
		if inc.kind == &"simulation" or inc.expected_restart not in [&"penalty", &"free_kick"]:
			_check(func(): _offer(inc, "Penalty — %s" % inc.label(), ["Cancel the penalty", "The penalty stands"],
				func(choice): if choice == 0: _change_restart(inc, inc.expected_restart if inc.expected_restart != &"" else &"dropped_ball", inc.expected_team)))
		elif inc.expected_restart == &"free_kick":
			# Factual: the foul was outside the area.
			_check(func(): _change_restart(inc, &"free_kick", inc.expected_team, "VAR: the foul was outside the area — free kick"))
		else:
			_check()
	elif type == &"free_kick" and inc.expected_restart == &"penalty":
		# Factual: inside the area.
		_check(func(): _change_restart(inc, &"penalty", inc.expected_team, "VAR: the foul was inside the area — penalty"))


## A direct red card shown — or one that should have been.
func on_card(player: Footballer, colour: StringName, inc: Incident) -> void:
	if colour != &"red" or inc == null:
		return
	if inc.expected_card != &"red" and inc.offender == player:
		_check(func(): _offer(inc, "Red card — %s" % inc.label(), ["Downgrade to a yellow card", "The red card stands"],
			func(choice): if choice == 0: _rescind(player, true)))
	elif inc.offender != player and inc.offender != null:
		_check(func():
			_rescind(player, false)
			m.message.emit("VAR: mistaken identity — the red card is for #%d" % inc.offender.number, 4.0))


## A stoppage: was a penalty or a red card missed in the move before it?
func on_stoppage() -> void:
	for i in range(m.laws.incidents.size() - 1, -1, -1):
		var inc: Incident = m.laws.incidents[i]
		if m.clock - inc.time > 25.0:
			break
		if inc.reviewed or inc.whistled or inc.advantage:
			continue
		if inc.kind in [&"foul", &"holding", &"handball"] and (inc.expected_restart == &"penalty" or inc.expected_card == &"red"):
			inc.reviewed = true
			var what := "a penalty" if inc.expected_restart == &"penalty" else "a red card"
			_check(func(): _offer(inc, "Possible %s — %s" % [what, inc.label()],
				["Give %s" % what, "No — play was right to go on"],
				func(choice): if choice == 0: _change_restart(inc, inc.expected_restart, inc.expected_team)))
			return


func _offer(inc: Incident, title: String, choices: Array, apply: Callable) -> void:
	if inc != null:
		inc.reviewed = true
	m.message.emit("VAR: I recommend an on-field review", 3.0)
	m.sound.flag_beep()
	m.lost_seconds += 60.0
	review_requested.emit(inc, title, choices, func(choice):
		apply.call(choice)
		if inc != null and choice == 0:
			inc.overturned = true)


func _overturn_goal(goal_inc: Incident, cancel: Incident, words: String) -> void:
	var scoring: Team = goal_inc.details.scoring
	scoring.goals = maxi(scoring.goals - 1, 0)
	goal_inc.restart_given = cancel.expected_restart
	goal_inc.restart_team = cancel.expected_team
	goal_inc.overturned = true
	cancel.whistled = true
	cancel.restart_given = cancel.expected_restart
	cancel.restart_team = cancel.expected_team
	m.message.emit(words, 4.0)
	m.sound.groan()
	m.redo_restart(cancel.expected_restart, cancel.expected_team, cancel.position)


func _give_goal(goal_inc: Incident) -> void:
	var scoring: Team = goal_inc.details.scoring
	var conceding: Team = m.teams[1] if scoring == m.teams[0] else m.teams[0]
	scoring.goals += 1
	goal_inc.restart_given = &"kick_off"
	goal_inc.restart_team = conceding
	goal_inc.overturned = true
	m.message.emit("Goal awarded after review", 4.0)
	m.sound.roar(scoring == m.teams[0])
	m.redo_restart(&"kick_off", conceding, Vector3.ZERO)


func _change_restart(inc: Incident, type: StringName, to: Team, words := "") -> void:
	if inc != null:
		inc.whistled = true
		inc.restart_given = type
		inc.restart_team = to
		inc.overturned = true
	if words != "":
		m.message.emit(words, 4.0)
	m.redo_restart(type, to, inc.position if inc != null else m.ball.global_position)


func _rescind(player: Footballer, to_yellow: bool) -> void:
	player.sent_off = false
	player.on_pitch = true
	player.visible = true
	player.state = Footballer.State.PLAY
	for c in m.assessor.cards:
		if c.player == player and c.colour in [&"red", &"second_yellow"]:
			c.colour = &"yellow" if to_yellow else &"rescinded"
			if c.incident != null:
				for g in c.incident.cards_given:
					if g.player == player:
						g.colour = c.colour
	if to_yellow:
		player.yellow_cards = maxi(player.yellow_cards, 1)
		m.message.emit("Red card downgraded to a yellow after review", 4.0)
