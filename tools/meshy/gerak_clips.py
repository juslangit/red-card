"""Puts a clip keyed by hand in gerak onto the Meshy rig.

gerak (`~/Desktop/projects/3d/bengkel/gerak`, one of bengkel's tools) poses this same
character in the browser and saves the result to `~/Documents/gerak/clips/<name>.json`.
A clip so saved is copied into `clips/` here, so the forge rebuilds from the repository
rather than from whatever happens to be in the home folder.

What gerak writes is per bone, per frame, the bone's **local** rotation and position
exactly as they sit in the .glb it was posed against — three.js hands out a glTF node's
own transform, and that is what is stored.

Blender does not hold a pose that way, which is the whole difficulty of this file. A
pose bone carries a `matrix_basis` measured *from its rest pose*, in whatever frame the
glTF importer invented for that bone (glTF stores no bone tails, so Blender makes them
up). Turning one into the other for bone `b`:

    basis = C⁻¹ · (L_rest⁻¹ · L_frame) · C        C = W_rest⁻¹ · G⁻¹ · bone.matrix_local

where `L` is the node's local matrix, `W` its world matrix built up the parent chain,
and `G` the quarter turn about X that takes Y-up glTF into Z-up Blender. `C` is the
difference between the file's idea of the bone's frame and Blender's; it cancels out of
the parent chain, which is why only the bone's own is needed.

`G` was measured rather than assumed: predicting the basis for the character's own
imported `run` action this way reproduces Blender's values exactly (error 0.00000),
while the opposite sign or no rotation at all is out by most of a quaternion.

None of that is trusted on the day. `build` finishes by stepping the rig through the
action it just made and comparing every bone's position against the clip's own — see
`_verify`. Blender operators lie about having worked, and a rig that is subtly wrong
still exports, still plays and still looks like an animation.
"""

import json
import math
import os
import struct

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.realpath(__file__))
CLIPS = os.path.join(HERE, "clips")

## glTF is Y-up, Blender is Z-up, and the importer turns the scene a quarter turn about
## X to get from one to the other. Measured against the file's own actions, see above.
G = Matrix.Rotation(math.pi / 2, 4, "X")

## How far a bone may sit from where the clip puts it before the conversion is called
## wrong. The rig is in centimetres, so this is a tenth of a millimetre; a real mistake
## is out by tens of centimetres, not by rounding.
TOLERANCE = 0.01


# --- reading what gerak and glTF wrote -------------------------------------------

def _header(path):
    """The JSON chunk of a .glb, which is all the rest pose needs."""
    with open(path, "rb") as handle:
        magic, _version, _length = struct.unpack("<III", handle.read(12))
        if magic != 0x46546C67:
            raise SystemExit(f"{path} is not a .glb")
        chunk, _kind = struct.unpack("<II", handle.read(8))
        return json.loads(handle.read(chunk))


def _local(node):
    """A glTF node's own transform as one matrix."""
    move = Matrix.Translation(Vector(node.get("translation", [0, 0, 0])))
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    turn = Quaternion((w, x, y, z)).to_matrix().to_4x4()
    scale = Matrix.Diagonal(Vector(node.get("scale", [1, 1, 1])).to_4d())
    return move @ turn @ scale


def _rest(model):
    """Every bone's rest transform in the file gerak posed against.

    Returns its own local matrix and its world matrix, by name. Both are needed: the
    local one to measure a frame against, the world one to work out `C`.

    The chain stops at the topmost joint rather than running on up to the scene, because
    the node above this skeleton is an Armature scaled to a hundredth — the rig is built
    in centimetres and shrunk to metres at the very top. Blender keeps that hundredth on
    the armature *object* and its bones stay in centimetres, so a world matrix that has
    already been through it is measuring a different thing. This cost an afternoon once:
    the rotations came out perfect, because a uniform scale cancels either side of a
    conjugation, and the hips landed 1.84 m away, because a translation does not.
    """
    glb = _header(model)
    nodes = glb["nodes"]
    bones = {joint for skin in glb.get("skins", []) for joint in skin["joints"]}
    parent = {}
    for index, node in enumerate(nodes):
        for child in node.get("children", []):
            parent[child] = index

    local = [_local(node) for node in nodes]

    def world(index):
        above = parent.get(index)
        if above is None or (bones and above not in bones):
            return local[index]
        return world(above) @ local[index]

    return {node.get("name"): (local[i], world(i)) for i, node in enumerate(nodes)}


def path_for(character, meaning):
    """The clip file for this character, or None if it was never keyed by hand."""
    candidate = os.path.join(CLIPS, f"{character}-{meaning}.json")
    return candidate if os.path.exists(candidate) else None


# --- putting it on the rig --------------------------------------------------------

def build(rig, clip_file, action_name, model):
    """Reads `clip_file` onto `rig` as an action called `action_name`.

    `model` is the .glb the clip was posed against, which is where the rest pose it was
    measured from lives. It need not be the file the rig was loaded from — the two share
    a skeleton — but it must be the one gerak saw, because a re-export renames nothing
    and yet writes every node's local transform in Blender's bone frames rather than
    Meshy's.
    """
    clip = json.loads(open(clip_file).read())
    tracks = clip["tracks"]
    rest = _rest(model)

    missing = [bone for bone in tracks if bone not in rig.data.bones]
    if missing:
        raise SystemExit(f"{os.path.basename(clip_file)} keys bones the rig has not: {missing}")

    frames = {}
    for bone, keys in tracks.items():
        rest_local, rest_world = rest[bone]
        correction = rest_world.inverted() @ G.inverted() @ rig.data.bones[bone].matrix_local
        for key in keys:
            turn = Quaternion((key["q"][3], key["q"][0], key["q"][1], key["q"][2]))
            frame_local = Matrix.Translation(Vector(key["p"])) @ turn.to_matrix().to_4x4()
            basis = correction.inverted() @ (rest_local.inverted() @ frame_local) @ correction
            frames.setdefault(key["f"], {})[bone] = basis

    action = bpy.data.actions.new(action_name)
    action.use_fake_user = True
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = action

    ## Which bones carry a position of their own. On this rig only the hips do — the
    ## rest of the skeleton is joints turning on fixed bones — and keying a location
    ## that never changes writes three dead curves per bone into the game's file.
    travelling = [bone for bone in tracks
                  if any((frames[f][bone].to_translation()
                          - frames[min(frames)][bone].to_translation()).length > 1e-4
                         for f in frames)]

    for frame in sorted(frames):
        for bone, basis in frames[frame].items():
            posed = rig.pose.bones[bone]
            posed.rotation_mode = "QUATERNION"
            posed.rotation_quaternion = basis.to_quaternion()
            posed.location = basis.to_translation() if bone in travelling else (0, 0, 0)
            posed.keyframe_insert("rotation_quaternion", frame=frame)
            if bone in travelling:
                posed.keyframe_insert("location", frame=frame)

    for curve in _curves(action):
        for point in curve.keyframe_points:
            point.interpolation = "LINEAR" if clip.get("interp") == "linear" else "BEZIER"

    _verify(rig, tracks, rest, sorted(frames))
    length = max(frames) / float(clip.get("fps", 24))
    print(f"  read {action_name} from gerak: {len(tracks)} bones, {len(frames)} frames, "
          f"{length:.2f}s, position on {travelling or 'nothing'}")
    return action


def _curves(action):
    """The curves in an action, whichever Blender this is — see `rig_clips.curves`."""
    flat = getattr(action, "fcurves", None)
    if flat is not None:
        return flat
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                return bag.fcurves
    return []


def _verify(rig, tracks, rest, frames):
    """Steps the rig through the action and checks every bone landed where the clip says.

    The conversion above is arithmetic on four coordinate frames, and arithmetic that is
    wrong in one of them still produces a smooth, plausible, entirely incorrect run. So
    the pose is measured rather than assumed: each bone's position in the posed rig is
    compared with the same bone's position worked out straight from the clip's numbers.
    """
    scene = bpy.context.scene
    parent = {}
    for bone in rig.data.bones:
        parent[bone.name] = bone.parent.name if bone.parent else None

    keyed = {bone: {key["f"]: key for key in keys} for bone, keys in tracks.items()}
    worst = 0.0
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()

        world = {}

        def wanted(bone):
            if bone in world:
                return world[bone]
            key = keyed.get(bone, {}).get(frame)
            if key is None:
                local = rest[bone][0]
            else:
                turn = Quaternion((key["q"][3], key["q"][0], key["q"][1], key["q"][2]))
                local = Matrix.Translation(Vector(key["p"])) @ turn.to_matrix().to_4x4()
            above = parent[bone]
            world[bone] = (wanted(above) if above else Matrix.Identity(4)) @ local
            return world[bone]

        for bone in tracks:
            here = rig.pose.bones[bone].matrix.to_translation()
            there = (G @ wanted(bone)).to_translation()
            worst = max(worst, (here - there).length)

    scene.frame_set(frames[0])
    if worst > TOLERANCE:
        raise SystemExit(f"the clip did not land on the rig: a bone is {worst:.3f} cm "
                         f"from where gerak put it (allowed {TOLERANCE})")
    print(f"  checked against gerak's own numbers: worst bone out by {worst:.5f} cm")
