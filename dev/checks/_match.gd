extends Node3D

## A whole match refereed by the bot, headless and fast. Prints what happened.
##   Godot --headless --path . res://dev/checks/_match.tscn -- [level] [half_seconds] [speed]

var m: Match
var bot: BotReferee
var start := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var level := args[0] if args.size() > 0 else "town"
	var half := float(args[1]) if args.size() > 1 else 120.0
	var speed := float(args[2]) if args.size() > 2 else 8.0
	Engine.time_scale = speed
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 64
	var settings := Settings.new()
	settings.apply()
	m = Match.new()
	var home := Names.team_from(0)
	var away := Names.team_from(1)
	m.setup(home, away, level, half)
	add_child(m)
	var ref := Referee.new()
	ref.setup(m, settings)
	add_child(ref)
	ref.global_position = Vector3(-5, 0, 10)
	m.attach_referee(ref)
	bot = BotReferee.new()
	bot.setup(m, ref)
	bot.log_decisions = OS.get_cmdline_user_args().has("verbose")
	add_child(bot)
	start = Time.get_ticks_msec()
	if OS.get_cmdline_user_args().has("verbose"):
		verbose = true
	if verbose: m.phase_changed.connect(func(ph): print("   phase -> %s  stopped_for=%s" % [Match.Phase.keys()[ph], m.stopped_for.kind if m.stopped_for else "-"]))
	if verbose: m.laws.recorded.connect(func(inc): print("   INCIDENT %s %s" % [inc.kind, inc.label()]))
	m.half_ended.connect(func(h): print("--- end of half %d at %.1f  score %d-%d" % [h, m.match_seconds() / 60.0, home.goals, away.goals]))


var _next_status := 0.0
var verbose := false


func _process(_delta: float) -> void:
	if m.clock > _next_status:
		_next_status = m.clock + 4.0
		var c = m.ai.carrier
		if not verbose:
			return
		print("t=%5.1f %-9s ball=(%5.1f,%4.1f,%5.1f) v=%4.1f carrier=%s poss=%d" % [m.clock, Match.Phase.keys()[m.phase], m.ball.global_position.x, m.ball.global_position.y, m.ball.global_position.z, m.ball.speed(), ("%s#%d" % [c.team.short, c.number]) if c else "-", m.ai.possession])
	if m.phase == Match.Phase.FULL_TIME:
		_summary()
		get_tree().quit()
	if Time.get_ticks_msec() - start > 600000:
		print("TIMEOUT phase ", m.phase)
		_summary()
		get_tree().quit()


func _summary() -> void:
	var counts := {}
	for inc in m.laws.incidents:
		counts[inc.kind] = counts.get(inc.kind, 0) + 1
	print("incidents: ", counts)
	print("ai: ", m.ai.stats)
	print("score %s %d - %d %s" % [m.teams[0].name, m.teams[0].goals, m.teams[1].goals, m.teams[1].name])
	var r := m.assessor.report
	print("mark ", r.get("mark"), " ", r.get("band"), " decisions ", r.get("decisions_right"), "/", r.get("decisions_total"))
	print("positioning ", r.get("positioning"))
	print("wall ms ", Time.get_ticks_msec() - start)
