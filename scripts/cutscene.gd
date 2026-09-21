class_name Cutscene
extends CanvasLayer

## The camera, taken off you for a few seconds.
##
## Everything here is filmed inside the game: the real ground, the real kits, the players
## standing where the match has actually put them. Nothing is pre-rendered, so a cutscene
## cannot go stale when the game changes, and any of it can be recorded for a trailer by
## pointing a screen recorder at the game.
##
## A scene is a list of shots. Each shot says where the camera starts, where it ends, what
## it is looking at, how long it takes and what the caption says:
##
##     play([
##         {"from": Vector3(-30, 8, 30), "to": Vector3(-18, 3, 14), "look": Vector3.ZERO,
##          "seconds": 3.0, "caption": "STATION ROAD"},
##     ], func(): print("done"))
##
## Two rules it keeps, both learned from the rest of this game:
##
##   it can always be skipped   any key, any click. A cutscene you cannot escape is a
##                              cutscene you resent the second time you see it.
##   it never steals a decision play is paused while it runs, so nothing happens on the
##                              pitch that you are being marked on and cannot see.

signal finished

const BAR := 0.12          # how much of the screen each black bar takes
const FADE := 0.35

var _camera: Camera3D
var _was_current: Camera3D
var _shots: Array = []
var _at := 0
var _t := 0.0
var _done: Callable = Callable()
var _top: ColorRect
var _bottom: ColorRect
var _caption: Label
var _match  # Match, paused while a scene runs
var _running := false
var _pausing := true
## The HUD comes off the screen while the camera is not yours. A score bug and a control
## legend over a cutscene is the clearest way to say "this is still the game, we just took
## your camera", which is the opposite of what a cutscene is for.
var hud: CanvasLayer
## The referee, so he can have his head back. It is cut away for the camera that lives in
## it; a cutscene films him from outside, where a headless official is quite a sight.
var referee


func _init(match_node = null) -> void:
	_match = match_node
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_top = ColorRect.new()
	_top.color = Color(0, 0, 0, 1)
	_top.anchor_right = 1.0
	root.add_child(_top)
	_bottom = ColorRect.new()
	_bottom.color = Color(0, 0, 0, 1)
	_bottom.anchor_right = 1.0
	_bottom.anchor_top = 1.0
	_bottom.anchor_bottom = 1.0
	root.add_child(_bottom)
	_caption = UiTheme.label("", UiTheme.TITLE, UiTheme.CHALK, UiTheme.display())
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.offset_top = -300.0
	_caption.offset_bottom = -210.0
	root.add_child(_caption)
	_camera = Camera3D.new()
	_camera.fov = 48.0
	add_child(_camera)
	_show(false)


func playing() -> bool:
	return _running


## Films a list of shots, then hands the camera back and calls `on_done`.
## `pause` is false for a scene the players have to move in — the walkout, where what you
## are watching is the twenty-two actually walking to their places.
func play(shots: Array, on_done := Callable(), pause := true) -> void:
	if shots.is_empty():
		if on_done.is_valid():
			on_done.call()
		return
	_shots = shots
	_at = 0
	_t = 0.0
	_done = on_done
	_running = true
	_pausing = pause
	_was_current = get_viewport().get_camera_3d()
	_camera.current = true
	_show(true)
	if hud != null:
		hud.visible = false
	if referee != null and is_instance_valid(referee):
		referee.body.set_head_hidden(false)
	if _match != null and _pausing:
		_match.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_frame(0.0)


func skip() -> void:
	if not _running:
		return
	_finish()


func _unhandled_input(event: InputEvent) -> void:
	if not _running:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if pressed:
		get_viewport().set_input_as_handled()
		_finish()


func _process(delta: float) -> void:
	if _running:
		_frame(delta)


func _frame(delta: float) -> void:
	var shot: Dictionary = _shots[_at]
	_t += delta
	var length: float = float(shot.get("seconds", 3.0))
	var along: float = clampf(_t / length, 0.0, 1.0)
	# Eased, so a shot starts and ends like a camera on a shoulder rather than a slider.
	var eased := ease(along, 0.6)
	var from: Vector3 = shot.get("from", Vector3(0, 6, 20))
	var to: Vector3 = shot.get("to", from)
	_camera.global_position = from.lerp(to, eased)
	var look_from: Vector3 = shot.get("look", Vector3.ZERO)
	var look_to: Vector3 = shot.get("look_to", look_from)
	# A target that moves: a player walking out, the ball, whoever is being sent off.
	var follow = shot.get("follow")
	if follow != null and is_instance_valid(follow):
		look_from = (follow as Node3D).global_position + Vector3(0, 1.2, 0)
		look_to = look_from
	var target := look_from.lerp(look_to, eased)
	if _camera.global_position.distance_to(target) > 0.2:
		_camera.look_at(target, Vector3.UP)
	_camera.fov = lerpf(float(shot.get("fov", 48.0)), float(shot.get("fov_to", shot.get("fov", 48.0))), eased)
	_caption.text = String(shot.get("caption", ""))
	# A ground's name is a caption; the game's own name is a title card.
	_caption.add_theme_font_size_override("font_size", int(shot.get("size", UiTheme.TITLE)))
	# The caption fades in and holds; the bars are there the whole time.
	var showing: float = clampf(minf(_t, length - _t) / FADE, 0.0, 1.0)
	_caption.modulate.a = showing
	if along >= 1.0:
		_at += 1
		_t = 0.0
		if _at >= _shots.size():
			_finish()


func _finish() -> void:
	_running = false
	_show(false)
	if _was_current != null and is_instance_valid(_was_current):
		_was_current.current = true
	if _match != null and _pausing:
		_match.paused = false
	if hud != null:
		hud.visible = true
	if referee != null and is_instance_valid(referee):
		referee.body.set_head_hidden(true)
	var done := _done
	_done = Callable()
	finished.emit()
	if done.is_valid():
		done.call()


func _show(on: bool) -> void:
	visible = on
	_caption.text = ""
	var size := get_viewport().get_visible_rect().size
	_top.offset_bottom = size.y * BAR
	_bottom.offset_top = -size.y * BAR
