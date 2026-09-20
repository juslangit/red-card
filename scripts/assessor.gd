class_name Assessor
extends RefCounted

## The match assessor: watches the referee and marks the performance out of ten.
##
## Real referees are assessed this way, and the scale is the real one's shape too: most
## performances land between 7.8 and 8.6, a good one is 8.4, and anything under 8.0 is a
## match with a problem in it. Getting a key match incident wrong — a goal, a penalty, a
## red card — costs far more than any number of throw-ins.
##
## It only ever reads the truth at the end, in `finish()`, and in `quick_verdict()`, which
## decides how loudly the players complain and never reaches the screen as words.

const BASE_MARK := 8.4

var m
var cards: Array = []            # {player, colour, time, incident}
var flags: Array = []            # {flag, accepted, correct}
var advantage_calls: Array = []  # {incident or null, time}
var empty_stops: Array = []      # whistles for nothing
var timekeeping: Array = []      # {half, ended_at, owed, forced}
var added_time_given: Array = []
var subs: Array = []
var _samples := 0
var _good_position := 0
var _too_close := 0
var _too_far := 0
var _blocked := 0
var _distance_sum := 0.0
var _sample_accum := 0.0
## Where the referee has been, one point a second of open play. A real assessor's report
## talks about whether he kept the diagonal; this is what that is drawn from.
var trail: PackedVector2Array = PackedVector2Array()
var _distance_run := 0.0
var _sprint_seconds := 0.0
var _last_ref_pos := Vector3.INF
var report: Dictionary = {}
var finished := false


func _init(match_node) -> void:
	m = match_node


# --- watching ---------------------------------------------------------------------------

func step(delta: float) -> void:
	var ref: Node3D = m.referee
	if ref == null:
		return
	if _last_ref_pos != Vector3.INF:
		_distance_run += ref.global_position.distance_to(_last_ref_pos)
	_last_ref_pos = ref.global_position
	if ref.get("sprinting"):
		_sprint_seconds += delta
	if m.phase != Match.Phase.LIVE:
		return
	_sample_accum += delta
	if _sample_accum < 1.0:
		return
	_sample_accum = 0.0
	var d: float = ref.global_position.distance_to(m.ball.global_position)
	trail.append(Vector2(ref.global_position.x, ref.global_position.z))
	_samples += 1
	_distance_sum += d
	if d < 5.0:
		_too_close += 1
	elif d > 35.0:
		_too_far += 1
	else:
		_good_position += 1
	if m.view_quality(m.ball.global_position) < 0.5:
		_blocked += 1


func note_card(player: Footballer, colour: StringName) -> void:
	var entry := {"player": player, "colour": colour, "time": m.clock, "incident": null}
	# Which offence is it for? The most recent one by this player that calls for a card,
	# or failing that any recent one by him.
	for i in range(m.laws.incidents.size() - 1, -1, -1):
		var inc: Incident = m.laws.incidents[i]
		if m.clock - inc.time > 180.0:
			break
		if inc.offender == player and not inc.cards_given.any(func(c): return true):
			entry.incident = inc
			inc.cards_given.append({"player": player, "colour": colour})
			break
	if entry.incident == null and m.stopped_for != null and m.stopped_for.offender != null:
		# A card shown to somebody who did not commit the offence: mistaken identity if the
		# offence called for one.
		var inc: Incident = m.stopped_for
		entry["wrong_player"] = inc.offender
		inc.cards_given.append({"player": player, "colour": colour, "wrong_player": true})
		entry.incident = inc
	cards.append(entry)


func note_flag(flag: Dictionary, accepted: bool, ignored := false) -> void:
	flags.append({"flag": flag, "accepted": accepted, "ignored": ignored, "correct": flag.get("incident") != null, "time": m.clock})


func note_advantage(incident: Incident) -> void:
	advantage_calls.append({"incident": incident, "time": m.clock})


func note_substitution(waited: float, stoppages_missed: int) -> void:
	subs.append({"waited": waited, "missed": stoppages_missed})


func note_timekeeping(minutes_over: float, owed: int, forced: bool) -> void:
	timekeeping.append({"half": m.half, "over": minutes_over, "owed": owed, "forced": forced})


func note_added_time(given: int, owed: int) -> void:
	added_time_given.append({"half": m.half, "given": given, "owed": owed})


# --- verdicts ---------------------------------------------------------------------------

## +1 right, -1 wrong, 0 nothing to judge. For the players' reactions only.
func quick_verdict(incident: Incident) -> int:
	if incident == null:
		return -1 if m.stopped_for == null and m.phase == Match.Phase.SET_PIECE else 0
	if incident.restart_given == &"":
		return 0
	if incident.kind == &"simulation":
		return -1 if incident.restart_team != null and incident.restart_team == incident.offender.team else 1
	var right_type := incident.restart_given == incident.expected_restart
	var right_team := incident.restart_team == incident.expected_team
	if incident.kind == &"out" and right_team:
		return 1
	return 1 if right_type and right_team else -1


## Marks every incident, and the rest, into the report.
func finish() -> void:
	if finished:
		return
	finished = true
	var lines: Array = []
	var mark := BASE_MARK
	var key_right := 0
	var key_total := 0
	var decisions_right := 0
	var decisions_total := 0
	for inc in m.laws.incidents:
		var result := _judge(inc)
		inc.verdict = result.text
		inc.points = result.points
		mark += result.points
		if result.counts:
			decisions_total += 1
			if result.points >= 0.0:
				decisions_right += 1
			if inc.key:
				key_total += 1
				if result.points >= 0.0:
					key_right += 1
		if result.text != "":
			lines.append({"incident": inc, "text": result.text, "points": result.points, "key": inc.key})
	# Cards shown with no offence behind them.
	for c in cards:
		if c.incident == null:
			mark -= 0.3
			lines.append({"incident": null, "text": "%s card shown to %s with no offence to justify it" % [String(c.colour).capitalize(), Incident.who(c.player)], "points": -0.3, "key": c.colour != &"yellow"})
	# Flags.
	for f in flags:
		var right: bool = f.correct == f.accepted
		if not right:
			var delta := -0.1
			mark += delta
			var called: String = String(f.flag.get("kind", &"offside"))
			var what := ("Accepted a wrong %s flag" % called) if f.accepted else (("Ignored a correct %s flag" if f.ignored else "Waved down a correct %s flag") % called)
			lines.append({"incident": f.flag.get("incident"), "text": what, "points": delta, "key": false})
	# Positioning.
	var positioning := _positioning()
	mark += positioning.points
	# Timekeeping.
	for t in timekeeping:
		var owed: float = t.owed
		var over: float = t.over
		if t.forced:
			mark -= 0.3
			lines.append({"incident": null, "text": "Half %d: never ended — play went %.0f minutes past time" % [t.half, over], "points": -0.3, "key": false})
		elif over < -0.3:
			mark -= 0.4
			lines.append({"incident": null, "text": "Half %d ended %.1f minutes early" % [t.half, -over], "points": -0.4, "key": true})
		elif over < owed - 0.6:
			mark -= 0.1
			lines.append({"incident": null, "text": "Half %d: %.1f minutes added, %d were owed" % [t.half, over, int(owed)], "points": -0.1, "key": false})
		elif over > owed + 2.0:
			mark -= 0.05
			lines.append({"incident": null, "text": "Half %d ran %.1f minutes over the time owed" % [t.half, over - owed], "points": -0.05, "key": false})
	for e in empty_stops:
		mark -= 0.1
	for sub in subs:
		if sub.missed >= 2:
			mark -= 0.03
			lines.append({"incident": null, "text": "A substitute was kept waiting through %d stoppages" % sub.missed, "points": -0.03, "key": false})
	mark = clampf(mark, 5.0, 9.6)
	report = {
		"mark": snappedf(mark, 0.1),
		"band": _band(mark),
		"lines": lines,
		"key_right": key_right, "key_total": key_total,
		"decisions_right": decisions_right, "decisions_total": decisions_total,
		"positioning": positioning,
		"trail": trail,
		"distance_km": _distance_run / 1000.0 * m.clock_scale(),
		"cards": cards.size(),
	}


func _band(mark: float) -> String:
	if mark >= 8.7:
		return "Excellent"
	if mark >= 8.4:
		return "Good — ready for a higher level"
	if mark >= 8.1:
		return "Expected standard"
	if mark >= 7.8:
		return "Below the expected standard"
	return "Serious concerns"


func _positioning() -> Dictionary:
	var n := maxi(_samples, 1)
	var good := float(_good_position) / n
	var close := float(_too_close) / n
	var far := float(_too_far) / n
	var points := (good - 0.7) * 0.4 - close * 0.3
	return {"good": good, "close": close, "far": far, "blocked": float(_blocked) / n,
		"average": _distance_sum / n, "points": clampf(points, -0.3, 0.12)}


## The verdict on one incident: what the referee did, whether it was right, and what it
## costs or earns.
func _judge(inc: Incident) -> Dictionary:
	var out := {"text": "", "points": 0.0, "counts": true}
	var expected_card := inc.expected_card
	# Advantage for a promising attack cancels the caution (Law 12.3).
	if inc.advantage and inc.spa and not inc.dogso and expected_card == &"yellow" and inc.severity < Laws.Severity.RECKLESS:
		expected_card = &""
	var given_card := &""
	for c in inc.cards_given:
		if c.get("wrong_player", false):
			continue
		given_card = c.colour
	var wrong_player := inc.cards_given.any(func(c): return c.get("wrong_player", false))
	var weight := 0.45 if inc.key else 0.12
	match inc.kind:
		&"foul", &"holding", &"handball", &"back_pass":
			var name := inc.label()
			if inc.whistled and inc.restart_given != &"":
				if inc.restart_given == inc.expected_restart and inc.restart_team == inc.expected_team:
					out.text = "%s — %s, correct" % [name, _say(inc.expected_restart)]
					out.points = 0.03 if not inc.key else 0.12
				elif inc.restart_team == inc.expected_team:
					out.text = "%s — gave %s, should have been %s" % [name, _say(inc.restart_given), _say(inc.expected_restart)]
					out.points = -weight
				else:
					out.text = "%s — restart given the wrong way" % name
					out.points = -weight
			elif inc.advantage:
				if inc.details.get("advantage_realised", true):
					out.text = "%s — advantage, well played" % name
					out.points = 0.06
				else:
					out.text = "%s — advantage did not come and play was not brought back" % name
					out.points = -0.1
			else:
				out.text = "%s — missed" % name
				out.points = -weight if inc.severity > Laws.Severity.CARELESS or inc.key else -0.08
		&"simulation":
			if inc.restart_given != &"" and inc.restart_team == inc.offender.team:
				out.text = "%s — rewarded with %s: deceived" % [inc.label(), _say(inc.restart_given)]
				out.points = -0.5 if inc.key else -0.2
			elif given_card == &"yellow":
				out.text = "%s — cautioned for simulation, excellent" % inc.label()
				out.points = 0.1
			else:
				out.text = "%s — not deceived, but no caution" % inc.label()
				out.points = 0.0
				out.counts = false
		&"offside":
			if inc.whistled and inc.restart_given == &"indirect_free_kick":
				out.text = "%s — correct (%.2f m)" % [inc.label(), inc.details.get("margin", 0.0)]
				out.points = 0.03 if not inc.key else 0.1
			else:
				out.text = "%s — missed (%.2f m)" % [inc.label(), inc.details.get("margin", 0.0)]
				out.points = -0.06 if not inc.key else -0.3
		&"out":
			if inc.restart_given == &"":
				out.counts = false
			elif inc.restart_given == inc.expected_restart and inc.restart_team == inc.expected_team:
				out.counts = true
			else:
				out.text = "Ball out — gave %s to %s, should have been %s to %s" % [_say(inc.restart_given),
					inc.restart_team.name if inc.restart_team else "?", _say(inc.expected_restart),
					inc.expected_team.name if inc.expected_team else "?"]
				out.points = -0.04 if inc.expected_restart == &"throw_in" else -0.1
		&"goal":
			var given := inc.restart_given == &"kick_off"
			var should := inc.expected_restart == &"kick_off"
			if given == should:
				out.text = "%s — %s, correct" % [inc.label(), "given" if given else "disallowed"]
				out.points = 0.1
			elif given:
				var why: Incident = inc.details.get("cancelled_by")
				out.text = "%s — given, but it should have been disallowed for %s" % [inc.label(), why.label() if why else "an offence"]
				out.points = -0.6
			else:
				out.text = "%s — a good goal disallowed" % inc.label()
				out.points = -0.6
		&"hit_referee":
			if inc.expected_restart == &"dropped_ball" and not inc.whistled:
				out.text = "The ball hit you and changed possession — should have been a dropped ball"
				out.points = -0.1
			else:
				out.counts = false
		&"serious_injury":
			if inc.whistled or m.clock - inc.time < inc.window:
				out.counts = false
			else:
				out.text = "%s — play not stopped for a serious injury" % inc.label()
				out.points = -0.1
		&"dissent":
			out.counts = false
			if given_card == &"yellow":
				out.text = "%s — cautioned" % inc.label()
				out.points = 0.03
			else:
				out.text = "%s — went unpunished" % inc.label()
				out.points = -0.05
			return out
	# The card.
	if inc.kind in [&"foul", &"holding", &"handball", &"simulation"] and (expected_card != &"" or given_card != &""):
		var red_given := given_card in [&"red", &"second_yellow"]
		var red_due := expected_card == &"red"
		if wrong_player:
			out.text += " · card shown to the wrong player"
			out.points -= 0.5
		elif expected_card == given_card or red_due and red_given:
			if expected_card != &"":
				out.text += " · %s card, correct (%s)" % [String(expected_card), inc.card_reason]
				out.points += 0.05 if not red_due else 0.15
		elif expected_card == &"":
			out.text += " · %s card not warranted" % String(given_card)
			out.points -= 0.5 if red_given else 0.15
		elif given_card == &"":
			out.text += " · missed %s card (%s)" % [String(expected_card), inc.card_reason]
			out.points -= 0.5 if red_due else 0.15
		else:
			out.text += " · %s card, should have been %s (%s)" % [String(given_card), String(expected_card), inc.card_reason]
			out.points -= 0.5 if red_due or red_given else 0.1
	if inc.reviewed and inc.overturned:
		out.text += " · corrected after review"
	return out


static func _say(restart: StringName) -> String:
	return {
		&"free_kick": "a free kick", &"indirect_free_kick": "an indirect free kick",
		&"penalty": "a penalty", &"throw_in": "a throw-in", &"corner": "a corner",
		&"goal_kick": "a goal kick", &"kick_off": "a goal", &"dropped_ball": "a dropped ball",
		&"play_on": "play on",
	}.get(restart, String(restart))
