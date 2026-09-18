"""The sepak takraw animations, written against the same Meshy rig.

Everything in `badminton_clips` about the rig applies here unchanged — world-axis
rotations in degrees, a T-pose to depart from, and `lean()` rather than a spine bend.

    +Z is up          -Y is the way they are facing        +X is their left

    RightArm      +Y raises overhead,  -Y drops to the hip
                  +Z swings forward,   -Z swings back behind
    LeftArm       -Y raises overhead,  +Y drops to the hip
    RightForeArm  +Z bends the elbow,  LeftForeArm  -Z bends the elbow
    UpLeg         -X swings the leg forward, +X back
    Leg           +X bends the knee
    Foot          +X points the toes

Real numbers, copied rather than guessed:

    arm straight overhead     RightArm (0,  94, -32)   LeftArm (0, -72, -14)
    arm hanging at the hip    RightArm (0, -72, -38)   LeftArm (0,  28, -58)
    arm horizontal, forward   Z near +/-80, Y near +/-30

**What is different about this sport** is that the arms do nothing. The ball is played
with the feet, knees, chest and head, and touching it with an arm is a fault — so in every
clip but one the arms are held out to the sides for balance, which from the T-pose is only
a small drop. The one exception is the throw, where an inside player tosses the ball to the
server with both hands.

Everything happens on the right leg. The left is the one they stand on, and in the serve
that is the whole call: the tekong's standing foot must not leave the floor before the
kicking foot meets the ball (Law 11.1.4).

**Feet on the floor are measured, not judged.** A bent knee on this rig lifts the foot,
because everything turns about the hips and nothing pulls the body down after it. Every
key with a foot meant to be on the floor carries a MOVE that puts it back there — found by
posing the rig in Blender and reading the ankle's height against its rest height of
0.13 m, which is the only way a foot hovering four centimetres up can be seen at all.

Every clip here is prefixed `st_`, so that six sports can share one character without
arguing over the word "serve".
"""

import math

from badminton_clips import MOVE, lean

FPS = 24


def _with(base, **changes):
    pose = dict(base)
    pose.update(changes)
    return pose


def _moved(pose, up, forward=0.0):
    """Shifts the whole body: `up` off the floor (or down into it, for a bent knee), and
    `forward` the way they are facing.

    MOVE cannot go through `_with` as a keyword — it is the string "@move", and
    `_with(pose, MOVE=...)` keys a bone called "MOVE". The volleyball and tennis files
    both say so.
    """
    shifted = dict(pose)
    shifted[MOVE] = (0.0, -forward, up)
    return shifted


# --- the kicking thigh --------------------------------------------------------------
#
# A sepak sila — the inside-of-the-foot kick every receive and set is played with — is a
# thigh lifted forward, turned out at the hip so the knee points to the side, and swung
# a little outward. Turned out like that, the knee bends *across* the body, so the foot
# comes up in front of the standing leg with its inside facing the sky.
#
# That turn about the thigh's own length cannot be written as three world angles by eye,
# so it is built here from the three movements a coach would describe and converted into
# the angles the rig takes. For the right leg:
#
#     lift       how far the thigh comes up in front, 0 hanging to 90 horizontal
#     turn_out   how far the knee is turned out to the right, 0 to 90
#     swing      how far the lifted thigh then swings out to the right
#
# With turn_out at 90 the knee bends straight across towards the left leg.

def _rot(axis, degrees):
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    if axis == "X":
        return [[1, 0, 0], [0, c, -s], [0, s, c]]
    if axis == "Y":
        return [[c, 0, s], [0, 1, 0], [-s, 0, c]]
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


def _mul(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(3)) for c in range(3)] for r in range(3)]


def _right_thigh(lift, turn_out, swing=0.0):
    """The world angles for a right thigh lifted, turned out and swung. See above."""
    m = _mul(_rot("Z", -swing), _mul(_rot("X", -lift), _rot("Z", -turn_out)))
    # Back to the X-then-Y-then-Z world angles `pose_bone` builds its rotation from.
    y = math.degrees(math.asin(max(-1.0, min(1.0, -m[2][0]))))
    x = math.degrees(math.atan2(m[2][1], m[2][2]))
    z = math.degrees(math.atan2(m[1][0], m[0][0]))
    return (round(x, 1), round(y, 1), round(z, 1))


# Arms out to the sides and a little down, elbows soft. This is where a takraw player's
# arms are for almost the whole of a rally — not hanging, because the arms are the only
# balance a body standing on one leg has, and not up, because a raised arm near the ball
# is an arm the ball can hit.
_ARMS_OUT = {
    "LeftArm": (0, 34, -8),
    "LeftForeArm": (0, 0, -14),
    "RightArm": (0, -34, 8),
    "RightForeArm": (0, 0, 14),
}

# Wider and higher, for the moments a body is off balance: the kick at full height, the
# spike in the air.
_ARMS_WIDE = {
    "LeftArm": (0, 18, -10),
    "LeftForeArm": (0, 0, -12),
    "RightArm": (0, -18, 10),
    "RightForeArm": (0, 0, 12),
}


# How an inside player or the tekong stands before a touch: square on, knees soft, arms
# loosely out. Upright, because the ball arrives from above rather than off the floor.
STANCE = lean(_with(_ARMS_OUT, **{
    "LeftUpLeg": (-8, 0, -4),
    "LeftLeg": (14, 0, 0),
    "RightUpLeg": (-8, 0, 4),
    "RightLeg": (14, 0, 0),
    "Spine02": (4, 0, 0),
}), 4)


# The frame the kicking foot meets the ball in st_serve and st_spike. Player.ST_SERVE_CONTACT
# and Player.ST_SPIKE_CONTACT are these in seconds, and they must agree.
ST_SERVE_CONTACT_FRAME = 13
ST_SPIKE_CONTACT_FRAME = 14


# The blocker's arms: folded in against the chest, elbows down. The one thing they must
# not be is up.
_BLOCK_ARMS = {
    "LeftArm": (0, 60, -70),
    "LeftForeArm": (0, 0, -120),
    "RightArm": (0, -60, 70),
    "RightForeArm": (0, 0, 120),
}

# The top of the block, turned 170° to put their back to the net. See st_block.
_BLOCK_UP = _with(_BLOCK_ARMS, **{
    "Hips": (-16, 0, 170),
    "LeftUpLeg": (14, 0, -6), "LeftLeg": (70, 0, 0),
    "RightUpLeg": (14, 0, 6), "RightLeg": (70, 0, 0),
    "LeftFoot": (30, 0, 0), "RightFoot": (30, 0, 0),
    "Spine02": (-10, 0, 0), "neck": (-12, 0, 0),
})


CLIPS = {
    # --- starting it off ---------------------------------------------------------
    #
    # The tekong's power serve, the sepak kuda: struck with the top of the foot, toes
    # pointed, the leg swinging up in front from behind the body like a football
    # volley taken at chest height. The body falls back as the leg comes up, because
    # that is the only way a leg gets that high, and the arms go wide to hold it.
    #
    # The left foot does not move. Not an inch, and not up onto its toes — a standing
    # foot that leaves the floor before the kick lands is the fault the referee is
    # watching this clip for, so a clip that lifted it would be committing it.
    "st_serve": {
        "loop": False,
        "keys": [
            # In the circle, weight on the left foot, right foot a half step back.
            (0, _with(STANCE, RightUpLeg=(10, 0, 4), RightLeg=(16, 0, 0))),
            # The leg drawn back, knee bent, as the ball comes in from the thrower.
            (6, lean(_with(_ARMS_OUT,
                           LeftUpLeg=(-10, 0, -4), LeftLeg=(20, 0, 0),
                           RightUpLeg=(34, 0, 6), RightLeg=(70, 0, 0),
                           RightFoot=(30, 0, 0),
                           Spine02=(6, 0, 0)), 8)),
            # Swinging through, knee leading.
            (10, lean(_with(_ARMS_OUT,
                            LeftUpLeg=(-4, 0, -4), LeftLeg=(12, 0, 0),
                            RightUpLeg=(-70, 0, 6), RightLeg=(60, 0, 0),
                            RightFoot=(30, 0, 0),
                            neck=(6, 0, 0)), -8)),
            # Contact. Leg nearly straight and well above horizontal, toes pointed, the
            # body leaning back over a straight standing leg, arms wide.
            (ST_SERVE_CONTACT_FRAME, lean(_with(_ARMS_WIDE,
                            LeftUpLeg=(0, 0, -4), LeftLeg=(4, 0, 0),
                            RightUpLeg=(-122, 0, 6), RightLeg=(10, 0, 0),
                            RightFoot=(40, 0, 0),
                            Spine02=(-6, 0, 0), neck=(10, 0, 0)), -24)),
            # Follow-through: the leg carries on up and across towards the left.
            (18, lean(_with(_ARMS_WIDE,
                            LeftUpLeg=(0, 0, -4), LeftLeg=(6, 0, 0),
                            RightUpLeg=(-132, 0, 22), RightLeg=(16, 0, 0),
                            RightFoot=(30, 0, 0),
                            Spine02=(-8, 0, 0), neck=(8, 0, 0)), -28)),
            # Coming down in front.
            (26, _moved(lean(_with(_ARMS_OUT,
                            LeftUpLeg=(-4, 0, -4), LeftLeg=(14, 0, 0),
                            RightUpLeg=(-30, 0, 6), RightLeg=(30, 0, 0),
                            RightFoot=(10, 0, 0)), -4), 0.0, 0.04)),
            (36, STANCE),
        ],
    },

    # An inside player's toss to the tekong: both hands under the ball at the waist, a
    # dip of the knees, and a gentle lob out of the hands. The only clip in the sport
    # with hands on the ball, and the feet stay where they are — an inside player who
    # lifts a foot during the throw has committed a fault of their own.
    "st_throw": {
        "loop": False,
        "keys": [
            (0, _with(STANCE,
                      LeftArm=(0, 60, -66), LeftForeArm=(0, 0, -72),
                      RightArm=(0, -60, 66), RightForeArm=(0, 0, 72))),
            (7, _moved(lean(_with(STANCE,
                           LeftUpLeg=(-16, 0, -4), LeftLeg=(30, 0, 0),
                           RightUpLeg=(-16, 0, 4), RightLeg=(30, 0, 0),
                           LeftArm=(0, 64, -76), LeftForeArm=(0, 0, -40),
                           RightArm=(0, -64, 76), RightForeArm=(0, 0, 40)), 10), -0.03, 0.07)),
            # Release: arms swung up to chest height and straight, legs extended.
            (13, _moved(_with(STANCE,
                       LeftUpLeg=(-4, 0, -4), LeftLeg=(6, 0, 0),
                       RightUpLeg=(-4, 0, 4), RightLeg=(6, 0, 0),
                       LeftArm=(0, 8, -94), LeftForeArm=(0, 0, -8),
                       RightArm=(0, -8, 94), RightForeArm=(0, 0, 8),
                       neck=(-8, 0, 0)), 0.0, 0.05)),
            (20, _with(STANCE,
                       LeftArm=(0, -12, -92), LeftForeArm=(0, 0, -10),
                       RightArm=(0, 12, 92), RightForeArm=(0, 0, 10),
                       neck=(-10, 0, 0))),
            (32, STANCE),
        ],
    },

    # --- the first touch ---------------------------------------------------------
    #
    # Sepak sila: the inside of the foot, at knee height, knee turned out. Quick — the
    # ball is popped straight up for the next touch rather than swung at.
    "st_receive": {
        "loop": False,
        "keys": [
            (0, STANCE),
            (5, _moved(lean(_with(_ARMS_OUT,
                           LeftUpLeg=(-10, 0, -4), LeftLeg=(22, 0, 0),
                           RightUpLeg=_right_thigh(48, 80, 34), RightLeg=(92, 0, 0),
                           RightFoot=(-10, 0, 0)), 6), 0.0, 0.03)),
            (9, lean(_with(_ARMS_OUT,
                           LeftUpLeg=(-8, 0, -4), LeftLeg=(16, 0, 0),
                           RightUpLeg=_right_thigh(38, 70, 30), RightLeg=(84, 0, 0),
                           RightFoot=(-10, 0, 0)), 4)),
            (15, STANCE),
        ],
    },

    # A header: up onto the toes with a little hop, head back, then the forehead snaps
    # through the ball.
    "st_header": {
        "loop": False,
        "keys": [
            (0, STANCE),
            (4, _moved(lean(_with(STANCE,
                           LeftUpLeg=(-18, 0, -4), LeftLeg=(36, 0, 0),
                           RightUpLeg=(-18, 0, 4), RightLeg=(36, 0, 0),
                           neck=(-18, 0, 0), Spine02=(-8, 0, 0)), -6), -0.05, 0.05)),
            (8, _moved(_with(_ARMS_WIDE,
                             LeftUpLeg=(-2, 0, -4), LeftLeg=(4, 0, 0),
                             RightUpLeg=(-2, 0, 4), RightLeg=(4, 0, 0),
                             LeftFoot=(30, 0, 0), RightFoot=(30, 0, 0),
                             Spine02=(-10, 0, 0), neck=(-22, 0, 0)), 0.18)),
            # Contact: head through, chin down.
            (11, _moved(lean(_with(_ARMS_WIDE,
                                   LeftUpLeg=(-4, 0, -4), LeftLeg=(8, 0, 0),
                                   RightUpLeg=(-4, 0, 4), RightLeg=(8, 0, 0),
                                   LeftFoot=(24, 0, 0), RightFoot=(24, 0, 0),
                                   Spine02=(12, 0, 0), neck=(24, 0, 0)), 10), 0.14)),
            (16, STANCE),
        ],
    },

    # --- the second --------------------------------------------------------------
    #
    # The feeder's set near the net: the same sila as the receive, but the foot raised to
    # the waist and held there a beat, because the whole of a set is putting the ball
    # exactly where the killer wants it.
    "st_set": {
        "loop": False,
        "keys": [
            (0, STANCE),
            (6, lean(_with(_ARMS_OUT,
                           LeftUpLeg=(-8, 0, -4), LeftLeg=(18, 0, 0),
                           RightUpLeg=_right_thigh(84, 80, 30), RightLeg=(88, 0, 0),
                           RightFoot=(-10, 0, 0)), -4)),
            (10, lean(_with(_ARMS_OUT,
                            LeftUpLeg=(-4, 0, -4), LeftLeg=(10, 0, 0),
                            RightUpLeg=_right_thigh(98, 80, 28), RightLeg=(86, 0, 0),
                            RightFoot=(-10, 0, 0), neck=(-10, 0, 0)), -8)),
            (14, lean(_with(_ARMS_OUT,
                            LeftUpLeg=(-4, 0, -4), LeftLeg=(10, 0, 0),
                            RightUpLeg=_right_thigh(94, 80, 28), RightLeg=(88, 0, 0),
                            RightFoot=(-10, 0, 0), neck=(-14, 0, 0)), -8)),
            (22, STANCE),
        ],
    },

    # --- the third ---------------------------------------------------------------
    #
    # The roll spike. Off the left foot, the body tips back and rolls over to the left in
    # the air, and the right leg comes up and over the top to strike the ball above the
    # tape on the far side of the head. The kicking leg is almost straight at contact and
    # the body is closer to lying down than standing up.
    "st_spike": {
        "loop": False,
        "keys": [
            # The last step of the approach, into the left leg.
            (0, _moved(lean(_with(_ARMS_OUT,
                           LeftUpLeg=(-30, 0, -4), LeftLeg=(56, 0, 0),
                           RightUpLeg=(18, 0, 4), RightLeg=(40, 0, 0),
                           Spine02=(8, 0, 0)), 14), -0.10)),
            # Take-off: the left leg drives, straight, off its toes; the right swings up
            # bent.
            (4, _moved(_with(_ARMS_WIDE,
                             LeftUpLeg=(-4, 0, -4), LeftLeg=(6, 0, 0),
                             LeftFoot=(40, 0, 0),
                             RightUpLeg=(-60, 0, 4), RightLeg=(70, 0, 0),
                             Hips=(-8, 4, 0)), 0.10)),
            # Rising, tipping back, the left leg up first as the scissor starts.
            (10, _moved(_with(_ARMS_WIDE,
                              Hips=(-26, 14, 0),
                              LeftUpLeg=(-70, 0, -4), LeftLeg=(40, 0, 0),
                              RightUpLeg=(-50, 0, 4), RightLeg=(50, 0, 0),
                              neck=(-10, 0, 0)), 0.72)),
            # Contact at the top: the left leg scissored down, the right straight up and
            # over, body tipped back and rolled.
            (ST_SPIKE_CONTACT_FRAME, _moved(_with(_ARMS_WIDE,
                              Hips=(-40, 26, 0),
                              LeftUpLeg=(6, 0, -4), LeftLeg=(40, 0, 0),
                              RightUpLeg=(-112, 0, 10), RightLeg=(8, 0, 0),
                              RightFoot=(30, 0, 0),
                              neck=(-6, 0, 0)), 0.88)),
            # Through: the right leg sweeps down across, the roll carries on.
            (19, _moved(_with(_ARMS_WIDE,
                              Hips=(-26, 38, 0),
                              LeftUpLeg=(-10, 0, -4), LeftLeg=(30, 0, 0),
                              RightUpLeg=(-60, 0, 20), RightLeg=(20, 0, 0),
                              neck=(-6, 0, 0)), 0.55)),
            # Landing, knees taking it.
            (25, _moved(lean(_with(_ARMS_OUT,
                            LeftUpLeg=(-26, 0, -4), LeftLeg=(52, 0, 0),
                            RightUpLeg=(-26, 0, 4), RightLeg=(52, 0, 0),
                            Spine02=(10, 0, 0)), 16), -0.09, 0.04)),
            (36, STANCE),
        ],
    },

    # --- at the net --------------------------------------------------------------
    #
    # The block. A takraw blocker turns their back on the net and jumps, and it is the
    # back and the legs that meet the ball — so the body arches back over the tape, the
    # legs come up, and the arms are kept in against the chest. Never up: a hand raised to
    # block is a fault in this sport, and a blocker who puts one up has given the point
    # away.
    #
    # The turn is on the hips and stops short of a full half-turn, at 170°. A key at
    # exactly 180 has no preferred way round, and the curves between two keys either side
    # of it can take the long way and spin the body through a full circle.
    "st_block": {
        "loop": False,
        "keys": [
            (0, _moved(lean(_with(_ARMS_OUT,
                                  LeftUpLeg=(-24, 0, -4), LeftLeg=(46, 0, 0),
                                  RightUpLeg=(-24, 0, 4), RightLeg=(46, 0, 0)), 14), -0.07)),
            # Turning as they leave the floor.
            (4, _moved(_with(_BLOCK_ARMS, Hips=(0, 0, 90),
                             LeftUpLeg=(-10, 0, -4), LeftLeg=(20, 0, 0),
                             RightUpLeg=(-10, 0, 4), RightLeg=(20, 0, 0)), 0.26)),
            # Up, back to the net, and arched towards it: head back over the tape, heels
            # kicked up behind, arms folded in against the chest.
            (9, _moved(_BLOCK_UP, 0.6)),
            (14, _moved(_BLOCK_UP, 0.5)),
            # Down with their back still to the net...
            (20, _moved(_with(_ARMS_OUT, Hips=(0, 0, 170),
                              LeftUpLeg=(-24, 0, -4), LeftLeg=(46, 0, 0),
                              RightUpLeg=(-24, 0, 4), RightLeg=(46, 0, 0)), -0.07)),
            # ...and a small hop round to face it again, rather than the feet skating
            # round on the floor.
            (26, _moved(_with(_ARMS_OUT, Hips=(0, 0, 90),
                              LeftUpLeg=(-6, 0, -4), LeftLeg=(10, 0, 0),
                              RightUpLeg=(-6, 0, 4), RightLeg=(10, 0, 0),
                              LeftFoot=(30, 0, 0), RightFoot=(30, 0, 0)), 0.12)),
            (32, _moved(lean(_with(_ARMS_OUT,
                                   LeftUpLeg=(-20, 0, -4), LeftLeg=(40, 0, 0),
                                   RightUpLeg=(-20, 0, 4), RightLeg=(40, 0, 0)), 10), -0.05, 0.03)),
            (40, _moved(STANCE, 0.0)),
        ],
    },
}
