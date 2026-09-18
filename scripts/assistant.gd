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
## At the village ground they are **club assistants** — a volunteer from each side in a
## tracksuit, who only flag the ball out of play (never offside, which is the referee's
## alone at that level) and are not neutral: on a close one they tend to see it their own
## team's way.

const SIGHT_ERROR := 0.018
const BASE_ERROR := 0.10
const FLAG_HOLD := 4.0

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
	quad.size = Vector2(38.0, 30.0)
	cloth.mesh = quad
	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = Color(1.0, 0.85, 0.05) if kind == "neutral" else Color(0.95, 0.3, 0.1)
	cloth_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.material_override = cloth_mat
	cloth.position = Vector3(19.0, 38.0, 0)
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
	if flag_up:
		_flag_time += delta
		if _flag_time > FLAG_HOLD and m.phase == Match.Phase.LIVE:
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
	if kind != "neutral":
		return
	_perceived.clear()
	_perceived_team = team
	for p: Footballer in positions:
		if signf(p.global_position.x) != side:
			continue
		var out_of_line := absf(p.global_position.x - body.global_position.x)
		var sigma := BASE_ERROR + out_of_line * SIGHT_ERROR
		_perceived[p] = positions[p] + _rng.randfn(0.0, sigma)
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


func _raise() -> void:
	body.arms.set_right(body.arms.to_model(Vector3.UP), Vector3.ZERO, 1.0)
	flag_up = true
	_flag_time = 0.0


func lower() -> void:
	flag_up = false
	body.arms.release_right()
