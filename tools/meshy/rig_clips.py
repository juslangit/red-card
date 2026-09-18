"""Puts the badminton animations onto a Meshy character and exports it for the game.

    blender --background --python tools/meshy/rig_clips.py -- player_blue
    blender --background --python tools/meshy/rig_clips.py -- player_blue preview

Meshy generates and rigs the character and throws in a walk and a run, which are two
of the clips the game needs and two it would be a waste of time to key by hand. It has
an animation library for the rest, but nothing in it is badminton — so the shots are
authored here, on Meshy's own rig, and the result is one file with everything in it.

Reads  assets/meshy/<name>/<name>_rigged.glb  (plus _walking, _running and _smash)
Writes assets/meshy/<name>/<name>_animated.glb

Both sports' clips go into that one file. Badminton's are named for the shot; beach
volleyball's all begin `vb_`, so the two can share a character without arguing over
the word "serve".
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.realpath(__file__))
PROJECT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from badminton_clips import BONES, FPS, MOVE  # noqa: E402
from badminton_clips import CLIPS as BADMINTON_CLIPS  # noqa: E402
from volleyball_clips import CLIPS as VOLLEYBALL_CLIPS  # noqa: E402
from tennis_clips import CLIPS as TENNIS_CLIPS  # noqa: E402
from takraw_clips import CLIPS as TAKRAW_CLIPS  # noqa: E402

# Both sports go into one character.
#
# The same two athletes play badminton and beach volleyball, and a second exported file
# per sport would mean two copies of a seven-megabyte mesh to keep in step. The
# volleyball clips are all prefixed `vb_`, so nothing collides — which matters most for
# the word "serve", which both sports have and mean completely different things by.
# Tennis's are `tn_` and sepak takraw's `st_` for the same reason.
CLIPS = dict(BADMINTON_CLIPS)
for _name, _clip in (list(VOLLEYBALL_CLIPS.items()) + list(TENNIS_CLIPS.items())
                     + list(TAKRAW_CLIPS.items())):
    if _name in CLIPS:
        raise SystemExit(f"clip name {_name} is claimed by both sports")
    CLIPS[_name] = _clip


def curves(action):
    """The animation curves in an action, whichever Blender this is.

    Blender 4.4 rebuilt actions as layers of strips holding channel bags, and the flat
    `action.fcurves` list that every script in the world used stopped existing. This
    returns the curves either way, so the forge runs on the version installed rather
    than the version it was written against.
    """
    flat = getattr(action, "fcurves", None)
    if flat is not None:
        return flat
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                return bag.fcurves
    return []


def source(name, suffix=""):
    return os.path.join(PROJECT, "assets", "meshy", name, f"{name}{suffix}.glb")


# --- reading Meshy's files ------------------------------------------------------

def load_character(name):
    """The rigged character, with the debris Meshy leaves in the file removed."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=source(name, "_rigged"))

    # Every rigged file comes with a 2 m icosphere in it that is not part of the
    # character. Left in, it is a giant invisible bubble around the player that throws
    # off every measurement the game makes of the model.
    for junk in [o for o in bpy.data.objects if o.type == "MESH" and not o.parent]:
        print(f"  dropping {junk.name}, which is not part of the character")
        bpy.data.objects.remove(junk, do_unlink=True)

    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    rig.animation_data_clear()

    missing = [bone for bone in BONES if bone not in rig.data.bones]
    if missing:
        sys.exit(f"rig is missing bones the clips need: {missing}")
    return rig


# The smash is Meshy's own, made from a description by `meshy.py motion smash` and put
# onto each character's rig by Meshy (`meshy.py animate <name> motion:smash smash`). It
# is 2.5 s of wind-up, scissor jump, strike and landing; the game starts a shot the
# instant the racket meets the shuttle, so only the part from just before contact to the
# landing is kept. Contact is frame 24 of Meshy's clip (the hand at its highest, 2.6 m
# up), which puts it 6 frames into the trimmed one — the same quarter of a second the
# hand-keyed smash took, so nothing in the game had to be retimed.
SMASH_FRAMES = (17.6, 40.8)

# The crouch and push-off the smash above starts just after, as a clip of its own. Frames
# 1-9 of Meshy's clip are only the arm lifting; from 10 the hips drop 8 cm, and the feet
# leave the floor at about 17 (measured 2026-09-15). The game plays it when it can see a
# smash coming, timed to end on the strike, and the smash then carries on from the pose
# it left. A smash nobody saw coming still starts at 17.6, as before.
SMASH_WINDUP_FRAMES = (10.0, 17.6)

# Which of the Hips' location channels carry the journey rather than the body's own
# rise and fall. On Meshy's rig the Hips bone's Y axis is the world's up: in the smash,
# channel 0 is 0.8 m of drift to the side, 1 is the 0.65 m jump and 2 is forwards and
# back.
HIPS_SIDEWAYS_AND_FORWARDS = (0, 2)


def steal_animation(name, suffix, clip_name, rig, frames=None, drop=(0, 1)):
    """Takes one of Meshy's own animations and leaves the rest of the file behind.

    An action is only a list of curves addressed by bone name, so once it is in the
    file it plays on any rig with the same bones — and every Meshy export of the same
    character has exactly the same skeleton.

    `frames` keeps only that stretch of the clip, moved to start at frame 0. `drop` is
    which of the Hips' location channels to throw away.
    """
    path = source(name, suffix)
    if not os.path.exists(path):
        print(f"  no {suffix} file, skipping {clip_name}")
        return None

    before = set(bpy.data.actions)
    arrived = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    fresh = [a for a in bpy.data.actions if a not in before]
    for extra in [o for o in bpy.data.objects if o not in arrived]:
        bpy.data.objects.remove(extra, do_unlink=True)

    if not fresh:
        print(f"  {suffix} had no animation in it")
        return None

    # A generated motion arrives with a second, near-empty action of a fraction of a
    # frame beside the real one. The clip is the long one.
    fresh.sort(key=lambda a: a.frame_range[1] - a.frame_range[0], reverse=True)
    action = fresh[0]
    for spare in fresh[1:]:
        bpy.data.actions.remove(spare)

    # The walk and the run travel. The game drives the player across the court itself,
    # so a clip that also moves them would send them sliding off the back of the hall
    # at twice the speed. The hips keep their bounce and lose their journey.
    travel = curves(action)
    for curve in list(travel):
        if curve.data_path.endswith(".location") and curve.array_index in drop:
            travel.remove(curve)

    if frames is not None:
        first, last = frames
        for curve in travel:
            points = curve.keyframe_points
            for index in reversed(range(len(points))):
                if not first - 0.01 <= points[index].co.x <= last + 0.01:
                    points.remove(points[index])
            for point in points:
                point.co.x -= first
                point.handle_left.x -= first
                point.handle_right.x -= first
        action.frame_range = (0.0, last - first)

    action.name = clip_name
    action.use_fake_user = True
    print(f"  took {clip_name} from Meshy ({len(travel)} curves)")
    return action


# --- writing the badminton clips ------------------------------------------------

## An upper arm and the bone that hangs off it, so the arm's rest direction can be
## measured rather than assumed.
ARM_CHAIN = {"LeftArm": "LeftForeArm", "RightArm": "RightForeArm"}

## How far off sideways an arm may rest and still count as a T-pose.
##
## 20, and the number is load-bearing. The two characters the clips were authored on rest
## 12 to 13 degrees off sideways — they are T-posed by eye but not to the axis — and the
## one that needed correcting rests 54. A threshold of 12 caught all three, which made
## every rig agree exactly and **changed the two characters Luqman has already played**:
## their posed arms moved about twelve degrees. Correctness that rewrites what somebody
## has accepted is not obviously correctness, so the shipped pair are left alone and only
## a rig that is plainly in some other pose is brought into line.
LEAVE_ALONE_WITHIN = 20.0

## Worked out once per character, because it depends on the rig and not on the clip.
_LIFTS = {}


def lift_to_t_pose(rig, bone_name):
    """The rotation that takes an arm from where it rests to straight out sideways.

    Every arm angle in `badminton_clips.py` and its neighbours is written as a departure
    from a T-pose — "straight out sideways", as the header there says — because that is
    how Meshy generated the two athletes the clips were authored on. Measured, their
    upper arms rest 3 to 5 degrees below level, which is a T-pose.

    A character generated later came back in an **A-pose**: arms resting 53 degrees below
    level. `pose_bone` turns a world rotation into a local one *relative to the bone's
    rest*, so every arm angle in all 33 clips landed about 53 degrees short — the figure
    stood with its arms pinned to its chest and its hands inside its torso through the
    whole set, while the same clips on the older characters were fine. Nothing errored and
    nothing was missing; the clips simply measured from somewhere else.

    So the difference is measured off the rig and taken out. The direction comes from the
    forearm's head rather than the bone's own tail, because glTF does not store tails and
    Blender invents them — every bone in this skeleton came in over a thousand units long
    pointing somewhere nobody chose.

    A rig that is already in a T-pose gets a rotation of about zero, so this is applied to
    every character rather than to the ones known to need it: one code path, and the next
    character Meshy hands back in some third pose is handled without anybody noticing it
    needed to be.
    """
    child = ARM_CHAIN.get(bone_name)
    if child is None or child not in rig.data.bones or bone_name not in rig.data.bones:
        return Matrix.Identity(3)
    key = (rig.name, bone_name)
    if key in _LIFTS:
        return _LIFTS[key]
    along = rig.data.bones[child].head_local - rig.data.bones[bone_name].head_local
    if along.length < 1e-6:
        _LIFTS[key] = Matrix.Identity(3)
        return _LIFTS[key]
    along.normalize()
    # Straight out sideways: +X for their left arm, -X for their right, exactly as the
    # header of `badminton_clips.py` defines a T-pose.
    #
    # Levelling alone is not enough, and measuring said so. The first version rotated the
    # arm onto its own horizontal projection, which fixed the drop and left the splay: the
    # posed arm came out 9.7 degrees below level against the reference rig's 9.8 — right —
    # while pointing a quarter of the way forward, because an A-pose carries the arms
    # forward as well as down. `point` still folded across the chest.
    sideways = Vector((1.0 if along.x >= 0.0 else -1.0, 0.0, 0.0))
    apart = math.degrees(along.angle(sideways))
    if apart < LEAVE_ALONE_WITHIN:
        # Already a T-pose. Left untouched rather than nudged onto an exact axis, so the
        # two characters the clips were authored on export byte for byte as before and a
        # fix for a new rig cannot quietly restate an old one.
        _LIFTS[key] = Matrix.Identity(3)
        return _LIFTS[key]
    print("  %s rests %.0f deg off sideways — levelling it before posing" % (bone_name, apart))
    _LIFTS[key] = along.rotation_difference(sideways).to_matrix()
    return _LIFTS[key]


def pose_bone(rig, bone_name, degrees):
    """Rotates one bone by three angles about the world axes rather than its own.

    Meshy's rig arrives through glTF, which does not store bone tails, so Blender
    invents them — every bone in this skeleton came in over a thousand units long
    pointing in a direction nobody chose. Euler angles in a bone's own space are
    therefore meaningless here. These are turned into whatever local rotation produces
    the requested world rotation, so a pose can be written the way it looks.

    The arm is brought level before the clip's own rotation is applied, so that "straight
    out sideways" means the same thing on a character that rests in an A-pose as on the
    two it was written for. See `lift_to_t_pose`.
    """
    posed = rig.pose.bones[bone_name]
    rest = posed.bone.matrix_local.to_3x3()

    wanted = Matrix.Identity(3)
    for axis, angle in zip("XYZ", degrees):
        if angle:
            wanted = Matrix.Rotation(math.radians(angle), 3, axis) @ wanted
    wanted = wanted @ lift_to_t_pose(rig, bone_name)

    posed.rotation_mode = "QUATERNION"
    posed.rotation_quaternion = (rest.inverted() @ wanted @ rest).to_quaternion()


def move_hips(rig, offset):
    """Shifts the whole body, in metres, without rotating anything.

    Rotation alone cannot produce a lunge. Swinging the hip forward as far as a lunge
    goes just lifts the foot off the floor into a knee raise — what makes it a lunge is
    that the body drops and travels with the leg. That is a translation, and the hips
    are the only bone in the rig it belongs on.
    """
    posed = rig.pose.bones["Hips"]
    rest = posed.bone.matrix_local.to_3x3()
    # Bones on this rig are in centimetres while the armature object is scaled to a
    # hundredth, so a metre of travel is a hundred units before it is turned into the
    # bone's own frame.
    posed.location = rest.inverted() @ (Vector(offset) * 100.0)


def clear_pose(rig):
    for posed in rig.pose.bones:
        posed.rotation_mode = "QUATERNION"
        posed.rotation_quaternion = (1, 0, 0, 0)
        posed.location = (0, 0, 0)
        posed.scale = (1, 1, 1)


def build_clip(rig, clip_name, clip):
    action = bpy.data.actions.new(clip_name)
    action.use_fake_user = True
    rig.animation_data.action = action

    for frame, pose in clip["keys"]:
        clear_pose(rig)
        for bone_name, degrees in pose.items():
            if bone_name == MOVE:
                move_hips(rig, degrees)
            else:
                pose_bone(rig, bone_name, degrees)
        # Every bone the clip touches anywhere is keyed on every one of its frames,
        # or a bone moved in one key would drift for the whole clip from wherever it
        # happened to be left at the end of the last one.
        for bone_name in _bones_used(clip):
            rig.pose.bones[bone_name].keyframe_insert("rotation_quaternion", frame=frame)
        if _travels(clip):
            rig.pose.bones["Hips"].keyframe_insert("location", frame=frame)

    for curve in curves(action):
        for point in curve.keyframe_points:
            point.interpolation = "BEZIER"
    print(f"  keyed {clip_name}: {len(clip['keys'])} poses, "
          f"{clip['keys'][-1][0]} frames, {'loops' if clip['loop'] else 'once'}")
    return action


def _bones_used(clip):
    used = set()
    for _frame, pose in clip["keys"]:
        used.update(pose)
    used.discard(MOVE)
    return sorted(used)


def _travels(clip):
    return any(MOVE in pose for _frame, pose in clip["keys"])


def forge(name):
    rig = load_character(name)
    print(f"forging {name}")

    steal_animation(name, "_walking", "walk", rig)
    steal_animation(name, "_running", "run", rig)
    meshy_smash = steal_animation(name, "_smash", "smash", rig, frames=SMASH_FRAMES,
                                  drop=HIPS_SIDEWAYS_AND_FORWARDS)
    steal_animation(name, "_smash", "smash_windup", rig, frames=SMASH_WINDUP_FRAMES,
                    drop=HIPS_SIDEWAYS_AND_FORWARDS)

    rig.animation_data_create()
    for clip_name, clip in CLIPS.items():
        # The hand-keyed smash stays in badminton_clips.py as the fallback for a
        # character with no Meshy smash file.
        if clip_name == "smash" and meshy_smash is not None:
            continue
        build_clip(rig, clip_name, clip)

    rig.animation_data.action = None
    clear_pose(rig)

    out = source(name, "_animated")
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        export_animation_mode="ACTIONS",
        export_animations=True,
        export_bake_animation=True,
        export_optimize_animation_size=False,
        export_yup=True,
    )
    size = os.path.getsize(out) / 1024 / 1024
    print(f"wrote {os.path.relpath(out, PROJECT)}  ({size:.1f} MB, "
          f"{len(bpy.data.actions)} clips)")


# --- looking at it --------------------------------------------------------------

SHOTS = [
    ("ready", 0), ("run", None), ("lunge", 1), ("smash", 0), ("smash", 1),
    ("forehand", 1), ("backhand", 0), ("serve", 0), ("celebrate", 1), ("tired", 0),
]


def preview(name):
    """A row of the character in one pose from each clip, so they can be looked at."""
    rig = load_character(name)
    body = next(o for o in bpy.data.objects if o.type == "MESH")
    height = 1.8
    spacing = height * 0.78

    for column, (clip_name, key_index) in enumerate(SHOTS):
        bpy.ops.object.select_all(action="DESELECT")
        rig.select_set(True)
        body.select_set(True)
        bpy.context.view_layer.objects.active = rig
        bpy.ops.object.duplicate()
        copy = bpy.context.view_layer.objects.active

        clear_pose(copy)
        if key_index is not None:
            for bone_name, degrees in CLIPS[clip_name]["keys"][key_index][1].items():
                if bone_name == MOVE:
                    move_hips(copy, degrees)
                else:
                    pose_bone(copy, bone_name, degrees)
        # Only the rig moves. The body is parented to it, so moving both puts every
        # character at twice its column and half of them off the side of the frame.
        copy.location.x = column * spacing
        # Turned away from the camera, because a badminton pose is mostly about how far
        # forward the racket is and a head-on view shows none of that.
        copy.rotation_euler.z = math.radians(38)

    rig.hide_render = True
    body.hide_render = True

    _camera(len(SHOTS) * spacing, height)
    _render(os.path.join(HERE, "_preview.png"))
    print("labels: " + "  |  ".join(f"{c}[{k}]" for c, k in SHOTS))


def _camera(width, height):
    centre = (width - height * 0.78) * 0.5 - height * 0.10
    bpy.ops.object.camera_add(location=(centre, -width, height * 0.55))
    camera = bpy.context.object
    camera.rotation_euler = (math.radians(90), 0, 0)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = width * 1.02
    bpy.context.scene.camera = camera

    bpy.ops.object.light_add(type="SUN", location=(width * 0.4, -width, height * 3))
    key = bpy.context.object
    key.data.energy = 4.0
    key.rotation_euler = (math.radians(52), 0, math.radians(28))

    world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.13, 0.14, 0.16, 1)


def _render(path):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 3400
    scene.render.resolution_y = 1250
    scene.render.filepath = path
    scene.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    print("wrote", path)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    who = argv[0] if argv else "player_blue"
    bpy.context.scene.render.fps = FPS
    if len(argv) > 1 and argv[1] == "preview":
        preview(who)
    else:
        forge(who)
