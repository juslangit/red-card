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
var _tilted := 0
var _lean_sum := 0.0
var _tilt_sum := 0.0
var _lean_n := 0.0


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
	# The torso, every frame, so the lean reported is the lean through the cycle rather
	# than whatever the pose happened to be on the last one.
	var hips_now := skel.find_bone("Hips")
	var head_now := skel.find_bone("Head")
	if hips_now >= 0 and head_now >= 0:
		var spine: Vector3 = (skel.get_bone_global_pose(head_now).origin
			- skel.get_bone_global_pose(hips_now).origin).normalized()
		# In the skeleton's own space this character faces +Z; +X is still his left.
		_lean_sum += rad_to_deg(asin(clampf(spine.z, -1.0, 1.0)))
		_tilt_sum += rad_to_deg(asin(clampf(spine.x, -1.0, 1.0)))
		_lean_n += 1
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
	# How the body is carried: forward lean is a gait, sideways tilt is a fault. Luqman
	# spotted the players running canted over to one side on 2026-09-21 — the lean in
	# `amplify()` was being applied about the hip bone's own X axis, which on a glTF rig is
	# whatever the exporter left it as, so nine degrees of forward lean came out sideways.
	var forward_lean: float = _lean_sum / maxf(_lean_n, 1.0)
	var side_tilt: float = _tilt_sum / maxf(_lean_n, 1.0)
	if absf(side_tilt) > 2.5:
		_tilted += 1
		print("BAD  %s carries a %.1f degree sideways tilt" % [clip, side_tilt])
	print("           leaning %.0f deg forward, %.1f deg sideways" % [forward_lean, side_tilt])
	print("%-10s %.2f s  swings %.2f m %-9s  %.0f%% of the cycle on the ground, lifts %.2f m  → %.2f m/s"
		% [clip, a.length, travel, "sideways" if lines[0].sideways else "forwards",
		contact * 100.0, lift, travel * 2.0 / a.length])

	at += 1
	frame = 0
	_track.clear()
	_lean_sum = 0.0
	_tilt_sum = 0.0
	_lean_n = 0.0
	if at >= clips.size():
		print("%d clip(s) carry a sideways tilt" % _tilted)
		get_tree().quit(1 if _tilted > 0 else 0)
