class_name PitchMap
extends Control

## Where you were when each decision happened, drawn on the pitch.
##
## This is the one page of a real assessor's report the game was missing. The numbers were
## already being collected — every incident knows how far away the referee was, how much
## of it he could see, and now where he was standing; and the assessor drops a point of the
## referee's position onto a trail once a second of open play. All that was missing was
## somewhere to look at them.
##
## It draws three things over a plan of the pitch:
##
##   the trail      a faint mark for every second of open play, so the shape of the match
##                  shows through: a referee who kept the diagonal leaves a diagonal, one
##                  who followed the ball everywhere leaves a smear down the middle.
##   the decisions  one dot per judged incident, where the referee was standing, in the
##                  colour of the verdict — green for right, red for wrong.
##   the sightline  a line from that dot to where the thing actually happened, thin and
##                  pale when he could see it, broken up when his view was blocked.
##
## Nothing here reveals anything: by the time this is on screen the match is over and the
## report has already said what was right and wrong.

const MARGIN := 18.0

var spec: PitchSpec
var trail: PackedVector2Array = PackedVector2Array()
## One entry per judged decision: {at: Vector2, incident: Vector2, right: bool,
## neutral: bool, view: float, minute: int}
var decisions: Array = []


func setup(pitch: PitchSpec, walked: PackedVector2Array, report_lines: Array) -> void:
	spec = pitch
	trail = walked
	decisions.clear()
	for line in report_lines:
		var inc: Incident = line.get("incident")
		if inc == null or inc.ref_at == Vector3.ZERO:
			continue
		var points: float = line.get("points", 0.0)
		decisions.append({
			"at": Vector2(inc.ref_at.x, inc.ref_at.z),
			"incident": Vector2(inc.position.x, inc.position.z),
			"right": points > 0.0,
			"neutral": is_equal_approx(points, 0.0),
			"view": inc.ref_view,
			"minute": inc.minute,
		})
	custom_minimum_size = Vector2(0, 520)
	queue_redraw()


## The pitch is drawn to fit whatever room it is given, keeping its shape.
func _place(point: Vector2) -> Vector2:
	var box := size - Vector2(MARGIN, MARGIN) * 2.0
	var scale := minf(box.x / spec.length, box.y / spec.width)
	return size * 0.5 + point * scale


func _metres(m: float) -> float:
	var box := size - Vector2(MARGIN, MARGIN) * 2.0
	return m * minf(box.x / spec.length, box.y / spec.width)


func _draw() -> void:
	if spec == null:
		return
	var grass := Color(0.16, 0.26, 0.17)
	var chalk := Color(0.86, 0.92, 0.86, 0.5)
	var half_length := spec.length * 0.5
	var half_width := spec.width * 0.5
	var top_left := _place(Vector2(-half_length, -half_width))
	var bottom_right := _place(Vector2(half_length, half_width))
	draw_rect(Rect2(top_left, bottom_right - top_left), grass, true)
	draw_rect(Rect2(top_left, bottom_right - top_left), chalk, false, 2.0)
	# Halfway line, centre circle, both penalty areas and both six-yard boxes.
	draw_line(_place(Vector2(0, -half_width)), _place(Vector2(0, half_width)), chalk, 2.0)
	draw_arc(_place(Vector2.ZERO), _metres(PitchSpec.CENTRE_CIRCLE), 0.0, TAU, 48, chalk, 2.0)
	# The areas are measured out from the posts, as Law 1 writes them.
	for side: float in [-1.0, 1.0]:
		_box(side, half_length - PitchSpec.PENALTY_AREA_DEPTH,
			PitchSpec.GOAL_WIDTH * 0.5 + PitchSpec.PENALTY_AREA_REACH, chalk)
		_box(side, half_length - PitchSpec.GOAL_AREA_DEPTH,
			PitchSpec.GOAL_WIDTH * 0.5 + PitchSpec.GOAL_AREA_REACH, chalk)

	# Where he spent the match. A full ninety minutes is five thousand points, which draws
	# as a solid block and says nothing, so it is thinned to about six hundred — enough to
	# show the shape of where he went without filling the pitch in.
	var step := maxi(1, int(trail.size() / 600.0))
	var index := 0
	while index < trail.size():
		draw_circle(_place(trail[index]), 2.2, Color(0.95, 0.85, 0.35, 0.16))
		index += step

	# And where he was when it mattered.
	for d: Dictionary in decisions:
		var at: Vector2 = _place(d.at)
		var what: Vector2 = _place(d.incident)
		var colour: Color = UiTheme.EDGE if d.neutral else (UiTheme.GOOD if d.right else UiTheme.BAD)
		# The sightline: dotted when his view of it was poor, so a decision made through a
		# crowd of players reads differently from one made with a clear sight of it.
		if d.view < 0.5:
			_dotted(at, what, Color(colour, 0.5))
		else:
			draw_line(at, what, Color(colour, 0.35), 1.5)
		draw_circle(what, 3.0, Color(0.9, 0.93, 0.9, 0.55))
		draw_circle(at, 7.0, Color(colour, 0.9))
		draw_circle(at, 7.0, Color(0.06, 0.07, 0.06, 0.9), false, 1.5)


func _box(side: float, from_x: float, half: float, chalk: Color) -> void:
	var near := Vector2(side * from_x, -half)
	var far := Vector2(side * (spec.length * 0.5), half)
	draw_rect(Rect2(_place(Vector2(minf(near.x, far.x), near.y)),
		_place(Vector2(maxf(near.x, far.x), far.y)) - _place(Vector2(minf(near.x, far.x), near.y))),
		chalk, false, 2.0)


func _dotted(from: Vector2, to: Vector2, colour: Color) -> void:
	var along := to - from
	var length := along.length()
	if length < 1.0:
		return
	var step := along / length * 6.0
	var at := from
	var drawn := 0.0
	while drawn < length - 6.0:
		draw_line(at, at + step * 0.55, colour, 1.5)
		at += step
		drawn += 6.0
