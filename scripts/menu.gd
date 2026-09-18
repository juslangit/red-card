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
	side_column.add_child(_side_plate)
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 12)
	_side_plate.add_child(_side)

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
	go_career.grab_focus.call_deferred()
	if not Game.settings.trained:
		_side.add_child(Menus.card_tag(UiTheme.YELLOW, "NEW HERE?"))
		_side.add_child(Menus.text("The training ground teaches every signal in a few minutes: moving, the whistle, pointing, advantage, cards, the flag and the watch.", UiTheme.BODY, UiTheme.CHALK))


func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _back() -> Button:
	return Menus.button("‹ Back", _main, 260)


# --- career -----------------------------------------------------------------------------

func _career() -> void:
	_clear()
	var career := Game.career
	_page.add_child(Menus.title("CAREER"))
	var level_title := UiTheme.label(career.title().to_upper(), UiTheme.TITLE, UiTheme.ACCENT, UiTheme.display())
	level_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_page.add_child(level_title)
	var level: Dictionary = Venue.level_by_id(career.level_id())
	_page.add_child(Menus.text("Matches at %s. %s" % [level.name, _officials_words(level)], UiTheme.BODY, UiTheme.CHALK))
	if career.finished:
		_page.add_child(Menus.card_tag(UiTheme.GOOD, "CAREER COMPLETE"))
		_page.add_child(Menus.text("You refereed the cup final. Start again from the village field any time.", UiTheme.BODY))
	else:
		var played := career.marks.size()
		_page.add_child(Menus.text("Season: match %d of %d · average %s · %.1f to go up" % [played + 1, career.matches_this_season(),
			("%.2f" % career.average()) if played > 0 else "—", Career.PROMOTION_MARK], UiTheme.BODY))
		var fixture := career.next_fixture()
		var home := Names.club(fixture.home)
		var away := Names.club(fixture.away)
		_page.add_child(_gap(10))
		_page.add_child(_fixture_card(home, away))
		var go := Menus.button("Referee this match", func():
			var cfg := fixture.duplicate()
			cfg["half"] = Game.half_seconds()
			Game.start_match(cfg))
		_page.add_child(go)
		go.grab_focus.call_deferred()
	_page.add_child(Menus.button("Start a new career", func():
		Game.career.reset()
		_career(), UiTheme.BUTTON_WIDTH))
	_page.add_child(_back())
	# The history on the right.
	_side.add_child(UiTheme.label("MATCHES REFEREED", UiTheme.HEADING, UiTheme.ACCENT, UiTheme.heavy()))
	if career.history.is_empty():
		_side.add_child(Menus.text("None yet. Everybody starts on a Sunday morning at the rec.", UiTheme.BODY))
	for h in career.history.slice(maxi(0, career.history.size() - 12)):
		var line := "%s   %s %s %s   ·   %.1f" % [Career.LEVEL_TITLES[h.level], Names.club(h.home).short, h.score, Names.club(h.away).short, h.mark]
		_side.add_child(Menus.text(line, UiTheme.BODY, UiTheme.CHALK))


func _officials_words(level: Dictionary) -> String:
	var bits := []
	match level.assistants:
		"club":
			bits.append("Club linesmen who only flag the ball out — and not always fairly. Offside is yours alone.")
		_:
			bits.append("Two neutral assistant referees.")
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
	_page.add_child(Menus.button("Ground: %s" % level.short, func():
		_quick.level = (_quick.level + 1) % Venue.LEVELS.size()
		_quick_match()))
	_page.add_child(Menus.button("Home: %s" % home.name, func():
		_quick.home = (_quick.home + 1) % Names.CLUBS.size()
		if _quick.home == _quick.away:
			_quick.home = (_quick.home + 1) % Names.CLUBS.size()
		_quick_match()))
	_page.add_child(Menus.button("Away: %s" % away.name, func():
		_quick.away = (_quick.away + 1) % Names.CLUBS.size()
		if _quick.away == _quick.home:
			_quick.away = (_quick.away + 1) % Names.CLUBS.size()
		_quick_match()))
	_page.add_child(Menus.button("Halves: %d minutes" % Game.settings.half_minutes, func():
		Game.settings.half_minutes = 5 + (Game.settings.half_minutes - 4) % 4
		Game.settings.save()
		_quick_match()))
	var go := Menus.button("Kick off", func():
		Game.start_match({"mode": "quick", "level": level.id, "home": _quick.home, "away": _quick.away, "half": Game.half_seconds()}))
	_page.add_child(go)
	_page.add_child(_back())
	go.grab_focus.call_deferred()
	_side.add_child(UiTheme.label(level.name.to_upper(), UiTheme.HEADING, UiTheme.ACCENT, UiTheme.heavy()))
	_side.add_child(Menus.text(_officials_words(level), UiTheme.BODY, UiTheme.CHALK))


# --- training and challenges ------------------------------------------------------------

func _list(mode: String) -> void:
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
		first.grab_focus.call_deferred()


func _describe(s: Dictionary) -> void:
	for c in _side.get_children():
		c.queue_free()
	_side.add_child(UiTheme.label(s.title.to_upper(), UiTheme.TITLE, UiTheme.CHALK, UiTheme.display()))
	_side.add_child(Menus.text(s.brief, UiTheme.BODY, UiTheme.CHALK))


# --- settings ---------------------------------------------------------------------------

func _settings() -> void:
	_clear()
	var s := Game.settings
	_page.add_child(Menus.title("SETTINGS"))
	_page.add_child(_slider("Master volume", 0.0, 1.0, s.master, func(v): s.master = v))
	_page.add_child(_slider("Crowd", 0.0, 1.0, s.crowd, func(v): s.crowd = v))
	_page.add_child(_slider("Whistle and effects", 0.0, 1.0, s.effects, func(v): s.effects = v))
	_page.add_child(_slider("Mouse sensitivity", Settings.SENSITIVITY_MIN, Settings.SENSITIVITY_MAX, s.sensitivity, func(v): s.sensitivity = v))
	_page.add_child(_slider("Head bob", 0.0, 1.0, s.head_bob, func(v): s.head_bob = v))
	_page.add_child(Menus.button("Invert look: %s" % ("on" if s.invert_y else "off"), func():
		s.invert_y = not s.invert_y
		s.save()
		_settings()))
	_page.add_child(Menus.button("Fullscreen: %s" % ("on" if s.fullscreen else "off"), func():
		s.fullscreen = not s.fullscreen
		s.apply()
		s.save()
		_settings()))
	_page.add_child(Menus.button("Halves: %d minutes" % s.half_minutes, func():
		s.half_minutes = 5 + (s.half_minutes - 4) % 4
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
	_clear()
	_page.add_child(Menus.title("CREDITS"))
	_page.add_child(Menus.text("Red Card — made by Luqman Hakeem with Claude.\nBuilt in Godot 4.7.", UiTheme.BODY, UiTheme.CHALK))
	_page.add_child(Menus.text("Footballer: generated and rigged with Meshy.\nSpectators: \"Simple Low Poly Character\" by PIXELOKAY and \"Low-poly Woman\" by Razvan Savescu, both CC Attribution, via Sketchfab.\nType: Barlow by Jeremy Tribby, SIL Open Font License.\nSound: CC0 recordings from Freesound — see assets/audio/SOURCES.md — and Kenney.", UiTheme.BODY))
	_page.add_child(Menus.text("The Laws of the Game are the IFAB's. All clubs and players are fictional.", UiTheme.BODY))
	var b := _back()
	_page.add_child(b)
	b.grab_focus.call_deferred()
