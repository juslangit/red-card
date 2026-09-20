class_name Captions
extends Node3D

## Short speech bubbles over people's heads: "TACKLE!", "REF!", "OUT — BLUEPORT".
##
## Luqman asked for these on 2026-09-20 so that what just happened, and who it happened
## to, reads at a glance — including an assistant's call over his own head, which is where
## a referee actually looks.
##
## They say only what anybody on the field can see or hear. A bubble never carries the
## truth the referee is being judged on: a tackle says "TACKLE!" whether or not it was a
## foul, the fouled player shouts "REF!" whether or not he has a case, and the assistant's
## bubble says what his flag says — which can be wrong. That is Referee For Fun's rule
## carried over: nothing on screen during play may decide the decision for the player.
##
## Bubbles are pooled: eight of them, reused, so a busy minute costs nothing.

const POOL := 8
const RISE := 0.35
const HOLD := 1.6
const FADE := 0.45

var _free: Array[Bubble] = []
var _live: Array[Bubble] = []


func _ready() -> void:
	for i in POOL:
		var b := Bubble.new()
		add_child(b)
		b.hide_now()
		_free.append(b)


## Says something over a node's head. `tone` colours the bubble: a team colour for a
## player's shout, gold for an official's call.
func say(over: Node3D, words: String, tone := UiTheme.CHALK, height := 2.35) -> void:
	if over == null or not is_instance_valid(over) or words == "":
		return
	# One bubble per person: a second shout replaces the first rather than stacking.
	for b in _live:
		if b.target == over:
			b.set_words(words, tone)
			b.restart()
			return
	if _free.is_empty():
		var oldest: Bubble = _live.pop_front()
		_free.append(oldest)
	var bubble: Bubble = _free.pop_back()
	bubble.target = over
	bubble.offset = height
	bubble.set_words(words, tone)
	bubble.restart()
	_live.append(bubble)


func _process(delta: float) -> void:
	for i in range(_live.size() - 1, -1, -1):
		var b: Bubble = _live[i]
		if not b.step(delta):
			b.hide_now()
			_live.remove_at(i)
			_free.append(b)


## One bubble: a rounded plate with a tail, and the word on it, both facing the camera.
class Bubble extends Node3D:
	var target: Node3D
	var offset := 2.35
	var life := 0.0
	var _label: Label3D
	var _plate: MeshInstance3D
	var _material: ShaderMaterial

	func _init() -> void:
		_plate = MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 0.5)
		_plate.mesh = quad
		_material = ShaderMaterial.new()
		_material.shader = load("res://assets/shaders/bubble.gdshader")
		_plate.material_override = _material
		_plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_plate)
		_label = Label3D.new()
		_label.font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
		_label.font_size = 96
		_label.pixel_size = 0.0032
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.shaded = false
		_label.modulate = UiTheme.INK
		_label.position = Vector3(0, 0, 0.01)
		add_child(_label)

	func set_words(words: String, tone: Color) -> void:
		_label.text = words
		_label.modulate = UiTheme.INK if tone.get_luminance() > 0.45 else UiTheme.CHALK
		_material.set_shader_parameter("fill", tone)
		# The plate is cut to the words: a bubble that is always the same width around a
		# one-word shout looks like a label, not somebody speaking.
		var font: Font = _label.font
		var width: float = font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, _label.font_size).x
		var size := Vector2(width * _label.pixel_size + 0.42, 0.46)
		(_plate.mesh as QuadMesh).size = size
		_material.set_shader_parameter("size", size)

	func restart() -> void:
		life = 0.0
		visible = true

	func hide_now() -> void:
		visible = false
		target = null

	## Returns false once it is finished.
	func step(delta: float) -> bool:
		if target == null or not is_instance_valid(target):
			return false
		life += delta
		var total := Captions.RISE + Captions.HOLD + Captions.FADE
		if life > total:
			return false
		var rising := clampf(life / Captions.RISE, 0.0, 1.0)
		var alpha := 1.0 - clampf((life - Captions.RISE - Captions.HOLD) / Captions.FADE, 0.0, 1.0)
		global_position = target.global_position + Vector3(0, offset + 0.12 * rising + 0.1 * (1.0 - alpha), 0)
		# Bubbles grow with distance so one forty metres away is still a word, not a dot —
		# up to a point, or a shout across the pitch would fill the screen.
		var camera := get_viewport().get_camera_3d()
		var away := camera.global_position.distance_to(global_position) if camera != null else 15.0
		var far_scale := clampf(away / 14.0, 1.0, 2.6)
		var scale_up := (0.7 + 0.3 * ease(rising, 0.4)) * far_scale
		scale = Vector3.ONE * scale_up
		_material.set_shader_parameter("alpha", alpha)
		_label.modulate.a = alpha
		_label.outline_modulate.a = 0.0
		return true
