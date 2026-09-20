class_name ScenarioRun
extends Node

## Plays one drill or challenge: places everybody, runs the script, decides when the
## moment is over, and judges what the referee did with the same Assessor the career uses.

signal finished(result: Dictionary)

var def: Dictionary
var m: Match
var ref: Referee
var hud: Hud
var t := 0.0
var _done := false
var _started := false
var _script_done := {}
var _markers: Array = []
var _visited := 0
var _brief_layer: CanvasLayer
var _event_time := -1.0
var _was_set_piece := false
## When the drill's own clock first saw the incident. The match clock stops whenever play
## does, so it cannot be used to give up on a drill that has stopped for good.
var _incident_at := -1.0
var _arms_player: Footballer = null
## The incident this scenario's own script caused. The players go on playing around the
## script, so a drill that simply took the first incident of the right kind could end up
## judging a foul the AI committed somewhere else — and marking the referee wrong for
## missing something that was never the lesson.
var _scripted: Incident = null


func _ready() -> void:
	m.whistle_every_restart = true
	_show_brief()
	# Wait a frame so the match has built itself.
	await get_tree().process_frame
	_setup()


func _player(ref_pair: Array) -> Footballer:
	var team: Team = m.teams[ref_pair[0]]
	for p in team.players:
		if p.number == ref_pair[1]:
			return p
	return null


func _setup() -> void:
	ref.global_position = def.get("ref_at", Vector3(-5, 0, -8))
	if def.has("ref_look"):
		var to: Vector3 = def.ref_look - ref.global_position
		ref.yaw = atan2(-to.x, -to.z)
	if def.has("markers"):
		# Movement drill: nobody plays; the match stays before kick-off.
		for p in m.players:
			p.visible = true
		for at in def.markers:
			_markers.append(_marker(at))
		_started = true
		return
	if def.has("clock"):
		var c: Dictionary = def.clock
		m.half = c.half
		m.half_started_at = m.clock - c.minute * 60.0 / m.clock_scale()
		m.lost_seconds = c.lost
		m.teams[0].attack = -1
		m.teams[1].attack = 1
		m.begin_open_play()
		m.ai.give_ball(_player([0, 4]))
		_started = true
		return
	# Everybody not named drifts to their shape relative to where the ball will be.
	for entry in def.get("place", []):
		var p := _player([entry[0], entry[1]])
		p.global_position = entry[2]
		p.velocity = Vector3.ZERO
		p.heading = Vector3(p.team.attack, 0, 0)
	var ball_at := Vector3.ZERO
	if def.has("give"):
		var carrier := _player(def.give)
		ball_at = carrier.global_position
	elif not def.get("place", []).is_empty():
		ball_at = def.place[0][2]
	# Put the rest roughly in shape around the ball so nobody sprints in from nowhere.
	var named := {}
	for entry in def.get("place", []):
		named[_player([entry[0], entry[1]])] = true
	m.ball.place(ball_at)
	# "Clear ahead": every defender not named is put behind the ball, so the named ones
	# are the last line — the last man really is the last man.
	var clear: bool = def.get("clear_ahead", false)
	for p in m.players:
		if named.has(p) or p.is_keeper():
			if p.is_keeper() and not named.has(p):
				p.global_position = Vector3(m.spec.goal_line_x(-p.team.attack) + p.team.attack * 1.0, 0, 0)
			continue
		var target: Vector3 = m.ai._shape_target(p)
		if clear and p.team == m.teams[1]:
			target.x = minf(target.x, ball_at.x - 10.0)
		# Keep them clear of the scripted moment.
		if target.distance_to(ball_at) < 9.0:
			target += (target - ball_at).normalized() * 9.0
		p.global_position = m.spec.clamp_to_field(target, 1.0)
	m.begin_open_play()
	for pair in def.get("run", []):
		var p := _player([pair[0], pair[1]])
		m.ai.held[p] = true
		p.goal = pair[2]
		p.hurry = 0.85
	# Players who must stand exactly where they were put until something happens.
	for pair in def.get("hold", []):
		var p := _player(pair)
		m.ai.held[p] = true
		p.goal = p.global_position
		p.hurry = 0.1
	if def.has("give"):
		var giver := _player(def.give)
		m.ai.give_ball(giver)
		# He waits for his cue: left to himself he passes it on before the moment happens.
		if not m.ai.held.has(giver):
			m.ai.held[giver] = true
			giver.goal = giver.global_position
			giver.hurry = 0.2
	_started = true


func _marker(at: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.9
	mesh.bottom_radius = 0.9
	mesh.height = 0.06
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UiTheme.ACCENT
	mat.emission_enabled = true
	mat.emission = UiTheme.ACCENT
	mat.emission_energy_multiplier = 1.4
	node.material_override = mat
	m.add_child(node)
	node.global_position = at + Vector3(0, 0.03, 0)
	return node


func _show_brief() -> void:
	_brief_layer = CanvasLayer.new()
	_brief_layer.layer = 6
	add_child(_brief_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.build()
	_brief_layer.add_child(root)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.plate(UiTheme.ACCENT, 0.86))
	panel.position = Vector2(40, 130)
	panel.custom_minimum_size = Vector2(620, 0)
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(Menus.card_tag(UiTheme.ACCENT, "TRAINING" if def.mode == "training" else "SCENARIO"))
	box.add_child(UiTheme.label(def.title.to_upper(), UiTheme.TITLE, UiTheme.CHALK, UiTheme.display()))
	var words := Menus.text(def.brief, UiTheme.BODY, UiTheme.CHALK)
	words.custom_minimum_size = Vector2(580, 0)
	box.add_child(words)


func _physics_process(delta: float) -> void:
	if not _started or _done or m.paused:
		return
	t += delta
	for i in def.get("script", []).size():
		var step: Dictionary = def.script[i]
		if _script_done.has(i) or t < step.t:
			continue
		_script_done[i] = true
		var before := m.laws.incidents.size()
		_do(step)
		if _scripted == null and m.laws.incidents.size() > before:
			var made: Incident = m.laws.incidents.back()
			if String(made.kind) == String(def.get("judge", "")):
				_scripted = made
		if _event_time < 0.0:
			_event_time = t
	if _arms_player != null:
		var rel := m.ball.global_position - _arms_player.global_position
		if Vector2(rel.x, rel.z).length() < 1.0 and rel.y > 0.5 and rel.y < 2.1:
			var kicker: Footballer = m.ball.last_touch as Footballer
			m.laws.handball(_arms_player, kicker, _arms_player.global_position, {"blocked": &"shot"})
			if String(def.get("judge", "")) == "handball":
				_scripted = m.laws.incidents.back()
			var bounce := Vector3(-m.ball.velocity.x, 2.0, -m.ball.velocity.z * 0.5).normalized()
			m.ball.kick(bounce * m.ball.speed() * 0.3, _arms_player, &"handball")
			_arms_player = null
	# Held runners keep running to where they were sent.
	for pair in def.get("run", []) + def.get("run_after", []):
		var p := _player([pair[0], pair[1]])
		if m.ai.held.has(p) and p.is_free():
			p.goal = pair[2]
			if m.ai.carrier == p:
				p.hurry = 0.8
	_check_end()


func _do(step: Dictionary) -> void:
	match step.do:
		"foul":
			var by := _player(step.by)
			var on := _player(step.on)
			var severity: Laws.Severity = {"careless": Laws.Severity.CARELESS, "reckless": Laws.Severity.RECKLESS,
				"excessive": Laws.Severity.EXCESSIVE}.get(step.get("severity", "careless"))
			# Bring the tackler right up to the man first, so the contact is visible.
			by.global_position = on.global_position - on.heading * 0.9 + Vector3(0, 0, 0.3)
			m.ai.force_foul(by, on, severity, step.get("sliding", false), step.get("behind", true), step.get("stays_up", false))
			if step.get("flagged", false):
				var inc: Incident = m.laws.incidents.back()
				var ar: Assistant = m.assistants[1] if on.global_position.z > 0.0 else m.assistants[0]
				ar.body.global_position = Vector3(on.global_position.x - 4.0, 0, ar.body.global_position.z)
				ar.flag_foul(inc)
			if not step.get("stays_up", false):
				m.ai.held.erase(on)
				m.ai.held.erase(by)
			else:
				# Beaten: the tackler is left behind on the grass, not straight back in.
				by.goal = by.global_position
				by.hurry = 0.1
				by.fall(on.heading, 1.6)
		"release":
			m.ai.held.clear()
		"dive":
			var diver := _player(step.by)
			m.ai.held.clear()
			m.ai._lose_ball()
			m.laws.simulation(diver, diver.global_position)
			diver.fall(diver.heading, 2.4)
			m.ball.velocity = diver.heading * 2.0
		"kick":
			var by := _player(step.by)
			m.ai.held.erase(by)
			m.ball.place(step.from)
			m.ai.carrier = null
			by.one_shot("kick", 0.5)
			m.ball.kick(step.velocity, by, StringName(step.get("kind", "clearance")))
			# Players who walk away once the ball has gone, so the drill's moment is not theirs.
			for pair in def.get("run_after", []):
				var walker := _player([pair[0], pair[1]])
				m.ai.held[walker] = true
				walker.goal = pair[2]
				walker.hurry = 0.5
			m.on_played(by, StringName(step.get("kind", "clearance")))
			m.sound_kick(m.ball.global_position, (step.velocity as Vector3).length())
		"shoot":
			var by := _player(step.by)
			m.ai.held.erase(by)
			m.ai.held.clear()
			m.ai.carrier = null
			var from := m.ball.global_position
			var at: Vector3 = step.at
			var speed := 22.0
			var flat := at - from
			var tt := Vector2(flat.x, flat.z).length() / speed
			var v := Vector3(flat.x, 0, flat.z).normalized() * speed + Vector3.UP * ((at.y - from.y) / tt + 0.5 * Ball.GRAVITY * tt)
			by.one_shot("kick", 0.5)
			m.ball.kick(v, by, &"shot")
			m.sound_kick(from, speed)
		"arms":
			var p := _player(step.by)
			p.arms.set_right(Vector3(-1.0, 0.25, 0.3), Vector3.ZERO, 1.0)
			p.arms.set_left(Vector3(1.0, 0.25, 0.3), Vector3.ZERO, 1.0)
			# The scenario itself decides the handball when the ball gets there, rather than
			# leaving it to the AI's dice.
			_arms_player = p
		"hold":
			var by := _player(step.by)
			var on := _player(step.on)
			m.ai.held.erase(by)
			m.ai.held.erase(on)
			by.global_position = on.global_position - on.heading * 0.8
			by.arms.set_right(by.arms.to_model((on.global_position - by.global_position).normalized()), Vector3.ZERO, 1.0)
			m.laws.foul(by, on, &"holding", Laws.Severity.CARELESS, on.global_position, {"holding": true})
			on.fall(-on.heading, 2.0)
		"pass":
			var by := _player(step.by)
			m.ai.held.erase(by)
			var to := _player(step.to)
			m.ai.carrier = null
			# Firm and to feet: a soft pass takes four seconds and anybody can cut it out.
			var v: Vector3 = m.ai._pass_velocity(m.ball.global_position, to.global_position + Vector3(2, 0, 0), false) * 1.25
			by.one_shot("pass", 0.5)
			m.ball.kick(v, by, &"pass")
			m.sound_kick(m.ball.global_position, v.length())
		"false_flag":
			var on := _player(step.on)
			var ar: Assistant = m.assistants[1] if on.global_position.x > 0.0 else m.assistants[0]
			ar._raise()
			m.raise_flag(ar, &"offside", on, null)
		"keeper_picks_up":
			var team: Team = m.teams[step.team]
			var gk: Footballer = team.keeper()
			gk.global_position = m.ball.global_position - Vector3(team.attack * -0.5, 0, 0)
			var passer: Footballer = m.ball.last_touch as Footballer
			m.ball.pick_up(gk)
			m.ai.carrier = gk
			m.ai._decide_in = 6.0
			gk.one_shot("keeper_catch", 0.6)
			m.laws.back_pass(gk, passer, gk.global_position)


## The incident this scenario is about: the one its own script caused, if it caused one.
func _incident() -> Incident:
	if _scripted != null:
		return _scripted
	var kind: String = def.get("judge", "")
	for inc in m.laws.incidents:
		if String(inc.kind) == kind:
			return inc
	return null


func _check_end() -> void:
	if def.has("markers"):
		for i in _markers.size():
			var mk: MeshInstance3D = _markers[i]
			if mk.visible and Vector2(ref.global_position.x - mk.global_position.x, ref.global_position.z - mk.global_position.z).length() < 2.0:
				mk.visible = false
				_visited += 1
				m.sound.whistle()
		if _visited >= _markers.size():
			_finish({"passed": true, "lines": ["You can move, sprint and look. Referees run ten or twelve kilometres a match — mostly at a jog, sprinting only when play demands it."]})
		return
	if def.get("judge") == "time":
		if m.phase == Match.Phase.FULL_TIME:
			var entry: Dictionary = m.assessor.timekeeping.back()
			var over: float = entry.over
			var owed: int = entry.owed
			var ok: bool = over >= owed - 0.3 and over <= owed + 1.5 and not entry.forced
			_finish({"passed": ok, "lines": ["You ended it %.1f minutes into added time; %d were owed." % [over, owed]]})
		return
	if def.get("judge") == "flag":
		if not m.assessor.flags.is_empty():
			var f: Dictionary = m.assessor.flags[0]
			if f.get("ignored", false):
				_finish({"passed": false, "lines": ["The flag stayed up until your assistant gave up. Ignoring it is not a decision — accept it (whistle) or wave it down (X)."]})
				return
			var ok: bool = not f.accepted
			_finish({"passed": ok, "lines": ["He was level — and level is onside. The flag was wrong, and you %s it." % ("waved it down" if ok else "went with")]})
		elif t > 12.0:
			_finish({"passed": false, "lines": ["The flag stayed up and you neither accepted it nor waved it down."]})
		return
	var inc := _incident()
	if inc == null:
		if t > 14.0:
			_finish({"passed": false, "lines": ["Nothing happened that needed judging — try again."]})
		return
	if _incident_at < 0.0:
		_incident_at = t
	# Over when play restarts after the incident, or after long enough with no whistle.
	if m.phase == Match.Phase.SET_PIECE:
		_was_set_piece = true
	var limit: float = 16.0 if def.get("end_on_restart", false) else float(def.get("end_after", 9.0))
	var restarted := _was_set_piece and m.phase == Match.Phase.LIVE
	var waited := m.clock - inc.time > limit and m.phase == Match.Phase.LIVE and not inc.whistled
	if def.get("end_on_restart", false):
		waited = m.clock - inc.time > limit and m.phase == Match.Phase.LIVE and not _was_set_piece
	# And in the end, judge it whatever the ball did next. Two backstops, because a drill
	# can be left hanging in two different ways.
	#
	# The first used to wait for one particular phase — play stopped at a set piece,
	# needing the whistle — which is only the commonest of the ways a drill ends. A
	# referee who does nothing never restarts anything, and the loose ball after the
	# incident can just as well run out for a corner, end in the net or be dead at a
	# kick-off, each of which is a phase of its own that nothing will move on from. The
	# dive drill hung on exactly that about one run in three, and the check reported a
	# timeout instead of a verdict. It waits while the referee is visibly still dealing
	# with the incident — whistle blown, restart not yet given — because cutting in there
	# would mark a decision missed that was about to be made.
	var dealing_with_it: bool = inc.whistled and inc.restart_given == &"" and not inc.advantage
	var moved_on := m.clock - inc.time > limit + 4.0 and not dealing_with_it
	# The second ends it whatever state it is in, measured on the drill's own clock rather
	# than the match's, which stops whenever play does. Nothing waits for ever.
	var gave_up := t - _incident_at > limit + 20.0
	if restarted or waited or moved_on or gave_up:
		_judge(inc)


func _judge(inc: Incident) -> void:
	var verdict: Dictionary = m.assessor._judge(inc)
	var needs_decision := inc.kind in [&"out", &"foul", &"holding", &"handball", &"offside", &"back_pass", &"hit_referee"]
	var decided := inc.restart_given != &"" or inc.advantage
	var passed: bool = verdict.points >= 0.0 and (decided or not needs_decision)
	if inc.kind == &"simulation":
		# The lesson is not to be fooled; the caution is the extra mark.
		passed = inc.restart_given == &"" or inc.restart_team != inc.offender.team
	if inc.kind == &"hit_referee":
		passed = inc.restart_given == &"dropped_ball"
		verdict.text = "The ball hit you and changed possession — a dropped ball to the team that had it." if passed else "The ball hit you and changed possession: stop play (whistle) and give a dropped ball (B) to the team that had it."
	var lines: Array = [verdict.text if verdict.text != "" else inc.label()]
	if inc.kind == &"simulation" and passed and inc.cards_given.is_empty():
		lines.append("No penalty — good. Full marks would have been a caution for simulation at the next stoppage.")
	_finish({"passed": passed, "lines": lines, "incident": inc})


func _finish(result: Dictionary) -> void:
	if _done:
		return
	_done = true
	result["title"] = def.title
	result["law"] = def.get("law", "")
	result["next"] = def.get("next", "")
	_brief_layer.visible = false
	finished.emit(result)
