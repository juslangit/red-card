"""Bakes a body-part map for the footballer, so the kit can be painted properly.

    blender --background --python tools/meshy/bake_kit_map.py -- footballer

Writes assets/characters/footballer/footballer_parts.png, a 1024x1024 map in the model's
own UV layout where every texel says what part of the body it belongs to:

    R   the part: skin, hand, torso, arm, hips-and-thigh, shin, foot, head
    G   how far along that part the texel is, or the height up the body
    B   how much the surface faces the player's back, 0 front to 1 back
    A   how far across the body the texel is, 0 at his right to 1 at his left

The last two are what let the shirt number be printed on the back of the shirt in the
shader, where it creases and turns with the fabric instead of floating behind it.

`kit.gdshader` reads it and paints a football kit: a shirt with a collar and cuffs, shorts,
socks to the knee and boots — instead of guessing from the colours in the original texture,
which could only ever repaint what Meshy had already drawn (a badminton top, bare shins and
trainers).

The part of each texel comes from the vertex's heaviest bone, which is exactly what a body
part is; "along" is where it sits on that bone, which is what separates a sleeve from a
bare arm, shorts from a thigh, and a sock from a boot.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.realpath(__file__))
PROJECT = os.path.dirname(os.path.dirname(HERE))
# 2048: at 1024 the back of the shirt got only a few dozen texels across and the printed
# number came out with blocky edges.
SIZE = 2048

# What each bone is, and the number that goes in the red channel.
PARTS = {
    "skin": 0,
    "hand": 20,
    "torso": 40,
    "arm": 80,
    "hips": 120,
    "shin": 160,
    "foot": 200,
    "head": 240,
}

BONE_PARTS = {
    "Hips": "hips", "Spine": "torso", "Spine01": "torso", "Spine02": "torso",
    "LeftShoulder": "torso", "RightShoulder": "torso",
    "LeftArm": "arm", "RightArm": "arm",
    "LeftForeArm": "arm", "RightForeArm": "arm",
    "LeftHand": "hand", "RightHand": "hand",
    "LeftUpLeg": "hips", "RightUpLeg": "hips",
    "LeftLeg": "shin", "RightLeg": "shin",
    "LeftFoot": "foot", "RightFoot": "foot",
    "LeftToeBase": "foot", "RightToeBase": "foot",
    "neck": "head", "Head": "head", "head_end": "head", "headfront": "head",
}


def source(name, suffix=""):
    return os.path.join(PROJECT, "assets", "characters", name, f"{name}{suffix}.glb")


def load(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=source(name, "_rigged"))
    for junk in [o for o in bpy.data.objects if o.type == "MESH" and not o.parent]:
        bpy.data.objects.remove(junk, do_unlink=True)
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = next(o for o in bpy.data.objects if o.type == "MESH")
    return rig, body


# Which bones measure "along" down their own length, and which use the body's height
# instead. A sleeve, a sock and a boot are places on a limb; a collar is a height.
LIMBS = {"LeftArm", "RightArm", "LeftForeArm", "RightForeArm",
         "LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"}


def bone_axis(rig, name):
    """A bone's head, and the direction and length down to its first child's head.

    Not to its tail: glTF stores no bone tails, so Blender invents them — on this
    skeleton they come in some four thousand units long pointing in directions nobody
    chose (the same trap Referee For Fun's rig_clips.py documents). The first child's head
    is where the bone really ends: the elbow for an upper arm, the ankle for a shin.
    """
    bone = rig.data.bones.get(name)
    if bone is None or not bone.children:
        return None
    head = rig.matrix_world @ bone.head_local
    tail = rig.matrix_world @ bone.children[0].head_local
    along = tail - head
    if along.length < 1e-4:
        return None
    return head, along.normalized(), along.length


def vertex_facts(rig, body):
    """Per vertex: its part, how far along it is, and how far it faces backwards."""
    groups = {g.index: g.name for g in body.vertex_groups}
    axes = {name: bone_axis(rig, name) for name in LIMBS}
    facts = []
    world = body.matrix_world
    places = [world @ v.co for v in body.data.vertices]
    low, high = min(p.z for p in places), max(p.z for p in places)
    span = max(high - low, 1e-6)
    left, right = min(p.x for p in places), max(p.x for p in places)
    width = max(right - left, 1e-6)
    for vert in body.data.vertices:
        best, best_weight = None, -1.0
        for g in vert.groups:
            if g.weight > best_weight and groups.get(g.group) in BONE_PARTS:
                best, best_weight = groups[g.group], g.weight
        part = BONE_PARTS.get(best, "skin")
        position = world @ vert.co
        # On a limb, how far down that limb; everywhere else, how high up the body — which
        # is what a collar is, and what tells a shirt from shorts.
        along = (position.z - low) / span
        axis = axes.get(best)
        if axis is not None:
            head, direction, length = axis
            along = min(max((position - head).dot(direction) / length, 0.0), 1.0)
        # The model faces -Y in Blender after the glTF import, so the back faces +Y.
        normal = (world.to_3x3() @ vert.normal).normalized()
        backness = normal.y * 0.5 + 0.5
        across = (position.x - left) / width
        facts.append((PARTS[part], along, backness, across))
    return facts


def bake(name):
    rig, body = load(name)
    mesh = body.data
    mesh.calc_loop_triangles()
    uv_layer = mesh.uv_layers.active.data
    facts = vertex_facts(rig, body)

    pixels = [0.0] * (SIZE * SIZE * 4)
    painted = [False] * (SIZE * SIZE)

    def put(x, y, fact):
        if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
            return
        at = (y * SIZE + x) * 4
        pixels[at] = fact[0] / 255.0
        pixels[at + 1] = fact[1]
        pixels[at + 2] = fact[2]
        pixels[at + 3] = fact[3]
        painted[y * SIZE + x] = True

    for tri in mesh.loop_triangles:
        corners = []
        for loop_index, vert_index in zip(tri.loops, tri.vertices):
            uv = uv_layer[loop_index].uv
            corners.append((uv.x * SIZE, uv.y * SIZE, facts[vert_index]))
        _fill(corners, put)

    _dilate(pixels, painted)

    image = bpy.data.images.new("parts", SIZE, SIZE, alpha=True)
    image.pixels = pixels
    out = os.path.join(PROJECT, "assets", "characters", name, f"{name}_parts.png")
    image.filepath_raw = out
    image.file_format = "PNG"
    image.save()
    print(f"wrote {os.path.relpath(out, PROJECT)}  ({len(mesh.loop_triangles)} triangles)")


def _fill(corners, put):
    """Rasterises one triangle in UV space, interpolating "along" and "backness" and
    taking the part from whichever corner the texel is nearest — a part is a name, and
    averaging a sock with a boot would give neither."""
    (x0, y0, f0), (x1, y1, f1), (x2, y2, f2) = corners
    low_x, high_x = int(math.floor(min(x0, x1, x2))), int(math.ceil(max(x0, x1, x2)))
    low_y, high_y = int(math.floor(min(y0, y1, y2))), int(math.ceil(max(y0, y1, y2)))
    area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
    if abs(area) < 1e-9:
        return
    for y in range(low_y, high_y + 1):
        for x in range(low_x, high_x + 1):
            px, py = x + 0.5, y + 0.5
            w0 = ((x1 - px) * (y2 - py) - (x2 - px) * (y1 - py)) / area
            w1 = ((x2 - px) * (y0 - py) - (x0 - px) * (y2 - py)) / area
            w2 = 1.0 - w0 - w1
            if w0 < -0.002 or w1 < -0.002 or w2 < -0.002:
                continue
            nearest = f0 if w0 >= w1 and w0 >= w2 else (f1 if w1 >= w2 else f2)
            along = w0 * f0[1] + w1 * f1[1] + w2 * f2[1]
            back = w0 * f0[2] + w1 * f1[2] + w2 * f2[2]
            across = w0 * f0[3] + w1 * f1[3] + w2 * f2[3]
            put(x, y, (nearest[0], along, back, across))


def _dilate(pixels, painted, rounds=4):
    """Spreads the map a few texels past the edge of every island, so that filtering at
    the seams does not sample empty space and leave a rim of the wrong part."""
    for _ in range(rounds):
        additions = []
        for y in range(SIZE):
            for x in range(SIZE):
                if painted[y * SIZE + x]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < SIZE and 0 <= ny < SIZE and painted[ny * SIZE + nx]:
                        at = (ny * SIZE + nx) * 4
                        additions.append((x, y, pixels[at], pixels[at + 1], pixels[at + 2], pixels[at + 3]))
                        break
        for x, y, r, g, b, a in additions:
            at = (y * SIZE + x) * 4
            pixels[at], pixels[at + 1], pixels[at + 2], pixels[at + 3] = r, g, b, a
            painted[y * SIZE + x] = True


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bake(argv[0] if argv else "footballer")
