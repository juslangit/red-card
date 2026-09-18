class_name Menus
extends RefCounted

## Small builders for the interface, so every screen looks the same without repeating
## itself: buttons that light up gold on hover or focus, titles, and a full-screen
## backdrop. Sizes come from UiTheme.

static var _hover: AudioStream
static var _press: AudioStream


## A button that tweens between dark and gold on hover and focus, and plays a tick.
## Hover and focus are the same look on purpose: with a keyboard or a pad the focused
## button is the one under your "cursor", and two different highlights on screen at once
## is how Referee For Fun's players lost track of which one Enter would press.
static func button(text: String, action: Callable, width := UiTheme.BUTTON_WIDTH) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, UiTheme.BUTTON_HEIGHT)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	make_live(b)
	b.pressed.connect(func():
		_play(_press_sound())
		action.call())
	return b


static func make_live(b: Button) -> void:
	var plate := UiTheme.live_button_style()
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, plate)
	b.mouse_entered.connect(func():
		b.grab_focus())
	b.focus_entered.connect(func():
		_play(_hover_sound())
		paint_live(b, plate, true))
	b.focus_exited.connect(func(): paint_live(b, plate, false))


static func paint_live(b: Button, plate: StyleBoxFlat, lit: bool) -> void:
	if not b.is_inside_tree():
		return
	var tween := b.create_tween()
	tween.set_parallel(true)
	tween.tween_property(plate, "bg_color", UiTheme.ACCENT if lit else UiTheme.RAISED, 0.12)
	tween.tween_property(plate, "border_color", UiTheme.CHALK if lit else UiTheme.ACCENT.darkened(0.45), 0.12)
	b.add_theme_color_override("font_color", UiTheme.INK if lit else UiTheme.CHALK)
	b.add_theme_color_override("font_focus_color", UiTheme.INK if lit else UiTheme.CHALK)
	b.add_theme_color_override("font_hover_color", UiTheme.INK if lit else UiTheme.CHALK)


static func title(text: String, size := UiTheme.HUGE, colour := UiTheme.CHALK) -> Label:
	var l := UiTheme.label(text, size, colour, UiTheme.display())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


static func text(words: String, size := UiTheme.BODY, colour := UiTheme.MUTED) -> Label:
	var l := UiTheme.label(words, size, colour, UiTheme.body())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A dark, slightly see-through wash over the whole screen, for overlays.
static func backdrop(alpha := 0.72) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	return r


## A tag in a card colour: the red-card motif the title screen uses.
static func card_tag(colour: Color, words: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.slant(colour))
	p.add_child(UiTheme.label(words, UiTheme.SMALL, UiTheme.INK if colour == UiTheme.YELLOW else UiTheme.CHALK, UiTheme.heavy()))
	return p


static func _hover_sound() -> AudioStream:
	if _hover == null:
		_hover = load("res://assets/audio/ui/ui_hover.ogg")
	return _hover


static func _press_sound() -> AudioStream:
	if _press == null:
		_press = load("res://assets/audio/ui/ui_press.ogg")
	return _press


static func _play(stream: AudioStream) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Effects"
	p.volume_db = -6.0
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
