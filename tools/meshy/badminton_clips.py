"""The badminton animations, written against the Meshy rig.

A pose is a dictionary of bone name to three rotations in degrees, and the rotations
are about the *world* axes rather than the bone's own. That is deliberate. Meshy's
characters arrive through glTF, which has no concept of a bone tail, so Blender guesses
one — and every bone in this rig came in over a thousand units long pointing somewhere
arbitrary. Bone-local euler angles on a rig like that are unguessable. World axes are
not, because the character stands in a known orientation:

    +Z is up          -Y is the way they are facing        +X is their left

The character is generated in a T-pose, so every arm angle here is a departure from
straight out sideways, not from hanging at the side. That catches you out: an arm at
rest by the hip is a large rotation, not a small one. The two arms are mirror images,
so their signs are opposite:

    RightArm      +Y raises overhead,  -Y drops to the hip
                  +Z swings forward,   -Z swings back behind
    LeftArm       -Y raises overhead,  +Y drops to the hip
                  -Z swings forward,   +Z swings back behind
    RightForeArm  +Z bends the elbow,  LeftForeArm  -Z bends the elbow

Elbows bend about the arm's own rest frame, which is carried along by the shoulder, so
"bend the elbow" means the same thing whether the arm is overhead or by the hip.

Below the waist both sides share signs, because a hip and a knee only fold one way:

    UpLeg    -X swings the leg forward, +X back
    Leg      +X bends the knee
    Spine    +X leans the body forward

Frames are at 24 fps. `loop` marks the clips that repeat rather than play once; the
game reads that list too, so a clip only has to be described in one place.
"""

FPS = 24

## A pose entry under this key is not a bone but a shift of the whole body, in metres,
## along the world axes. Only the lunge and the celebration need it.
MOVE = "@move"

# Bones that exist on the Meshy rig, for the sanity check in the forge. A misspelled
# bone name is otherwise silent: the pose simply does not happen and the character
# plays the shot with one arm.
BONES = [
    "Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
    "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
    "Spine02", "Spine01", "Spine",
    "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
    "RightShoulder", "RightArm", "RightForeArm", "RightHand",
    "neck", "Head",
]

def lean(pose, degrees):
    """Leans the whole body forward from the ankles, keeping the feet on the floor.

    The obvious way to lean somebody forward is to bend their spine, and on this rig it
    barely works. Meshy's auto-rigging puts the torso almost entirely on the hip bone
    and the neck — the three spine bones between them carry 418 units of weight against
    the hips' 601 — so a forty-degree bend at the waist moves a sliver of shirt and
    leaves the player standing upright.

    Rotating the hips does move the whole body, but it takes the legs with it and lifts
    the feet off the floor. So the hips turn and both thighs turn back by the same
    amount, which cancels at the knee and leaves a body leaning over planted feet.
    """
    tilted = dict(pose)
    tilted["Hips"] = _add(tilted.get("Hips"), (degrees, 0, 0))
    for thigh in ("LeftUpLeg", "RightUpLeg"):
        tilted[thigh] = _add(tilted.get(thigh), (-degrees, 0, 0))
    return tilted


def _add(existing, extra):
    if existing is None:
        return extra
    return tuple(a + b for a, b in zip(existing, extra))


# The stance everything else is a departure from: knees soft, racket up in front,
# weight forward. A badminton player at rest is not standing still, they are waiting.
READY = lean({
    "Spine02": (6, 0, 0),
    "Spine": (4, 0, 0),
    "LeftUpLeg": (-12, 0, -4),
    "LeftLeg": (26, 0, 0),
    "RightUpLeg": (-12, 0, 4),
    "RightLeg": (26, 0, 0),
    "LeftArm": (0, 52, -30),
    "LeftForeArm": (0, 0, -62),
    "RightArm": (0, -48, 34),
    "RightForeArm": (0, 0, 72),
}, 12)


# Standing still with the arms down, which nobody on a badminton court does during a rally
# and everybody does before and after one. The ready stance is a crouch with a racket up;
# an umpire walking on in it looks like they are about to receive serve.
STAND = {
    "LeftUpLeg": (-2, 0, -2), "LeftLeg": (3, 0, 0),
    "RightUpLeg": (-2, 0, 2), "RightLeg": (3, 0, 0),
    "LeftArm": (0, 76, -6), "LeftForeArm": (0, 0, -14),
    "RightArm": (0, -76, 6), "RightForeArm": (0, 0, 14),
}

# The line judges' chair pose, which the umpire's high chair borrows at the end of a match.
SEATED = {
    MOVE: (0.0, 0.0, -0.44),
    "Spine02": (6, 0, 0),
    "LeftUpLeg": (-84, 0, -7), "LeftLeg": (82, 0, 0), "LeftFoot": (-4, 0, 0),
    "RightUpLeg": (-84, 0, 7), "RightLeg": (82, 0, 0), "RightFoot": (-4, 0, 0),
    "LeftArm": (0, 74, -16), "LeftForeArm": (0, 0, -54),
    "RightArm": (0, -72, 18), "RightForeArm": (0, 0, 56),
}


def _with(base, **changes):
    """A pose described as a departure from another one, which is how a shot is
    actually played — everything below the waist stays where it was."""
    pose = dict(base)
    pose.update(changes)
    return pose


def _moved(pose, shift):
    """A pose with the whole body shifted. `MOVE` is not a bone, so it cannot go
    through `_with`'s keyword arguments."""
    posed = dict(pose)
    posed[MOVE] = shift
    return posed


CLIPS = {
    # --- the ones that repeat ---------------------------------------------------
    "idle": {
        "loop": True,
        "keys": [
            (0, _with(READY, LeftUpLeg=(-8, 0, -4), RightUpLeg=(-8, 0, 4),
                      LeftLeg=(16, 0, 0), RightLeg=(16, 0, 0), Spine02=(6, 0, 0),
                      LeftArm=(0, 70, -18), LeftForeArm=(0, 0, -40),
                      RightArm=(0, -66, 22), RightForeArm=(0, 0, 48))),
            (14, _with(READY, LeftUpLeg=(-12, 0, -4), RightUpLeg=(-12, 0, 4),
                       LeftLeg=(26, 0, 0), RightLeg=(26, 0, 0), Spine02=(9, 0, 0),
                       LeftArm=(0, 74, -16), LeftForeArm=(0, 0, -36),
                       RightArm=(0, -70, 20), RightForeArm=(0, 0, 44))),
            (28, _with(READY, LeftUpLeg=(-8, 0, -4), RightUpLeg=(-8, 0, 4),
                       LeftLeg=(16, 0, 0), RightLeg=(16, 0, 0), Spine02=(6, 0, 0),
                       LeftArm=(0, 70, -18), LeftForeArm=(0, 0, -40),
                       RightArm=(0, -66, 22), RightForeArm=(0, 0, 48))),
        ],
    },
    "ready": {
        "loop": True,
        "keys": [
            (0, READY),
            (10, _with(READY, Spine02=(14, 0, 0),
                       LeftLeg=(34, 0, 0), RightLeg=(34, 0, 0),
                       RightArm=(0, -42, 38), RightForeArm=(0, 0, 78))),
            (20, READY),
        ],
    },
    # --- going backwards and sideways without turning your back ------------------
    #
    # Nobody in a net sport turns round and runs at a ball that is behind them. The
    # ball is in front of you and your eyes stay on it, so you go back on your toes
    # with your chest square to the net and you go across on a chassé. Turning to
    # sprint is how you leave the court, not how you play a shot.
    #
    # Both are deliberately symmetrical left to right, because the game plays the same
    # clip whichever way the player is going and only turns their shoulders into it.
    # See `Player.FOOTWORK`.

    # Backwards: short strides, the knee coming through low, the trailing foot pushing
    # off its toe, and the weight back behind the hips. A long backwards stride puts
    # you on the floor, which is why a real one is barely half a forward one.
    "backpedal": {
        "loop": True,
        "keys": [
            (0, lean(_with(READY,
                           RightUpLeg=(26, 0, 6), RightLeg=(16, 0, 0), RightFoot=(-24, 0, 0),
                           LeftUpLeg=(-12, 0, -4), LeftLeg=(48, 0, 0),
                           Spine02=(2, 0, 0),
                           RightArm=(0, -44, 18), RightForeArm=(0, 0, 70),
                           LeftArm=(0, 50, -44), LeftForeArm=(0, 0, -58)), -7)),
            (5, lean(_with(READY,
                           RightUpLeg=(4, 0, 6), RightLeg=(34, 0, 0), RightFoot=(-10, 0, 0),
                           LeftUpLeg=(4, 0, -6), LeftLeg=(34, 0, 0), LeftFoot=(-10, 0, 0),
                           Spine02=(4, 0, 0),
                           RightArm=(0, -48, 34), RightForeArm=(0, 0, 74),
                           LeftArm=(0, 52, -34), LeftForeArm=(0, 0, -64)), -5)),
            (10, lean(_with(READY,
                            LeftUpLeg=(26, 0, -6), LeftLeg=(16, 0, 0), LeftFoot=(-24, 0, 0),
                            RightUpLeg=(-12, 0, 4), RightLeg=(48, 0, 0),
                            Spine02=(2, 0, 0),
                            RightArm=(0, -50, 44), RightForeArm=(0, 0, 78),
                            LeftArm=(0, 46, -22), LeftForeArm=(0, 0, -52)), -7)),
            (15, lean(_with(READY,
                            RightUpLeg=(4, 0, 6), RightLeg=(34, 0, 0), RightFoot=(-10, 0, 0),
                            LeftUpLeg=(4, 0, -6), LeftLeg=(34, 0, 0), LeftFoot=(-10, 0, 0),
                            Spine02=(4, 0, 0),
                            RightArm=(0, -48, 34), RightForeArm=(0, 0, 74),
                            LeftArm=(0, 52, -34), LeftForeArm=(0, 0, -64)), -5)),
            (20, lean(_with(READY,
                            RightUpLeg=(26, 0, 6), RightLeg=(16, 0, 0), RightFoot=(-24, 0, 0),
                            LeftUpLeg=(-12, 0, -4), LeftLeg=(48, 0, 0),
                            Spine02=(2, 0, 0),
                            RightArm=(0, -44, 18), RightForeArm=(0, 0, 70),
                            LeftArm=(0, 50, -44), LeftForeArm=(0, 0, -58)), -7)),
        ],
    },
    # Sideways: the chassé. The feet come wide apart and snap back together, and the
    # body drops as they spread and rises as they close, which is the whole of what a
    # shuffle looks like from the chair. Feet never cross.
    "shuffle": {
        "loop": True,
        "keys": [
            (0, lean(_moved(_with(READY,
                           LeftUpLeg=(-6, 0, -17), LeftLeg=(30, 0, 0),
                           RightUpLeg=(-6, 0, 17), RightLeg=(30, 0, 0),
                           LeftArm=(0, 46, -36), LeftForeArm=(0, 0, -58),
                           RightArm=(0, -42, 40), RightForeArm=(0, 0, 66)),
                        (0.0, 0.0, -0.06)), 12)),
            (4, lean(_moved(_with(READY,
                           LeftUpLeg=(-10, 0, -3), LeftLeg=(16, 0, 0),
                           RightUpLeg=(-10, 0, 3), RightLeg=(16, 0, 0),
                           LeftArm=(0, 50, -30), LeftForeArm=(0, 0, -52),
                           RightArm=(0, -46, 34), RightForeArm=(0, 0, 60)),
                        (0.0, 0.0, 0.03)), 8)),
            (8, lean(_moved(_with(READY,
                           LeftUpLeg=(-6, 0, -17), LeftLeg=(30, 0, 0),
                           RightUpLeg=(-6, 0, 17), RightLeg=(30, 0, 0),
                           LeftArm=(0, 46, -36), LeftForeArm=(0, 0, -58),
                           RightArm=(0, -42, 40), RightForeArm=(0, 0, 66)),
                        (0.0, 0.0, -0.06)), 12)),
            (12, lean(_moved(_with(READY,
                           LeftUpLeg=(-10, 0, -3), LeftLeg=(16, 0, 0),
                           RightUpLeg=(-10, 0, 3), RightLeg=(16, 0, 0),
                           LeftArm=(0, 50, -30), LeftForeArm=(0, 0, -52),
                           RightArm=(0, -46, 34), RightForeArm=(0, 0, 60)),
                        (0.0, 0.0, 0.03)), 8)),
            (16, lean(_moved(_with(READY,
                           LeftUpLeg=(-6, 0, -17), LeftLeg=(30, 0, 0),
                           RightUpLeg=(-6, 0, 17), RightLeg=(30, 0, 0),
                           LeftArm=(0, 46, -36), LeftForeArm=(0, 0, -58),
                           RightArm=(0, -42, 40), RightForeArm=(0, 0, 66)),
                        (0.0, 0.0, -0.06)), 12)),
        ],
    },
    # Bent double with hands on the knees, between rallies in a long third game.
    "tired": {
        "loop": True,
        "keys": [
            (0, lean({
                "Spine02": (16, 0, 0), "Spine01": (8, 0, 0), "Spine": (-14, 0, 0),
                "neck": (-16, 0, 0),
                "LeftUpLeg": (-6, 0, -6), "LeftLeg": (22, 0, 0),
                "RightUpLeg": (-6, 0, 6), "RightLeg": (22, 0, 0),
                "LeftArm": (0, 58, -52), "LeftForeArm": (0, 0, -48),
                "RightArm": (0, -56, 52), "RightForeArm": (0, 0, 48),
            }, 46)),
            (18, lean({
                "Spine02": (18, 0, 0), "Spine01": (9, 0, 0), "Spine": (-16, 0, 0),
                "neck": (-18, 0, 0),
                "LeftUpLeg": (-6, 0, -6), "LeftLeg": (26, 0, 0),
                "RightUpLeg": (-6, 0, 6), "RightLeg": (26, 0, 0),
                "LeftArm": (0, 62, -50), "LeftForeArm": (0, 0, -44),
                "RightArm": (0, -60, 50), "RightForeArm": (0, 0, 44),
            }, 51)),
            (36, lean({
                "Spine02": (16, 0, 0), "Spine01": (8, 0, 0), "Spine": (-14, 0, 0),
                "neck": (-16, 0, 0),
                "LeftUpLeg": (-6, 0, -6), "LeftLeg": (22, 0, 0),
                "RightUpLeg": (-6, 0, 6), "RightLeg": (22, 0, 0),
                "LeftArm": (0, 58, -52), "LeftForeArm": (0, 0, -48),
                "RightArm": (0, -56, 52), "RightForeArm": (0, 0, 48),
            }, 46)),
        ],
    },
    # Both palms up at the umpire. The one time anybody looks at the chair.
    "argue": {
        "loop": True,
        "keys": [
            (0, lean(_with(READY, LeftArm=(0, 38, -48), LeftForeArm=(0, 0, -78),
                           RightArm=(0, -36, 50), RightForeArm=(0, 0, 78),
                           neck=(-10, 0, 0)), -16)),
            (16, lean(_with(READY, LeftArm=(0, 26, -58), LeftForeArm=(0, 0, -86),
                            RightArm=(0, -24, 60), RightForeArm=(0, 0, 86),
                            neck=(-16, 0, 0)), -22)),
            (32, lean(_with(READY, LeftArm=(0, 38, -48), LeftForeArm=(0, 0, -78),
                            RightArm=(0, -36, 50), RightForeArm=(0, 0, 78),
                            neck=(-10, 0, 0)), -16)),
        ],
    },

    # A nod towards the chair.
    #
    # Deliberately not the celebration, and it took a decision to keep them apart. This
    # is a player acknowledging that the official got one right after a bad patch, which
    # in this game is a rarer event than winning a point and has to read as a smaller,
    # quieter thing than one — reusing `celebrate` would have looked like they were
    # cheering the rally rather than the chair.
    #
    # The **arm** is the gesture and the head is the second half of it. Rendered side by
    # side, a version built the other way round — two head dips and the hand where it
    # already was — was almost invisible: a nod is a few degrees of neck on a figure the
    # umpire is watching from several metres away, and the spine cannot help, because
    # Meshy's rig puts almost no weight on it (see `lean`). Raising the bat towards the
    # chair is also simply what players do.
    "nod": {
        "loop": False,
        "keys": [
            (0, READY),
            # Bat coming up, head starting down.
            (6, _with(READY, neck=(14, 0, 0),
                      RightArm=(0, -18, 52), RightForeArm=(0, 0, 64))),
            # Held up towards the chair, head level again.
            (13, _with(READY, neck=(2, 0, 0),
                       RightArm=(0, 4, 58), RightForeArm=(0, 0, 58))),
            (20, _with(READY, neck=(18, 0, 0),
                       RightArm=(0, 2, 57), RightForeArm=(0, 0, 60))),
            # And down.
            (28, _with(READY, neck=(6, 0, 0),
                       RightArm=(0, -26, 46), RightForeArm=(0, 0, 66))),
            (38, READY),
        ],
    },

    # The line judges sit in their corner for the whole match, which is the one thing
    # they do that no player ever does. Same rig, same file, so they get the clip too.
    "sit": {
        "loop": True,
        "keys": [
            (0, {
                MOVE: (0.0, 0.0, -0.44),
                "Spine02": (6, 0, 0),
                "LeftUpLeg": (-84, 0, -7), "LeftLeg": (82, 0, 0), "LeftFoot": (-4, 0, 0),
                "RightUpLeg": (-84, 0, 7), "RightLeg": (82, 0, 0), "RightFoot": (-4, 0, 0),
                "LeftArm": (0, 74, -16), "LeftForeArm": (0, 0, -54),
                "RightArm": (0, -72, 18), "RightForeArm": (0, 0, 56),
            }),
            (30, {
                MOVE: (0.0, 0.0, -0.44),
                "Spine02": (9, 0, 0),
                "LeftUpLeg": (-84, 0, -7), "LeftLeg": (82, 0, 0), "LeftFoot": (-4, 0, 0),
                "RightUpLeg": (-84, 0, 7), "RightLeg": (82, 0, 0), "RightFoot": (-4, 0, 0),
                "LeftArm": (0, 76, -14), "LeftForeArm": (0, 0, -50),
                "RightArm": (0, -74, 16), "RightForeArm": (0, 0, 52),
            }),
            (60, {
                MOVE: (0.0, 0.0, -0.44),
                "Spine02": (6, 0, 0),
                "LeftUpLeg": (-84, 0, -7), "LeftLeg": (82, 0, 0), "LeftFoot": (-4, 0, 0),
                "RightUpLeg": (-84, 0, 7), "RightLeg": (82, 0, 0), "RightFoot": (-4, 0, 0),
                "LeftArm": (0, 74, -16), "LeftForeArm": (0, 0, -54),
                "RightArm": (0, -72, 18), "RightForeArm": (0, 0, 56),
            }),
        ],
    },

    # --- the shots, played once -------------------------------------------------
    # Wind up, contact overhead, follow through down across the body. The non-racket
    # arm points up at the shuttle, which is the thing that makes a badminton smash
    # look like badminton and not like a serve at tennis.
    "smash": {
        "loop": False,
        "keys": [
            (0, lean(_with(READY, RightArm=(0, 94, -32), RightForeArm=(0, 0, -78),
                           LeftArm=(0, -72, -14), LeftForeArm=(0, 0, -8),
                           Spine01=(-8, 0, 0)), -26)),
            (6, lean(_with(READY, RightArm=(0, 90, 24), RightForeArm=(0, 0, -6),
                           LeftArm=(0, -30, 24), LeftForeArm=(0, 0, -32)), 6)),
            (18, lean(_with(READY, RightArm=(0, -26, 72), RightForeArm=(0, 0, 46),
                            LeftArm=(0, 24, 34), LeftForeArm=(0, 0, -52)), 22)),
        ],
    },
    "forehand": {
        "loop": False,
        "keys": [
            (0, _with(READY, RightArm=(0, -22, -62), RightForeArm=(0, 0, 54),
                      Spine02=(8, 0, -12))),
            (6, _with(READY, RightArm=(0, 8, 32), RightForeArm=(0, 0, 14),
                      Spine02=(12, 0, 8))),
            (16, _with(READY, RightArm=(0, -14, 86), RightForeArm=(0, 0, 58),
                       Spine02=(14, 0, 14))),
        ],
    },
    "backhand": {
        "loop": False,
        "keys": [
            (0, _with(READY, RightArm=(0, -18, 82), RightForeArm=(0, 0, 88),
                      Spine02=(8, 0, 16))),
            (6, _with(READY, RightArm=(0, 12, 22), RightForeArm=(0, 0, 26),
                      Spine02=(10, 0, -4))),
            (16, _with(READY, RightArm=(0, 20, -42), RightForeArm=(0, 0, 10),
                       Spine02=(8, 0, -12))),
        ],
    },
    # Underarm and below the waist, because in badminton it has to be.
    "serve": {
        "loop": False,
        "keys": [
            (0, _with(READY, RightArm=(0, -72, -38), RightForeArm=(0, 0, 46),
                      LeftArm=(0, 28, -58), LeftForeArm=(0, 0, -18),
                      Spine02=(6, 0, 0))),
            (8, _with(READY, RightArm=(0, -64, 18), RightForeArm=(0, 0, 22),
                      LeftArm=(0, 34, -44), LeftForeArm=(0, 0, -24))),
            (20, _with(READY, RightArm=(0, -30, 62), RightForeArm=(0, 0, 52),
                       LeftArm=(0, 48, -24), LeftForeArm=(0, 0, -34))),
        ],
    },
    # A long step onto the front foot with the racket at full stretch. This is how a
    # player reaches a net shot, and it is the single most recognisable badminton shape.
    "lunge": {
        "loop": False,
        "keys": [
            (0, READY),
            # These numbers are measured rather than judged. A lunge only reads as one
            # if both feet are on the floor, and by eye it is impossible to tell a
            # planted front foot from one hanging four centimetres above the court. The
            # foot heights were swept against the rig until the front foot landed flat
            # and the back one trailed on its toe with the heel up, which is what the
            # shot actually looks like.
            (8, {
                MOVE: (0.0, -0.24, -0.20),
                "Hips": (18, 0, 0),
                "Spine02": (10, 0, 0), "Spine01": (6, 0, 0),
                "RightUpLeg": (-74, 0, 6), "RightLeg": (64, 0, 0),
                "RightFoot": (-18, 0, 0),
                "LeftUpLeg": (10, 0, -8), "LeftLeg": (30, 0, 0),
                "LeftFoot": (-40, 0, 0),
                "RightArm": (0, -22, 86), "RightForeArm": (0, 0, 12),
                "LeftArm": (0, 34, 62), "LeftForeArm": (0, 0, -26),
            }),
            (24, READY),
        ],
    },
    "celebrate": {
        "loop": False,
        "keys": [
            (0, READY),
            (8, lean(_with(READY, **{MOVE: (0.0, 0.0, 0.12)},
                           RightArm=(0, 104, 8), RightForeArm=(0, 0, -22),
                           LeftArm=(0, -104, -8), LeftForeArm=(0, 0, 22),
                           neck=(-14, 0, 0),
                           LeftLeg=(14, 0, 0), RightLeg=(14, 0, 0)), -26)),
            (20, lean(_with(READY, RightArm=(0, 88, 18), RightForeArm=(0, 0, -46),
                            LeftArm=(0, -88, -18), LeftForeArm=(0, 0, 46),
                            neck=(-8, 0, 0)), -20)),
            (34, READY),
        ],
    },

    # --- the ceremony, before and after the match -------------------------------
    # The cutscenes' clips. Officials use all of them; players use the handshake.
    "stand": {
        "loop": True,
        "keys": [
            (0, STAND),
            (30, _with(STAND, Spine02=(2, 0, 0), neck=(2, 0, 0))),
            (60, STAND),
        ],
    },
    # Right hand out at waist height and two pumps. The forearm does the pumping: the
    # upper arm stays where it is, which is what keeps a handshake from looking like a
    # wave.
    "handshake": {
        "loop": False,
        "keys": [
            (0, STAND),
            (8, _with(STAND, neck=(8, 0, 0),
                      RightArm=(0, -42, 76), RightForeArm=(0, 0, 22))),
            (12, _with(STAND, neck=(8, 0, 0),
                       RightArm=(0, -42, 76), RightForeArm=(0, 0, 38))),
            (16, _with(STAND, neck=(8, 0, 0),
                       RightArm=(0, -42, 76), RightForeArm=(0, 0, 18))),
            (20, _with(STAND, neck=(8, 0, 0),
                       RightArm=(0, -42, 76), RightForeArm=(0, 0, 36))),
            (24, _with(STAND, neck=(6, 0, 0),
                       RightArm=(0, -42, 76), RightForeArm=(0, 0, 22))),
            (34, STAND),
        ],
    },
    # The same from the umpire's high chair: leaning out and reaching down to a player
    # stood below, which is how a real umpire shakes hands at the end of a match — from
    # the chair, before the result is announced (BWF ITTO 5.6.5).
    "sit_handshake": {
        "loop": False,
        "keys": [
            (0, SEATED),
            (8, _with(SEATED, Spine02=(18, 0, 0), neck=(16, 0, 0),
                      RightArm=(0, 2, 104), RightForeArm=(0, 0, 10))),
            (12, _with(SEATED, Spine02=(18, 0, 0), neck=(16, 0, 0),
                       RightArm=(0, 2, 104), RightForeArm=(0, 0, 26))),
            (16, _with(SEATED, Spine02=(18, 0, 0), neck=(16, 0, 0),
                       RightArm=(0, 2, 104), RightForeArm=(0, 0, 6))),
            (20, _with(SEATED, Spine02=(18, 0, 0), neck=(16, 0, 0),
                       RightArm=(0, 2, 104), RightForeArm=(0, 0, 24))),
            (24, _with(SEATED, Spine02=(16, 0, 0), neck=(14, 0, 0),
                       RightArm=(0, 2, 104), RightForeArm=(0, 0, 10))),
            (34, SEATED),
        ],
    },
    # The toss. Coin at the chest, flicked up with the head following it, caught, and held
    # out for both sides to see. The coin itself is not on the rig — the cutscene flies it
    # from the hand at the flick (frame 12) and back into it at the catch (frame 28).
    "coin_toss": {
        "loop": False,
        "keys": [
            (0, STAND),
            (8, _with(STAND, neck=(12, 0, 0),
                      RightArm=(0, -62, 40), RightForeArm=(0, 0, 96))),
            (12, _with(STAND, neck=(-12, 0, 0),
                       RightArm=(0, -36, 62), RightForeArm=(0, 0, 104))),
            (22, _with(STAND, neck=(-16, 0, 0),
                       RightArm=(0, -60, 44), RightForeArm=(0, 0, 86))),
            (28, _with(STAND, neck=(12, 0, 0),
                       RightArm=(0, -62, 42), RightForeArm=(0, 0, 94))),
            (36, _with(STAND, neck=(8, 0, 0),
                       RightArm=(0, -40, 74), RightForeArm=(0, 0, 40))),
            (52, _with(STAND, neck=(8, 0, 0),
                       RightArm=(0, -40, 74), RightForeArm=(0, 0, 38))),
            (62, STAND),
        ],
    },
    # Arm straight out to the right and held: the tournament referee showing a removed
    # umpire the way off court.
    "point": {
        "loop": False,
        "keys": [
            (0, STAND),
            (10, _with(STAND, neck=(0, 0, 0),
                       RightArm=(0, -8, 16), RightForeArm=(0, 0, 4))),
            (44, _with(STAND, neck=(0, 0, 0),
                       RightArm=(0, -10, 16), RightForeArm=(0, 0, 6))),
            (56, STAND),
        ],
    },
}

LOOPING = sorted(name for name, clip in CLIPS.items() if clip["loop"])
