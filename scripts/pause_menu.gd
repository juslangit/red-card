class_name PauseMenu
extends CanvasLayer

## Escape during a match: resume, the controls, a few settings, or leave.

var play  # the Play scene
var _root: Control
var _list: VBoxContainer
var _controls_page: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.build()
	add_child(_root)
	# Nearly opaque: at 0.78 the training brief and the HUD showed through and fought the
	# menu for attention.
	_root.add_child(Menus.backdrop(0.93))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_top", 110)
	_root.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 80)
	margin.add_child(row)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 14)
	_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_list)
	_list.add_child(Menus.title("PAUSED"))
	_list.add_child(Menus.button("Resume", toggle))
	_list.add_child(Menus.button("Restart", func(): play.retry()))
	_list.add_child(Menus.button("Quit to menu", func(): play.leave()))
	_list.add_child(_slider("Mouse sensitivity", Settings.SENSITIVITY_MIN, Settings.SENSITIVITY_MAX, Game.settings.sensitivity,
		func(v): Game.settings.sensitivity = v))
	_list.add_child(_slider("Head bob", 0.0, 1.0, Game.settings.head_bob, func(v): Game.settings.head_bob = v))
	_list.add_child(_slider("Crowd volume", 0.0, 1.0, Game.settings.crowd, func(v):
		Game.settings.crowd = v
		Game.settings.apply()))
	_controls_page = _controls()
	row.add_child(_controls_page)
	visible = false


func _slider(label: String, lo: float, hi: float, value: float, on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_child(Menus.text(label, UiTheme.SMALL, UiTheme.MUTED))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = value
	s.custom_minimum_size = Vector2(UiTheme.BUTTON_WIDTH, 36)
	s.value_changed.connect(func(v):
		on_change.call(v)
		Game.settings.save())
	box.add_child(s)
	return box


## The controls, on the pause screen where somebody who has forgotten one will look.
##
## Two fixed columns, key and meaning. The meaning must be told how wide it may be: a
## wrapping label in a row with no width of its own is squeezed to nothing and wraps
## every letter onto its own line — which is what the first version of this panel did.
func _controls() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UiTheme.label("THE REFEREE'S CONTROLS", UiTheme.HEADING, UiTheme.ACCENT, UiTheme.heavy()))
	var lines := [
		["WASD", "Move · Shift to sprint"],
		["Mouse · ← ↑ ↓ →", "Look — look down to see your body"],
	]
	for action in [&"rc_whistle", &"rc_point", &"rc_advantage", &"rc_yellow", &"rc_red", &"rc_wave",
			&"rc_indirect", &"rc_drop", &"rc_sub", &"rc_watch", &"rc_notebook"]:
		lines.append([Controls.spelling(Game.settings, action), Controls.DEFAULTS[action].label])
	for line in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		var key := UiTheme.label(line[0], UiTheme.BODY, UiTheme.CHALK, UiTheme.heavy())
		key.custom_minimum_size = Vector2(250, 0)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(key)
		var meaning := Menus.text(line[1], UiTheme.SMALL, UiTheme.MUTED)
		meaning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(meaning)
		box.add_child(row)
	return panel


func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	# Everything else on screen steps aside: the drill's brief and the HUD showed through
	# the backdrop and sat behind the word PAUSED.
	play.hud.visible = not visible
	if play.scenario != null and not play.scenario._done:
		play.scenario._brief_layer.visible = not visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		(_list.get_child(1) as Button).grab_focus()
