extends Control

## The opening: a red card is held up, the title lands, and the menu follows. Any key
## or click skips it — nobody wants to watch an intro twice.

var _t := 0.0
var _card: Panel
var _title: Label
var _sub: Label
var _done := false


func _ready() -> void:
	theme = UiTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_card = Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.RED
	style.set_corner_radius_all(14)
	style.shadow_size = 30
	style.shadow_color = Color(0, 0, 0, 0.6)
	_card.add_theme_stylebox_override("panel", style)
	_card.size = Vector2(190, 265)
	_card.pivot_offset = _card.size * 0.5
	add_child(_card)
	_title = UiTheme.label("RED CARD", 150, UiTheme.CHALK, UiTheme.display())
	add_child(_title)
	_sub = UiTheme.label("YOU ARE THE REFEREE", UiTheme.TITLE, UiTheme.ACCENT, UiTheme.heavy())
	add_child(_sub)
	_title.modulate.a = 0.0
	_sub.modulate.a = 0.0
	var whistle := AudioStreamPlayer.new()
	whistle.stream = load("res://assets/audio/whistle_firm.wav")
	whistle.volume_db = -6.0
	add_child(whistle)
	get_tree().create_timer(0.55).timeout.connect(whistle.play)


func _process(delta: float) -> void:
	_t += delta
	var screen := get_viewport_rect().size
	# The card rises from below and snaps upright, the way a referee holds it up.
	var rise := ease(clampf(_t / 0.6, 0.0, 1.0), 0.3)
	_card.position = Vector2(screen.x * 0.5 - _card.size.x * 0.5, lerpf(screen.y + 40.0, screen.y * 0.5 - 330.0, rise))
	_card.rotation_degrees = lerpf(-30.0, -8.0, rise)
	_title.reset_size()
	_title.position = Vector2(screen.x * 0.5 - _title.size.x * 0.5, screen.y * 0.5 - 20.0)
	_sub.reset_size()
	_sub.position = Vector2(screen.x * 0.5 - _sub.size.x * 0.5, screen.y * 0.5 + 150.0)
	_title.modulate.a = clampf((_t - 0.6) / 0.3, 0.0, 1.0)
	_sub.modulate.a = clampf((_t - 1.0) / 0.4, 0.0, 1.0)
	if _t > 3.0:
		_go()


func _input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) and event.is_pressed():
		_go()


func _go() -> void:
	if _done:
		return
	_done = true
	Game.to_menu()
