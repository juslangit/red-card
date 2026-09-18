class_name PitchSpec
extends RefCounted

## The field of play, from Law 1 of the IFAB Laws of the Game.
##
## One source of truth, the same rule Referee For Fun lives by: the numbers that paint
## the lines are the numbers that judge the ball. Nothing anywhere else may hard-code a
## pitch dimension, because a line drawn in one place and judged in another is how a
## ball that looks out gets given as in.
##
## Axes, used everywhere in the game:
##
##     +X   along the length, towards the east goal
##     +Z   across the width, towards the far touchline (the main stand is at -Z)
##     +Y   up
##
## The centre spot is the origin. Lines are 12 cm wide (the maximum Law 1 allows) and,
## as the Law says, the lines belong to the areas they bound — a ball on the line is in.

## Length and width vary by venue. Law 1 allows 90–120 m by 45–90 m; international
## matches are 100–110 by 64–75, and nearly every professional ground is 105 x 68.
var length := 105.0
var width := 68.0

const LINE_WIDTH := 0.12

## Fixed by Law 1 whatever the size of the pitch. Metres — the Law is written in yards,
## and these are its own metric figures.
const GOAL_WIDTH := 7.32          # between the inside edges of the posts
const GOAL_HEIGHT := 2.44         # to the underside of the crossbar
const POST_WIDTH := 0.12          # same as the line: posts and line are the same width
const GOAL_AREA_DEPTH := 5.5
const GOAL_AREA_REACH := 5.5      # beyond each post
const PENALTY_AREA_DEPTH := 16.5
const PENALTY_AREA_REACH := 16.5  # beyond each post
const PENALTY_SPOT := 11.0        # from the goal line
const CENTRE_CIRCLE := 9.15
const PENALTY_ARC := 9.15         # from the penalty spot
const CORNER_ARC := 1.0
const GOAL_DEPTH := 2.0           # how far the net runs back; not in the Law

## The ball: size 5, 68–70 cm around, so 11 cm in radius.
const BALL_RADIUS := 0.11

## Distance opponents must keep at free kicks, corners and kick-offs.
const TEN_YARDS := 9.15


static func of_size(pitch_length: float, pitch_width: float) -> PitchSpec:
	var spec := PitchSpec.new()
	spec.length = pitch_length
	spec.width = pitch_width
	return spec


func half_length() -> float:
	return length * 0.5


func half_width() -> float:
	return width * 0.5


## The x of a goal line, for the end a team is attacking (+1 east, -1 west).
func goal_line_x(end: int) -> float:
	return half_length() * end


## The centre of a goal mouth on the goal line.
func goal_centre(end: int) -> Vector3:
	return Vector3(goal_line_x(end), 0.0, 0.0)


func penalty_spot(end: int) -> Vector3:
	return Vector3(goal_line_x(end) - PENALTY_SPOT * end, 0.0, 0.0)


# --- judging the ball -------------------------------------------------------------------
#
# Law 9: the ball is out of play when it has *wholly* passed over the goal line or the
# touchline, on the ground or in the air. The line is part of the field, so the ball is
# still in while any part of it is over any part of the line — its centre has to be a
# full radius past the outer edge of the paint before it is out.
#
# The painted line is centred on the boundary figure, and the boundary is the *outer*
# edge of the line. So the field runs to half_length and half_width exactly, and the
# paint lies inside that.

## How far past the touchline the ball is, in metres, measured from the outer edge of the
## line to the near side of the ball. Positive means wholly out.
func past_touchline(ball: Vector3) -> float:
	return absf(ball.z) - half_width() - BALL_RADIUS


## The same for the goal line.
func past_goal_line(ball: Vector3) -> float:
	return absf(ball.x) - half_length() - BALL_RADIUS


func is_over_touchline(ball: Vector3) -> bool:
	return past_touchline(ball) > 0.0


func is_over_goal_line(ball: Vector3) -> bool:
	return past_goal_line(ball) > 0.0


## Law 10: a goal is scored when the whole of the ball passes over the goal line, between
## the goalposts and under the crossbar. Between the posts means inside their inner edges.
func is_in_goal_mouth(ball: Vector3) -> bool:
	return absf(ball.z) < GOAL_WIDTH * 0.5 - BALL_RADIUS * 0.2 \
		and ball.y < GOAL_HEIGHT - BALL_RADIUS * 0.2


func is_in_play(ball: Vector3) -> bool:
	return not is_over_touchline(ball) and not is_over_goal_line(ball)


# --- areas ------------------------------------------------------------------------------

## Whether a point on the ground is inside the penalty area at an end. The lines are part
## of the area, so the outer edge of the paint is the boundary.
func in_penalty_area(point: Vector3, end: int) -> bool:
	var from_line := (goal_line_x(end) - point.x) * end
	var reach := GOAL_WIDTH * 0.5 + PENALTY_AREA_REACH
	return from_line >= -0.01 and from_line <= PENALTY_AREA_DEPTH and absf(point.z) <= reach


func in_goal_area(point: Vector3, end: int) -> bool:
	var from_line := (goal_line_x(end) - point.x) * end
	var reach := GOAL_WIDTH * 0.5 + GOAL_AREA_REACH
	return from_line >= -0.01 and from_line <= GOAL_AREA_DEPTH and absf(point.z) <= reach


## Which half a point is in: +1 east, -1 west. The halfway line belongs to neither half
## for offside (Law 11: a player on the halfway line is not in the opponents' half).
func half_of(point: Vector3) -> int:
	return 1 if point.x > 0.0 else -1


## Distance from a point to the nearer goal post's inside edge, which is what a goal
## kick, a corner and a shooting angle all care about.
func distance_to_goal(point: Vector3, end: int) -> float:
	var goal := goal_centre(end)
	var dz := maxf(absf(point.z) - GOAL_WIDTH * 0.5, 0.0)
	return Vector2(goal.x - point.x, dz).length()


## Nearest corner arc to a point, for a corner kick: the corner on the side the ball went
## out, at the end it went out.
func corner_for(point: Vector3, end: int) -> Vector3:
	var side := 1.0 if point.z > 0.0 else -1.0
	var x := goal_line_x(end) - 0.6 * end
	return Vector3(x, 0.0, (half_width() - 0.6) * side)


## Where a goal kick is taken: anywhere in the goal area (Law 16). The AI puts it on the
## edge of the goal area on the side the ball went out.
func goal_kick_spot(point: Vector3, end: int) -> Vector3:
	var side := 1.0 if point.z > 0.0 else -1.0
	return Vector3(goal_line_x(end) - GOAL_AREA_DEPTH * end, 0.0, 4.0 * side)


## Where a throw-in is taken: the point where the ball crossed the touchline.
func throw_in_spot(crossed: Vector3) -> Vector3:
	var side := 1.0 if crossed.z > 0.0 else -1.0
	var x := clampf(crossed.x, -half_length() + 1.0, half_length() - 1.0)
	return Vector3(x, 0.0, half_width() * side)


## Clamps a point to the field, for anything that must not end up behind a goal.
func clamp_to_field(point: Vector3, margin := 0.0) -> Vector3:
	return Vector3(
		clampf(point.x, -half_length() + margin, half_length() - margin),
		point.y,
		clampf(point.z, -half_width() + margin, half_width() - margin))
