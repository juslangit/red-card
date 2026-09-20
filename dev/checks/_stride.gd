extends Node3D

## Measures how far a foot travels in each travelling clip, and prints the ground speed
## that clip is really running at. `Footballer.CLIP_SPEED` is set from these: playing a
## clip faster or slower than the speed the body is moving is what makes feet skate.

var anim: AnimationPlayer
var skel: Skeleton3D
var clips := ["run", "fb_sprint", "walk", "backpedal", "shuffle"]
var at := 0
var frame := 0
var lo := INF
var hi := -INF


func _ready() -> void:
	var scene: Node3D = load("res://assets/characters/footballer/footballer_animated.glb").instantiate()
	add_child(scene)
	anim = scene.find_child("AnimationPlayer", true, false)
	skel = scene.find_child("Skeleton3D", true, false)
	anim.play(clips[0])


func _process(_delta: float) -> void:
	var clip: String = clips[at]
	var a: Animation = anim.get_animation(clip)
	var steps := 48
	var t: float = a.length * float(frame) / steps
	anim.play(clip)
	anim.seek(t, true)
	skel.force_update_all_bone_transforms()
	var foot := skel.get_bone_global_pose(skel.find_bone("LeftFoot")).origin
	lo = minf(lo, foot.z)
	hi = maxf(hi, foot.z)
	frame += 1
	if frame > steps:
		# Bone space is the armature's centimetres. One cycle is two steps.
		var travel := (hi - lo) / 100.0
		print("%-10s  %.2f s   foot travel %.2f m   that is %.2f m/s" % [clip, a.length, travel, travel * 2.0 / a.length])
		at += 1
		frame = 0
		lo = INF
		hi = -INF
		if at >= clips.size():
			get_tree().quit()
