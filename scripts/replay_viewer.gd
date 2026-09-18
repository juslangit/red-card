class_name ReplayViewer
extends CanvasLayer

## Plays a moment of the match back from the Recorder, in the real world, from three
## cameras: your own eyes as they were at the time, a broadcast camera up in the stand,
## and a close camera beside the incident.
##
## "Your eyes" is the important one. The assessor's report can say you were wrong, but
## the replay from where you actually stood is what shows *why* — a body in the way, a
## bad angle, too far off play — which is the lesson a real referee takes from a
## debrief. VAR's pitch-side monitor uses the same viewer with decision buttons added.

signal closed
signal chosen(index: int)

enum View { EYES, BROADCAST, CLOSE }

var m: Match
var ref: Referee
var active := false
var view := View.BROADCAST
var speed := 0.5
var playing := true

var _from := 0.0
var _to := 0.0
var _t := 0.0
var _focus := Vector3.ZERO
var _frames: Array = []
var _saved: Dictionary = {}
var _camera: Camera3D
var _root: Control
var _title: Label
var _time: Label
var _slider: HSlider
var _choices: HBoxContainer
var _view_buttons: Array = []
var _orbit := 0.0
var _close_button: Button


func setup(match_node: Match, referee: Referee) -> void:
	m = match_node
	ref = referee


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_camera = Camera3D.new()
	_camera.fov = 50.0
	m.add_child(_camera)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.build()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# A broadcast strip along the bottom.
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UiTheme.plate(UiTheme.RED, 0.88))
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -210
	_root.add_child(strip)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	strip.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	box.add_child(top)
	top.add_child(Menus.card_tag(UiTheme.RED, "REPLAY"))
	_title = UiTheme.label("", UiTheme.HEADING, UiTheme.CHALK, UiTheme.heavy())
	top.add_child(_title)
	_time = UiTheme.label("", UiTheme.BODY, UiTheme.MUTED, UiTheme.heavy())
	top.add_child(_time)
	_slider = HSlider.new()
	_slider.custom_minimum_size = Vector2(600, 30)
	_slider.step = 0.01
	_slider.value_changed.connect(func(v): if not playing: _t = v)
	box.add_child(_slider)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(Menus.button("Play / pause", func(): playing = not playing, 230))
	row.add_child(Menus.button("Slow", func(): speed = 0.25 if speed > 0.3 else 1.0, 150))
	for pair in [["Your eyes", View.EYES], ["Broadcast", View.BROADCAST], ["Close", View.CLOSE]]:
		var b := Menus.button(pair[0], func(): view = pair[1], 200)
		row.add_child(b)
		_view_buttons.append(b)
	_close_button = Menus.button("Close", close, 160)
	row.add_child(_close_button)
	_choices = HBoxContainer.new()
	_choices.add_theme_constant_override("separation", 16)
	box.add_child(_choices)
	visible = false


## Opens a replay of the moments around `centre`. `choices` turns it into a pitch-side
## monitor: a row of decisions, one of which must be chosen to leave.
func open(centre: float, title: String, focus: Vector3, choices: Array = []) -> void:
	_frames = m.recorder.between(centre - 5.0, centre + 2.5)
	if _frames.size() < 2:
		return
	_save_world()
	active = true
	visible = true
	m.paused = true
	ref.enabled = false
	_from = _frames[0].t
	_to = _frames[-1].t
	_t = _from
	_focus = focus
	_slider.min_value = _from
	_slider.max_value = _to
	_title.text = title
	playing = true
	view = View.BROADCAST
	for c in _choices.get_children():
		c.queue_free()
	for i in choices.size():
		var index := i
		var b := Menus.button(choices[i], func():
			chosen.emit(index)
			close(), 300)
		_choices.add_child(b)
	_choices.visible = not choices.is_empty()
	_close_button.visible = choices.is_empty()
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## True while this is a pitch-side monitor with a decision still to make.
func deciding() -> bool:
	return active and _choices.visible


func close() -> void:
	if not active:
		return
	active = false
	visible = false
	_restore_world()
	ref.camera.current = true
	m.paused = false
	ref.enabled = true
	closed.emit()


func _process(delta: float) -> void:
	if not active:
		return
	if playing:
		_t += delta * speed
		if _t > _to:
			_t = _from
		_slider.set_value_no_signal(_t)
	_time.text = "%+.1f s" % (_t - (_to - 2.5))
	_pose(_t)
	_aim(delta)


func _pose(t: float) -> void:
	var i := 0
	while i < _frames.size() - 2 and _frames[i + 1].t < t:
		i += 1
	var a: Dictionary = _frames[i]
	var b: Dictionary = _frames[mini(i + 1, _frames.size() - 1)]
	var span: float = maxf(b.t - a.t, 0.001)
	var k := clampf((t - a.t) / span, 0.0, 1.0)
	for n in m.players.size():
		var p: Footballer = m.players[n]
		if n >= (a.players as PackedVector3Array).size():
			continue
		var state: int = (a.states as PackedInt32Array)[n]
		p.visible = state != -1 or p.on_pitch
		var pa: Vector3 = a.players[n]
		var pb: Vector3 = b.players[n]
		var pos := pa.lerp(pb, k)
		var vel := (pb - pa) / span
		var facing: Vector3 = (a.headings[n] as Vector3).slerp(b.headings[n], k) if (a.headings[n] as Vector3).length() > 0.1 else Vector3.FORWARD
		p.replay_pose(pos, facing, vel, state == Footballer.State.FALLEN)
	m.ball.global_position = (a.ball as Vector3).lerp(b.ball, k)
	if a.has("ref"):
		ref.global_position = (a.ref as Vector3).lerp(b.ref, k)
		var look: Transform3D = a.ref_look
		var flat := -look.basis.z
		flat.y = 0.0
		if flat.length() > 0.01:
			ref.body.puppet(((b.ref as Vector3) - (a.ref as Vector3)) / span, flat)


func _aim(delta: float) -> void:
	var frame: Dictionary = _frames[0]
	for f in _frames:
		if f.t <= _t:
			frame = f
	match view:
		View.EYES:
			if frame.has("ref_look"):
				_camera.global_transform = frame.ref_look
				_camera.fov = 78.0
		View.BROADCAST:
			var b := m.ball.global_position
			_camera.fov = 32.0
			_camera.global_position = Vector3(clampf(b.x, -40, 40) * 0.85, 22.0, -m.spec.half_width() - 26.0)
			_camera.look_at(b.lerp(_focus, 0.5), Vector3.UP)
		View.CLOSE:
			_orbit += delta * 0.25
			_camera.fov = 45.0
			_camera.global_position = _focus + Vector3(cos(_orbit) * 9.0, 2.6, sin(_orbit) * 9.0)
			_camera.look_at(_focus + Vector3(0, 0.8, 0), Vector3.UP)


func _save_world() -> void:
	var positions := []
	for p in m.players:
		positions.append({"p": p, "pos": p.global_position, "heading": p.heading, "visible": p.visible})
	_saved = {"players": positions, "ball": m.ball.global_position, "ref": ref.global_position}


func _restore_world() -> void:
	if _saved.is_empty():
		return
	for entry in _saved.players:
		var p: Footballer = entry.p
		p.global_position = entry.pos
		p.heading = entry.heading
		p.visible = entry.visible
		p.replay_pose(entry.pos, entry.heading, Vector3.ZERO, p.state == Footballer.State.FALLEN)
	m.ball.global_position = _saved.ball
	ref.global_position = _saved.ref
	_saved = {}
