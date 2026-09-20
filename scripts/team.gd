class_name Team
extends RefCounted

## One side: its name, its kit, its shape and its eleven.

var name := "Home"
var short := "HOM"
var shirt := Color(0.75, 0.15, 0.15)
var shorts := Color(0.95, 0.95, 0.95)
var keeper_shirt := Color(0.15, 0.75, 0.35)
## Socks, and the second colour used for the collar, the cuffs, the sock turnover and the
## flash on the boots.
var socks := Color(0.75, 0.15, 0.15)
var trim := Color(0.95, 0.95, 0.95)
## 0 or 1 — which side of the match this is. Home is 0.
var index := 0
## Which way this team is attacking right now: +1 towards +X, -1 towards -X. Swaps at
## half time (Law 8: teams change ends for the second half).
var attack := 1

## Character, 0 to 1. How often they tackle, how hard, and how often they go down
## without being touched. Set per team so a match has a personality.
var aggression := 0.5
var discipline := 0.5
var honesty := 0.7

var players: Array = []       # every Footballer who started or came on
var bench: Array = []         # names of substitutes still available
var subs_used := 0
const MAX_SUBS := 5

var goals := 0


## Players still on the field: not sent off, not substituted.
func on_field() -> Array:
	return players.filter(func(p): return p.on_pitch)


func keeper() -> Node:
	for p in players:
		if p.on_pitch and p.role == Footballer.Role.GK:
			return p
	return null


## The x of the goal this team defends.
func own_goal_x(spec: PitchSpec) -> float:
	return spec.goal_line_x(-attack)


## 4-4-2, in "team space": u runs 0 at their own goal line to 1 at the opponent's, v
## runs -1 to 1 across the pitch from their right to their left when attacking. The
## roles and numbers are the traditional ones for the shape.
const FORMATION_442 := [
	{"role": 0, "num": 1, "u": 0.02, "v": 0.0},
	{"role": 1, "num": 2, "u": 0.22, "v": -0.62},
	{"role": 1, "num": 5, "u": 0.19, "v": -0.22},
	{"role": 1, "num": 6, "u": 0.19, "v": 0.22},
	{"role": 1, "num": 3, "u": 0.22, "v": 0.62},
	{"role": 2, "num": 7, "u": 0.45, "v": -0.66},
	{"role": 2, "num": 4, "u": 0.41, "v": -0.2},
	{"role": 2, "num": 8, "u": 0.41, "v": 0.2},
	{"role": 2, "num": 11, "u": 0.45, "v": 0.66},
	{"role": 3, "num": 9, "u": 0.62, "v": -0.16},
	{"role": 3, "num": 10, "u": 0.6, "v": 0.18},
]


## Team space to the world, for the half this team is attacking.
func to_world(u: float, v: float, spec: PitchSpec) -> Vector3:
	var x := (u - 0.5) * spec.length * attack
	# v is to the team's right-when-attacking; the right of a team attacking +X is -Z.
	var z := v * spec.half_width() * -attack
	return Vector3(x, 0.0, z)


func to_team_space(point: Vector3, spec: PitchSpec) -> Vector2:
	var u := point.x * attack / spec.length + 0.5
	var v := -point.z * attack / spec.half_width()
	return Vector2(u, v)
