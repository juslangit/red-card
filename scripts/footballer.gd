class_name Footballer
extends Node3D

## One player: a body that runs where it is told, faces where it is told, and plays the
## clip that matches.
##
## Nothing in here decides anything about football. `MatchAI` decides where each player
## goes and what they do with the ball; this makes the body do it believably. Movement
## is kinematic — a desired velocity, eased towards with a limit on acceleration — rather
## than physics, because twenty-two rigid bodies shoving each other is a pile-up, not a
## football match.

enum Role { GK, DF, MF, FW }
enum State { PLAY, ONE_SHOT, FALLEN, CELEBRATING, PROTESTING, OFF }

const MODEL := "res://assets/characters/footballer/footballer_animated.glb"
## Which part of the body each texel belongs to — see tools/meshy/bake_kit_map.py.
const PARTS_MAP := "res://assets/characters/footballer/footballer_parts.png"
const DIGITS := "res://assets/characters/footballer/digits.png"
const HEIGHT := 1.80

## Which clip means what. Several are borrowed from the net sports until football's own
## are authored (tools/meshy/football_clips.py); the game only ever asks for the left-hand
## name, so swapping a clip is a change to this table and nothing else.
const CLIPS := {
	"idle": ["fb_idle", "ready", "idle"],
	"stand_still": ["fb_stand", "idle"],
	"walk": ["walk"],
	"run": ["fb_run", "run"],
	"sprint": ["fb_sprint", "run"],
	"backpedal": ["fb_backpedal", "backpedal"],
	"shuffle": ["fb_side", "shuffle"],
	"kick": ["fb_kick", "st_serve"],
	"pass": ["fb_pass", "st_set"],
	"tackle": ["fb_tackle", "lunge"],
	"slide": ["fb_slide", "lunge"],
	"header": ["fb_header", "st_header"],
	"throw_in": ["fb_throw_in", "st_throw"],
	"keeper_ready": ["fb_keeper_ready", "vb_ready"],
	"keeper_dive": ["fb_keeper_dive", "vb_dig"],
	"keeper_dive_right": ["fb_keeper_dive_right", "fb_keeper_dive", "vb_dig"],
	"keeper_catch": ["fb_keeper_catch", "vb_set"],
	"keeper_throw": ["fb_keeper_throw", "st_throw"],
	"fall": ["fb_fall", "idle"],
	"lie": ["fb_lie", "idle"],
	"celebrate": ["celebrate"],
	"argue": ["argue"],
	"tired": ["tired"],
	"shake": ["handshake"],
	"point": ["point"],
}

## The ground speed each travelling clip really covers at normal playback, so the rate can
## be matched to the speed the body is moving and the feet do not skate. Every one of these
## is measured by dev/checks/_stride.tscn, which follows both feet through a full cycle —
## `run` was once guessed at 5.2 m/s and is in fact a 2.8 m/s jog, which is why players
## skated at a sprint.
##
## Backing off and stepping sideways used to be guessed at too, because Meshy's own clips
## for them were not gaits: its backpedal swung a foot 25 cm with a foot on the ground 61
## per cent of the time (0.6 m/s), and its shuffle swung one 10 cm and never lifted it at
## all (0.3 m/s), under players travelling at three and four. Both are written by hand now
## in tools/meshy/football_clips.py and measured like the rest.
##
## Running, sprinting and the base `run` are all one clip since 2026-09-23 — the one
## Luqman keyed by hand in gerak and asked to be shipped as he saved it — so all three
## measure the same 0.94 m stride. A sprint is that cycle played faster, which is what
## the rate below is for; it reaches the top of its clamp at about 5.1 m/s rather than
## carrying its own longer stride the way the amplified `fb_sprint` used to.
const CLIP_SPEED := {"walk": 1.58, "run": 2.82, "sprint": 2.82, "backpedal": 2.65, "shuffle": 1.66}
## As fast as a body can go on its heels or sideways before it has to turn and run. A
## defender backing off does exactly this: he holds his ground facing the ball for as long
## as he can, and when the attacker goes past that he turns and chases. Leaving it out is
## what had players gliding sideways across the pitch at full pace.
const BACKPEDAL_LIMIT := 4.0
## Below this much left in the legs, a player standing still shows it.
const TIRED_BELOW := 0.74
const SIDESTEP_LIMIT := 3.0
## Above this, the legs change from Meshy's jog to the harder-swinging sprint.
const SPRINT_FROM := 4.8

signal fell(player: Footballer)

var team: Team
var role := Role.MF
var number := 0
var player_name := ""
var slot := 0

## How fast, how good, how hot-headed and how honest. Pace is top speed in m/s.
var pace := 7.6
var skill := 0.6
var aggression := 0.5
var honesty := 0.7
var stamina := 1.0

var yellow_cards := 0
var sent_off := false
var on_pitch := true

## Movement. `goal` is where the AI wants the body; `hurry` is how fast, 0 to 1 of pace.
var velocity := Vector3.ZERO
var goal := Vector3.ZERO
var hurry := 0.5
## Where to look. When set, the body faces this while moving — the way a defender
## backs off an attacker, facing him — and the legs choose backpedal or shuffle.
var face_point: Variant = null
var heading := Vector3(0, 0, 1)
## Pushed on by the AI to keep players out of each other.
var separation := Vector3.ZERO

var state := State.PLAY
var _state_left := 0.0
var _fall_dir := Vector3.FORWARD
var _fall_amount := 0.0
var injured := false
var _clip_fall := false
## Officials stand like officials — relaxed, arms down — not in a player's ready stance.
var official := false

var _model: Node3D
var _pivot: Node3D
var _mesh: MeshInstance3D
var _anim: AnimationPlayer
var _clip := ""
var _rate := 1.0
var _running := false
## How far he is leaning into the turn he is making, in radians.
var _bank := 0.0
var arms: ArmPoser
var skeleton: Skeleton3D

static var _material: ShaderMaterial


func setup(for_team: Team, shirt_number: int, as_role: Role, display_name: String) -> void:
	team = for_team
	number = shirt_number
	role = as_role
	player_name = display_name


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	var scene: PackedScene = load(MODEL)
	_model = scene.instantiate()
	# The Meshy model faces +Z; everything in Godot faces -Z. Turned once, here.
	_model.rotation.y = PI
	_pivot.add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false)
	skeleton = _model.find_child("Skeleton3D", true, false)
	_mesh = _model.find_child("char1", true, false)
	# Everything a body can be left standing or running in has to loop, or the clip stops
	# on its last frame and the player freezes mid-stride while still travelling. This used
	# to be a list of clip names, and `fb_sprint` was baked on 2026-09-20 without being
	# added to it, so anybody running flat out froze after two thirds of a second. Going
	# through the meanings instead means a new clip loops by being wired into CLIPS, which
	# is the only way it can be reached at all; dev/checks/_clips.tscn holds it to that.
	for meaning in ["idle", "stand_still", "walk", "run", "sprint", "backpedal", "shuffle",
			"keeper_ready", "lie", "celebrate", "argue", "tired"]:
		for clip: String in CLIPS.get(meaning, [meaning]):
			if _anim.has_animation(clip):
				_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_dress()
	arms = ArmPoser.new()
	skeleton.add_child(arms)
	_add_numbers()
	play("idle")


func _dress() -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://assets/shaders/kit.gdshader")
		var original: BaseMaterial3D = _mesh.mesh.surface_get_material(0)
		_material.set_shader_parameter("albedo_tex", original.albedo_texture)
		_material.set_shader_parameter("parts_tex", load(PARTS_MAP))
		_material.set_shader_parameter("digits_tex", load(DIGITS))
	_mesh.material_override = _material
	var shirt := team.keeper_shirt if role == Role.GK else team.shirt
	_mesh.set_instance_shader_parameter("shirt_color", shirt)
	_mesh.set_instance_shader_parameter("shorts_color", team.shorts)
	# A keeper's socks follow his own shirt, as they do in a real kit.
	_mesh.set_instance_shader_parameter("socks_color", shirt if role == Role.GK else team.socks)
	_mesh.set_instance_shader_parameter("trim_color", team.trim)
	# A spread of skin tones across a squad, fixed by the shirt number so a player looks
	# the same every match.
	var tones := [1.0, 0.92, 0.8, 0.66, 0.52, 0.42, 1.04, 0.72]
	_mesh.set_instance_shader_parameter("skin_tone", tones[(number * 7 + team.index * 3) % tones.size()])


## The shirt number, printed onto the back of the shirt by the kit shader (see
## kit.gdshader): the digits and the colour go in as one instance parameter, and the shader
## finds the place from how far up and across the body each texel is. Nothing is parented
## to a bone, so nothing can clip through the player's own back when he bends.
func _add_numbers() -> void:
	if number <= 0:
		return
	var shirt: Color = team.keeper_shirt if role == Role.GK else team.shirt
	var tens := float(number / 10)
	var units := float(number % 10)
	_mesh.set_instance_shader_parameter("number", Vector3(
		tens if tens >= 1.0 else -1.0, units, 1.0 if shirt.get_luminance() > 0.5 else 0.0))


## Where the head is right now, in the world.
func head_position() -> Vector3:
	var bone := skeleton.find_bone("Head")
	if bone < 0:
		return global_position + Vector3(0, 1.62, 0)
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin + Vector3(0, 0.06, 0)


## Cuts this body's head out of the picture, for the one player whose eyes the camera is
## sitting in. The shadow keeps its head (see kit.gdshader).
func set_head_hidden(hidden: bool) -> void:
	_mesh.set_instance_shader_parameter("hide_head", 1.0 if hidden else 0.0)


func radius() -> float:
	return 0.35


func is_keeper() -> bool:
	return role == Role.GK


## True while the body is free to be steered: not on the floor, not mid-kick.
func is_free() -> bool:
	return on_pitch and (state == State.PLAY)


func can_move() -> bool:
	return on_pitch and state in [State.PLAY, State.ONE_SHOT, State.PROTESTING, State.CELEBRATING]


func top_speed() -> float:
	return pace * lerpf(0.8, 1.0, stamina)


func foot_position() -> Vector3:
	return global_position + heading * 0.35


## Plays a clip by what it means, blending from whatever was on.
##
## The playback rate is eased rather than set outright. A player's speed changes every
## tick — pressing, turning, arriving — and feeding that straight into `speed_scale` made
## the legs judder; the rate now catches up over about a fifth of a second, which reads as
## a stride settling.
func play(meaning: String, blend := 0.2, speed := 1.0) -> void:
	var clip := _resolve(meaning)
	if clip == "":
		return
	# Restarting a clip that has stopped is the belt to the braces above: if a clip ever
	# reaches this point without looping, the body picks itself up on the next frame
	# instead of standing frozen until its speed happens to call for something else.
	if clip != _clip or not _anim.is_playing():
		_anim.play(clip, blend)
		_clip = clip
		_rate = speed
	_rate = move_toward(_rate, speed, 5.0 * get_process_delta_time() * maxf(absf(_rate - speed), 0.35))
	_anim.speed_scale = _rate


func _resolve(meaning: String) -> String:
	for name in CLIPS.get(meaning, [meaning]):
		if _anim.has_animation(name):
			return name
	return ""


## A keeper throwing himself at the ball rather than toppling over where he stands, which
## is what he used to do: a save out of reach called `fall()`. The clip is chosen by which
## hand the ball is on, and he carries real speed across the goal so the dive covers ground.
func dive_at(at: Vector3, seconds := 1.4) -> void:
	var across := at - global_position
	across.y = 0.0
	if across.length() < 0.05:
		across = Vector3.UP.cross(heading)
	var to_his_left := across.dot(Vector3.UP.cross(heading)) > 0.0
	one_shot("keeper_dive" if to_his_left else "keeper_dive_right", seconds)
	velocity = across.normalized() * clampf(across.length() / 0.45, 3.5, 9.0)


## A clip that plays once and hands the body back, like a kick or a tackle.
func one_shot(meaning: String, seconds: float, speed := 1.0) -> void:
	if not on_pitch or state == State.FALLEN:
		return
	var clip := _resolve(meaning)
	if clip == "":
		return
	_anim.play(clip, 0.08, speed)
	_anim.seek(0.0, true)
	_clip = clip
	state = State.ONE_SHOT
	_state_left = seconds


## Down on the ground — tripped, fouled, or pretending. `seconds` is how long they stay
## there; `hurt` keeps them down until play stops and somebody comes on.
func fall(towards: Vector3, seconds: float, hurt := false) -> void:
	if not on_pitch or state == State.FALLEN:
		return
	state = State.FALLEN
	_state_left = seconds
	injured = hurt
	var flat := Vector3(towards.x, 0.0, towards.z)
	_fall_dir = flat.normalized() if flat.length() > 0.01 else heading
	velocity *= 0.5
	# With football's own fall clip, the body turns to face the way it is going down and
	# the clip does the falling. Keepers diving sideways still tip over whole, arms up.
	_clip_fall = _anim.has_animation("fb_fall") and not is_keeper()
	if _clip_fall:
		heading = _fall_dir
		transform.basis = Basis.looking_at(heading, Vector3.UP)
	elif is_keeper():
		arms.set_right(arms.to_model(Vector3.UP + _fall_dir * 0.3), Vector3.ZERO, 1.0)
		arms.set_left(arms.to_model(Vector3.UP + _fall_dir * 0.3), Vector3.ZERO, 1.0)
	play("fall", 0.1)
	arms.release()
	fell.emit(self)


func get_up() -> void:
	if state == State.FALLEN:
		_state_left = 0.0
		injured = false


func celebrate(seconds: float) -> void:
	if not on_pitch or state == State.FALLEN:
		return
	state = State.CELEBRATING
	_state_left = seconds


func protest(seconds: float) -> void:
	if not on_pitch or state == State.FALLEN:
		return
	state = State.PROTESTING
	_state_left = seconds


func calm() -> void:
	if state in [State.PROTESTING, State.CELEBRATING]:
		state = State.PLAY
		_state_left = 0.0


## Off the field for good: sent off, or substituted. The body walks to the touchline and
## then disappears.
func leave(exit_point: Vector3) -> void:
	on_pitch = false
	state = State.OFF
	goal = exit_point
	hurry = 0.3
	face_point = null
	arms.release()


## Puts the body where a replay says it was: position, facing, a speed for the legs, and
## whether it was on the floor.
func replay_pose(pos: Vector3, facing: Vector3, speed_vec: Vector3, fallen: bool) -> void:
	global_position = pos
	velocity = speed_vec
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length() > 0.01:
		heading = flat.normalized()
		transform.basis = Basis.looking_at(heading, Vector3.UP)
	if fallen:
		_fall_dir = heading
		_fall_amount = 1.0
		_apply_fall()
		play("lie", 0.1)
	else:
		if _fall_amount > 0.0:
			_fall_amount = 0.0
			_apply_fall()
		var st := state
		state = State.PLAY
		_animate()
		state = st
	if fallen and _clip_fall:
		play("lie", 0.1)


## Drives the body from outside, for the referee: the player's own input decides the
## velocity and the facing, and the body only has to look like it is doing that.
func puppet(new_velocity: Vector3, facing: Vector3) -> void:
	velocity = new_velocity
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length() > 0.01:
		heading = flat.normalized()
		transform.basis = Basis.looking_at(heading, Vector3.UP)
	if state == State.ONE_SHOT:
		_state_left -= get_physics_process_delta_time()
		if _state_left <= 0.0:
			state = State.PLAY
		return
	_animate()


## Advances the body by one tick: steering, facing, the fall and the clip.
func step(delta: float) -> void:
	_state_left -= delta
	match state:
		State.ONE_SHOT:
			if _state_left <= 0.0:
				state = State.PLAY
		State.FALLEN:
			velocity = velocity.move_toward(Vector3.ZERO, 12.0 * delta)
			_fall_amount = move_toward(_fall_amount, 1.0, delta * 3.2)
			if _state_left <= 0.0 and not injured:
				_fall_amount = move_toward(_fall_amount, 0.0, delta * 6.4)
				if _fall_amount <= 0.0:
					state = State.PLAY
					if is_keeper():
						arms.release()
			_apply_fall()
		State.CELEBRATING, State.PROTESTING:
			if _state_left <= 0.0:
				state = State.PLAY
		State.OFF:
			pass
	if state != State.FALLEN and _fall_amount > 0.0:
		_fall_amount = move_toward(_fall_amount, 0.0, delta * 3.0)
		_apply_fall()

	if state != State.FALLEN:
		_steer(delta)
	global_position += velocity * delta
	global_position.y = 0.0
	_face(delta)
	_animate()
	# Ninety minutes wears a player down a little; sprinting wears them down faster.
	var sprinting := velocity.length() > pace * 0.8
	stamina = clampf(stamina + (-0.004 if sprinting else 0.0015) * delta, 0.55, 1.0)

	if state == State.OFF and global_position.distance_to(goal) < 1.0:
		visible = false


func _steer(delta: float) -> void:
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var distance := to_goal.length()
	var want := Vector3.ZERO
	var limit := top_speed() * clampf(hurry, 0.0, 1.0)
	if state in [State.CELEBRATING]:
		limit = maxf(limit, pace * 0.6)
	if distance > 0.15:
		# Arrive rather than overshoot: slow down over the last couple of metres.
		var arrive := clampf(distance / 2.0, 0.0, 1.0)
		want = to_goal / distance * limit * arrive
	want += separation
	var accel := 7.5 if want.length() > velocity.length() else 11.0
	if state == State.ONE_SHOT:
		accel = 3.0
		want *= 0.4
	velocity = velocity.move_toward(want, accel * delta)


func _face(delta: float) -> void:
	var look := Vector3.ZERO
	if face_point != null and state != State.OFF:
		look = (face_point as Vector3) - global_position
		# Past the speed a man can cover on his heels or sideways, he turns and runs,
		# whatever he would rather be watching.
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		if flat.length() > SIDESTEP_LIMIT:
			var want := flat.normalized()
			var away := look.normalized().dot(want) if look.length() > 0.05 else 1.0
			if away < 0.72 and (flat.length() > BACKPEDAL_LIMIT or absf(away) < 0.62):
				look = flat
	elif velocity.length() > 0.4:
		look = velocity
	look.y = 0.0
	var turned := 0.0
	if look.length() > 0.05 and state != State.FALLEN:
		var target := look.normalized()
		var angle := heading.signed_angle_to(target, Vector3.UP)
		# Nobody turns on a sixpence at seven metres a second. The faster he is going, the
		# wider the arc he has to take — which is why players used to pivot on the spot
		# while still playing a forward running clip.
		var rate := lerpf(11.0, 2.7, clampf(Vector3(velocity.x, 0, velocity.z).length() / maxf(pace, 0.1), 0.0, 1.0))
		var turn := clampf(angle, -rate * delta, rate * delta)
		turned = turn / maxf(delta, 0.0001)
		heading = heading.rotated(Vector3.UP, turn).normalized()
	if heading.length() > 0.01:
		var basis := Basis.looking_at(heading, Vector3.UP)
		transform.basis = basis
	# And he leans into the turn, like anybody running round a bend. It eases in and out
	# so a flick of the head does not throw the body over.
	# Into the bend, not out of it. Turning left is a positive rotation about up, and a
	# positive roll on the pivot drops his left shoulder, so the two share a sign.
	var want_bank := clampf(turned * Vector3(velocity.x, 0, velocity.z).length() * 0.022, -0.3, 0.3)
	_bank = move_toward(_bank, want_bank, delta * 2.4)
	if state != State.FALLEN and _fall_amount <= 0.0:
		_pivot.rotation.z = _bank


func _animate() -> void:
	match state:
		State.ONE_SHOT:
			return
		State.FALLEN:
			if _clip_fall:
				if _fall_amount > 0.6:
					play("lie", 0.3)
				return
			play("lie" if _fall_amount > 0.8 else "fall", 0.15)
			return
		State.CELEBRATING:
			if velocity.length() < 1.5:
				play("celebrate", 0.2)
				return
		State.PROTESTING:
			if velocity.length() < 1.2:
				play("argue", 0.2)
				return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.35:
		if official:
			play("stand_still", 0.25)
		elif is_keeper() and state == State.PLAY:
			play("keeper_ready", 0.25)
		elif stamina < TIRED_BELOW:
			# Ninety minutes in the legs: hands down, blowing. The stamina that decides
			# this is the same one that has been slowing him down all match, so the body
			# says what the numbers have been doing.
			play("tired", 0.4)
		else:
			play("idle", 0.25)
		return
	var along := heading.dot(velocity / speed)
	# The gait only changes at the edges of a band, so a player hovering around the
	# walk-to-run speed does not flicker between the two clips.
	if speed > 3.0:
		_running = true
	elif speed < 2.1:
		_running = false
	if along < -0.45:
		play("backpedal", 0.3, clampf(speed / CLIP_SPEED.backpedal, 0.7, 1.5))
	elif along < 0.55:
		play("shuffle", 0.3, clampf(speed / CLIP_SPEED.shuffle, 0.7, 1.75))
	elif not _running:
		play("walk", 0.35, clampf(speed / CLIP_SPEED.walk, 0.65, 1.6))
	elif speed < SPRINT_FROM:
		play("run", 0.35, clampf(speed / CLIP_SPEED.run, 0.85, 1.45))
	else:
		play("sprint", 0.35, clampf(speed / CLIP_SPEED.sprint, 0.9, 1.8))


## Tips the body over about its feet, in the direction of the fall. The model is put
## down on its side of the pivot so it lies on the grass rather than through it.
func _apply_fall() -> void:
	if _clip_fall:
		_pivot.transform = Transform3D.IDENTITY
		return
	var local_dir := transform.basis.inverse() * _fall_dir
	local_dir.y = 0.0
	if local_dir.length() < 0.01:
		local_dir = Vector3(0, 0, -1)
	local_dir = local_dir.normalized()
	var axis := Vector3.UP.cross(local_dir).normalized()
	var amount := ease(_fall_amount, 0.6)
	_pivot.transform = Transform3D(Basis(axis, amount * deg_to_rad(84.0)), Vector3(0, 0.16 * amount, 0))
