class_name Assistant
extends Node3D

## An assistant referee on a touchline, with a flag.
##
## Two of them, on opposite touchlines, each responsible for one half — the diagonal
## system. Each keeps level with the second-last defender in his half, which is the only
## place offside can be judged from, and flags for offside and for the ball leaving the
## field. The referee decides; the flag is advice.
##
## They are good but not perfect, and the imperfection is modelled on what makes it hard
## for a real one: a player a long way from where he is standing, and a margin of a few
## centimetres. `SIGHT_ERROR` is how many metres wrong his judgement of the line can be,
## per metre he is out of line with it.
##
## They also flag fouls they are better placed to see than the referee (Law 6): anything
## within `FOUL_SIGHT` metres of them, more surely the closer and the worse it is. The flag
## goes up and waggles; if the referee whistles, the assistant points the way the free
## kick goes. Luqman asked for both on 2026-09-18 — "two linesmen to help the player detect
## offside, foul near them".
##
## At the village ground they are **club assistants** — a volunteer from each side. They
## flag offside and fouls too (they used to flag only the ball out, until Luqman asked for
## help with offside at every level), but they are less sharp than a neutral assistant and
## not neutral: on a close one they tend to see it their own team's way.

const SIGHT_ERROR := 0.018
const BASE_ERROR := 0.10
const FLAG_HOLD := 4.0
## A club linesman judges the line worse than a qualified assistant.
const CLUB_SIGHT_ERROR := 0.03
const CLUB_BASE_ERROR := 0.25
## How far away an assistant can judge a foul, and how long he takes to be sure.
## Measured 2026-09-18: fouls mostly happen in the middle, 30-55 m from either assistant;
## at 22 m they never flagged one. 34 m covers their own side of the pitch.
const FOUL_SIGHT := 34.0
const FOUL_REACTION := 0.7

var m
var side := 1               # +1 covers the east half from the +Z touchline, -1 the west from -Z
var kind := "neutral"       # neutral | club
var club: Team = null       # for a club assistant, whose he is
var body: Footballer
var flag_up := false
var _flag_time := 0.0
var _perceived := {}        # Footballer -> perceived offside margin at the last moment of play
var _perceived_team: Team = null
var _flag_node: Node3D
var _rng := RandomNumberGenerator.new()
var _official_team: Team


func setup(match_node, which_side: int, assistant_kind: String) -> void:
	m = match_node
	side = which_side
	kind = assistant_kind
	_rng.randomize()


func _ready() -> void:
	_official_team = Team.new()
	_official_team.name = "Officials"
	if kind == "club":
		club = m.teams[0] if side < 0 else m.teams[1]
		_official_team.shirt = club.shirt.darkened(0.35)
		_official_team.shorts = Color(0.15, 0.15, 0.18)
	else:
		_official_team.shirt = Referee.kit_colour(m.teams)
		_official_team.shorts = Color(0.06, 0.06, 0.07)
	_official_team.keeper_shirt = _official_team.shirt
	body = Footballer.new()
	body.setup(_official_team, 0, Footballer.Role.MF, "Assistant")
	body.official = true
	add_child(body)
	body.pace = 7.0
	body.global_position = Vector3(side * m.spec.half_length() * 0.4, 0, _line_z())
	body.heading = Vector3(0, 0, -side)
	# The flag: a stick and a cloth in the right hand.
	var hand := BoneAttachment3D.new()
	hand.bone_name = "RightHand"
	body.skeleton.add_child(hand)
	_flag_node = Node3D.new()
	hand.add_child(_flag_node)
	var stick := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.8
	cyl.bottom_radius = 0.8
	cyl.height = 55.0
	stick.mesh = cyl
	stick.position = Vector3(0, 22.0, 0)
	_flag_node.add_child(stick)
	var cloth := MeshInstance3D.new()
	var quad := QuadMesh.new()
	# A little larger than life, and bright: at thirty metres a real one is a few pixels.
	quad.size = Vector2(52.0, 40.0)
	cloth.mesh = quad
	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = Color(1.0, 0.85, 0.05) if kind == "neutral" else Color(0.95, 0.3, 0.1)
	cloth_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth_mat.emission_enabled = true
	cloth_mat.emission = cloth_mat.albedo_color
	cloth_mat.emission_energy_multiplier = 0.8
	cloth.material_override = cloth_mat
	cloth.position = Vector3(26.0, 36.0, 0)
	_flag_node.add_child(cloth)
	# Hide the shirt number: officials have none.
	for label in body.find_children("*", "Label3D", true, false):
		label.visible = false


func _line_z() -> float:
	return side * (m.spec.half_width() + 1.2)


func step(delta: float) -> void:
	if body == null:
		return
	# Keep level with the second-last defender in my half, or the ball if it is nearer the
	# goal line. Stay in my half.
	var target_x := _second_last_x()
	var ball_x: float = m.ball.global_position.x
	if ball_x * side > target_x * side:
		target_x = ball_x
	target_x = clampf(target_x * side, 0.0, m.spec.half_length()) * side
	body.goal = Vector3(target_x, 0, _line_z())
	body.hurry = 0.95
	body.face_point = Vector3(target_x, 0, 0)
	body.step(delta)
	_raise_foul_waggle(delta)
	if flag_up:
		_flag_time += delta
		if _flag_time > FLAG_HOLD * (1.5 if _waggle else 1.0) and m.phase == Match.Phase.LIVE:
			# Not acknowledged: he lowers it and the referee has, in effect, waved it down.
			if m.flag.get("assistant") == self:
				m.wave_flag(true)
			lower()


## The second-last defender of whichever team defends my half.
func _second_last_x() -> float:
	var defending: Team = m.teams[0] if m.teams[0].attack == -side else m.teams[1]
	var xs: Array = []
	for p: Footballer in defending.on_field():
		xs.append(p.global_position.x * side)
	xs.sort()
	xs.reverse()
	return (xs[1] if xs.size() >= 2 else m.spec.half_length() * 0.5) * side


## A moment of play: note who looks offside to me, with my own error on it.
func on_offside_moment(team: Team, positions: Dictionary) -> void:
	_perceived.clear()
	_perceived_team = team
	for p: Footballer in positions:
		if signf(p.global_position.x) != side:
			continue
		var out_of_line := absf(p.global_position.x - body.global_position.x)
		var sigma := BASE_ERROR + out_of_line * SIGHT_ERROR
		var bias := 0.0
		if kind == "club":
			sigma = CLUB_BASE_ERROR + out_of_line * CLUB_SIGHT_ERROR
			# His own side's forwards look onside to him.
			bias = -0.3 if team == club else 0.15
		_perceived[p] = positions[p] + bias + _rng.randfn(0.0, sigma)
	if not m.ball.touched.is_connected(_on_touch):
		m.ball.touched.connect(_on_touch)


func _on_touch(by: Node, kind_of_touch: StringName) -> void:
	if not by is Footballer or m.phase != Match.Phase.LIVE:
		return
	var p: Footballer = by
	if _perceived_team == null:
		return
	if p.team != _perceived_team:
		if kind_of_touch not in [&"block", &"save", &"handball"]:
			_perceived.clear()
			_perceived_team = null
		return
	if _perceived.has(p) and _perceived[p] > 0.0:
		var inc: Incident = null
		if not m.laws.incidents.is_empty():
			var last: Incident = m.laws.incidents.back()
			if last.kind == &"offside" and last.offender == p and absf(last.time - m.clock) < 0.05:
				inc = last
		_raise()
		m.raise_flag(self, &"offside", p, inc)
		_perceived.clear()
		_perceived_team = null
	else:
		_perceived.erase(p)


## The ball has gone out: signal which way. A neutral assistant is nearly always right
## about who touched it last; a club one sees it his own team's way when it is close.
func on_out(incident: Incident) -> void:
	if signf(incident.position.x) != side and kind == "neutral":
		return
	if kind == "club" and signf(incident.position.x) != side:
		return
	var team: Team = incident.expected_team
	if team == null:
		return
	var wrong := _rng.randf() < 0.04
	if kind == "club" and team != club and _rng.randf() < 0.35:
		wrong = true
	if wrong and incident.kind == &"out":
		team = m.teams[1] if team == m.teams[0] else m.teams[0]
	incident.details["assistant_said"] = team
	_point_for(team, incident)


func _point_for(team: Team, incident: Incident) -> void:
	var dir := Vector3(team.attack, 0.6, 0)
	if incident.expected_restart in [&"corner", &"goal_kick"]:
		var gl: bool = incident.details.get("goal_line", false)
		if gl and incident.expected_restart == &"corner" and incident.expected_team == team:
			dir = Vector3(0, -0.3, 0).lerp(Vector3(signf(incident.position.x), 0, signf(incident.position.z)), 0.8)
		elif gl:
			dir = Vector3(0, 0.1, -side)  # towards the goal area: a goal kick
	body.arms.set_right(body.arms.to_model(dir.normalized()), Vector3.ZERO, 1.0)
	flag_up = true
	_flag_time = 0.0


## A foul has happened (the truth, from Laws). Decide whether I saw it, and if so flag it a
## moment later — unless the referee has already whistled or played advantage.
func on_incident(inc: Incident) -> void:
	if inc.kind not in [&"foul", &"holding", &"handball"] or inc.offender == null:
		return
	var d := body.global_position.distance_to(inc.position)
	if d > FOUL_SIGHT or signf(inc.position.x) != side and absf(inc.position.x) > 6.0:
		return
	var chance := clampf(1.0 - d / FOUL_SIGHT, 0.0, 1.0) * 0.9 + 0.25 * float(inc.severity) / 3.0
	if kind == "club":
		chance *= 0.7
		if inc.offender.team == club:
			chance *= 0.5
	if _rng.randf() > chance:
		return
	flag_foul(inc)


## Flags a foul, after the moment it takes to be sure. Called directly by a drill that
## needs the assistant to see it.
func flag_foul(inc: Incident) -> void:
	await get_tree().create_timer(FOUL_REACTION).timeout
	if not is_instance_valid(self) or m.phase != Match.Phase.LIVE or inc.whistled or inc.advantage or not m.flag.is_empty():
		return
	_raise(true)
	m.raise_flag(self, &"foul", inc.offender, inc)


## After the referee accepts a foul flag: the flag points the way the free kick goes.
func point_restart(to: Team) -> void:
	_waggle = false
	body.arms.set_right(body.arms.to_model(Vector3(to.attack, 0.5, 0).normalized()), Vector3.ZERO, 1.0)
	flag_up = true
	_flag_time = 0.0


var _waggle := false
var _waggle_t := 0.0


func _raise_foul_waggle(delta: float) -> void:
	if not _waggle:
		return
	# A foul is signalled with the flag up and waggled, so it is not mistaken for offside.
	_waggle_t += delta * 9.0
	var dir := Vector3(sin(_waggle_t) * 0.35, 1.0, 0).normalized()
	body.arms.set_right(body.arms.to_model(dir), Vector3.ZERO, 1.0)


func _raise(foul := false) -> void:
	_waggle = foul
	body.arms.set_right(body.arms.to_model(Vector3.UP), Vector3.ZERO, 1.0)
	flag_up = true
	_flag_time = 0.0


func lower() -> void:
	flag_up = false
	_waggle = false
	body.arms.release_right()
