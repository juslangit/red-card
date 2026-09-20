extends Node

## Plays every training drill and challenge twice: once with a referee who gets it right,
## which must pass, and once with one who does nothing, which must not (except the dive,
## where doing nothing is allowed). Headless:
##   Godot --headless --path . res://dev/checks/_scenarios.tscn

var queue: Array = []
var current: Dictionary = {}
var holder: Node3D
var results: Array = []
var run: ScenarioRun
var started := 0


func _ready() -> void:
	Engine.time_scale = 4.0
	var only := OS.get_cmdline_user_args()
	for s in Scenarios.LIST:
		if not only.is_empty() and s.id not in only:
			continue
		queue.append({"id": s.id, "idle": false})
		if s.id not in ["t_move", "t_time"]:
			queue.append({"id": s.id, "idle": true})
	_next()


func _next() -> void:
	if holder != null:
		holder.queue_free()
		holder = null
	if queue.is_empty():
		var bad := 0
		for r in results:
			var expect_pass: bool = not r.idle or r.id == "s_dive"
			var ok: bool = r.passed == expect_pass
			if not ok:
				bad += 1
			print("%s  %-18s %-6s passed=%s  %s" % ["ok " if ok else "BAD", r.id, "idle" if r.idle else "right", r.passed, r.line])
		print("%d wrong of %d" % [bad, results.size()])
		get_tree().quit()
		return
	current = queue.pop_front()
	var def := Scenarios.find(current.id)
	holder = Node3D.new()
	add_child(holder)
	var m := Match.new()
	m.setup(Names.team_from(0), Names.team_from(1), def.get("level", "town"), 360.0)
	holder.add_child(m)
	var ref := Referee.new()
	ref.setup(m, Game.settings)
	holder.add_child(ref)
	m.attach_referee(ref)
	var hud := Hud.new()
	hud.setup(m, ref, Game.settings)
	holder.add_child(hud)
	run = Scenarios.start(current.id, m, ref, hud)
	holder.add_child(run)
	run.finished.connect(_done)
	if not OS.get_cmdline_user_args().is_empty():
		m.laws.recorded.connect(func(inc): print("   %.2f INCIDENT %s  must_stop=%s" % [m.clock, inc.label(), inc.must_stop]))
		m.phase_changed.connect(func(ph): print("   %.2f phase %s" % [m.clock, Match.Phase.keys()[ph]]))
		m.ball.touched.connect(func(by, kind): print("   %.2f touch %s %s poss=%d" % [m.clock, by.name if not by is Footballer else Incident.who(by), kind, m.ai.possession]))
		m.ball.hit_referee.connect(func(sp): print("   %.2f HIT REF %.1f" % [m.clock, sp]))
	var bot := BotReferee.new()
	bot.setup(m, ref)
	_bot = bot
	bot.idle = current.idle
	bot.stay = def.get("ref_still", false)
	bot.trace = not OS.get_cmdline_user_args().is_empty()
	holder.add_child(bot)
	if current.id == "t_move" and not current.idle:
		holder.set_meta("markers", true)
	started = Time.get_ticks_msec()


var _tick := 0.0
var _bot: BotReferee


func _process(_d: float) -> void:
	if holder == null:
		return
	# Tell the bot which incident this drill is about, so it deals with that one first.
	if _bot != null and run != null:
		_bot.focus = run._scripted
	if OS.get_cmdline_user_args().has("positions") and run != null and run.m != null:
		_tick += _d
		if _tick > 0.25:
			_tick = 0.0
			var p9 = run._player([0, 9])
			var b = run.m.ball
			print("   t=%.2f ball(%.1f,%.1f,%.1f) v%.1f  #9(%.1f,%.1f) held=%s free=%s state=%d" % [run.t, b.global_position.x, b.global_position.y, b.global_position.z, b.speed(), p9.global_position.x, p9.global_position.z, run.m.ai.held.has(p9), p9.is_free(), p9.state])
	if holder.has_meta("markers") and run._markers.size() > 0:
		# Walk to the next marker not yet visited.
		for mk in run._markers:
			if mk.visible:
				run.ref.global_position = run.ref.global_position.move_toward(Vector3(mk.global_position.x, 0, mk.global_position.z), 0.4)
				break
	if Time.get_ticks_msec() - started > 60000:
		# A timeout says nothing on its own, so it says where it stopped: a drill that
		# hangs is nearly always one waiting for a phase that nothing is going to leave.
		var inc := run._incident()
		_done({"passed": false, "lines": ["TIMEOUT in %s at clock %.1f, %s" % [
			Match.Phase.keys()[run.m.phase], run.m.clock,
			"no incident yet" if inc == null else "%.1f s after %s" % [run.m.clock - inc.time, inc.label()]]]})


func _done(result: Dictionary) -> void:
	results.append({"id": current.id, "idle": current.idle, "passed": result.passed, "line": " / ".join(result.lines)})
	# When a case comes out the wrong way, say what happened to the incident it was about,
	# there and then. This check has been flaky more than once, and every hunt for the
	# reason cost a run of the same drill twenty times over waiting for it to happen again;
	# four lines here turn the next one into a read rather than a hunt.
	var expected: bool = not current.idle or current.id == "s_dive"
	if result.passed != expected and run != null:
		var inc := run._incident()
		if inc == null:
			print("     why: no incident of the right kind ever happened")
		else:
			print("     why: %s  whistled=%s at %.1f (%.1f s after it), restart=%s to %s, cards=%d, advantage=%s"
				% [inc.label(), inc.whistled, inc.whistle_time, inc.whistle_time - inc.time,
				inc.restart_given if inc.restart_given != &"" else "none",
				inc.restart_team.short if inc.restart_team != null else "-",
				inc.cards_given.size(), inc.advantage])
			print("     ended in %s at clock %.1f, %.1f s after the incident"
				% [Match.Phase.keys()[run.m.phase], run.m.clock, run.m.clock - inc.time])
	_next.call_deferred()
