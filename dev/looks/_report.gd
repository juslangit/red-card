extends Node3D

## The assessor's report at the end of a match, for looking at.
##
##   Godot --path . --resolution 1600x900 res://dev/looks/_report.tscn [-- level seconds]
##
## Plays a short match with the bot refereeing it, then opens the report the way the game
## does. Written on 2026-09-20 for the positioning map — a page of numbers the game had
## been collecting all along and never showed anybody.

var m: Match
var ref: Referee
var bot: BotReferee
var screen: ReportScreen
var _shown := false
var _wait := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var level: String = args[0] if args.size() > 0 else "town"
	var half := float(args[1]) if args.size() > 1 else 45.0
	Engine.time_scale = 6.0
	Engine.max_physics_steps_per_frame = 64
	var settings := Settings.new()
	m = Match.new()
	m.setup(Names.team_from(0), Names.team_from(1), level, half)
	add_child(m)
	ref = Referee.new()
	ref.setup(m, settings)
	add_child(ref)
	ref.global_position = Vector3(-5, 0, 10)
	m.attach_referee(ref)
	bot = BotReferee.new()
	bot.setup(m, ref)
	add_child(bot)


func _process(delta: float) -> void:
	if m.phase != Match.Phase.FULL_TIME or _shown:
		if _shown:
			_wait += delta
			if _wait > 0.6:
				get_viewport().get_texture().get_image().save_png("res://dev/shots/report.png")
				get_tree().quit()
		return
	_shown = true
	Engine.time_scale = 1.0
	# The report screen belongs to the Play scene; here it is given just enough of one to
	# open with — the match it is reporting on, and a replay viewer for its buttons.
	var stand_in := Node.new()
	stand_in.set_script(load("res://dev/looks/_report_play.gd"))
	add_child(stand_in)
	stand_in.set("m", m)
	var viewer := ReplayViewer.new()
	viewer.setup(m, ref)
	add_child(viewer)
	stand_in.set("replay", viewer)
	screen = ReportScreen.new()
	screen.play = stand_in
	add_child(screen)
	screen.open(m.assessor.report, "")
	print("protests %d, waved away %d" % [m.assessor.protests, m.assessor.protests_managed])
	for line in m.assessor.report.lines:
		if line.incident == null:
			print("   report line: %s (%+.2f)" % [line.text, line.points])
	print("mark %.1f, %d decisions, trail of %d points"
		% [m.assessor.report.mark, m.assessor.report.lines.size(), m.assessor.report.trail.size()])
