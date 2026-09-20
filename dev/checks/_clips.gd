extends Node3D

## Nothing a body can be left in may stop moving.
##
##     Godot --headless --path . res://dev/checks/_clips.tscn
##
## Luqman saw the running animation freeze on 2026-09-20. A clip that does not loop stops
## at its last frame and the player stands there mid-stride, still travelling, until his
## speed changes enough to call for a different clip. `fb_sprint` had been baked the same
## day and left out of the list of clips that are told to loop, so anybody who ran flat out
## for longer than the clip's 0.67 seconds froze.
##
## Two checks, because the first one alone would only have caught this particular cause:
##
##   1. every clip a body can hold, whichever name it resolves to, loops;
##   2. a body actually kept at each gait goes on moving — its feet are somewhere else
##      four seconds later, which is the symptom itself rather than one reason for it.

const CYCLES := ["idle", "stand_still", "walk", "run", "sprint", "backpedal", "shuffle",
	"keeper_ready", "lie", "celebrate", "argue", "tired"]
## The ones that travel, which are the ones a freeze shows up in.
const GAITS := ["walk", "run", "sprint", "backpedal", "shuffle"]
const WATCH := 4.0

var body: Footballer
var bad := 0
var at := 0
var elapsed := 0.0
var _last := Vector3.ZERO
var _still := 0.0
var _moved := 0.0


func _ready() -> void:
	body = Footballer.new()
	body.setup(Names.team_from(0), 9, Footballer.Role.MF, "Test")
	add_child(body)
	var anim: AnimationPlayer = body.find_child("AnimationPlayer", true, false)
	for meaning in CYCLES:
		for name: String in Footballer.CLIPS.get(meaning, [meaning]):
			if not anim.has_animation(name):
				continue
			var clip: Animation = anim.get_animation(name)
			var looping := clip.loop_mode != Animation.LOOP_NONE
			if not looping:
				bad += 1
			print("%s %-14s %-16s %.2f s" % ["    " if looping else "BAD ", meaning, name, clip.length])


func _process(delta: float) -> void:
	if at >= GAITS.size():
		return
	var gait: String = GAITS[at]
	body.play(gait, 0.1, 1.0)
	elapsed += delta
	var foot: Vector3 = body.skeleton.get_bone_global_pose(body.skeleton.find_bone("LeftFoot")).origin
	if elapsed > 0.5:      # let the blend settle before watching
		if foot.distance_to(_last) < 0.0005:
			_still += delta
		else:
			_moved = maxf(_moved, foot.distance_to(_last))
			_still = 0.0
	_last = foot
	if elapsed > WATCH:
		# A third of a second without the foot moving is a freeze: even the slowest gait
		# here moves it every frame.
		var frozen := _still > 0.33
		if frozen:
			bad += 1
		print("%s %-14s watched %.0f s, longest still %.2f s" % ["BAD " if frozen else "    ", gait, WATCH, _still])
		at += 1
		elapsed = 0.0
		_still = 0.0
		if at >= GAITS.size():
			print("%d clip problem(s)" % bad)
			get_tree().quit(1 if bad > 0 else 0)
