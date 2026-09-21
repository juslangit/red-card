extends Node3D

## The title screen and every menu page, over the National Stadium at night.
##
## The stadium behind the menu is the real one from the final, built by the same Venue
## code, with a camera drifting slowly round the bowl — the promise of where the career
## ends up.

var _ui: Control
var _page: VBoxContainer
var _side: VBoxContainer
var _side_plate: PanelContainer
var _camera: Camera3D
var _t := 0.0
var _quick := {"level": 1, "home": 0, "away": 1}
var _rebinding: StringName = &""
## Which page is showing, so Escape knows whether there is anywhere to go back to.
var _page_name := "main"
## The stepped setting that was last changed, so the focus can find its way back to it
## after the page is rebuilt, and whether it claimed the focus this time round — a page
## that grabs focus for its own first button would otherwise take it straight back.
var _focus_wanted := ""
var _focus_taken := false
## Whether "start a new career" is waiting for a second press.
var _confirm_reset := false
var _rebind_button: Button


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var venue := Venue.new()
	add_child(venue)
	venue.build("final")
	venue.stands.set_colours(Names.club(0).shirt, Names.club(0).shorts, Names.club(1).shirt, Names.club(1).shorts)
	venue.stands.set_excitement(0.15, 0.15)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)
	_camera.current = true

	# The title sequence, once a session: an empty ground, the name, and in. It is the
	# first thing a room full of people sees, and the menu was starting cold.
	var opening := Cutscene.new()
	add_child(opening)
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UiTheme.build()
	layer.add_child(_ui)
	# A dark wash down the left for the menu to sit on.
	var wash := TextureRect.new()
	wash.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	wash.custom_minimum_size = Vector2(900, 0)
	var grad := Gradient.new()
	grad.set_color(0, Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.94))
	grad.set_color(1, Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 4
	wash.texture = tex
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.size = Vector2(900, 2000)
	_ui.add_child(wash)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 110)
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 60)
	margin.add_theme_constant_override("margin_right", 80)
	_ui.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 90)
	margin.add_child(row)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 14)
	_page.custom_minimum_size = Vector2(620, 0)
	row.add_child(_page)
	# The right-hand column sits on its own plate: straight over a stand full of people
	# its text could not be read.
	var side_column := VBoxContainer.new()
	side_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(side_column)
	_side_plate = PanelContainer.new()
	_side_plate.add_theme_stylebox_override("panel", UiTheme.plate(UiTheme.ACCENT, 0.84))
	_side_plate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_column.add_child(_side_plate)
	# It scrolls. The settings page lists every verb in the game down this column, and with
	# the four for looking about added on 2026-09-20 the last of them fell off the bottom of
	# the screen where nothing could reach them.
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_plate.add_child(side_scroll)
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 12)
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(_side)

	if not Game.title_seen:
		Game.title_seen = true
		_ui.visible = false
		opening.play(Cutscenes.title(null), func():
			_ui.visible = true
			_camera.current = true)
	var page: String = Game.pending.get("page", "")
	match page:
		"career":
			_career()
		"training":
			_list("training")
		"scenarios":
			_list("scenario")
		_:
			_main()


func _process(delta: float) -> void:
	_side_plate.visible = _side.get_children().any(func(c): return not c.is_queued_for_deletion())
	_t += delta * 0.05
	_camera.global_position = Vector3(cos(_t) * 62.0, 18.0 + sin(_t * 0.7) * 3.0, sin(_t) * 44.0)
	_camera.look_at(Vector3(0, 2.0, 0), Vector3.UP)


func _clear() -> void:
	_focus_taken = false
	for c in _page.get_children():
		c.queue_free()
	for c in _side.get_children():
		c.queue_free()


func _logo() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 26)
	# The card itself: a red card, tilted, the way it is held up.
	var card := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.RED
	style.set_corner_radius_all(8)
	style.shadow_size = 12
	style.shadow_color = Color(0, 0, 0, 0.5)
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(78, 108)
	card.rotation_degrees = -9.0
	box.add_child(card)
	var words := VBoxContainer.new()
	words.add_child(UiTheme.label("RED CARD", 110, UiTheme.CHALK, UiTheme.display()))
	var sub := UiTheme.label("YOU ARE THE REFEREE", UiTheme.HEADING, UiTheme.ACCENT, UiTheme.heavy())
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	words.add_child(sub)
	box.add_child(words)
	return box


func _main() -> void:
	_page_name = "main"
	_confirm_reset = false
	_clear()
	_page.add_child(_logo())
	_page.add_child(_gap(30))
	var career := Game.career
	var go_career := Menus.button("Career — %s" % career.title() if not career.history.is_empty() else "Start a career", _career)
	_page.add_child(go_career)
	_page.add_child(Menus.button("Quick match", _quick_match))
	_page.add_child(Menus.button("Training ground", func(): _list("training")))
	_page.add_child(Menus.button("Challenges", func(): _list("scenario")))
	_page.add_child(Menus.button("Settings", _settings))
	_page.add_child(Menus.button("Credits", _credits))
	_page.add_child(Menus.button("Quit", func(): get_tree().quit()))
	if not _focus_taken:
		go_career.grab_focus.call_deferred()
	if not Game.settings.trained:
		_side.add_child(Menus.card_tag(UiTheme.YELLOW, "NEW HERE?"))
		_side.add_child(Menus.text("The training ground teaches every signal in a few minutes: moving, the whistle, pointing, advantage, cards, the flag and the watch.", UiTheme.BODY, UiTheme.CHALK))


func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


## A stepped setting, which rebuilds its page and then puts the focus back on itself —
## without that, every press of an arrow key would bounce you to the top of the page.
func _stepped(text: String, step: Callable) -> Button:
	var b := Menus.chooser(text, func(way: int):
		_focus_wanted = text.split(":")[0]
		step.call(way))
	if _focus_wanted != "" and text.begins_with(_focus_wanted):
		_focus_wanted = ""
		_focus_taken = true
		b.grab_focus.call_deferred()
	return b


func _back() -> Button:
	return Menus.button("‹ Back", _main, 260)


# --- career -----------------------------------------------------------------------------

## The career page. Three questions, in the order a referee asks them: where am I in all
## this, am I doing well enough to go up, and who have I got next?
##
## It used to answer the first not at all — you had to know that the County League was the
## second of four — and the second in a grey sentence, which is the least readable thing on
## a page and the most important thing on it. Worse, "Start a new career", which wipes
## everything, sat directly under "Referee this match" looking exactly the same as it.
func _career() -> void:
	_page_name = "career"
	_clear()
	var career := Game.career
	_page.add_child(Menus.title("CAREER"))
	_page.add_child(_ladder(career))
	_page.add_child(_gap(6))
	if career.finished:
		_page.add_child(Menus.card_tag(UiTheme.GOOD, "CAREER COMPLETE"))
		_page.add_child(Menus.career_record(career))
	else:
		_page.add_child(_season_so_far(career))
		_page.add_child(_gap(8))
		var fixture := career.next_fixture()
		_page.add_child(_fixture_card(Names.club(fixture.home), Names.club(fixture.away)))
		_page.add_child(_ground_line(Venue.level_by_id(career.level_id())))
		_page.add_child(_gap(6))
		var go := Menus.button("Referee this match", func():
			var cfg := fixture.duplicate()
			cfg["half"] = Game.half_seconds()
			Game.start_match(cfg))
		_page.add_child(go)
		if not _focus_taken:
			go.grab_focus.call_deferred()
	_page.add_child(_gap(10))
	_page.add_child(_reset_button())
	_page.add_child(_back())
	_career_history(career)


## Where you are in the whole thing: four rungs, the ones behind you ticked with the
## average that got you off them, the one you are on lit, the rest to come.
func _ladder(career: Career) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var done := {}
	for entry in career.level_averages:
		done[int(entry.level)] = float(entry.average)
	for i in Career.LEVELS.size():
		var here: bool = i == career.level and not career.finished
		var passed: bool = done.has(i)
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", UiTheme.plate(
			UiTheme.ACCENT if here else (UiTheme.GOOD if passed else UiTheme.EDGE),
			0.9 if here else 0.55))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		plate.add_child(box)
		var name: String = Career.LEVEL_TITLES[i]
		var ink: Color = UiTheme.ACCENT if here else UiTheme.CHALK
		box.add_child(UiTheme.label(name.to_upper(), UiTheme.SMALL, ink, UiTheme.heavy()))
		var under: String = ("✓ %.2f" % float(done[i])) if passed else ("YOU ARE HERE" if here else "—")
		box.add_child(UiTheme.label(under, UiTheme.SMALL,
			UiTheme.GOOD if passed else (UiTheme.CHALK if here else UiTheme.MUTED), UiTheme.body()))
		plate.custom_minimum_size = Vector2(200, 0)
		row.add_child(plate)
	return row


## This season: a mark for each match played, and how far the average is from the bar.
func _season_so_far(career: Career) -> Control:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiTheme.plate(UiTheme.ACCENT, 0.84))
	var box := VBoxContainer.new()
	plate.add_child(box)
	box.add_theme_constant_override("separation", 4)
	var played: int = career.marks.size()
	var total: int = career.matches_this_season()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(UiTheme.label("MATCH %d OF %d" % [mini(played + 1, total), total],
		UiTheme.BODY, UiTheme.CHALK, UiTheme.heavy()))
	for i in total:
		var pip := UiTheme.label(("%.1f" % float(career.marks[i])) if i < played else "·",
			UiTheme.SMALL, UiTheme.GOOD if i < played else UiTheme.MUTED, UiTheme.heavy())
		pip.custom_minimum_size = Vector2(46, 0)
		head.add_child(pip)
	box.add_child(head)
	if played > 0:
		var average := career.average()
		var short := Career.PROMOTION_MARK - average
		var words := "Average %.2f — %.2f short of the %.1f you need" % [average, short, Career.PROMOTION_MARK]
		if short <= 0.0:
			words = "Average %.2f — that is promotion form" % average
		box.add_child(Menus.text(words, UiTheme.BODY, UiTheme.GOOD if short <= 0.0 else UiTheme.YELLOW))
		box.add_child(_gauge(average))
	else:
		box.add_child(Menus.text("%.1f on average over the season takes you up." % Career.PROMOTION_MARK,
			UiTheme.BODY, UiTheme.MUTED))
	return plate


## The bar: 5 to 10, your average filled in, and a mark at the promotion line.
func _gauge(average: float) -> Control:
	var bar := ColorRect.new()
	bar.color = UiTheme.RAISED
	bar.custom_minimum_size = Vector2(UiTheme.BUTTON_WIDTH, 16)
	var fill := ColorRect.new()
	fill.color = UiTheme.GOOD if average >= Career.PROMOTION_MARK else UiTheme.YELLOW
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf((average - 5.0) / 5.0, 0.0, 1.0)
	bar.add_child(fill)
	var line := ColorRect.new()
	line.color = UiTheme.CHALK
	line.anchor_bottom = 1.0
	line.anchor_left = (Career.PROMOTION_MARK - 5.0) / 5.0
	line.anchor_right = line.anchor_left
	line.offset_right = 3.0
	bar.add_child(line)
	return bar


## The ground and who else is on it, as chips rather than a paragraph.
func _ground_line(level: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(Menus.card_tag(UiTheme.EDGE, level.name.to_upper()))
	row.add_child(Menus.card_tag(UiTheme.EDGE,
		"CLUB LINESMEN" if level.assistants == "club" else "NEUTRAL ASSISTANTS"))
	if level.fourth_official:
		row.add_child(Menus.card_tag(UiTheme.EDGE, "FOURTH OFFICIAL"))
	if level.var:
		row.add_child(Menus.card_tag(UiTheme.YELLOW, "VAR"))
	return row


## Wiping a career takes two presses now. It sat under "Referee this match" looking exactly
## like it, and one stray click threw away a season.
func _reset_button() -> Button:
	if not _confirm_reset:
		var b := Menus.button("Start a new career", func():
			_confirm_reset = true
			_career(), 420)
		b.add_theme_color_override("font_color", UiTheme.MUTED)
		return b
	var confirm := Menus.button("Yes — wipe it and start again", func():
		Game.career.reset()
		_confirm_reset = false
		_career(), 420)
	confirm.add_theme_color_override("font_color", UiTheme.RED)
	return confirm


## Every match refereed, newest first, under the level it was played at.
func _career_history(career: Career) -> void:
	_side.add_child(UiTheme.label("MATCHES REFEREED", UiTheme.HEADING, UiTheme.ACCENT, UiTheme.heavy()))
	if career.history.is_empty():
		_side.add_child(Menus.text("None yet. Everybody starts on a Sunday morning at the rec.", UiTheme.BODY))
		return
	var last_level := -1
	for h in career.history.slice(maxi(0, career.history.size() - 14)):
		if int(h.level) != last_level:
			last_level = int(h.level)
			_side.add_child(_gap(4))
			_side.add_child(UiTheme.label(Career.LEVEL_TITLES[last_level].to_upper(),
				UiTheme.SMALL, UiTheme.MUTED, UiTheme.heavy()))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var fixture := UiTheme.label("%s %s %s" % [Names.club(h.home).short, h.score, Names.club(h.away).short],
			UiTheme.BODY, UiTheme.CHALK, UiTheme.body())
		fixture.custom_minimum_size = Vector2(240, 0)
		row.add_child(fixture)
		var mark := float(h.mark)
		row.add_child(UiTheme.label("%.1f" % mark, UiTheme.BODY,
			UiTheme.GOOD if mark >= Career.PROMOTION_MARK else UiTheme.YELLOW, UiTheme.heavy()))
		_side.add_child(row)


func _officials_words(level: Dictionary) -> String:
	var bits := []
	match level.assistants:
		"club":
			bits.append("Club linesmen, one from each side: they flag offside and fouls near them, but not as sharply as qualified assistants — and not always fairly.")
		_:
			bits.append("Two neutral assistant referees who flag offside and fouls near them.")
	if level.fourth_official:
		bits.append("A fourth official with the added-time board.")
	if level.var:
		bits.append("VAR in your ear.")
	return " ".join(bits)


func _fixture_card(home: Dictionary, away: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	for c in [home, away]:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiTheme.slant(c.shirt))
		var ink := UiTheme.CHALK if (c.shirt as Color).get_luminance() < 0.6 else UiTheme.INK
		p.add_child(UiTheme.label(c.name.to_upper(), UiTheme.TITLE, ink, UiTheme.display()))
		p.custom_minimum_size = Vector2(300, 0)
		row.add_child(p)
		if c == home:
			var v := PanelContainer.new()
			v.add_theme_stylebox_override("panel", UiTheme.slant(UiTheme.INK))
			v.add_child(UiTheme.label("v", UiTheme.TITLE, UiTheme.MUTED, UiTheme.display()))
			row.add_child(v)
	return row


# --- quick match ------------------------------------------------------------------------

func _quick_match() -> void:
	_clear()
	_page.add_child(Menus.title("QUICK MATCH"))
	var level: Dictionary = Venue.LEVELS[_quick.level]
	var home := Names.club(_quick.home)
	var away := Names.club(_quick.away)
	_page.add_child(_fixture_card(home, away))
	# Stepped, not pressed: left and right move each of these either way. Keeping the
	# keyboard focus where it was matters here, or choosing a ground would throw you back
	# to the top of the page on every step.
	_page.add_child(_stepped("Ground: %s" % level.short, func(way: int):
		_quick.level = posmod(_quick.level + way, Venue.LEVELS.size())
		_quick_match()))
	_page.add_child(_stepped("Home: %s" % home.name, func(way: int):
		_quick.home = posmod(_quick.home + way, Names.CLUBS.size())
		if _quick.home == _quick.away:
			_quick.home = posmod(_quick.home + way, Names.CLUBS.size())
		_quick_match()))
	_page.add_child(_stepped("Away: %s" % away.name, func(way: int):
		_quick.away = posmod(_quick.away + way, Names.CLUBS.size())
		if _quick.away == _quick.home:
			_quick.away = posmod(_quick.away + way, Names.CLUBS.size())
		_quick_match()))
	_page.add_child(_stepped("Halves: %d minutes" % Game.settings.half_minutes, func(way: int):
		Game.settings.half_minutes = 5 + posmod(Game.settings.half_minutes - 5 + way, 4)
		Game.settings.save()
		_quick_match()))
	var go := Menus.button("Kick off", func():
		Game.start_match({"mode": "quick", "level": level.id, "home": _quick.home, "away": _quick.away, "half": Game.half_seconds()}))
	_page.add_child(go)
	_page.add_child(_back())
	if not _focus_taken:
		go.grab_focus.call_deferred()
	_side.add_child(UiTheme.label(level.name.to_upper(), UiTheme.HEADING, UiTheme.ACCENT, UiTheme.heavy()))
	_side.add_child(Menus.text(_officials_words(level), UiTheme.BODY, UiTheme.CHALK))


# --- training and challenges ------------------------------------------------------------

func _list(mode: String) -> void:
	_page_name = mode
	_clear()
	_page.add_child(Menus.title("TRAINING GROUND" if mode == "training" else "CHALLENGES"))
	_page.add_child(Menus.text("One signal at a time, with instructions." if mode == "training" else "One real refereeing problem each. No hints.", UiTheme.BODY))
	var first: Button = null
	for s in Scenarios.of_mode(mode):
		var b := Menus.button(s.title, func():
			Game.start_match({"mode": mode, "scenario": s.id, "level": s.get("level", "town"), "home": 0, "away": 1, "half": 360.0}))
		b.focus_entered.connect(func(): _describe(s))
		_page.add_child(b)
		if first == null:
			first = b
	_page.add_child(_back())
	if first != null:
		if not _focus_taken:
			first.grab_focus.call_deferred()


func _describe(s: Dictionary) -> void:
	for c in _side.get_children():
		c.queue_free()
	_side.add_child(UiTheme.label(s.title.to_upper(), UiTheme.TITLE, UiTheme.CHALK, UiTheme.display()))
	_side.add_child(Menus.text(s.brief, UiTheme.BODY, UiTheme.CHALK))


# --- settings ---------------------------------------------------------------------------

func _settings() -> void:
	_page_name = "settings"
	_clear()
	var s := Game.settings
	_page.add_child(Menus.title("SETTINGS"))
	_page.add_child(_slider("Master volume", 0.0, 1.0, s.master, func(v): s.master = v))
	_page.add_child(_slider("Crowd", 0.0, 1.0, s.crowd, func(v): s.crowd = v))
	_page.add_child(_slider("Whistle and effects", 0.0, 1.0, s.effects, func(v): s.effects = v))
	_page.add_child(_slider("Mouse sensitivity", Settings.SENSITIVITY_MIN, Settings.SENSITIVITY_MAX, s.sensitivity, func(v): s.sensitivity = v))
	_page.add_child(_slider("Head bob", 0.0, 1.0, s.head_bob, func(v): s.head_bob = v))
	_page.add_child(_stepped("Invert look: %s" % ("on" if s.invert_y else "off"), func(_way: int):
		s.invert_y = not s.invert_y
		s.save()
		_settings()))
	_page.add_child(_stepped("Fullscreen: %s" % ("on" if s.fullscreen else "off"), func(_way: int):
		s.fullscreen = not s.fullscreen
		s.apply()
		s.save()
		_settings()))
	_page.add_child(_stepped("Halves: %d minutes" % s.half_minutes, func(way: int):
		s.half_minutes = 5 + posmod(s.half_minutes - 5 + way, 4)
		s.save()
		_settings()))
	_page.add_child(_back())
	# Keys on the right, each rebindable.
	_side.add_child(UiTheme.label("CONTROLS — click one, then press a key", UiTheme.HEADING, UiTheme.ACCENT, UiTheme.heavy()))
	for action in Controls.ORDER:
		var b := Menus.button("%s   ·   %s" % [Controls.spelling(s, action), Controls.DEFAULTS[action].label], func(): pass, 820)
		b.pressed.connect(func():
			_rebinding = action
			_rebind_button = b
			b.text = "Press a key for: %s" % Controls.DEFAULTS[action].label)
		_side.add_child(b)
	_side.add_child(Menus.button("Reset controls", func():
		Controls.reset(s)
		_settings(), 400))


func _unhandled_input(event: InputEvent) -> void:
	if _rebinding != &"" and event is InputEventKey and event.pressed:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_ESCAPE:
			_rebinding = &""
			_settings()
			return
		Controls.rebind(Game.settings, _rebinding, key)
		_rebinding = &""
		_settings()
		get_viewport().set_input_as_handled()
		return
	# Escape goes back a page, the way it does everywhere else. Without it the only way off
	# a page was to find the Back button with the mouse.
	if event.is_action_pressed(&"ui_cancel") and _page_name != "main":
		_main()
		get_viewport().set_input_as_handled()


func _slider(label: String, lo: float, hi: float, value: float, on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_child(Menus.text(label, UiTheme.SMALL, UiTheme.MUTED))
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = (hi - lo) / 100.0
	sl.value = value
	sl.custom_minimum_size = Vector2(UiTheme.BUTTON_WIDTH, 36)
	sl.value_changed.connect(func(v):
		on_change.call(v)
		Game.settings.apply()
		Game.settings.save())
	box.add_child(sl)
	return box


func _credits() -> void:
	_page_name = "credits"
	_clear()
	_page.add_child(Menus.title("CREDITS"))
	_page.add_child(Menus.text("Red Card — made by Luqman Hakeem with Claude.\nBuilt in Godot 4.7.", UiTheme.BODY, UiTheme.CHALK))
	_page.add_child(Menus.text("Footballer: generated and rigged with Meshy.\nSpectators: \"Simple Low Poly Character\" by PIXELOKAY and \"Low-poly Woman\" by Razvan Savescu, both CC Attribution, via Sketchfab.\nType: Barlow by Jeremy Tribby, SIL Open Font License.\nSound: CC0 recordings from Freesound — see assets/audio/SOURCES.md — and Kenney.", UiTheme.BODY))
	_page.add_child(Menus.text("The Laws of the Game are the IFAB's. All clubs and players are fictional.", UiTheme.BODY))
	var b := _back()
	_page.add_child(b)
	b.grab_focus.call_deferred()
