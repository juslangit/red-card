class_name Referee
extends CharacterBody3D

## You. A referee on foot, in first person, with a body.
##
## Walk, jog, sprint, backpedal and sidestep; turn your head, and look down to see your
## own shirt, shorts and boots moving. The body is the footballer model in referee kit,
## driven by this script rather than by the AI, with the head shrunk away so the camera
## can sit where the eyes are.
##
## A referee's language is a whistle and two arms, so that is the whole interface:
##
##   whistle   left click. Tap to stop play or start a restart; hold for the long whistle
##             that ends a half.
##   point     right click. Your arm points where you are looking, and what that means
##             depends on the moment — a free kick one way or the other, a penalty if you
##             point at the spot, a corner or a goal kick, the centre circle for a goal.
##             The prompt under the crosshair always says what your point would give.
##   cards     Y and R, to the player you are looking at. Look at the right one.
##   advantage space: both arms swept forward, play on.
##
## Everything goes to the Match, which does what it is told. Nothing here knows whether
## a decision is right.

signal pointed(meaning: Dictionary)

const EYE_HEIGHT := 1.68
const JOG := 4.3
const SPRINT := 7.4
const BACKPEDAL := 3.2
## Sideways is slower than forwards, and now looks it: the side-step clip covers 1.66 m/s
## and will stretch to about 2.9 before the feet start to skate. Strafing at very nearly
## jogging pace was a video game habit, not a referee's.
const SIDESTEP := 2.9
const ACCEL := 14.0
## Stamina: a full sprint empties it in about twelve seconds; standing refills it in ten.
const SPRINT_COST := 0.085
const JOG_RECOVERY := 0.035
const REST_RECOVERY := 0.1
## The long whistle is a whistle held this long.
const LONG_WHISTLE := 0.55

var m: Match
var settings: Settings
var camera: Camera3D
var body: Footballer
var radius := 0.32
var yaw := 0.0
var pitch := 0.0
var stamina := 1.0
## Ninety minutes take something out of anybody: the most stamina can refill to.
var fitness := 1.0
var sprinting := false
var indirect_arm := false
var holding_watch := false
var enabled := true
## For the checks: a scripted referee ignores the keyboard.
var scripted := false
## For the looks: hold the watch up without a key.
var force_watch := false

var _whistle_down := -1.0
var _bob_phase := 0.0
var _last_step := 0.0
var _shake := 0.0
var _card_node: MeshInstance3D
var _card_material: StandardMaterial3D
## The hand the card is held in, and the player it is being shown to.
var _card_hand: BoneAttachment3D
var _card_for: Footballer
var _watch_label: Label3D
var _signal_left := 0.0
var _body_yaw := 0.0
var _body_turning := false
var _pad_look := Vector2.ZERO


## Black, unless a team plays in something dark, in which case the fluorescent yellow
## every federation keeps for exactly that.
static func kit_colour(teams: Array) -> Color:
	var black := Color(0.06, 0.06, 0.07)
	var options := [black, Color(0.85, 0.95, 0.12), Color(0.1, 0.75, 0.75), Color(0.9, 0.3, 0.55)]
	var best: Color = black
	var best_gap := -1.0
	for option: Color in options:
		var gap := INF
		for team in teams:
			var shirt: Color = team.shirt
			gap = minf(gap, Vector3(shirt.r - option.r, shirt.g - option.g, shirt.b - option.b).length())
			gap = minf(gap, Vector3(team.keeper_shirt.r - option.r, team.keeper_shirt.g - option.g, team.keeper_shirt.b - option.b).length() + 0.25)
		if gap > best_gap + 0.15:
			best = option
			best_gap = gap
	return best


func setup(match_node: Match, player_settings: Settings) -> void:
	m = match_node
	settings = player_settings


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

	var kit := Team.new()
	kit.name = "Referee"
	kit.shirt = kit_colour(m.teams)
	kit.shorts = Color(0.05, 0.05, 0.06)
	kit.keeper_shirt = kit.shirt
	body = Footballer.new()
	body.setup(kit, 0, Footballer.Role.MF, "Referee")
	body.official = true
	add_child(body)
	for label in body.find_children("*", "Label3D", true, false):
		label.visible = false
	# The body must not cast its shadow into the camera, or the player sees a shadow of a
	# man with no head.
	for mesh in body.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Our own head, cut out of our own view for good — it is the head being the head that
	# hides it, not where it is this frame, so a sprint cannot shake it loose.
	body.set_head_hidden(true)

	camera = Camera3D.new()
	camera.fov = 78.0
	camera.near = 0.06
	camera.far = 600.0
	camera.position = Vector3(0, EYE_HEIGHT, 0)
	add_child(camera)
	camera.current = true

	_make_card()
	_make_watch()
	yaw = rotation.y
	_body_yaw = yaw


func look_transform() -> Transform3D:
	return camera.global_transform


## The card, held in the right hand. One mesh, recoloured for yellow or red.
##
## The hand is only a place to hold it: where the card sits and which way it faces are set
## every frame in `_hold_card()`, in the world. Left to the bone's own axes it was twelve
## centimetres along the hand bone, which runs back down the forearm — so the card sat
## behind the fist, edge on, and Luqman could not see the card he had just shown.
func _make_card() -> void:
	_card_hand = BoneAttachment3D.new()
	_card_hand.bone_name = "RightHand"
	body.skeleton.add_child(_card_hand)
	_card_node = MeshInstance3D.new()
	# The card stands outside the skeleton, on its own, and is placed in the world every
	# frame. Inside it, everything is in the skeleton's own centimetres, and turning it to
	# face anybody meant an orthonormal basis that threw that hundredth away: the card came
	# out seven metres wide and read as a streak across the sky.
	_card_node.top_level = true
	var quad := BoxMesh.new()
	# A real card is 7 x 10 cm.
	quad.size = Vector3(0.075, 0.105, 0.003)
	_card_node.mesh = quad
	_card_material = StandardMaterial3D.new()
	_card_material.albedo_color = UiTheme.YELLOW
	_card_material.emission_enabled = true
	_card_material.emission = UiTheme.YELLOW
	_card_material.emission_energy_multiplier = 0.3
	_card_node.material_override = _card_material
	_card_node.visible = false
	add_child(_card_node)


## A wristwatch on the left wrist, whose face really shows the match time. Raise the
## wrist (hold Tab) to read it, as a referee does.
func _make_watch() -> void:
	var wrist := BoneAttachment3D.new()
	wrist.bone_name = "LeftHand"
	body.skeleton.add_child(wrist)
	var strap := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5.5, 1.2, 5.0)
	strap.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.06)
	strap.material_override = mat
	strap.position = Vector3(0, -3.0, 0)
	wrist.add_child(strap)
	_watch_label = Label3D.new()
	_watch_label.font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
	_watch_label.font_size = 64
	_watch_label.pixel_size = 0.05
	_watch_label.modulate = Color(0.75, 1.0, 0.8)
	_watch_label.shaded = false
	_watch_label.no_depth_test = false
	_watch_label.position = Vector3(0, -2.3, 0)
	_watch_label.rotation_degrees = Vector3(-90, 0, 0)
	wrist.add_child(_watch_label)


# --- input ------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or scripted:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * settings.sensitivity
		pitch -= motion.relative.y * settings.sensitivity * (-1.0 if settings.invert_y else 1.0)
		pitch = clampf(pitch, deg_to_rad(-82.0), deg_to_rad(70.0))
	if event.is_action_pressed(&"rc_whistle"):
		_whistle_down = 0.0
	elif event.is_action_released(&"rc_whistle") and _whistle_down >= 0.0:
		blow(_whistle_down >= LONG_WHISTLE)
		_whistle_down = -1.0
	elif event.is_action_pressed(&"rc_point"):
		point()
	elif event.is_action_pressed(&"rc_advantage"):
		advantage()
	elif event.is_action_pressed(&"rc_yellow"):
		card(&"yellow")
	elif event.is_action_pressed(&"rc_red"):
		card(&"red")
	elif event.is_action_pressed(&"rc_wave"):
		wave()
	elif event.is_action_pressed(&"rc_indirect"):
		indirect_arm = not indirect_arm
		if indirect_arm:
			body.arms.set_right(Vector3.UP, Vector3.ZERO, 1.0)
		else:
			body.arms.release_right()
	elif event.is_action_pressed(&"rc_drop"):
		dropped_ball()
	elif event.is_action_pressed(&"rc_sub"):
		m.allow_substitution()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key >= KEY_1 and key <= KEY_9 and m.added_announced >= 0 and m.level.fourth_official:
			m.set_added_time(key - KEY_0)


func _physics_process(delta: float) -> void:
	if m == null or (not enabled and m.paused):
		return
	if _whistle_down >= 0.0:
		_whistle_down += delta
	_pad_look = Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if _pad_look.length() > 0.15 and enabled and not scripted:
		yaw -= _pad_look.x * 2.6 * delta
		pitch -= _pad_look.y * 2.0 * delta * (-1.0 if settings.invert_y else 1.0)
		pitch = clampf(pitch, deg_to_rad(-82.0), deg_to_rad(70.0))
	holding_watch = force_watch or (enabled and not scripted and Input.is_action_pressed(&"rc_watch"))
	_move(delta)
	_look(delta)
	_signals(delta)
	_bump(delta)
	_watch_label.text = _watch_text()


## Where the referee wants to go, from the keys or the stick, relative to where he is
## looking. Scripted referees set `wish` directly.
var wish := Vector2.ZERO
var wish_sprint := false


func _move(delta: float) -> void:
	var input := wish
	var want_sprint := wish_sprint
	if not scripted and enabled:
		input = Input.get_vector(&"rc_left", &"rc_right", &"rc_forward", &"rc_back")
		want_sprint = Input.is_action_pressed(&"rc_sprint")
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var dir := right * input.x - forward * input.y
	var speed := JOG
	if input.y > 0.3:
		speed = BACKPEDAL
	elif absf(input.x) > 0.7 and input.y > -0.3:
		speed = SIDESTEP
	sprinting = want_sprint and input.y < 0.2 and stamina > 0.08 and input.length() > 0.2
	if sprinting:
		speed = SPRINT * lerpf(0.82, 1.0, fitness)
		stamina = maxf(stamina - SPRINT_COST * delta, 0.0)
	else:
		var recover := REST_RECOVERY if input.length() < 0.1 else JOG_RECOVERY
		stamina = minf(stamina + recover * delta, fitness)
	# A tired referee is a slow referee.
	speed *= lerpf(0.72, 1.0, clampf(stamina * 2.5, 0.0, 1.0))
	var target := dir * speed * minf(input.length(), 1.0)
	var flat := Vector3(velocity.x, 0, velocity.z).move_toward(target, ACCEL * delta)
	velocity = Vector3(flat.x, velocity.y - 9.81 * delta, flat.z)
	move_and_slide()
	if is_on_floor():
		velocity.y = 0.0
	global_position.y = maxf(global_position.y, 0.0)
	# Ninety minutes of running wears the ceiling down a little.
	fitness = maxf(0.78, fitness - flat.length() * delta * 0.000012)


func _look(delta: float) -> void:
	# The body turns towards where you look, but only once your head has turned a long
	# way from it when you are standing — so you can look over your shoulder.
	var speed := Vector2(velocity.x, velocity.z).length()
	var diff := wrapf(yaw - _body_yaw, -PI, PI)
	# Once the head has turned far enough to pull the body round, the body comes all the
	# way round — it does not stop at the edge of the dead zone and leave you facing sideways.
	if absf(diff) > deg_to_rad(65.0):
		_body_turning = true
	if speed > 0.5 or _body_turning:
		_body_yaw += diff * minf(delta * 8.0, 1.0)
		if absf(diff) < deg_to_rad(4.0):
			_body_turning = false
	var facing := Vector3(-sin(_body_yaw), 0, -cos(_body_yaw))
	body.puppet(Vector3(velocity.x, 0, velocity.z), facing)

	# Head bob: a stride's rhythm in the camera, bigger at a sprint.
	var stride := speed / 1.6
	_bob_phase += stride * delta * TAU * 0.5
	var bob_amount: float = settings.head_bob * clampf(speed / SPRINT, 0.0, 1.0)
	var bob_y := absf(sin(_bob_phase)) * 0.055 * bob_amount
	var bob_x := sin(_bob_phase) * 0.025 * bob_amount
	if speed > 1.0 and sin(_bob_phase) * sin(_bob_phase - stride * delta * TAU * 0.5) < 0.0:
		m.sound.step()
	_shake = move_toward(_shake, 0.0, delta * 3.0)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.03
	var eye := Vector3(bob_x, EYE_HEIGHT - bob_y, 0)
	# Look-down: the eye moves forward a little over the chest, as a real head does when
	# it tips forward, so the view down clears the collarbones.
	# Eyes sit in front of the neck, and a head tipping down to look at the body moves them
	# further forward and a little down. Without this the camera sat inside the chest and
	# looking down showed the inside of the shirt — which, being back faces, is nothing.
	var down := clampf(-pitch / 1.3, 0.0, 1.0)
	eye += _forward() * (0.13 + 0.15 * down) - Vector3(0, 0.04 * down, 0)
	camera.global_position = global_position + eye + shake
	camera.global_rotation = Vector3(pitch, yaw, sin(_bob_phase) * 0.006 * bob_amount)


## Players and the referee sharing the same grass: somebody running into you knocks you
## about a bit.
func _bump(delta: float) -> void:
	for p: Footballer in m.players:
		if not p.on_pitch:
			continue
		var d: Vector3 = global_position - p.global_position
		d.y = 0.0
		var l := d.length()
		if l < 0.62 and l > 0.001:
			var push := d / l * (0.62 - l) * 12.0
			velocity += push
			_shake = maxf(_shake, clampf(p.velocity.length() / 6.0, 0.2, 1.0))


# --- signals and decisions --------------------------------------------------------------

func blow(long := false) -> void:
	m.whistle(long)
	# A hand to the mouth for the whistle... the right hand, forearm up to the face.
	if not indirect_arm:
		body.arms.set_right(body.arms.to_model(Vector3(0, -0.3, 0) + _forward() * 0.6),
			body.arms.to_model(Vector3.UP * 0.8 - _forward() * 0.2), 1.0)
		_signal_left = 0.5


func _forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func look_direction() -> Vector3:
	return -camera.global_transform.basis.z


## What pointing now would give. The prompt under the crosshair shows this all the time,
## so the player knows what their arm says before they raise it.
func interpret_point() -> Dictionary:
	if m.phase not in [Match.Phase.STOPPED, Match.Phase.GOAL]:
		return {}
	var look := look_direction()
	var flat := Vector3(look.x, 0, look.z).normalized()
	var here := global_position
	var spec := m.spec
	var inc: Incident = m.stopped_for
	var team_attacking_x := func(sign_x: float) -> Team:
		return m.teams[0] if signf(m.teams[0].attack) == signf(sign_x) else m.teams[1]
	var aimed_at := func(target: Vector3, degrees: float) -> bool:
		var to := target - here
		to.y = 0.0
		return to.length() > 0.5 and flat.angle_to(to.normalized()) < deg_to_rad(degrees)

	if m.phase == Match.Phase.GOAL:
		var scoring: Team = inc.details.scoring
		var conceding: Team = m.teams[1] if scoring == m.teams[0] else m.teams[0]
		if aimed_at.call(Vector3.ZERO, 22.0):
			return {"type": &"kick_off", "team": conceding, "label": "GOAL — %s" % scoring.name}
	elif inc != null and inc.kind == &"out" and inc.details.get("goal_line", false):
		var end := 1 if inc.position.x > 0.0 else -1
		var corner := Vector3(spec.goal_line_x(end), 0, spec.half_width() * signf(inc.position.z))
		var area := Vector3(spec.goal_line_x(end) - 3.0 * end, 0, 0)
		var attackers: Team = team_attacking_x.call(end)
		var defenders: Team = team_attacking_x.call(-end)
		if aimed_at.call(corner, 25.0):
			return {"type": &"corner", "team": attackers, "label": "CORNER — %s" % attackers.name}
		if aimed_at.call(area, 25.0) or look.y < -0.45:
			return {"type": &"goal_kick", "team": defenders, "label": "GOAL KICK — %s" % defenders.name}
		return {"label": "Point at the corner flag or the goal area"}
	elif inc != null and inc.kind == &"out":
		if absf(flat.x) < 0.25:
			return {"label": "Point along the line: which way is the throw?"}
		var team: Team = team_attacking_x.call(flat.x)
		return {"type": &"throw_in", "team": team, "label": "THROW-IN — %s" % team.name}
	# A stoppage for an offence: a penalty if pointing at a spot, else a free kick.
	for end in [-1, 1]:
		var spot := spec.penalty_spot(end)
		if here.distance_to(spot) < 45.0 and aimed_at.call(spot, 9.0) and look.y < -0.05:
			var team: Team = team_attacking_x.call(end)
			return {"type": &"penalty", "team": team, "label": "PENALTY — %s" % team.name}
	if absf(flat.x) < 0.2:
		return {"label": "Point towards the goal the free kick is going to"}
	var team: Team = team_attacking_x.call(flat.x)
	var type := &"indirect_free_kick" if indirect_arm else &"free_kick"
	return {"type": type, "team": team, "label": "%s — %s" % ["INDIRECT FREE KICK" if indirect_arm else "FREE KICK", team.name]}


func point() -> void:
	var meaning := interpret_point()
	var look := look_direction()
	body.arms.set_right(body.arms.to_model((look + Vector3(0, 0.25, 0)).normalized()), Vector3.ZERO, 1.0)
	_signal_left = 1.4
	if not meaning.has("type"):
		return
	pointed.emit(meaning)
	m.award(meaning.type, meaning.team)
	if indirect_arm:
		indirect_arm = false


func advantage() -> void:
	var f := _forward()
	var down := Vector3(0, -0.25, 0)
	body.arms.set_right(body.arms.to_model((f + down + f.cross(Vector3.UP) * 0.3).normalized()), Vector3.ZERO, 1.0)
	body.arms.set_left(body.arms.to_model((f + down - f.cross(Vector3.UP) * 0.3).normalized()), Vector3.ZERO, 1.0)
	_signal_left = 1.2
	m.signal_advantage()


## The player you are looking at: nearest to the line of sight, within a few degrees.
func target_player() -> Footballer:
	var eye := camera.global_position
	var look := look_direction()
	var best: Footballer = null
	var best_angle := deg_to_rad(7.0)
	for p: Footballer in m.players:
		if not p.on_pitch:
			continue
		var chest: Vector3 = p.global_position + Vector3(0, 1.2, 0)
		var to := chest - eye
		if to.length() > 45.0:
			continue
		var angle := look.angle_to(to.normalized())
		# Close players get a wider cone; they are bigger in view.
		var allowed := best_angle + atan(0.4 / maxf(to.length(), 0.5))
		if angle < allowed and (best == null or angle < best_angle):
			best = p
			best_angle = angle
	return best


func card(colour: StringName) -> void:
	if m.phase not in [Match.Phase.STOPPED, Match.Phase.SET_PIECE, Match.Phase.GOAL]:
		return
	var who := target_player()
	if who == null:
		return
	var c := UiTheme.YELLOW if colour == &"yellow" else UiTheme.RED
	_card_material.albedo_color = c
	_card_material.emission = c
	_card_node.visible = true
	_card_for = who
	# The arm goes up rather than out: a card held out towards the player puts your own
	# forearm across the top corner of your view and the card behind it. Straight up, with
	# only a lean towards him, keeps the hand high and the card clear of it.
	var toward := (who.global_position - global_position)
	toward.y = 0.0
	var aim := (toward.normalized() * 1.7 + Vector3.UP).normalized()
	body.arms.set_right(body.arms.to_model(aim), Vector3.ZERO, 1.0)
	_signal_left = 2.2
	_hold_card()
	m.show_card(who, colour)


## Puts the card above the fist and turns its face towards the player being booked, every
## frame it is up. Both of those are world directions: which way a bone happens to point
## is no way to hold a card.
func _hold_card() -> void:
	if not _card_node.visible:
		return
	# Above the fist, and a little back towards the eyes, so the hand never covers it.
	var eye_side := (camera.global_position - _card_hand.global_position)
	eye_side.y = 0.0
	if eye_side.length() > 0.01:
		eye_side = eye_side.normalized() * 0.045
	else:
		eye_side = Vector3.ZERO
	_card_node.global_position = _card_hand.global_position + Vector3.UP * 0.075 + eye_side
	var face := Vector3.ZERO
	if _card_for != null and is_instance_valid(_card_for):
		face = _card_for.global_position - _card_node.global_position
		face.y = 0.0
	if face.length() < 0.01:
		face = _forward()
		face.y = 0.0
	# The front of the box is +Z, and look_at points -Z at what it is given: aim it at the
	# reflection so the face, not the back, is turned towards the player.
	_card_node.look_at(_card_node.global_position - face.normalized(), Vector3.UP)


func wave() -> void:
	body.arms.set_right(body.arms.to_model((_forward() + Vector3(0, -0.6, 0)).normalized()), Vector3.ZERO, 1.0)
	_signal_left = 0.8
	m.wave_flag()


func dropped_ball() -> void:
	if m.phase != Match.Phase.STOPPED:
		return
	var last: Footballer = m.laws.last_player
	var team: Team = last.team if last != null else m.teams[0]
	m.award(&"dropped_ball", team)


func _signals(delta: float) -> void:
	_hold_card()
	if _signal_left > 0.0:
		_signal_left -= delta
		if _signal_left <= 0.0:
			_card_node.visible = false
			_card_for = null
			if not indirect_arm:
				body.arms.release_right()
			body.arms.release_left()
	if holding_watch:
		# Left forearm across in front of the eyes, face up.
		body.arms.set_left(body.arms.to_model((_forward() * 0.7 + Vector3(0, -0.5, 0)).normalized()),
			body.arms.to_model((_forward() * 0.3 + Vector3(0, 0.3, 0) + _forward().cross(Vector3.UP) * -0.7).normalized()), 1.0)
		pitch = move_toward(pitch, deg_to_rad(-38.0), delta * 3.0)
	elif _signal_left <= 0.0:
		body.arms.release_left()


func _watch_text() -> String:
	var secs := m.match_seconds()
	return "%02d:%02d" % [int(secs / 60.0), int(fmod(secs, 60.0))]
