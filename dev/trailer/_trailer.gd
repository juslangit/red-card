extends Node3D

## The trailer, played by the game.
##
##   Godot --path . --resolution 1920x1080 --fixed-fps 30 \
##         --write-movie dev/trailer/raw.avi res://dev/trailer/_trailer.tscn
##
## Two minutes, cut from a real match: a bot referees it while this walks a camera round
## the pitch, forces the moments the trailer needs, and puts a line of type on the screen
## now and then. Nothing here is a mock-up — the players are the match AI, the decisions
## are the Laws, the report at the end is the assessor's.
##
## It leads on the job rather than the football, because that is what makes the game
## unlike any other football game: you are the official, and the whistle is yours.
##
## Godot's Movie Maker writes one frame per tick at a fixed rate, so the recording is
## deterministic however slowly it renders — a two-minute film always comes out two
## minutes long.

const SECONDS := 118.0
## Movie Maker writes one frame per tick at a fixed rate, so the timeline is counted in
## frames. Taking it from `delta` made a 118-second film come out 68 seconds long.
const FPS := 30.0

var m: Match
var ref: Referee
var hud: Hud
var bot: BotReferee
var cam: Camera3D
var card: Label
var sub: Label
var fade: ColorRect
var t := 0.0
var _frames := 0.0
var _done := {}
var _shot := {}


func _ready() -> void:
	m = Match.new()
	m.setup(Names.team_from(0), Names.team_from(1), "town", 420.0)
	add_child(m)
	ref = Referee.new()
	ref.setup(m, Game.settings)
	add_child(ref)
	ref.global_position = Vector3(-6, 0, 10)
	m.attach_referee(ref)
	hud = Hud.new()
	hud.setup(m, ref, Game.settings)
	add_child(hud)
	hud.visible = false
	bot = BotReferee.new()
	bot.setup(m, ref)
	add_child(bot)
	cam = Camera3D.new()
	cam.fov = 42.0
	add_child(cam)
	cam.current = true

	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(fade)
	card = UiTheme.label("", UiTheme.HUGE, UiTheme.CHALK, UiTheme.display())
	# Outlined, because half of these lines sit over a sunlit sky.
	card.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.9))
	card.add_theme_constant_override("outline_size", 16)
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(card)
	sub = UiTheme.label("", UiTheme.HEADING, UiTheme.ACCENT, UiTheme.heavy())
	sub.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.9))
	sub.add_theme_constant_override("outline_size", 10)
	sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.offset_top = 130.0
	root.add_child(sub)


## One shot: the camera somewhere, looking at something, for a while.
func _look(from: Vector3, at: Vector3, fov := 42.0) -> void:
	cam.global_position = from
	cam.fov = fov
	if from.distance_to(at) > 0.3:
		cam.look_at(at, Vector3.UP)


## Says something, held for `seconds`, fading at both ends.
func _say(words: String, under := "", seconds := 2.6) -> void:
	card.text = words
	sub.text = under
	_shot["caption_left"] = seconds


func _once(key: String) -> bool:
	if _done.has(key):
		return false
	_done[key] = true
	return true


func _player(team: int, number: int) -> Footballer:
	for p: Footballer in m.teams[team].players:
		if p.number == number:
			return p
	return null


## A foul, on cue, in front of wherever the referee is standing.
func _stage_foul(severity: Laws.Severity, sliding: bool) -> Array:
	var attacker := _player(0, 10)
	var defender := _player(1, 5)
	if attacker == null or defender == null:
		return []
	var where: Vector3 = ref.global_position + (Vector3.FORWARD.rotated(Vector3.UP, ref.yaw)) * 7.0
	attacker.global_position = m.spec.clamp_to_field(where, 3.0)
	defender.global_position = attacker.global_position - Vector3(0.9, 0, 0.2)
	m.ai.give_ball(attacker)
	m.ai.force_foul(defender, attacker, severity, sliding, true, false)
	return [attacker, defender]


func _process(_delta: float) -> void:
	_frames += 1.0
	var delta := 1.0 / FPS
	t = _frames / FPS
	# The type fades itself out, so a line can be set once and forgotten.
	if _shot.has("caption_left"):
		_shot.caption_left -= delta
		var left: float = _shot.caption_left
		var alpha := clampf(minf(left, 0.45) / 0.45, 0.0, 1.0)
		card.modulate.a = alpha
		sub.modulate.a = alpha
		if left <= 0.0:
			card.text = ""
			sub.text = ""
			_shot.erase("caption_left")
	# Open from black, close to black.
	fade.color.a = clampf(1.0 - t / 1.2, 0.0, 1.0)
	if t > SECONDS - 2.0:
		fade.color.a = clampf((t - (SECONDS - 2.0)) / 2.0, 0.0, 1.0)
	# The HUD belongs to the referee's own eyes and nowhere else. Tying it to a stretch of
	# the clock left a control legend sitting over a cinematic wide, which is the quickest
	# way to make a trailer look like a screen recording; tying it to the camera cannot.
	hud.visible = ref.camera.current and _report_screen == null
	_cut()
	if t > SECONDS:
		get_tree().quit()


## The cut. Times are seconds from the first frame.
func _cut() -> void:
	var ball_at: Vector3 = m.ball.global_position

	# --- the job ------------------------------------------------------------------------
	if t < 3.0:
		if _once("kick"):
			m.whistle()          # away we go
		_look(ball_at + Vector3(4.0, 1.4, 4.0), ball_at + Vector3(0, 0.8, 0), 34.0)
	elif t < 9.0:
		# A challenge, close, at grass height: the thing you are being asked to judge.
		if _once("foul_1"):
			var two := _stage_foul(Laws.Severity.RECKLESS, true)
			if not two.is_empty():
				_shot["subject"] = two[0]
		var who = _shot.get("subject")
		if who != null and is_instance_valid(who):
			_look((who as Node3D).global_position + Vector3(3.4, 1.2, 3.0),
				(who as Node3D).global_position + Vector3(0, 0.8, 0), 34.0)
	elif t < 13.0:
		if _once("say_1"):
			_say("YOU ARE THE REFEREE", "", 3.2)
		var who = _shot.get("subject")
		if who != null and is_instance_valid(who):
			_look((who as Node3D).global_position + Vector3(1.6, 1.5, 3.0),
				(who as Node3D).global_position + Vector3(0, 1.0, 0), 38.0)
	elif t < 20.0:
		# Your own eyes, your own whistle.
		if _once("first_person"):
			ref.camera.current = true
			m.whistle()
		if t > 16.0 and _once("point"):
			ref.point()
	elif t < 27.0:
		if _once("say_2"):
			_say("EVERY DECISION IS YOURS", "the whistle · the arm · the card", 3.4)
		if _once("back_to_cam"):
			cam.current = true
		_look(ref.global_position + Vector3(3.4, 2.0, 3.4), ref.global_position + Vector3(0, 1.3, 0), 36.0)

	# --- the Laws -----------------------------------------------------------------------
	elif t < 36.0:
		if _once("card"):
			ref.camera.current = true
			var off := _player(1, 5)
			if off != null:
				m.show_card(off, &"yellow")
		if t > 31.0 and _once("say_3"):
			_say("AND THE LAWS ARE WATCHING", "", 3.0)
	elif t < 46.0:
		if _once("wide"):
			cam.current = true
		var along := (t - 36.0) / 10.0
		_look(Vector3(lerpf(-40.0, 10.0, along), 14.0, 34.0), ball_at, 46.0)
		if _once("say_4"):
			_say("ELEVEN A SIDE, PLAYED FOR REAL", "every tackle, offside and ball over the line", 3.6)

	# --- the grounds --------------------------------------------------------------------
	elif t < 58.0:
		var along := (t - 46.0) / 12.0
		_look(Vector3(lerpf(46.0, 20.0, along), lerpf(2.2, 8.0, along), lerpf(-30.0, -40.0, along)),
			Vector3(0, 1.0, 0), 44.0)
		if _once("say_5"):
			_say("FOUR GROUNDS", "a village rec to a floodlit final", 3.2)

	# --- the report ---------------------------------------------------------------------
	elif t < 74.0:
		if _once("report"):
			_open_report()
		if _once("say_6"):
			_say("AND SOMEBODY IS MARKING YOU", "", 3.0)
	elif t < 88.0:
		if _once("map"):
			_scroll_report()

	# --- back to the football -----------------------------------------------------------
	elif t < 104.0:
		if _once("close_report"):
			_close_report()
			cam.current = true
		var along := (t - 88.0) / 16.0
		_look(ball_at + Vector3(lerpf(8.0, 3.0, along), lerpf(3.0, 1.6, along), lerpf(9.0, 4.0, along)),
			ball_at + Vector3(0, 0.8, 0), lerpf(44.0, 34.0, along))
		if _once("say_7"):
			_say("GET IT RIGHT", "nobody will mention you. that is the job.", 3.6)

	# --- the title ----------------------------------------------------------------------
	else:
		if _once("title"):
			_say("RED CARD", "free · macOS and Windows · juslangit.github.io/red-card", 14.0)
		_look(Vector3(18.0, 2.0, 22.0), Vector3(0, 0.6, 0), 36.0)


# --- the report, shown the way the game shows it -------------------------------------

var _report_screen: ReportScreen
var _stand_in: Node


## The assessor's own report on the match being played, opened mid-trailer. It is the real
## screen with the real numbers, which is the only kind worth putting in a trailer.
func _open_report() -> void:
	m.assessor.finish()
	_stand_in = Node.new()
	_stand_in.set_script(load("res://dev/looks/_report_play.gd"))
	add_child(_stand_in)
	_stand_in.set("m", m)
	var viewer := ReplayViewer.new()
	viewer.setup(m, ref)
	add_child(viewer)
	_stand_in.set("replay", viewer)
	_report_screen = ReportScreen.new()
	_report_screen.play = _stand_in
	add_child(_report_screen)
	_report_screen.open(m.assessor.report, "")


## Down the page to the map: where you stood for every decision you made.
func _scroll_report() -> void:
	_say("WHERE YOU STOOD, FOR EVERY ONE", "", 3.2)
	var scroll := _report_screen.find_children("*", "ScrollContainer", true, false)
	if not scroll.is_empty():
		var bar := (scroll[0] as ScrollContainer)
		var tween := create_tween()
		tween.tween_property(bar, "scroll_vertical", 620, 6.0).set_trans(Tween.TRANS_SINE)


func _close_report() -> void:
	if _report_screen != null:
		_report_screen.queue_free()
		_report_screen = null
	m.paused = false
