class_name Ball
extends Node3D

## The match ball, with its own physics.
##
## Not a RigidBody3D. Referee For Fun learned this with the shuttle: a physics contact
## resolves before any script can see it, and the moment the game most needs to know —
## exactly when and where the ball wholly crossed a line — is gone by the time anyone
## asks. So the ball integrates itself, every physics tick, and checks the lines on the
## way. Gravity, air drag, bounce and rolling friction are all here and nowhere else.
##
## The ball also keeps the one piece of history the Laws care about most: who touched it
## last. That decides every throw-in, corner and goal kick, and the first touch after a
## pass decides offside. The referee counts as a touch for Law 9 but not for possession.

signal touched(by: Node, kind: StringName)
## The ball wholly crossed the touchline or the goal line. `where` is the point at which
## its centre crossed the outer edge of the line, which is where a throw-in is taken.
signal went_out(where: Vector3, over_goal_line: bool, in_goal: bool)
## The ball struck the referee (Law 9.2).
signal hit_referee(speed: float)
signal hit_woodwork(where: Vector3)

const GRAVITY := 9.81
## Air drag, as acceleration per (m/s)^2. From ½ρC_dA/m for a size-5 ball: 0.5 x 1.2 x
## 0.25 x 0.038 / 0.43 = 0.0133.
const DRAG := 0.0133
## Grass. How much vertical speed survives a bounce, and how much horizontal.
const BOUNCE := 0.55
const BOUNCE_GRIP := 0.82
## Rolling resistance on cut grass, as a deceleration. Tuned so a firm 15 m/s pass runs
## about forty metres, which is what a well-kept pitch gives.
const ROLL_FRICTION := 1.6
## Below this vertical speed a bounce becomes a roll.
const SETTLE_SPEED := 0.9

var spec: PitchSpec
var velocity := Vector3.ZERO
var on_ground := true
var in_play := true
## Frozen while a restart is being set up, or while the referee has stopped play and the
## players are standing about. Nothing moves it except `place()`.
var held := false
## Carried in a goalkeeper's hands, or a thrower's.
var carrier: Node3D = null
var carrier_offset := Vector3(0, 1.1, 0.35)

## Who touched it last, for restarts; and the last player of each team, for possession.
var last_touch: Node = null
var last_touch_time := -100.0
var last_touch_kind := &""
## Seconds since the match started, advanced by the match. Wall clock would drift under
## pause and slow motion.
var clock := 0.0

## The referee, for Law 9.2. Anything with `global_position` and a `radius`.
var referee: Node3D = null
var _ref_cooldown := 0.0

## The goal frames, as the match builds them: posts are vertical cylinders, bars are
## horizontal ones. Each is {a: Vector3, b: Vector3}.
var woodwork: Array = []

var _mesh: MeshInstance3D
var _spin_axis := Vector3.RIGHT


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = PitchSpec.BALL_RADIUS
	sphere.height = PitchSpec.BALL_RADIUS * 2.0
	sphere.radial_segments = 24
	sphere.rings = 14
	_mesh.mesh = sphere
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/ball.gdshader")
	_mesh.material_override = material
	add_child(_mesh)


## Puts the ball down, dead, at a point. Used for every restart.
func place(point: Vector3) -> void:
	carrier = null
	velocity = Vector3.ZERO
	global_position = Vector3(point.x, PitchSpec.BALL_RADIUS, point.z)
	on_ground = true
	in_play = true


## Strikes the ball. `by` is whoever did it, and `kind` is what it was — a pass, a shot,
## a clearance, a header, a throw — which the offside judge and the assessor both read.
func kick(new_velocity: Vector3, by: Node, kind: StringName = &"pass") -> void:
	carrier = null
	held = false
	velocity = new_velocity
	if velocity.y > 0.3:
		on_ground = false
	_record_touch(by, kind)


## A touch that does not send the ball anywhere in particular: a trap, a block, a keeper
## gathering it. Still a touch for every purpose in the Laws.
func touch(by: Node, kind: StringName = &"control") -> void:
	_record_touch(by, kind)


func _record_touch(by: Node, kind: StringName) -> void:
	last_touch = by
	last_touch_time = clock
	last_touch_kind = kind
	touched.emit(by, kind)


func pick_up(by: Node3D) -> void:
	carrier = by
	velocity = Vector3.ZERO
	_record_touch(by, &"hands")


func speed() -> float:
	return velocity.length()


func ground_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Where the ball will be after `seconds`, if nobody touches it. Cheap and approximate —
## rolling friction only, no bounces — which is what the AI needs to run onto a pass.
func predict(seconds: float) -> Vector3:
	var pos := global_position
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var speed_now := flat.length()
	if speed_now < 0.01:
		return pos
	var dir := flat / speed_now
	var stop_time := speed_now / ROLL_FRICTION
	var t := minf(seconds, stop_time)
	var travelled := speed_now * t - 0.5 * ROLL_FRICTION * t * t
	var out := pos + dir * travelled
	out.y = PitchSpec.BALL_RADIUS
	return out


func step(delta: float) -> void:
	if carrier != null:
		var basis := carrier.global_transform.basis
		global_position = carrier.global_position + basis * carrier_offset
		return
	if held:
		return
	_ref_cooldown = maxf(_ref_cooldown - delta, 0.0)

	var before := global_position
	var pos := before
	var v := velocity

	# Air drag always; gravity when it is off the ground.
	var speed_now := v.length()
	if speed_now > 0.0:
		v -= v * (DRAG * speed_now * delta)
	if on_ground:
		var flat := Vector3(v.x, 0.0, v.z)
		var s := flat.length()
		if s > 0.0:
			var slowed := maxf(s - ROLL_FRICTION * delta, 0.0)
			flat = flat * (slowed / s)
		v = Vector3(flat.x, 0.0, flat.z)
	else:
		v.y -= GRAVITY * delta

	pos += v * delta

	# The ground.
	if pos.y <= PitchSpec.BALL_RADIUS:
		pos.y = PitchSpec.BALL_RADIUS
		if v.y < -SETTLE_SPEED:
			v.y = -v.y * BOUNCE
			v.x *= BOUNCE_GRIP
			v.z *= BOUNCE_GRIP
			on_ground = false
		else:
			v.y = 0.0
			on_ground = true

	# Collisions work on `velocity` directly, so it is committed first.
	velocity = v
	pos = _woodwork(pos)
	pos = _nets(pos)
	_referee(pos)
	v = velocity
	global_position = pos

	# Law 9: out when wholly over the line.
	if in_play and spec != null:
		var over_goal := spec.is_over_goal_line(pos)
		var over_touch := spec.is_over_touchline(pos)
		if over_goal or over_touch:
			in_play = false
			var in_goal := over_goal and spec.is_in_goal_mouth(pos) and not over_touch
			went_out.emit(_crossing(before, pos, over_goal), over_goal, in_goal)

	# Roll the mesh so it looks like it is turning over, not sliding.
	var flat_v := Vector3(v.x, 0.0, v.z)
	if flat_v.length() > 0.05:
		_spin_axis = Vector3.UP.cross(flat_v.normalized())
		var turn := flat_v.length() * delta / PitchSpec.BALL_RADIUS
		_mesh.rotate(_spin_axis, turn)


## Where the ball's centre crossed the relevant line between two ticks. Interpolated,
## because at 30 m/s a tick is half a metre and a throw-in is taken where it went out.
func _crossing(a: Vector3, b: Vector3, goal_line: bool) -> Vector3:
	var limit_a: float
	var limit_b: float
	if goal_line:
		limit_a = spec.past_goal_line(a)
		limit_b = spec.past_goal_line(b)
	else:
		limit_a = spec.past_touchline(a)
		limit_b = spec.past_touchline(b)
	var span := limit_b - limit_a
	var t := 1.0 if absf(span) < 0.0001 else clampf(-limit_a / span, 0.0, 1.0)
	return a.lerp(b, t)


## Posts and crossbars: a ball meeting one bounces off it, keeping most of its speed.
func _woodwork(pos: Vector3) -> Vector3:
	var v := velocity
	var reach := PitchSpec.BALL_RADIUS + PitchSpec.POST_WIDTH * 0.5
	for bar in woodwork:
		var a: Vector3 = bar.a
		var b: Vector3 = bar.b
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var nearest := a + ab * t
		var offset := pos - nearest
		var d := offset.length()
		if d < reach and d > 0.0001:
			var n := offset / d
			if v.dot(n) < 0.0:
				var reflected := v - 2.0 * v.dot(n) * n
				velocity = reflected * 0.7
				on_ground = false
				hit_woodwork.emit(nearest)
			return nearest + n * reach
	return pos


## The nets. Once the ball is in the goal it is caught by the net rather than flying on
## into the crowd, which is only cosmetic — the goal was decided at the line.
func _nets(pos: Vector3) -> Vector3:
	if spec == null:
		return pos
	var hl := spec.half_length()
	var gw := PitchSpec.GOAL_WIDTH * 0.5
	if absf(pos.x) > hl and absf(pos.z) < gw + 0.3 and pos.y < PitchSpec.GOAL_HEIGHT + 0.3:
		var end := signf(pos.x)
		var back := hl + PitchSpec.GOAL_DEPTH - PitchSpec.BALL_RADIUS
		if absf(pos.x) > back:
			pos.x = back * end
			velocity.x *= -0.15
			velocity.z *= 0.3
		# The side netting.
		if absf(pos.z) > gw - PitchSpec.BALL_RADIUS and absf(pos.x) > hl + 0.2:
			pos.z = (gw - PitchSpec.BALL_RADIUS) * signf(pos.z)
			velocity.z *= -0.2
			velocity.x *= 0.5
		if pos.y > PitchSpec.GOAL_HEIGHT - PitchSpec.BALL_RADIUS and absf(pos.x) > hl + 0.2:
			pos.y = PitchSpec.GOAL_HEIGHT - PitchSpec.BALL_RADIUS
			velocity.y = minf(velocity.y, 0.0)
	return pos


## Law 9.2: the ball touching a match official. The game only models the referee, who
## is the one who gets hit — assistants stand outside the field.
func _referee(pos: Vector3) -> void:
	if referee == null or _ref_cooldown > 0.0 or carrier != null:
		return
	var body := referee.global_position
	var flat := Vector2(pos.x - body.x, pos.z - body.z)
	var radius: float = referee.get("radius") if referee.get("radius") != null else 0.3
	if flat.length() > radius + PitchSpec.BALL_RADIUS or pos.y > 1.85:
		return
	var n := Vector3(flat.x, 0.0, flat.y).normalized()
	var v := velocity
	if v.dot(n) >= 0.0:
		return
	var s := v.length()
	velocity = (v - 2.0 * v.dot(n) * n) * 0.35
	_ref_cooldown = 0.4
	_record_touch(referee, &"referee")
	hit_referee.emit(s)
