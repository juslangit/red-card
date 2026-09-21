extends Node3D

## What each travelling clip really does with the feet.
##
##     Godot --headless --path . res://dev/checks/_stride.tscn
##
## For every clip a body can travel in, it follows both feet through a full cycle and
## prints:
##
##   travel      how far a foot swings, along whichever way it swings. `Footballer.
##               CLIP_SPEED` is set from this: playing a clip faster or slower than the
##               body is moving is exactly what makes feet skate.
##   way         which way that swing runs — forwards, backwards or sideways. A clip whose
##               feet swing forwards cannot carry a body that is moving sideways, however
##               its rate is set, and that is what backpedal and shuffle were doing.
##   contact     the share of the cycle each foot spends near the ground. Walking is about
##               60 per cent a foot (both down for a moment); running is under 50 with a
##               moment neither foot is down. A clip with a foot down the whole time is
##               not a gait, it is a shuffle on the spot.
##   lift        how far the foot comes up. A gait that barely lifts reads as sliding even
##               when the rate is right.

const SAMPLES := 64

var anim: AnimationPlayer
var skel: Skeleton3D
var clips := ["walk", "run", "fb_run", "fb_sprint", "fb_backpedal", "fb_side"]
var at := 0
var frame := 0
var _low := Vector3.ZERO
var _track := {}


func _ready() -> void:
	var scene: Node3D = load("res://assets/characters/footballer/footballer_animated.glb").instantiate()
	add_child(scene)
	anim = scene.find_child("AnimationPlayer", true, false)
	skel = scene.find_child("Skeleton3D", true, false)
	for clip in clips.duplicate():
		if not anim.has_animation(clip):
			clips.erase(clip)
			print("(no clip %s)" % clip)
	anim.play(clips[0])


func _foot(name: String) -> Vector3:
	# Bone space is the armature's centimetres.
	return skel.get_bone_global_pose(skel.find_bone(name)).origin / 100.0


func _process(_delta: float) -> void:
	var clip: String = clips[at]
	var a: Animation = anim.get_animation(clip)
	anim.play(clip)
	anim.seek(a.length * float(frame) / SAMPLES, true)
	skel.force_update_all_bone_transforms()
	for side in ["LeftFoot", "RightFoot"]:
		var place := _foot(side)
		var seen: Array = _track.get(side, [])
		seen.append(place)
		_track[side] = seen
	frame += 1
	if frame <= SAMPLES:
		return

	var lines := []
	for side: String in _track.keys():
		var places: Array = _track[side]
		var lowest: float = places.map(func(p: Vector3) -> float: return p.y).min()
		var highest: float = places.map(func(p: Vector3) -> float: return p.y).max()
		# The swing, along the ground, and which way it runs.
		var span_x: float = places.map(func(p: Vector3) -> float: return p.x).max() \
			- places.map(func(p: Vector3) -> float: return p.x).min()
		var span_z: float = places.map(func(p: Vector3) -> float: return p.z).max() \
			- places.map(func(p: Vector3) -> float: return p.z).min()
		# The model faces -Z in Godot, so a foot swinging along Z is walking forwards.
		var sideways := span_x > span_z
		var travel: float = maxf(span_x, span_z)
		var down := 0
		for p: Vector3 in places:
			if p.y - lowest < 0.04:
				down += 1
		lines.append({"side": side, "travel": travel, "sideways": sideways,
			"contact": float(down) / places.size(), "lift": highest - lowest})
	var travel: float = (lines[0].travel + lines[1].travel) * 0.5
	var contact: float = (lines[0].contact + lines[1].contact) * 0.5
	var lift: float = (lines[0].lift + lines[1].lift) * 0.5
	print("%-10s %.2f s  swings %.2f m %-9s  %.0f%% of the cycle on the ground, lifts %.2f m  → %.2f m/s"
		% [clip, a.length, travel, "sideways" if lines[0].sideways else "forwards",
		contact * 100.0, lift, travel * 2.0 / a.length])

	at += 1
	frame = 0
	_track.clear()
	if at >= clips.size():
		get_tree().quit()
