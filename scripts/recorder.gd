class_name Recorder
extends RefCounted

## A flight recorder for the whole match: where everybody and the ball were, ten times a
## second, and where the referee was looking.
##
## It exists for replays. The assessor's report plays key moments back from here — from
## the referee's own eyes and from a broadcast camera — and VAR's on-field review does the
## same. Ten frames a second, interpolated on playback, is plenty for a body at a run and
## costs a few megabytes for a whole match.

const RATE := 10.0

var m
var frames: Array = []   # [{t, ball, players: PackedVector3Array, headings, ref, ref_look}]
var _accum := 0.0


func _init(match_node) -> void:
	m = match_node


func step(delta: float) -> void:
	_accum += delta
	if _accum < 1.0 / RATE:
		return
	_accum = 0.0
	var positions := PackedVector3Array()
	var headings := PackedVector3Array()
	var states := PackedInt32Array()
	for p: Footballer in m.players:
		positions.append(p.global_position)
		headings.append(p.heading)
		states.append(p.state if p.on_pitch else -1)
	var frame := {"t": m.clock, "ball": m.ball.global_position, "players": positions,
		"headings": headings, "states": states}
	if m.referee != null:
		frame["ref"] = m.referee.global_position
		frame["ref_look"] = m.referee.call("look_transform") if m.referee.has_method("look_transform") else Transform3D()
	frames.append(frame)


func mark(_what: StringName) -> void:
	pass


## The frames between two moments, for a replay.
func between(from: float, to: float) -> Array:
	return frames.filter(func(f): return f.t >= from and f.t <= to)


## The frame nearest a moment.
func at(t: float) -> Dictionary:
	if frames.is_empty():
		return {}
	var lo := 0
	var hi := frames.size() - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if frames[mid].t < t:
			lo = mid + 1
		else:
			hi = mid
	return frames[lo]
