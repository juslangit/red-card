extends Node3D

## The match screen: a Match, the referee in it, the HUD, and what happens around it —
## pausing, half-time, the full-time report, replays and VAR reviews.
##
## Every kind of game goes through here: a career fixture, a quick match, a training
## drill and a scenario challenge. `Game.pending` says which.

var m: Match
var ref: Referee
var hud: Hud
var config: Dictionary
var scenario: ScenarioRun = null
var pause_menu: PauseMenu
var report_screen: ReportScreen
var replay: ReplayViewer
var _half_time_left := 0.0
var _panel: CanvasLayer


func _ready() -> void:
	config = Game.pending if Game.pending.has("mode") else {"mode": "quick", "level": "town", "home": 0, "away": 1}
	var level: String = config.get("level", "town")
	var home := Names.team_from(config.get("home", 0))
	var away := Names.team_from(config.get("away", 1))
	m = Match.new()
	m.name = "Match"
	m.setup(home, away, level, config.get("half", Game.half_seconds()))
	add_child(m)

	ref = Referee.new()
	ref.name = "Referee"
	ref.setup(m, Game.settings)
	add_child(ref)
	# Out on the pitch by the centre circle for the kick-off, facing play.
	ref.global_position = Vector3(-4.0, 0, 12.0)
	ref.yaw = deg_to_rad(20.0)
	m.attach_referee(ref)

	hud = Hud.new()
	hud.setup(m, ref, Game.settings)
	add_child(hud)

	replay = ReplayViewer.new()
	replay.setup(m, ref)
	add_child(replay)

	pause_menu = PauseMenu.new()
	pause_menu.play = self
	add_child(pause_menu)

	report_screen = ReportScreen.new()
	report_screen.play = self
	add_child(report_screen)

	m.phase_changed.connect(_on_phase)
	if m.var_system != null:
		m.var_system.review_requested.connect(_on_review)
	if config.has("scenario"):
		scenario = Scenarios.start(config.scenario, m, ref, hud)
		add_child(scenario)
		scenario.finished.connect(_scenario_finished)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"rc_pause"):
		if replay.active:
			if not replay.deciding():
				replay.close()
		elif report_screen.visible:
			pass
		else:
			pause_menu.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"rc_notebook"):
		hud.toggle_notebook()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not pause_menu.visible and not report_screen.visible and not replay.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _half_time_left > 0.0:
		_half_time_left -= delta
		if _half_time_left <= 0.0:
			_close_panel()
			_second_half()


func _on_phase(phase: Match.Phase) -> void:
	match phase:
		Match.Phase.HALF_TIME:
			_show_panel("HALF-TIME", "%s %d – %d %s" % [m.teams[0].name, m.teams[0].goals, m.teams[1].goals, m.teams[1].name],
				"The teams change ends. Second half in a moment.")
			_half_time_left = 6.0
		Match.Phase.FULL_TIME:
			_full_time()


## VAR has sent the referee to the monitor: the replay, with the decision to make.
func _on_review(inc: Incident, title: String, choices: Array, apply: Callable) -> void:
	var when: float = inc.time if inc != null else m.clock - 3.0
	var focus: Vector3 = inc.position if inc != null else m.ball.global_position
	replay.open(when, "ON-FIELD REVIEW — %s" % title, focus, choices)
	replay.chosen.connect(func(i):
		apply.call(i)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED, CONNECT_ONE_SHOT)


func _second_half() -> void:
	m.start_second_half()
	# The referee takes his place for the other team's kick-off, mirrored.
	ref.global_position = Vector3(4.0, 0, 12.0)
	ref.yaw = deg_to_rad(-20.0)


func _full_time() -> void:
	m.assessor.finish()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ref.enabled = false
	var report: Dictionary = m.assessor.report
	var outcome := ""
	if config.get("mode") == "career":
		var score := "%d–%d" % [m.teams[0].goals, m.teams[1].goals]
		outcome = Game.career.record(config, report.mark, score)
	report_screen.open(report, outcome)


func _scenario_finished(result: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ref.enabled = false
	m.paused = true
	report_screen.open_scenario(result, scenario)


func _show_panel(title: String, line: String, sub: String) -> void:
	_close_panel()
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.build()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.add_child(UiTheme.label(title, UiTheme.HUGE, UiTheme.ACCENT, UiTheme.display()))
	box.add_child(UiTheme.label(line, UiTheme.TITLE, UiTheme.CHALK, UiTheme.heavy()))
	box.add_child(UiTheme.label(sub, UiTheme.BODY, UiTheme.MUTED, UiTheme.body()))
	card.add_child(box)
	root.add_child(card)
	card.reset_size()
	card.position = -card.size * 0.5
	_panel = layer


func _close_panel() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null


## Leaving the match: to the career screen for a career fixture, otherwise the menu.
func leave() -> void:
	var page := "career" if config.get("mode") == "career" else ("training" if config.get("mode") == "training" else ("scenarios" if config.get("mode") == "scenario" else ""))
	Game.to_menu(page)


func retry() -> void:
	Game.start_match(config)
