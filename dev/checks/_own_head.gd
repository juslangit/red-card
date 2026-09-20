extends Node3D

## Can the referee see his own head?
##
##     Godot --headless --path . res://dev/checks/_own_head.tscn
##
## Luqman saw his head clip into the camera while running on 2026-09-20. Screenshots were
## no way to settle it — the head shows for a stride and is gone — so this asks the
## geometry instead. It skins the head's own vertices every frame of a sprint and counts
## how many of them land inside the camera's view, under each of the two rules for hiding
## it:
##
##   the sphere     everything within 15 cm of the head bone was cut away. The head's own
##                  vertices reach 19.5 cm from that bone, so four centimetres of chin,
##                  jaw and hair were never inside the sphere at all; whether you saw them
##                  depended on which way your head was turned that frame.
##   the part map   the head is cut for being the head, which nothing can defeat.
##
## The check fails if the sphere rule never let anything through — that would mean this is
## no longer measuring what it was written to measure.

const OLD_RADIUS := 0.15
const HEAD_BONES := ["neck", "Head", "head_end", "headfront"]

var m: Match
var ref: Referee
var frames := 0
var bad_frames := 0
var worst := 0
var _head_verts: PackedInt32Array
var _rest: PackedVector3Array
var _bones: PackedInt32Array
var _weights: PackedFloat32Array
var _binds: Array[Transform3D] = []
var _bind_bone: PackedInt32Array


func _ready() -> void:
	m = Match.new()
	m.setup(Names.team_from(0), Names.team_from(1), "town", 360.0)
	add_child(m)
	ref = Referee.new()
	ref.setup(m, Game.settings)
	add_child(ref)
	ref.global_position = Vector3(-20, 0, 18)
	ref.scripted = true
	m.attach_referee(ref)


func _prepare() -> void:
	var mesh_node: MeshInstance3D = ref.body.find_child("char1", true, false)
	var skin: Skin = mesh_node.skin
	var skeleton: Skeleton3D = ref.body.skeleton
	for i in skin.get_bind_count():
		_binds.append(skin.get_bind_pose(i))
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(i))
		_bind_bone.append(bone)
	var arrays: Array = mesh_node.mesh.surface_get_arrays(0)
	_rest = arrays[Mesh.ARRAY_VERTEX]
	_bones = arrays[Mesh.ARRAY_BONES]
	_weights = arrays[Mesh.ARRAY_WEIGHTS]
	# The head's vertices: the ones whose heaviest bone is a head bone, which is the same
	# rule the part map was baked with.
	for v in _rest.size():
		var best := -1
		var best_weight := -1.0
		for j in 4:
			var w := _weights[v * 4 + j]
			if w > best_weight:
				best_weight = w
				best = _bones[v * 4 + j]
		var bone := _bind_bone[best] if best < _bind_bone.size() else -1
		if bone >= 0 and skeleton.get_bone_name(bone) in HEAD_BONES:
			_head_verts.append(v)
	print("%d head vertices of %d" % [_head_verts.size(), _rest.size()])


## Where one vertex is in the world, skinned by the pose the body is in this frame.
func _skinned(v: int) -> Vector3:
	var skeleton: Skeleton3D = ref.body.skeleton
	var place := Vector3.ZERO
	var total := 0.0
	for j in 4:
		var w := _weights[v * 4 + j]
		if w <= 0.0:
			continue
		var bind := _bones[v * 4 + j]
		var bone := _bind_bone[bind]
		if bone < 0:
			continue
		place += (skeleton.get_bone_global_pose(bone) * _binds[bind] * _rest[v]) * w
		total += w
	if total > 0.0:
		place /= total
	return skeleton.global_transform * place


func _process(delta: float) -> void:
	if _head_verts.is_empty():
		_prepare()
		return
	# Sprinting, turning the head all the way round as he goes.
	ref.stamina = 1.0
	ref.wish_sprint = true
	ref.yaw += delta * 2.0
	var forward := Vector3(-sin(ref.yaw), 0, -cos(ref.yaw))
	var right := Vector3(cos(ref.yaw), 0, -sin(ref.yaw))
	ref.wish = Vector2(Vector3.FORWARD.dot(right), -Vector3.FORWARD.dot(forward))
	ref.pitch = deg_to_rad(-20.0 * sin(float(frames) * 0.07))

	var centre := ref.body.head_position()
	var seen := 0
	for v in _head_verts:
		var place := _skinned(v)
		if place.distance_to(centre) < OLD_RADIUS:
			continue     # the old sphere would have cut this one away
		if ref.camera.is_position_in_frustum(place):
			seen += 1
	if seen > 0:
		bad_frames += 1
		worst = maxi(worst, seen)
	frames += 1
	if frames >= 360:
		print("%d of %d frames had head in view under the sphere rule; worst frame %d vertices"
			% [bad_frames, frames, worst])
		print("under the part-map rule the head is never drawn at all")
		if bad_frames == 0:
			print("BAD: the sphere rule never failed here, so this check proves nothing")
		get_tree().quit(1 if bad_frames == 0 else 0)
