class_name MatchAI
extends RefCounted

## Twenty-two players playing football.
##
## The AI does not know the referee exists, except as something to run around. It plays
## the match; the Laws of the Game are applied by `Laws`, which watches what the AI does
## and records the truth of every offence as it happens. That separation is the whole
## design: the AI commits fouls because footballers commit fouls, not because the game
## wants to test the referee, and it has no idea whether anybody saw.
##
## How a team plays:
##
##   Shape      every player has a place in a 4-4-2, in "team space" (u from own goal to
##              theirs, v across). The whole block slides towards the ball, pushes up in
##              possession and drops without it. The back four hold one line.
##   On ball    the carrier chooses between shooting, passing and dribbling every few
##              tenths of a second, by scoring each option. Pass speed is worked out from
##              the ball's own rolling friction so it arrives where it was meant to.
##   Off ball   the nearest two teammates offer angles; forwards hang on the last line
##              and sometimes go too early — which is where offside comes from.
##   Defending  the nearest player presses and tackles, the next covers.
##
## Every tackle's outcome is rolled from the two players' skill and temper and the angle
## of the challenge. A foul's severity is decided there and then — careless, reckless, or
## excessive force — and handed to `Laws` as a fact before the referee has reacted.

var m  # the Match; untyped to avoid a cycle between the two classes

var carrier: Footballer = null
## The team that last had the ball under control: 0, 1, or -1 for nobody yet.
var possession := -1
var _decide_in := 0.0
var _receiver: Footballer = null
var _receive_point := Vector3.ZERO
var _receiver_left := 0.0
## A kick being wound up: the ball leaves the boot a moment after the swing starts.
var _pending: Dictionary = {}
var _tackle_cooldown := {}
var _holding: Dictionary = {}
var _runs := {}  # player -> seconds left on a run in behind
var _rng := RandomNumberGenerator.new()
var _dribble_dir := Vector3.ZERO
var _last_mischief := 0.0
## How far past the last defender each forward is drifting right now, in team space.
var _lurk := {}
var _lurk_timer := 0.0

## Counts, for the checks and for tuning: what the football actually looked like.
var stats := {"passes": 0, "shots": 0, "tackles": 0, "fouls": 0, "dribble_losses": 0, "dives": 0, "handballs": 0, "holds": 0, "saves": 0, "crosses": 0, "clears": 0, "dribble_choices": 0, "zone": [0, 0, 0, 0, 0], "run_passes": 0}

## Players a scenario is steering. The AI leaves their movement alone, and a held
## carrier only dribbles where he is sent — no passing, no shooting — until released.
var held := {}  # Footballer -> true

## Set pieces.
var set_piece: Dictionary = {}
var set_piece_ready := false
var _set_piece_wait := 0.0

## Tuning. These are the dials worth turning first when a match looks wrong.
const CONTROL_RADIUS := 1.05
const TACKLE_RANGE := 1.7
const SLIDE_RANGE := 2.6
const TACKLE_CHANCE_PER_SECOND := 1.7
const SHOOT_RANGE := 32.0
const PRESSURE_RANGE := 3.0
const DIVE_CHANCE := 0.9       # per second, in the box, by an attacker with a defender close
const HOLDING_CHANCE := 0.12   # per second, by a defender chasing a runner
const HANDBALL_ARMS_CHANCE := 0.3


func _init(match_node) -> void:
	m = match_node
	_rng.randomize()


func seed_with(value: int) -> void:
	_rng.seed = value


# --- the main loop ----------------------------------------------------------------------

## One tick of open play.
func step(delta: float) -> void:
	var zone := clampi(int((ball().global_position.x / spec().length + 0.5) * 5.0), 0, 4)
	stats.zone[zone] += 1
	var bz := absf(ball().global_position.z) / spec().half_width()
	stats["wide"] = stats.get("wide", [0, 0, 0, 0])
	stats.wide[clampi(int(bz * 4.0), 0, 3)] += 1
	for key in _tackle_cooldown.keys():
		_tackle_cooldown[key] -= delta
	for key in _runs.keys():
		_runs[key] -= delta
		if _runs[key] <= 0.0:
			_runs.erase(key)
	_update_holding(delta)
	# A pass has a receiver for a few seconds at most. Without this, a ball that went
	# astray was left alone for good: nobody chases while a receiver is named.
	if _receiver != null:
		_receiver_left -= delta
		if _receiver_left <= 0.0 or ball().ground_speed() < 0.6 or not _receiver.is_free():
			_receiver = null
	_update_control()
	_timing(delta)
	_update_pending(delta)
	_resolve_save(delta)
	_position_everyone(delta)
	_carrier_logic(delta)
	_defend(delta)
	_keepers(delta)
	_mischief(delta)
	_separate()


func players() -> Array:
	return m.players.filter(func(p): return p.on_pitch)


func team_of(p: Footballer) -> Team:
	return p.team


func opponents(team: Team) -> Array:
	return players().filter(func(p): return p.team != team)


func teammates(p: Footballer) -> Array:
	return players().filter(func(q): return q.team == p.team and q != p)


func ball() -> Ball:
	return m.ball


func spec() -> PitchSpec:
	return m.spec


# --- who has the ball -------------------------------------------------------------------

## Works out who, if anybody, has the ball at their feet. A player who reaches a loose
## ball takes it; the carrier keeps it while it stays close; anybody else close enough
## has to win it with a tackle.
func _update_control() -> void:
	var b := ball()
	if b.carrier != null:
		# In a keeper's hands.
		carrier = b.carrier as Footballer
		possession = carrier.team.index
		return
	if not _pending.is_empty():
		return
	if carrier != null:
		var reach := carrier.foot_position().distance_to(Vector3(b.global_position.x, 0, b.global_position.z))
		if not carrier.is_free() and carrier.state != Footballer.State.ONE_SHOT:
			_lose_ball()
		elif reach > CONTROL_RADIUS * 1.8 or b.global_position.y > 1.0:
			_lose_ball()
		else:
			return
	# Loose ball: the first player to reach it controls it, if it is low enough and not
	# screaming past.
	var best: Footballer = null
	var best_d := CONTROL_RADIUS
	for p: Footballer in players():
		if not p.is_free() or p.is_keeper() and b.global_position.y > 2.2:
			continue
		var d := p.foot_position().distance_to(Vector3(b.global_position.x, 0, b.global_position.z))
		if d < best_d and b.global_position.y < 0.9:
			var relative: float = (b.velocity - p.velocity).length()
			var controllable := 11.0 + 6.0 * p.skill
			if relative < controllable:
				best = p
				best_d = d
	if best != null:
		_take(best)
		return
	_headers()


## Gives a player the ball at his feet, for a scenario.
func give_ball(p: Footballer) -> void:
	ball().place(p.global_position + p.heading * 0.6)
	_take(p)


func _take(p: Footballer) -> void:
	carrier = p
	var changed := possession != p.team.index
	possession = p.team.index
	_receiver = null
	ball().touch(p, &"control")
	_decide_in = _rng.randf_range(0.15, 0.45) if not changed else _rng.randf_range(0.25, 0.6)
	_dribble_dir = Vector3(p.team.attack, 0, 0)


func _lose_ball() -> void:
	carrier = null


## A ball in the air at head height near somebody: they head it.
func _headers() -> void:
	var b := ball()
	var h := b.global_position.y
	if h < 1.5 or h > 2.5 or b.velocity.y > 2.0:
		return
	for p: Footballer in players():
		if not p.is_free():
			continue
		var flat := Vector2(p.global_position.x - b.global_position.x, p.global_position.z - b.global_position.z)
		if flat.length() > 0.7:
			continue
		if p.is_keeper() and spec().in_penalty_area(p.global_position, -p.team.attack):
			b.pick_up(p)
			p.one_shot("keeper_catch", 0.6)
			carrier = p
			possession = p.team.index
			_decide_in = _rng.randf_range(1.5, 3.0)
			return
		p.one_shot("header", 0.5)
		var goal := spec().goal_centre(p.team.attack)
		var to_goal := goal - p.global_position
		var dir: Vector3
		var kind := &"header"
		if to_goal.length() < 14.0:
			dir = (goal + Vector3(0, 1.2, _rng.randf_range(-3.0, 3.0)) - b.global_position).normalized()
			b.kick(dir * _rng.randf_range(11.0, 15.0), p, &"shot")
			kind = &"shot"
		else:
			# A defensive header goes anywhere away from goal, often into touch.
			var own_box := spec().in_penalty_area(p.global_position, -p.team.attack)
			var spread := 1.4 if own_box else 0.6
			dir = Vector3(p.team.attack, 0.45, _rng.randf_range(-spread, spread)).normalized()
			b.kick(dir * _rng.randf_range(10.0, 16.0), p, &"header")
		m.on_played(p, kind)
		possession = p.team.index
		return


# --- the shape --------------------------------------------------------------------------

## Where each player belongs right now, given the ball and who has it.
func _shape_target(p: Footballer) -> Vector3:
	var team := p.team
	var slot: Dictionary = Team.FORMATION_442[p.slot]
	var ball_team := team.to_team_space(ball().global_position, spec())
	var attacking := possession == team.index
	var u: float = slot.u
	var v: float = slot.v
	# The block slides with the ball, and more so going forward than back.
	var shift := (ball_team.x - 0.5) * (0.62 if attacking else 0.5)
	u += shift + (0.1 if attacking else -0.04)
	v = v * (0.95 if attacking else 0.72) + ball_team.y * 0.22
	if p.role == Footballer.Role.DF:
		u = _defensive_line(team, attacking)
		if absf(slot.v) > 0.5 and attacking:
			u += 0.05
	elif p.role == Footballer.Role.FW and attacking:
		# Forwards live on the shoulder of the last defender — and like real ones, they
		# drift a step too far now and then. That step is where most offsides come from.
		var line := _offside_line_u(team)
		u = minf(u + 0.06, line - 0.01 + _lurk.get(p, 0.0))
	u = clampf(u, 0.04, 0.96)
	v = clampf(v, -0.95, 0.95)
	return team.to_world(u, v, spec())


## The back four's line, in team space. They hold it together, which is what makes an
## offside trap: the whole line steps up at once.
func _defensive_line(team: Team, attacking: bool) -> float:
	var ball_u := team.to_team_space(ball().global_position, spec()).x
	var line := 0.2 + (ball_u - 0.5) * 0.45
	if attacking:
		line += 0.1
	# Never further forward than the ball when defending, and never inside the six-yard box.
	if not attacking:
		line = minf(line, ball_u - 0.03)
	return clampf(line, 0.07, 0.55)


## The attackers' offside line in *their* team space: the second-last opponent, or the
## ball if it is further forward, or the halfway line if both are behind it.
func _offside_line_u(team: Team) -> float:
	var us: Array = []
	for q: Footballer in opponents(team):
		us.append(team.to_team_space(q.global_position, spec()).x)
	us.sort()
	var second_last: float = us[us.size() - 2] if us.size() >= 2 else 1.0
	var ball_u := team.to_team_space(ball().global_position, spec()).x
	return maxf(maxf(second_last, ball_u), 0.5)


func _position_everyone(_delta: float) -> void:
	for p: Footballer in players():
		if not p.can_move() or p == carrier or p.is_keeper():
			continue
		if _pending.get("player") == p or held.has(p):
			continue
		var target := _shape_target(p)
		var hurry := 0.55
		var attacking := possession == p.team.index
		# The intended receiver runs onto the pass.
		if p == _receiver:
			target = _receive_point
			hurry = 1.0
		elif _runs.has(p):
			target = _run_target(p)
			hurry = 1.0
		elif attacking and carrier != null and carrier.team == p.team:
			target = _support(p, target)
		elif carrier == null and p == _nearest_to_ball(p.team) and (_receiver == null or _receiver.team != p.team):
			target = _chase_point(p)
			hurry = 1.0
		p.goal = spec().clamp_to_field(target, 0.5)
		p.hurry = hurry
		# Everybody watches the ball.
		p.face_point = ball().global_position if p.global_position.distance_to(ball().global_position) < 30.0 else null
		if p.velocity.length() > p.pace * 0.7:
			p.face_point = null


## The two nearest teammates offer the carrier an angle; the rest keep their shape.
func _support(p: Footballer, shape: Vector3) -> Vector3:
	var near := teammates(carrier)
	near.sort_custom(func(a, b): return a.global_position.distance_to(carrier.global_position) < b.global_position.distance_to(carrier.global_position))
	var rank := near.find(p)
	if rank < 0 or rank > 1:
		return shape
	var ahead := Vector3(p.team.attack, 0, 0)
	var side := 1.0 if (p.global_position.z - carrier.global_position.z) > 0.0 else -1.0
	var offer := carrier.global_position + ahead * (6.0 if rank == 0 else -2.0) + Vector3(0, 0, side * (11.0 if rank == 0 else 9.0))
	return shape.lerp(offer, 0.65)


func _nearest_to_ball(team: Team) -> Footballer:
	var best: Footballer = null
	var best_d := INF
	for p: Footballer in players():
		if p.team != team or p.is_keeper() or not p.is_free():
			continue
		var d := p.global_position.distance_to(ball().predict(0.4))
		if d < best_d:
			best = p
			best_d = d
	return best


## Where to run to meet a loose ball: where it will be by the time we could get there.
func _chase_point(p: Footballer) -> Vector3:
	var t := 0.0
	for i in 12:
		var at := ball().predict(t)
		var need := p.global_position.distance_to(at) / maxf(p.top_speed(), 1.0)
		if need <= t:
			return at
		t += 0.25
	return ball().predict(t)


## A run in behind: towards the goal, beyond the last line.
func _run_target(p: Footballer) -> Vector3:
	var line := _offside_line_u(p.team)
	var slot: Dictionary = Team.FORMATION_442[p.slot]
	var lane: float = slot.v if absf(slot.v) > 0.3 else slot.v * 2.5
	return p.team.to_world(minf(line + 0.07, 0.9), clampf(lane, -0.85, 0.85), spec())


## Forwards' timing, which is imperfect. Every couple of seconds each one either holds
## the line, drifts a metre or three beyond it, or — when a teammate has the ball with
## time to look up — sets off early on a run in behind.
func _timing(delta: float) -> void:
	_lurk_timer -= delta
	if _lurk_timer > 0.0:
		return
	_lurk_timer = 1.5
	for p: Footballer in players():
		var winger := p.role == Footballer.Role.MF and absf(Team.FORMATION_442[p.slot].v) > 0.5
		if p.role != Footballer.Role.FW and not winger:
			continue
		var r := _rng.randf()
		_lurk[p] = _rng.randf_range(0.012, 0.035) if r < 0.22 and not winger else 0.0
		var ours := carrier != null and carrier.team == p.team and carrier != p
		if ours and not _runs.has(p) and _pressure(carrier) < 0.5 and _rng.randf() < 0.3:
			_runs[p] = 2.6


# --- on the ball ------------------------------------------------------------------------

func _carrier_logic(delta: float) -> void:
	if carrier == null or not _pending.is_empty():
		return
	var b := ball()
	if b.carrier == carrier:
		return  # keeper's hands; handled in _keepers
	if not carrier.can_move():
		return
	# Keep the ball at the feet: a sticky dribble. The ball is steered to just ahead of
	# the boots, which looks like close control and cannot be lost by accident — only by
	# a tackle, a pass or a shot.
	var ahead := carrier.global_position + carrier.heading * 0.62
	var to := ahead - b.global_position
	to.y = 0.0
	b.velocity = Vector3(carrier.velocity.x, 0, carrier.velocity.z) + to * 8.0
	b.global_position.y = PitchSpec.BALL_RADIUS
	b.on_ground = true

	if held.has(carrier):
		return
	_decide_in -= delta
	var goal := spec().goal_centre(carrier.team.attack)
	var pressure := _pressure(carrier)
	if _decide_in > 0.0:
		_dribble(pressure)
		return
	_decide_in = _rng.randf_range(0.2, 0.4)

	var distance := carrier.global_position.distance_to(goal)
	var angle := absf(carrier.global_position.z) / maxf(absf(goal.x - carrier.global_position.x), 1.0)
	# Shoot?
	if distance < SHOOT_RANGE and angle < 1.6:
		# Short halves need a match's worth of shots in twelve minutes, so these players
		# shoot more readily than real ones would.
		var chance := clampf((SHOOT_RANGE - distance) / SHOOT_RANGE, 0.0, 1.0) * 0.9 + (0.45 if distance < 18.0 else 0.1)
		if _rng.randf() < chance:
			_shoot(goal)
			return
	# Cross it? A wide player in the final third puts it into the box.
	var u := carrier.team.to_team_space(carrier.global_position, spec()).x
	if u > 0.7 and absf(carrier.global_position.z) > spec().half_width() * 0.45 and _rng.randf() < 0.7:
		_cross(goal)
		return
	# Clear it? A defender under pressure near his own goal gets rid of it.
	var own := spec().goal_centre(-carrier.team.attack)
	if carrier.global_position.distance_to(own) < 22.0 and pressure > 0.6 and _rng.randf() < 0.6:
		_clear()
		return
	# Pass?
	var option := _best_pass()
	var dribble_value := _dribble_value(pressure)
	# Under real pressure, sometimes he just loses it.
	if pressure > 0.85 and _rng.randf() < 0.08 * (1.2 - carrier.skill):
		stats.dribble_losses += 1
		var loose := carrier.heading.rotated(Vector3.UP, _rng.randf_range(-1.2, 1.2))
		_lose_ball()
		ball().kick(loose * _rng.randf_range(4.0, 8.0), ball().last_touch, &"control")
		return
	if not option.is_empty() and (option.score > dribble_value or pressure > 0.75):
		_pass(option)
		return
	stats.dribble_choices += 1
	_dribble(pressure)


func _pressure(p: Footballer) -> float:
	var nearest := INF
	for q: Footballer in opponents(p.team):
		nearest = minf(nearest, q.global_position.distance_to(p.global_position))
	return clampf(1.0 - (nearest - 1.0) / PRESSURE_RANGE, 0.0, 1.0)


func _dribble_value(pressure: float) -> float:
	var ahead := Vector3(carrier.team.attack, 0, 0)
	var space := 12.0
	for q: Footballer in opponents(carrier.team):
		var rel: Vector3 = q.global_position - carrier.global_position
		if rel.dot(ahead) > 0.0 and rel.length() < space:
			space = rel.length()
	return 0.2 + space / 16.0 - pressure * 0.5 + carrier.skill * 0.2


## Runs with the ball towards goal, bending away from whoever is closest.
func _dribble(pressure: float) -> void:
	var goal := spec().goal_centre(carrier.team.attack)
	var dir := (goal - carrier.global_position)
	dir.y = 0.0
	dir = dir.normalized()
	# Wide players run down the line, out towards the touchline, rather than at the goal.
	if absf(carrier.global_position.z) > spec().half_width() * 0.4 and absf(goal.x - carrier.global_position.x) > 16.0:
		dir = Vector3(carrier.team.attack, 0, signf(carrier.global_position.z) * 0.25).normalized()
	var closest: Footballer = null
	var closest_d := 6.0
	for q: Footballer in opponents(carrier.team):
		var d: float = q.global_position.distance_to(carrier.global_position)
		if d < closest_d:
			closest = q
			closest_d = d
	if closest != null:
		var away: Vector3 = carrier.global_position - closest.global_position
		away.y = 0.0
		dir = (dir + away.normalized() * (1.4 - closest_d / 6.0)).normalized()
	_dribble_dir = _dribble_dir.lerp(dir, 0.3).normalized()
	carrier.goal = spec().clamp_to_field(carrier.global_position + _dribble_dir * 6.0, 1.0)
	carrier.hurry = 0.78 + pressure * 0.15
	carrier.face_point = null


## The best teammate to pass to, and how good an idea it is.
func _best_pass() -> Dictionary:
	var best := {}
	var best_score := -INF
	var line := _offside_line_u(carrier.team)
	for mate: Footballer in teammates(carrier):
		if not mate.is_free():
			continue
		var target: Vector3 = mate.global_position + mate.velocity * 0.6
		var d := carrier.global_position.distance_to(target)
		if d < 5.0 or d > 45.0:
			continue
		var progress := (target.x - carrier.global_position.x) * carrier.team.attack
		var openness := _lane_openness(carrier.global_position, target, carrier.team)
		var marked := _marked_by(mate)
		var score := progress / 17.0 + openness * 0.8 - marked * 0.6 - d / 90.0
		if progress < -3.0:
			score -= 0.25
		# Width: a ball out to a wide player stretches the other side. Without this every
		# attack went down the middle and the ball reached a touchline once a match.
		score += 0.45 * absf(target.z) / spec().half_width()
		if mate.is_keeper():
			score -= 0.7
		# A pass to somebody standing offside is a mistake, but players make it: they
		# cannot see the line any better than the referee can. They just value it less.
		var mate_u := carrier.team.to_team_space(mate.global_position, spec()).x
		if mate_u > line + 0.01:
			score -= 0.25
		score += _rng.randf_range(-0.15, 0.15)
		if score > best_score:
			best_score = score
			best = {"to": mate, "at": target, "score": score, "distance": d}
	return best


## 0 to 1: how clear the straight line from a to b is of opponents.
func _lane_openness(a: Vector3, b: Vector3, team: Team) -> float:
	var ab := b - a
	var length := ab.length()
	var worst := 1.0
	for q: Footballer in opponents(team):
		var t := clampf((q.global_position - a).dot(ab) / (length * length), 0.0, 1.0)
		var closest := a + ab * t
		var gap: float = q.global_position.distance_to(closest)
		worst = minf(worst, clampf((gap - 0.5) / 3.0, 0.0, 1.0))
	return worst


func _marked_by(p: Footballer) -> float:
	var nearest := INF
	for q: Footballer in opponents(p.team):
		nearest = minf(nearest, q.global_position.distance_to(p.global_position))
	return clampf(1.0 - (nearest - 1.0) / 4.0, 0.0, 1.0)


func _pass(option: Dictionary) -> void:
	var mate: Footballer = option.to
	var target: Vector3 = option.at
	var d: float = option.distance
	var lofted := d > 28.0 and _rng.randf() < 0.55 or _lane_openness(carrier.global_position, target, carrier.team) < 0.3 and d > 15.0
	# Sometimes a runner is sent through instead: the ball is played into space ahead.
	if mate.role in [Footballer.Role.FW, Footballer.Role.MF] and (_runs.has(mate) or _rng.randf() < 0.18):
		stats.run_passes += 1
		_runs[mate] = 2.5
		target = _run_target(mate)
		d = carrier.global_position.distance_to(target)
	var error := (1.0 - carrier.skill) * 0.18 + _pressure(carrier) * 0.1 + d / 700.0
	var velocity := _pass_velocity(carrier.global_position, target, lofted)
	velocity = velocity.rotated(Vector3.UP, _rng.randfn(0.0, error))
	velocity *= _rng.randf_range(0.92, 1.1 + error)
	_receiver = mate
	_receive_point = target
	_receiver_left = 3.0
	_strike(velocity, &"pass", "pass" if not lofted else "kick", 0.18)


## The velocity that gets a ball from a to b. Along the ground, it is the speed that
## arrives with about 5 m/s left, from the ball's own rolling friction; in the air, a
## launch at 35 degrees with a little extra for drag.
func _pass_velocity(a: Vector3, b: Vector3, lofted: bool) -> Vector3:
	var flat := b - a
	flat.y = 0.0
	var d := flat.length()
	var dir := flat / maxf(d, 0.01)
	if not lofted:
		var arrive := 5.0
		var speed := sqrt(arrive * arrive + 2.0 * Ball.ROLL_FRICTION * d) * 1.06
		return dir * minf(speed, 26.0)
	var angle := deg_to_rad(35.0)
	var speed_air := sqrt(d * Ball.GRAVITY / sin(2.0 * angle)) * (1.0 + d * 0.004)
	return dir * cos(angle) * speed_air + Vector3.UP * sin(angle) * speed_air


func _shoot(goal: Vector3) -> void:
	var p := carrier
	# Aim for a corner, and miss some: a real side gets about a third of its shots on target.
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var target := goal + Vector3(0, _rng.randf_range(0.2, 2.3), side * _rng.randf_range(1.6, 3.6))
	var speed := _rng.randf_range(20.0, 28.0) * lerpf(0.85, 1.05, p.skill)
	var from := ball().global_position
	var flat := target - from
	var horizontal := Vector2(flat.x, flat.z).length()
	var t := horizontal / speed
	var vy := (target.y - from.y) / t + 0.5 * Ball.GRAVITY * t
	var dir := Vector3(flat.x, 0, flat.z).normalized() * speed + Vector3.UP * vy
	var error := (1.0 - p.skill) * 0.09 + _pressure(p) * 0.06 + horizontal / 400.0
	dir = dir.rotated(Vector3.UP, _rng.randfn(0.0, error))
	dir.y += _rng.randfn(0.0, error * 12.0)
	_receiver = null
	_strike(dir, &"shot", "kick", 0.2)


func _cross(goal: Vector3) -> void:
	stats.crosses += 1
	var target := goal - Vector3(carrier.team.attack * _rng.randf_range(4.0, 12.0), 0, _rng.randf_range(-6.0, 6.0))
	var v := _pass_velocity(ball().global_position, target, true)
	v = v.rotated(Vector3.UP, _rng.randfn(0.0, 0.08 + (1.0 - carrier.skill) * 0.08))
	v *= _rng.randf_range(0.9, 1.12)
	_receiver = null
	_strike(v, &"pass", "kick", 0.2)


func _clear() -> void:
	stats.clears += 1
	var wide := signf(carrier.global_position.z) if absf(carrier.global_position.z) > 3.0 else (1.0 if _rng.randf() < 0.5 else -1.0)
	var dir := Vector3(carrier.team.attack, 0, _rng.randf_range(-0.3, 1.6) * wide).normalized()
	var power := _rng.randf_range(19.0, 27.0)
	var v := dir * power * cos(0.6) + Vector3.UP * power * sin(0.6)
	_receiver = null
	_strike(v, &"clearance", "kick", 0.18)


## Starts a kick. The ball leaves the boot a fraction of a second later, which is the
## window in which a defender can still get a foot in.
func _strike(velocity: Vector3, kind: StringName, clip: String, windup: float) -> void:
	_pending = {"player": carrier, "velocity": velocity, "kind": kind, "left": windup}
	carrier.one_shot(clip, 0.55)
	carrier.goal = carrier.global_position + carrier.heading * 0.5
	var flat := Vector3(velocity.x, 0, velocity.z)
	if flat.length() > 0.1:
		carrier.face_point = carrier.global_position + flat.normalized() * 5.0


func _update_pending(delta: float) -> void:
	if _pending.is_empty():
		return
	var p: Footballer = _pending.player
	_pending.left -= delta
	var b := ball()
	if not p.on_pitch or p.state == Footballer.State.FALLEN:
		_pending = {}
		return
	# Keep the ball at the boot through the swing.
	var ahead := p.global_position + p.heading * 0.6
	b.velocity = (ahead - b.global_position) * 6.0
	b.velocity.y = 0.0
	b.global_position.y = PitchSpec.BALL_RADIUS
	b.on_ground = true
	if _pending.left > 0.0:
		return
	b.kick(_pending.velocity, p, _pending.kind)
	stats.shots += 1 if _pending.kind == &"shot" else 0
	stats.passes += 1 if _pending.kind == &"pass" else 0
	m.on_played(p, _pending.kind)
	m.sound_kick(b.global_position, (_pending.velocity as Vector3).length())
	carrier = null
	_pending = {}
	p.face_point = null


# --- defending --------------------------------------------------------------------------

func _defend(delta: float) -> void:
	var b := ball()
	var target: Footballer = carrier
	if target == null or b.carrier != null:
		return
	var defenders := opponents(target.team)
	defenders = defenders.filter(func(q): return q.is_free() and not q.is_keeper() and not held.has(q))
	defenders.sort_custom(func(a, c): return a.global_position.distance_to(target.global_position) < c.global_position.distance_to(target.global_position))
	if defenders.is_empty():
		return
	var own_goal := spec().goal_centre(-defenders[0].team.attack)
	# The presser goes to the ball, goal side.
	var presser: Footballer = defenders[0]
	# Jockey at two or three metres and pick the moment, rather than standing on his toes:
	# a presser glued to the carrier made every touch a panic and kept the ball in midfield.
	var stand_off := lerpf(2.8, 1.6, presser.aggression)
	if _tackle_cooldown.get(presser, 0.0) <= -1.2:
		stand_off = 1.0
	var goal_side := target.global_position + (own_goal - target.global_position).normalized() * stand_off
	presser.goal = goal_side
	presser.hurry = 1.0
	presser.face_point = target.global_position
	# The next one covers behind him.
	if defenders.size() > 1:
		var cover: Footballer = defenders[1]
		cover.goal = target.global_position + (own_goal - target.global_position).normalized() * 7.0
		cover.hurry = 0.8
		cover.face_point = target.global_position
	# Tackles.
	for q: Footballer in defenders.slice(0, 2):
		var d: float = q.global_position.distance_to(target.global_position)
		if _tackle_cooldown.get(q, 0.0) > 0.0:
			continue
		var sliding: bool = d > TACKLE_RANGE and d < SLIDE_RANGE and q.velocity.length() > 4.5 and _rng.randf() < 0.3
		if d > (SLIDE_RANGE if sliding else TACKLE_RANGE):
			continue
		var rate := TACKLE_CHANCE_PER_SECOND * lerpf(0.6, 1.4, q.aggression)
		if _rng.randf() < rate * delta:
			_tackle(q, target, sliding)
			return


## One challenge. The outcome is decided here, from who is better and how the tackle came
## in, and if it is a foul, how bad a foul — a fact recorded before anybody reacts.
func _tackle(defender: Footballer, attacker: Footballer, sliding: bool) -> void:
	_tackle_cooldown[defender] = 1.6
	stats.tackles += 1
	# Long enough for the clip: the standing tackle plants, reaches and recovers over
	# about a second, and cutting it at 0.45 s snapped the leg back mid-lunge.
	defender.one_shot("slide" if sliding else "tackle", 1.4 if sliding else 0.8)
	if sliding:
		defender.velocity = (attacker.global_position - defender.global_position).normalized() * 6.5
	# From behind: the attacker is facing away from the tackler.
	var from_tackler: Vector3 = (attacker.global_position - defender.global_position).normalized()
	var behind := attacker.heading.dot(from_tackler) > 0.5
	var clean := 0.45 + (defender.skill - attacker.skill) * 0.5
	var foul := 0.1 + defender.aggression * 0.22 + (0.28 if behind else 0.0) + (0.14 if sliding else 0.0)
	foul *= lerpf(1.2, 0.7, defender.team.discipline)
	var roll := _rng.randf()
	if roll < foul:
		_foul(defender, attacker, sliding, behind)
	elif roll < foul + clean:
		# Won it cleanly. Sometimes it squirts loose rather than to his feet.
		_lose_ball()
		# Won, but rarely neatly: the ball squirts away, often towards the touchline.
		var away := Vector3(-attacker.team.attack * _rng.randf_range(-0.4, 1.0), 0, _rng.randf_range(-1.2, 1.2)).normalized()
		ball().kick(away * _rng.randf_range(4.0, 13.0), defender, &"tackle")
		possession = defender.team.index
		if _rng.randf() < 0.25:
			attacker.fall(from_tackler, 1.0)
	# Otherwise the attacker rides it and carries on.


## A foul decided by a scenario rather than by the dice: who, how, how bad, and whether
## the fouled player stays on his feet.
func force_foul(defender: Footballer, attacker: Footballer, severity: Laws.Severity, sliding: bool,
		behind: bool, stays_up: bool) -> void:
	_tackle_cooldown[defender] = 3.0
	# Long enough for the clip: the standing tackle plants, reaches and recovers over
	# about a second, and cutting it at 0.45 s snapped the leg back mid-lunge.
	defender.one_shot("slide" if sliding else "tackle", 1.4 if sliding else 0.8)
	_foul(defender, attacker, sliding, behind, severity, 1 if stays_up else 0)


func _foul(defender: Footballer, attacker: Footballer, sliding: bool, behind: bool,
		forced_severity := -1, forced_stays_up := -1) -> void:
	stats.fouls += 1
	var severity := Laws.Severity.CARELESS
	var r := _rng.randf()
	var rough := defender.aggression * (1.5 if sliding else 1.0) * (1.6 if behind else 1.0)
	if r < 0.02 + 0.07 * rough:
		severity = Laws.Severity.EXCESSIVE
	elif r < 0.15 + 0.3 * rough:
		severity = Laws.Severity.RECKLESS
	if forced_severity >= 0:
		severity = forced_severity as Laws.Severity
	var push: Vector3 = (attacker.global_position - defender.global_position).normalized()
	# Most fouls put the man down. A careless trip on a strong player sometimes does not,
	# and he stumbles on with the ball — the classic moment for advantage.
	var stays_up := severity == Laws.Severity.CARELESS and _rng.randf() < 0.3 + attacker.skill * 0.2
	if forced_stays_up >= 0:
		stays_up = forced_stays_up == 1
	var hurt := severity == Laws.Severity.EXCESSIVE or severity == Laws.Severity.RECKLESS and _rng.randf() < 0.3
	if forced_severity >= 0:
		hurt = false
	m.laws.foul(defender, attacker, &"tackle", severity, attacker.global_position, {"sliding": sliding, "from_behind": behind})
	if stays_up:
		attacker.velocity *= 0.5
		return
	_lose_ball()
	var b := ball()
	b.velocity = push * _rng.randf_range(1.5, 4.0)
	attacker.fall(push, _rng.randf_range(1.6, 3.2) + (3.0 if hurt else 0.0), hurt and _rng.randf() < 0.5)


# --- keepers ----------------------------------------------------------------------------

func _keepers(delta: float) -> void:
	var b := ball()
	for team in m.teams:
		var gk: Footballer = team.keeper()
		if gk == null or not gk.can_move():
			continue
		var line_x := spec().goal_line_x(-team.attack)
		var goal := Vector3(line_x, 0, 0)
		if b.carrier == gk:
			_keeper_distribute(gk, delta)
			continue
		# A shot coming: try to save it.
		if _save_attempt(gk):
			continue
		# A loose ball in his own box that he can reach first: go and get it.
		if b.carrier == null and carrier == null and spec().in_penalty_area(b.global_position, -team.attack):
			var nearest_opp := INF
			for q: Footballer in opponents(team):
				nearest_opp = minf(nearest_opp, q.global_position.distance_to(b.global_position))
			var mine := gk.global_position.distance_to(b.global_position)
			if mine < nearest_opp and b.speed() < 14.0:
				gk.goal = b.predict(0.3)
				gk.hurry = 1.0
				if mine < 1.2 and b.global_position.y < 1.8:
					_keeper_gathers(gk)
				continue
		# Otherwise stand on the line between the ball and the middle of the goal.
		var to_ball := b.global_position - goal
		to_ball.y = 0.0
		var off := clampf(to_ball.length() * 0.09, 0.8, 9.0)
		gk.goal = goal + to_ball.normalized() * off
		gk.hurry = 0.7
		gk.face_point = b.global_position


func _keeper_gathers(gk: Footballer) -> void:
	var b := ball()
	# Law 12: a keeper may not handle a ball deliberately kicked to him by a teammate.
	var back_pass: bool = b.last_touch is Footballer and b.last_touch != gk \
		and (b.last_touch as Footballer).team == gk.team and b.last_touch_kind in [&"pass", &"clearance"]
	if back_pass and _rng.randf() > 0.12:
		# Nearly every keeper knows the rule and plays it with his feet instead.
		_take(gk)
		return
	b.pick_up(gk)
	gk.one_shot("keeper_catch", 0.6)
	carrier = gk
	possession = gk.team.index
	_decide_in = _rng.randf_range(2.0, 4.0)
	if back_pass:
		m.laws.back_pass(gk, b.last_touch, gk.global_position)


## Whether a shot is coming, and if so the keeper goes for it. The save is decided once,
## a reaction time before the ball reaches the line, by whether he could cover the
## distance to where it crosses — a few steps plus a full-length dive — and by how good
## he is. (It first waited until the ball was within two metres of him, which a shot at
## 25 m/s passes between two ticks; keepers saved nothing and six of seven shots went in.)
func _save_attempt(gk: Footballer) -> bool:
	var b := ball()
	if b.last_touch_kind not in [&"shot", &"header"] or b.carrier != null:
		return false
	if b.last_touch is Footballer and (b.last_touch as Footballer).team == gk.team:
		return false
	var line_x := spec().goal_line_x(-gk.team.attack)
	var vx := b.velocity.x
	if absf(vx) < 1.0 or signf(vx) != signf(line_x - b.global_position.x):
		return false
	var t := (line_x - b.global_position.x) / vx
	if t < 0.0 or t > 1.8:
		return false
	var cross := b.global_position + b.velocity * t
	cross.y = b.global_position.y + b.velocity.y * t - 0.5 * Ball.GRAVITY * t * t
	var on_target := absf(cross.z) < PitchSpec.GOAL_WIDTH * 0.5 + 0.3 and cross.y < PitchSpec.GOAL_HEIGHT + 0.3
	gk.face_point = b.global_position
	if not on_target:
		return false
	gk.goal = Vector3(line_x + 0.5 * gk.team.attack, 0, cross.z)
	gk.hurry = 1.0
	if t > 0.42 or _shot_decided == b.last_touch_time:
		return true
	_shot_decided = b.last_touch_time
	var reach := absf(cross.z - gk.global_position.z)
	var cover := 1.2 + gk.top_speed() * t * 0.6 + 1.6
	var high := cross.y > 2.1
	var chance := 0.78 + gk.skill * 0.15 - b.speed() / 120.0 - (0.15 if high else 0.0)
	chance -= clampf((reach - 1.0) / cover, 0.0, 1.0) * 0.55
	var saved := reach < cover and _rng.randf() < chance
	if reach > 1.0:
		# Out of reach standing up: he goes for it. This used to be `fall()`, which tipped
		# him over on the spot — the one moment of a match everybody watches, and the
		# keeper was falling down rather than diving.
		gk.dive_at(Vector3(gk.global_position.x, 0.0, cross.z), 1.4)
	else:
		gk.one_shot("keeper_catch", 0.7)
	if saved:
		stats.saves += 1
		_pending_save = {"gk": gk, "at": cross, "left": maxf(t - 0.05, 0.0), "catch": b.speed() < 22.0 and reach < 1.2 and _rng.randf() < 0.6}
	return true


var _shot_decided := -1.0
var _pending_save := {}


## The save happens when the ball arrives, not when the keeper decides to go.
func _resolve_save(delta: float) -> void:
	if _pending_save.is_empty():
		return
	_pending_save.left -= delta
	if _pending_save.left > 0.0:
		return
	var gk: Footballer = _pending_save.gk
	var b := ball()
	var cross: Vector3 = _pending_save.at
	if b.global_position.distance_to(cross) < 4.0 and b.in_play:
		if _pending_save.catch:
			b.pick_up(gk)
			carrier = gk
			possession = gk.team.index
			_decide_in = _rng.randf_range(2.0, 4.0)
		else:
			# Parried: round the post or back out, mostly wide.
			var side := signf(cross.z) if absf(cross.z) > 0.2 else (1.0 if _rng.randf() < 0.5 else -1.0)
			var away := Vector3(-gk.team.attack * _rng.randf_range(0.1, 0.9), _rng.randf_range(0.2, 0.6), side * _rng.randf_range(0.4, 1.0)).normalized()
			b.kick(away * maxf(b.speed() * 0.45, 7.0), gk, &"save")
			possession = -1
			carrier = null
	_pending_save = {}


func _keeper_distribute(gk: Footballer, delta: float) -> void:
	_decide_in -= delta
	# Stand still with it; opponents drop off.
	gk.goal = gk.global_position
	gk.face_point = spec().goal_centre(gk.team.attack)
	if _decide_in > 0.0:
		return
	var b := ball()
	b.carrier = null
	var target: Vector3
	var mates := teammates(gk).filter(func(q): return q.role == Footballer.Role.DF and _marked_by(q) < 0.4)
	if not mates.is_empty() and _rng.randf() < 0.55:
		var mate: Footballer = mates[_rng.randi() % mates.size()]
		target = mate.global_position
		_receiver = mate
		_receive_point = target
		_receiver_left = 3.0
		gk.one_shot("keeper_throw", 0.6)
		b.global_position = gk.global_position + gk.heading * 0.5 + Vector3(0, 1.0, 0)
		b.kick(_pass_velocity(b.global_position, target, false) * 0.9, gk, &"throw")
		m.on_played(gk, &"throw")
	else:
		target = gk.team.to_world(_rng.randf_range(0.55, 0.75), _rng.randf_range(-0.6, 0.6), spec())
		gk.one_shot("kick", 0.6)
		b.global_position = gk.global_position + gk.heading * 0.6
		b.global_position.y = PitchSpec.BALL_RADIUS
		b.kick(_pass_velocity(b.global_position, target, true), gk, &"clearance")
		m.on_played(gk, &"clearance")
		m.sound_kick(b.global_position, 25.0)
	carrier = null


# --- things players do that the Laws care about ----------------------------------------

## The less honourable parts of the game: dives, shirt-pulling and handball. Each has
## something the referee can see, because an offence nobody could see is a coin toss,
## not a decision.
func _mischief(delta: float) -> void:
	var b := ball()
	# Simulation: an attacker with the ball in the box goes down with a defender close
	# and no contact. What gives it away is exactly that — no tackle, no touch.
	if carrier != null and b.carrier == null and not carrier.is_keeper():
		var in_box := spec().in_penalty_area(carrier.global_position, carrier.team.attack)
		var final_third := carrier.team.to_team_space(carrier.global_position, spec()).x > 0.66
		var close := 99.0
		for q: Footballer in opponents(carrier.team):
			close = minf(close, q.global_position.distance_to(carrier.global_position))
		if (in_box or final_third) and close < 2.4 and close > 0.7 and m.clock - _last_mischief > 15.0:
			if _rng.randf() < DIVE_CHANCE * (1.0 - carrier.honesty) * (4.0 if in_box else 1.5) * delta:
				_last_mischief = m.clock
				var diver := carrier
				_lose_ball()
				stats.dives += 1
				m.laws.simulation(diver, diver.global_position)
				diver.fall(diver.heading, 2.2)
				b.velocity = diver.heading * 2.5
	# Handball: a defender who throws his arms out to block a shot or a cross, and the
	# ball hits them. With the arms by his side it is only a block.
	if b.carrier == null and b.speed() > 8.0 and b.last_touch is Footballer:
		var kicker: Footballer = b.last_touch
		for q: Footballer in opponents(kicker.team):
			if not q.is_free() or q.is_keeper() and spec().in_penalty_area(q.global_position, -q.team.attack):
				continue
			var rel: Vector3 = b.global_position - q.global_position
			var flat := Vector2(rel.x, rel.z).length()
			if flat > 0.95 or rel.y < 0.6 or rel.y > 2.0:
				continue
			if b.velocity.dot(-rel) <= 0.0:
				continue
			var arms_out := _rng.randf() < HANDBALL_ARMS_CHANCE * lerpf(0.5, 1.5, q.aggression)
			if has_meta("force_arms"):
				arms_out = get_meta("force_arms") == q
				remove_meta("force_arms")
			if arms_out:
				q.arms.set_right(Vector3(-1.0, 0.1, 0.4), Vector3.ZERO, 1.0)
				q.arms.set_left(Vector3(1.0, 0.1, 0.4), Vector3.ZERO, 1.0)
				_release_arms_later(q)
				stats.handballs += 1
				m.laws.handball(q, kicker, q.global_position, {"blocked": kicker_kind(b)})
			# Either way it is blocked.
			var bounce := Vector3(-b.velocity.x, absf(b.velocity.y) * 0.3 + 1.0, -b.velocity.z).normalized()
			b.kick(bounce * b.speed() * 0.35, q, &"handball" if arms_out else &"block")
			possession = -1
			carrier = null
			_receiver = null
			return


func kicker_kind(b: Ball) -> StringName:
	return b.last_touch_kind


func _release_arms_later(p: Footballer) -> void:
	var timer: SceneTreeTimer = m.get_tree().create_timer(0.9)
	timer.timeout.connect(func(): if is_instance_valid(p): p.arms.release())


## Shirt-pulling: a defender chasing a runner grabs him. The arm reaching out for the
## shirt is what the referee sees; the runner is slowed, and sometimes goes down.
func _update_holding(delta: float) -> void:
	for key: Footballer in _holding.keys():
		var h: Dictionary = _holding[key]
		h.left -= delta
		var defender: Footballer = key
		var attacker: Footballer = h.victim
		if h.left <= 0.0 or not attacker.is_free() or not defender.is_free():
			defender.arms.release()
			_holding.erase(key)
			continue
		var reach := attacker.global_position - defender.global_position
		defender.arms.set_right(defender.arms.to_model(reach.normalized() + Vector3(0, 0.1, 0)), Vector3.ZERO, 1.0)
		attacker.velocity *= 0.93
	if not _holding.is_empty():
		return
	for runner: Footballer in _runs.keys():
		if not is_instance_valid(runner) or not runner.is_free():
			continue
		for q: Footballer in opponents(runner.team):
			if not q.is_free() or q.is_keeper():
				continue
			var d: float = q.global_position.distance_to(runner.global_position)
			var behind: bool = (runner.global_position - q.global_position).dot(Vector3(runner.team.attack, 0, 0)) > 0.0
			if d < 1.8 and behind and _rng.randf() < HOLDING_CHANCE * lerpf(0.5, 1.6, q.aggression) * delta * 10.0:
				_holding[q] = {"victim": runner, "left": 0.9}
				stats.holds += 1
				var goes_down := _rng.randf() < 0.45
				m.laws.foul(q, runner, &"holding", Laws.Severity.CARELESS, runner.global_position, {"holding": true})
				if goes_down:
					runner.fall(Vector3(-runner.team.attack, 0, 0), 1.8)
				return


# --- separation -------------------------------------------------------------------------

## Keeps bodies out of each other, and out of the referee. Cheap: a push away from
## anybody within a metre.
func _separate() -> void:
	var all := players()
	var ref: Node3D = m.referee
	for p: Footballer in all:
		var push := Vector3.ZERO
		for q: Footballer in all:
			if q == p:
				continue
			var d: Vector3 = p.global_position - q.global_position
			d.y = 0.0
			var l := d.length()
			if l < 1.0 and l > 0.001:
				push += d / l * (1.0 - l) * 4.0
		if ref != null:
			var d: Vector3 = p.global_position - ref.global_position
			d.y = 0.0
			var l := d.length()
			if l < 1.6 and l > 0.001:
				push += d / l * (1.6 - l) * 5.0
		p.separation = push


# --- set pieces -------------------------------------------------------------------------
#
# A restart is described by the match as {type, team, spot}: the kind of restart, the
# Team that takes it, and where. The AI walks everybody to where they belong for it and
# the taker to the ball, and reports `set_piece_ready` once they are there. Whether it
# may then be taken — some need the whistle — is the match's business.

func begin_set_piece(restart: Dictionary) -> void:
	set_piece = restart
	set_piece_ready = false
	_set_piece_wait = 0.0
	carrier = null
	_receiver = null
	_pending = {}
	_runs.clear()
	for key: Footballer in _holding.keys():
		(key as Footballer).arms.release()
	_holding.clear()
	var team: Team = restart.team
	set_piece["taker"] = _choose_taker(restart)
	possession = team.index


func _choose_taker(restart: Dictionary) -> Footballer:
	var team: Team = restart.team
	var spot: Vector3 = restart.spot
	var pool := team.on_field().filter(func(p): return p.state != Footballer.State.FALLEN)
	match restart.type:
		&"goal_kick":
			var gk: Footballer = team.keeper()
			if gk != null:
				return gk
		&"penalty":
			pool = pool.filter(func(p): return not p.is_keeper())
			pool.sort_custom(func(a, b): return a.skill > b.skill)
			return pool[0]
		&"kick_off":
			pool = pool.filter(func(p): return p.role == Footballer.Role.FW)
	pool = pool.filter(func(p): return not p.is_keeper() or restart.type == &"free_kick" and spot.distance_to(spec().goal_centre(-team.attack)) < 20.0)
	pool.sort_custom(func(a, b): return a.global_position.distance_to(spot) < b.global_position.distance_to(spot))
	return pool[0] if not pool.is_empty() else team.on_field()[0]


## Walks everybody into position for the restart. Returns true once they are there.
func step_set_piece(delta: float) -> bool:
	if set_piece.is_empty():
		return false
	_set_piece_wait += delta
	var restart := set_piece
	var team: Team = restart.team
	var spot: Vector3 = restart.spot
	var taker: Footballer = restart.taker
	var type: StringName = restart.type
	var attack_goal := spec().goal_centre(team.attack)
	var own_goal := spec().goal_centre(-team.attack)
	var all_there := true
	for p: Footballer in players():
		if not p.can_move():
			continue
		var target := _shape_target(p)
		var ours: bool = p.team == team
		if p == taker:
			target = _taker_spot(type, spot, team)
			p.face_point = attack_goal if type != &"throw_in" else Vector3(spot.x, 0, 0)
		elif type == &"kick_off":
			var slot: Dictionary = Team.FORMATION_442[p.slot]
			target = p.team.to_world(minf(slot.u * 0.9, 0.46), slot.v, spec())
			if not ours:
				# Outside the centre circle until the ball is in play (Law 8).
				var from_centre := Vector3(target.x, 0, target.z)
				if from_centre.length() < PitchSpec.CENTRE_CIRCLE + 1.0:
					target = from_centre.normalized() * (PitchSpec.CENTRE_CIRCLE + 1.5) if from_centre.length() > 0.1 else Vector3(-p.team.attack * 10.0, 0, 0)
			elif p.role == Footballer.Role.FW:
				target = Vector3(-p.team.attack * 1.5, 0, 3.0 if p.number == 10 else -3.0)
		elif type == &"penalty":
			if p.is_keeper() and not ours:
				target = Vector3(spec().goal_line_x(team.attack) - 0.1 * team.attack, 0, 0)
				p.face_point = spot
			else:
				# Outside the area and the arc, behind the ball.
				var edge_x := spec().goal_line_x(team.attack) - (PitchSpec.PENALTY_AREA_DEPTH + 3.0) * team.attack
				target = Vector3(edge_x, 0, clampf(target.z, -18.0, 18.0))
		elif type == &"corner":
			target = _corner_target(p, ours, team, spot)
		elif type == &"goal_kick":
			if not ours:
				# Outside the penalty area until the ball is in play (Law 16).
				var box_edge := spec().goal_line_x(-team.attack) + (PitchSpec.PENALTY_AREA_DEPTH + 2.0) * team.attack
				if (target.x - box_edge) * team.attack < 0.0:
					target.x = box_edge
		elif type in [&"free_kick", &"indirect_free_kick"]:
			if not ours:
				var to_goal := own_goal_for(p) - spot
				var d := spot.distance_to(own_goal_for(p))
				if d < 32.0 and _is_wall_member(p, restart):
					target = spot + to_goal.normalized() * PitchSpec.TEN_YARDS + _wall_offset(p, restart, to_goal)
				elif target.distance_to(spot) < PitchSpec.TEN_YARDS:
					target = spot + (target - spot).normalized() * (PitchSpec.TEN_YARDS + 0.5)
		elif type == &"throw_in":
			if not ours and target.distance_to(spot) < 2.5:
				target = spot + (target - spot).normalized() * 3.0
		elif type == &"dropped_ball":
			if p != taker and target.distance_to(spot) < 4.0:
				target = spot + (target - spot).normalized() * 4.5
		if p.is_keeper() and type != &"penalty" and p != taker:
			target = Vector3(spec().goal_line_x(-p.team.attack) + 1.0 * p.team.attack, 0, 0)
		p.goal = target
		p.hurry = 0.9 if p == taker else 0.6
		if p != taker:
			p.face_point = spot
		var need := 1.2 if p == taker else 4.0
		if p.global_position.distance_to(target) > need and _set_piece_wait < 9.0:
			all_there = false
	var b := ball()
	b.held = true
	b.global_position = Vector3(spot.x, PitchSpec.BALL_RADIUS, spot.z)
	if type == &"throw_in" and taker.global_position.distance_to(spot) < 1.5:
		b.carrier = taker
		b.carrier_offset = Vector3(0, 2.1, 0.1)
	set_piece_ready = all_there and _set_piece_wait > 1.2
	return set_piece_ready


func own_goal_for(p: Footballer) -> Vector3:
	return spec().goal_centre(-p.team.attack)


func _taker_spot(type: StringName, spot: Vector3, team: Team) -> Vector3:
	match type:
		&"throw_in":
			# Behind the line, facing in.
			return Vector3(spot.x, 0, spot.z + signf(spot.z) * 0.4)
		&"corner", &"penalty", &"free_kick", &"indirect_free_kick", &"goal_kick", &"kick_off":
			return spot - Vector3(team.attack * 1.2, 0, 0)
	return spot


func _is_wall_member(p: Footballer, restart: Dictionary) -> bool:
	var defenders: Array = opponents(restart.team).filter(func(q): return not q.is_keeper())
	defenders.sort_custom(func(a, b): return a.global_position.distance_to(restart.spot) < b.global_position.distance_to(restart.spot))
	var size := 4 if (restart.spot as Vector3).distance_to(own_goal_for(p)) < 24.0 else 2
	return defenders.slice(0, size).has(p)


func _wall_offset(p: Footballer, restart: Dictionary, to_goal: Vector3) -> Vector3:
	var across := Vector3.UP.cross(to_goal.normalized())
	var slot := int(p.number % 4) - 1.5
	return across * slot * 0.6


func _corner_target(p: Footballer, ours: bool, team: Team, spot: Vector3) -> Vector3:
	var goal_x := spec().goal_line_x(team.attack)
	var near: float = signf(spot.z)
	if ours:
		if p.role in [Footballer.Role.FW, Footballer.Role.DF] and p.number in [9, 10, 5, 6]:
			var zs := {9: 1.5, 10: -2.5, 5: 4.0, 6: -0.5}
			return Vector3(goal_x - (7.0 + (p.number % 3) * 2.5) * team.attack, 0, zs[p.number] * near)
		return _shape_target(p)
	# Defending the corner: most of them in the box, marking space.
	if p.role in [Footballer.Role.DF, Footballer.Role.MF] and p.number in [2, 3, 5, 6, 4, 8]:
		var zs2 := {2: 3.5, 3: -3.5, 5: 1.0, 6: -1.5, 4: 5.5, 8: -5.0}
		return Vector3(goal_x - (5.5 + (p.number % 2) * 2.0) * team.attack, 0, zs2[p.number] * near)
	return _shape_target(p)


## Takes the restart. Called by the match once it may be taken.
func take_set_piece() -> void:
	var restart := set_piece
	var taker: Footballer = restart.taker
	var team: Team = restart.team
	var b := ball()
	b.held = false
	b.carrier = null
	b.place(restart.spot)
	carrier = taker
	var type: StringName = restart.type
	var velocity: Vector3
	var kind := &"pass"
	var goal := spec().goal_centre(team.attack)
	match type:
		&"penalty":
			var side := _rng.randf_range(-3.0, 3.0)
			var height := _rng.randf_range(0.2, 1.8)
			var target := goal + Vector3(0, height, side)
			var from := b.global_position
			var speed := _rng.randf_range(18.0, 25.0)
			var flat := target - from
			var t := Vector2(flat.x, flat.z).length() / speed
			velocity = Vector3(flat.x, 0, flat.z).normalized() * speed + Vector3.UP * ((target.y - from.y) / t + 0.5 * Ball.GRAVITY * t)
			kind = &"shot"
		&"corner":
			var in_box := goal - Vector3(team.attack * _rng.randf_range(6.0, 11.0), 0, _rng.randf_range(-4.0, 4.0))
			velocity = _pass_velocity(b.global_position, in_box, true)
			kind = &"corner"
		&"throw_in":
			var mates := teammates(taker)
			mates.sort_custom(func(a, c): return a.global_position.distance_to(taker.global_position) < c.global_position.distance_to(taker.global_position))
			var to: Footballer = mates[0] if not mates.is_empty() else taker
			velocity = _pass_velocity(b.global_position, to.global_position, false) * 0.8 + Vector3.UP * 4.0
			b.global_position.y = 2.0
			_receiver = to
			_receive_point = to.global_position
			_receiver_left = 3.0
			kind = &"throw_in"
		&"goal_kick":
			var target := team.to_world(_rng.randf_range(0.5, 0.7), _rng.randf_range(-0.6, 0.6), spec())
			if _rng.randf() < 0.4:
				var backs := teammates(taker).filter(func(q): return q.role == Footballer.Role.DF)
				if not backs.is_empty():
					target = (backs[_rng.randi() % backs.size()] as Footballer).global_position
					velocity = _pass_velocity(b.global_position, target, false)
			if velocity == Vector3.ZERO:
				velocity = _pass_velocity(b.global_position, target, true)
			kind = &"goal_kick"
		&"kick_off":
			var back := teammates(taker).filter(func(q): return q.role == Footballer.Role.MF)
			var target: Vector3 = (back[0] as Footballer).global_position if not back.is_empty() else Vector3(-team.attack * 8.0, 0, 0)
			velocity = _pass_velocity(b.global_position, target, false)
			kind = &"kick_off"
		&"free_kick", &"indirect_free_kick":
			var d := b.global_position.distance_to(goal)
			if type == &"free_kick" and d < 28.0 and absf(b.global_position.z) < 16.0 and _rng.randf() < 0.7:
				var target := goal + Vector3(0, _rng.randf_range(1.2, 2.2), _rng.randf_range(-3.2, 3.2))
				var from := b.global_position
				var speed := _rng.randf_range(20.0, 26.0)
				var flat := target - from
				var t := Vector2(flat.x, flat.z).length() / speed
				velocity = Vector3(flat.x, 0, flat.z).normalized() * speed + Vector3.UP * ((target.y - from.y) / t + 0.5 * Ball.GRAVITY * t + 1.5)
				kind = &"shot"
			else:
				var option := _best_pass()
				if option.is_empty():
					velocity = _pass_velocity(b.global_position, b.global_position + Vector3(team.attack * 20.0, 0, 0), true)
				else:
					velocity = _pass_velocity(b.global_position, option.at, option.distance > 25.0)
					_receiver = option.to
					_receive_point = option.at
					_receiver_left = 3.0
			kind = kind if kind == &"shot" else &"free_kick"
		&"dropped_ball":
			velocity = Vector3.ZERO
			kind = &"dropped_ball"
	taker.one_shot("throw_in" if type == &"throw_in" else "kick", 0.5)
	b.kick(velocity, taker, kind)
	m.on_played(taker, kind)
	if velocity.length() > 1.0:
		m.sound_kick(b.global_position, velocity.length())
	carrier = null if type != &"dropped_ball" else taker
	set_piece = {}
	possession = team.index
