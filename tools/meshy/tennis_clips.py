"""The tennis animations, written against the same Meshy rig.

Everything in `badminton_clips` about the rig applies here unchanged — world-axis
rotations in degrees, a T-pose to depart from, and `lean()` rather than a spine bend.

    +Z is up          -Y is the way they are facing        +X is their left

    RightArm      +Y raises overhead,  -Y drops to the hip
                  +Z swings forward,   -Z swings back behind
    LeftArm       -Y raises overhead,  +Y drops to the hip
    RightForeArm  +Z bends the elbow,  LeftForeArm  -Z bends the elbow
    UpLeg         -X swings the leg forward, +X back
    Leg           +X bends the knee

Real numbers, copied rather than guessed — the volleyball file learned this the hard
way and produced six poses of a man with his hands by his hips:

    arm straight overhead     RightArm (0,  94, -32)   LeftArm (0, -72, -14)
    arm hanging at the hip    RightArm (0, -72, -38)   LeftArm (0,  28, -58)
    arm horizontal, forward   Z near +/-80, Y near +/-30

**Why tennis needs its own serve at all.** It was played with the badminton smash, and
the two actions have almost nothing in common. A badminton smash is a short, flat,
wristy strike from a square stance. A tennis serve is the slowest and largest movement
in any of these four sports: the ball is thrown up by the *other* hand, the racket drops
behind the back, the body coils and uncoils, and contact happens at full stretch above
the head with both feet off the ground. It is also the only shot in tennis the umpire
watches from start to finish, because a foot fault happens at the beginning of it and
a let happens at the end.

Every clip here is prefixed `tn_`, so that three sports can share one character without
arguing over the word "serve" — which all three of them have and mean differently.
"""

from badminton_clips import MOVE, lean

FPS = 24


def _with(base, **changes):
    pose = dict(base)
    pose.update(changes)
    return pose


def _moved(pose, up):
    """Lifts the whole body off the ground, for the one key that leaves it.

    MOVE cannot go through `_with` as a keyword. It is the string "@move", so
    `_with(pose, MOVE=...)` keys a *bone* called "MOVE" — and Blender raises on a bone
    that does not exist, which is the only reason this was caught. The volleyball file
    carries the same warning and this file's author read it and did it anyway.
    """
    lifted = dict(pose)
    lifted[MOVE] = (0.0, 0.0, up)
    return lifted


# How a server stands before anything happens: side-on to the baseline, weight on the
# back foot, racket held out in front at waist height with the ball resting against the
# strings. Square-on would be wrong — a tennis serve begins turned away from the court,
# which is what lets the shoulders uncoil into it.
READY = lean({
    "Spine02": (4, 0, 0),
    "Spine": (3, 0, 0),
    "LeftUpLeg": (-8, 0, -6),
    "LeftLeg": (16, 0, 0),
    "RightUpLeg": (-6, 0, 6),
    "RightLeg": (14, 0, 0),
    # Both hands together in front, holding ball and racket.
    "LeftArm": (0, 30, -70),
    "LeftForeArm": (0, 0, -74),
    "RightArm": (0, -30, 70),
    "RightForeArm": (0, 0, 74),
    "neck": (-4, 0, 0),
}, 8)


CLIPS = {
    # --- the serve ---------------------------------------------------------------
    #
    # Five keys, because a serve is five distinct shapes and anybody who has watched
    # tennis knows all of them:
    #
    #   the stance      side-on, ball against the strings
    #   the toss        left arm straight up, ball released, racket starting back
    #   the trophy      left arm still up, racket dropped behind the head, elbow high
    #   contact         full extension, both arms overhead, up on the toes
    #   follow-through  racket swung down and across the body
    #
    # It is deliberately slow. At 24 fps this runs a second and a half, against the
    # badminton smash's three quarters — the serve is the one shot in this game the
    # umpire is meant to have time to look at, because the foot fault is in the first
    # key and the net cord is in the fourth.
    "tn_serve": {
        "loop": False,
        "keys": [
            (0, READY),
            # The toss. The left arm goes straight up and stays there — a tennis player
            # holds the tossing arm up long after the ball has left it, and dropping it
            # early is the single most obvious way to make a serve look wrong.
            (8, _with(READY,
                      LeftArm=(0, -72, -14), LeftForeArm=(0, 0, -8),
                      RightArm=(0, -56, 30), RightForeArm=(0, 0, 40),
                      Spine02=(-4, 0, 0), neck=(-16, 0, 0))),
            # The trophy. Racket hand behind the head, elbow up and out, knees bent,
            # back arched. The pose every photograph of a serve is taken at.
            #
            # The upper arm has to be nearly overhead AND swung back, not out to the
            # side. The first attempt at this used (0, 34, -58) and produced a man
            # holding his racket out sideways like a man showing somebody a racket —
            # rendered, looked at, and corrected, which is the only way these numbers
            # ever come out right.
            (16, _with(READY,
                       LeftArm=(0, -76, -10), LeftForeArm=(0, 0, -6),
                       RightArm=(0, 66, -84), RightForeArm=(0, 0, 124),
                       Spine02=(-12, 0, 0), Spine=(-6, 0, 0),
                       LeftLeg=(38, 0, 0), RightLeg=(36, 0, 0),
                       neck=(-20, 0, 0))),
            # Contact, at full stretch and off the ground. Both legs straighten, the
            # tossing arm has begun to come down, and the racket arm is as long as it
            # gets — a serve struck with a bent elbow is a serve nobody would hit.
            (22, _moved(_with(READY,
                       LeftArm=(0, -40, -34), LeftForeArm=(0, 0, -30),
                       RightArm=(0, 94, -32), RightForeArm=(0, 0, 6),
                       Spine02=(6, 0, 0),
                       LeftLeg=(6, 0, 0), RightLeg=(4, 0, 0),
                       LeftUpLeg=(-4, 0, -6), RightUpLeg=(-2, 0, 6),
                       neck=(-14, 0, 0)), 0.12)),
            # Down and across. The racket finishes past the opposite hip, which is what
            # makes the whole thing read as one movement rather than a chop.
            (36, _with(READY,
                       LeftArm=(0, 22, -60), LeftForeArm=(0, 0, -48),
                       RightArm=(0, -78, -30), RightForeArm=(0, 0, 54),
                       Spine02=(14, 0, 0), Spine=(6, 0, 0),
                       LeftLeg=(30, 0, 0), RightLeg=(28, 0, 0),
                       neck=(2, 0, 0))),
        ],
    },
}
