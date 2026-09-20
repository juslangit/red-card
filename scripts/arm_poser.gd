class_name ArmPoser
extends SkeletonModifier3D

## Points a character's arms, over the top of whatever the legs are doing.
##
## A referee signals with their arms while running — advantage is both arms swept
## forward at full stride, a free kick is one arm pointed while jogging back into
## position. No clip can hold every arm signal on top of every gait, so the arms are
## aimed here, after the animation has posed the body: each arm is given a direction,
## the upper arm is turned to point along it, then the forearm is turned to point along
## its own. The legs and spine keep the clip's pose underneath.
##
## Directions are in the model's own space, which for the Meshy rig is +Z forward, +X to
## the character's left, +Y up. `aim_world()` converts from the world for anything that
## points at a place — the penalty spot, a player, a corner flag.

## Per arm: where the upper arm and the forearm should point, and how much of that to
## apply (0 leaves the clip's arm alone, 1 replaces it). Weights ease towards their
## targets so a signal rises rather than snapping.
var right_upper := Vector3.DOWN
var right_fore := Vector3.DOWN
var left_upper := Vector3.DOWN
var left_fore := Vector3.DOWN
var right_weight := 0.0
var left_weight := 0.0
var right_target_weight := 0.0
var left_target_weight := 0.0

## How fast an arm comes up, in weight per second. A card is shown briskly.
var raise_rate := 7.0

## For the referee's own body: the head is shrunk to nothing after the clip has posed
## it, so the first-person camera, which sits where the eyes are, never sees the inside
## of its own face. Everything from the neck down stays, which is what the player sees
## when they look down.
var hide_head := false

const RIGHT := {"upper": "RightArm", "fore": "RightForeArm", "hand": "RightHand"}
const LEFT := {"upper": "LeftArm", "fore": "LeftForeArm", "hand": "LeftHand"}

var _bones := {}


func _ready() -> void:
	_bones.clear()


func set_right(upper: Vector3, fore: Vector3 = Vector3.ZERO, weight := 1.0) -> void:
	right_upper = upper.normalized()
	right_fore = (fore if fore != Vector3.ZERO else upper).normalized()
	right_target_weight = weight


func set_left(upper: Vector3, fore: Vector3 = Vector3.ZERO, weight := 1.0) -> void:
	left_upper = upper.normalized()
	left_fore = (fore if fore != Vector3.ZERO else upper).normalized()
	left_target_weight = weight


func release_right() -> void:
	right_target_weight = 0.0


func release_left() -> void:
	left_target_weight = 0.0


func release() -> void:
	right_target_weight = 0.0
	left_target_weight = 0.0


## A world direction in the model's space, for aiming at a place.
func to_model(world_dir: Vector3) -> Vector3:
	var skeleton := get_skeleton()
	if skeleton == null:
		return world_dir
	return (skeleton.global_transform.basis.inverse() * world_dir).normalized()


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if hide_head:
		var head := _bone(skeleton, "Head")
		if head >= 0:
			skeleton.set_bone_pose_scale(head, Vector3.ONE * 0.001)
	right_weight = move_toward(right_weight, right_target_weight, raise_rate * delta)
	left_weight = move_toward(left_weight, left_target_weight, raise_rate * delta)
	if right_weight > 0.001:
		_aim_arm(skeleton, RIGHT, right_upper, right_fore, right_weight)
	if left_weight > 0.001:
		_aim_arm(skeleton, LEFT, left_upper, left_fore, left_weight)


func _bone(skeleton: Skeleton3D, bone_name: String) -> int:
	if not _bones.has(bone_name):
		_bones[bone_name] = skeleton.find_bone(bone_name)
	return _bones[bone_name]


func _aim_arm(skeleton: Skeleton3D, arm: Dictionary, upper_dir: Vector3, fore_dir: Vector3,
		weight: float) -> void:
	var upper := _bone(skeleton, arm.upper)
	var fore := _bone(skeleton, arm.fore)
	var hand := _bone(skeleton, arm.hand)
	if upper < 0 or fore < 0 or hand < 0:
		return
	_aim_bone(skeleton, upper, fore, upper_dir, weight)
	_aim_bone(skeleton, fore, hand, fore_dir, weight)


## Turns one bone so the line from it to its child points along `want`, by the shortest
## rotation, blended by `weight`. Works in skeleton space, where the armature's 1/100
## scale does not change any direction.
func _aim_bone(skeleton: Skeleton3D, bone: int, child: int, want: Vector3, weight: float) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var child_pose := skeleton.get_bone_global_pose(child)
	var now := child_pose.origin - pose.origin
	if now.length_squared() < 1e-8:
		return
	now = now.normalized()
	var target := want.normalized()
	if now.dot(target) > 0.99999:
		return
	var turn := Quaternion(now, target) if now.dot(target) > -0.9999 \
		else Quaternion(now.cross(Vector3.UP).normalized(), PI)
	turn = Quaternion.IDENTITY.slerp(turn, weight)
	var turned := Transform3D(Basis(turn) * pose.basis, pose.origin)
	skeleton.set_bone_global_pose(bone, turned)
