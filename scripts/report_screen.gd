class_name ReportScreen
extends CanvasLayer

## The assessor's report: the mark, what went right and wrong, and a replay of each.
##
## This is the only place in the game the truth is shown, which is the Referee For Fun
## rule carried over: nothing may be revealed while there is still something to judge.
## Every line that has an incident behind it has a replay button, and the replay opens on
## the broadcast camera with "Your eyes" one click away.

var play  # the Play scene
var _root: Control
var _body: VBoxContainer
var _scroll: ScrollContainer
var _first_button: Button


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.build()
	add_child(_root)
	_root.add_child(Menus.backdrop(0.86))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 110)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 60)
	_root.add_child(margin)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	_scroll.add_child(_body)
	visible = false
	play.replay.closed.connect(func():
		if visible:
			_root.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)


func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()
	_first_button = null


func open(report: Dictionary, career_outcome: String) -> void:
	_clear()
	visible = true
	var m: Match = play.m
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 40)
	_body.add_child(head)
	var left := VBoxContainer.new()
	head.add_child(left)
	left.add_child(Menus.card_tag(UiTheme.ACCENT, "ASSESSOR'S REPORT"))
	left.add_child(Menus.title("%s %d – %d %s" % [m.teams[0].name.to_upper(), m.teams[0].goals, m.teams[1].goals, m.teams[1].name.to_upper()], UiTheme.TITLE))
	left.add_child(Menus.text("%s · %s" % [m.level.name, _mode_words()], UiTheme.BODY))
	var mark_box := VBoxContainer.new()
	head.add_child(mark_box)
	var colour := UiTheme.GOOD if report.mark >= 8.3 else (UiTheme.YELLOW if report.mark >= 7.9 else UiTheme.BAD)
	mark_box.add_child(UiTheme.label("%.1f" % report.mark, 140, colour, UiTheme.display()))
	mark_box.add_child(UiTheme.label(report.band, UiTheme.BODY, UiTheme.CHALK, UiTheme.heavy()))

	if career_outcome != "":
		_body.add_child(_career_banner(career_outcome))

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 50)
	_body.add_child(stats)
	var pos: Dictionary = report.positioning
	stats.add_child(_stat("KEY DECISIONS", "%d / %d" % [report.key_right, report.key_total]))
	stats.add_child(_stat("ALL DECISIONS", "%d / %d" % [report.decisions_right, report.decisions_total]))
	stats.add_child(_stat("WELL POSITIONED", "%d%%" % int(pos.good * 100.0)))
	stats.add_child(_stat("AVERAGE DISTANCE", "%.0f m" % pos.average))
	stats.add_child(_stat("DISTANCE RUN", "%.1f km" % report.distance_km))

	_body.add_child(UiTheme.label("THE MATCH, DECISION BY DECISION", UiTheme.HEADING, UiTheme.ACCENT, UiTheme.heavy()))
	var lines: Array = report.lines.duplicate()
	lines.sort_custom(func(a, b): return (a.incident.time if a.incident else 0.0) < (b.incident.time if b.incident else 0.0))
	if lines.is_empty():
		_body.add_child(Menus.text("Nothing to report — a quiet match."))
	for line in lines:
		_body.add_child(_line(line))
	_body.add_child(_positioning_note(pos))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	_body.add_child(buttons)
	var go := Menus.button("Continue", func(): play.leave())
	buttons.add_child(go)
	buttons.add_child(Menus.button("Referee it again", func(): play.retry()))
	go.grab_focus.call_deferred()


func _mode_words() -> String:
	match play.config.get("mode"):
		"career":
			return Game.career.title()
		"quick":
			return "Quick match"
	return ""


func _career_banner(outcome: String) -> Control:
	var words: Array = {
		"continue": ["SEASON CONTINUES", "Average so far %.2f — %.1f needed to go up." % [Game.career.average(), Career.PROMOTION_MARK]],
		"promoted": ["PROMOTED", "On to the %s." % Game.career.title()],
		"repeat": ["ANOTHER SEASON", "Your average fell short of %.1f. Another season at this level." % Career.PROMOTION_MARK],
		"champion": ["YOU REFEREED THE CUP FINAL", "The top of the game. Your career is complete."],
	}.get(outcome, ["", ""])
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	box.add_child(Menus.card_tag(UiTheme.GOOD if outcome in ["promoted", "champion"] else UiTheme.YELLOW, words[0]))
	var line := Menus.text(words[1], UiTheme.BODY, UiTheme.CHALK)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(line)
	return box


func _stat(label: String, value: String) -> Control:
	var box := VBoxContainer.new()
	box.add_child(UiTheme.label(label, UiTheme.SMALL, UiTheme.MUTED, UiTheme.heavy()))
	box.add_child(UiTheme.label(value, UiTheme.TITLE, UiTheme.CHALK, UiTheme.display()))
	return box


func _line(line: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var inc: Incident = line.incident
	var points: float = line.points
	var tag_colour := UiTheme.GOOD if points > 0.0 else (UiTheme.BAD if points < 0.0 else UiTheme.EDGE)
	var minute := UiTheme.label("%d'" % inc.minute if inc else "—", UiTheme.BODY, UiTheme.MUTED, UiTheme.heavy())
	minute.custom_minimum_size = Vector2(70, 0)
	row.add_child(minute)
	var tag := Menus.card_tag(tag_colour, ("+%.2f" % points) if points > 0.0 else ("%.2f" % points if points < 0.0 else "  ·  "))
	tag.custom_minimum_size = Vector2(110, 0)
	row.add_child(tag)
	if line.key:
		row.add_child(Menus.card_tag(UiTheme.RED, "KEY"))
	var words := Menus.text(line.text, UiTheme.BODY, UiTheme.CHALK)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	if inc != null and play.m.recorder.frames.size() > 2:
		var b := Menus.button("▶ Replay", func():
			_root.visible = false
			var ref_d := "%.0f m away" % inc.ref_distance
			play.replay.open(inc.time, "%d'  %s  —  you were %s" % [inc.minute, inc.label(), ref_d], inc.position), 200)
		row.add_child(b)
	return row


func _positioning_note(pos: Dictionary) -> Control:
	var words := "Positioning: %d%% of the time you were between 5 and 35 metres from the ball." % int(pos.good * 100.0)
	if pos.far > 0.2:
		words += " Too often a long way from play — the further away, the less you can see."
	if pos.close > 0.1:
		words += " You were in the way at times; players had to run round you."
	if pos.blocked > 0.25:
		words += " Your view was blocked by players a lot: move to see between them, not behind them."
	return Menus.text(words, UiTheme.BODY, UiTheme.MUTED)


## For a training drill or a scenario: one incident, one verdict, and the way on.
func open_scenario(result: Dictionary, run) -> void:
	_clear()
	visible = true
	_body.add_child(Menus.card_tag(UiTheme.ACCENT, "TRAINING" if play.config.get("mode") == "training" else "SCENARIO"))
	_body.add_child(Menus.title(result.title.to_upper(), UiTheme.TITLE))
	var passed: bool = result.passed
	_body.add_child(UiTheme.label("WELL DONE" if passed else "NOT QUITE", UiTheme.HUGE, UiTheme.GOOD if passed else UiTheme.BAD, UiTheme.display()))
	for line in result.lines:
		_body.add_child(Menus.text(line, UiTheme.BODY, UiTheme.CHALK))
	if result.has("law"):
		_body.add_child(Menus.text(result.law, UiTheme.BODY, UiTheme.MUTED))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	_body.add_child(buttons)
	var inc: Incident = result.get("incident")
	if inc != null:
		buttons.add_child(Menus.button("▶ Replay", func():
			_root.visible = false
			play.replay.open(inc.time, inc.label(), inc.position), 220))
	var again := Menus.button("Try again", func(): play.retry(), 260)
	buttons.add_child(again)
	if result.get("next", "") != "":
		buttons.add_child(Menus.button("Next", func():
			var cfg: Dictionary = play.config.duplicate()
			cfg.scenario = result.next
			Game.start_match(cfg), 220))
	buttons.add_child(Menus.button("Back", func(): play.leave(), 220))
	(buttons.get_child(buttons.get_child_count() - 2) as Button).grab_focus.call_deferred()
	if passed and play.config.get("mode") == "training":
		Game.settings.trained = true
		Game.settings.save()
