"""The football animations, written against the Meshy rig the same way Referee For Fun's
badminton, volleyball, tennis and sepak takraw clips are.

    blender --background --python tools/meshy/rig_clips.py -- footballer
    blender --background --python tools/meshy/rig_clips.py -- footballer preview football

Everything in `badminton_clips` about the rig applies unchanged — world-axis rotations
in degrees, and `lean()` rather than a spine bend, because this rig carries the torso on
the hips:

    +Z is up          -Y is the way they are facing        +X is their left

    RightArm      +Y raises overhead,  -Y drops to the hip
                  +Z swings forward,   -Z swings back behind
    LeftArm       -Y raises overhead,  +Y drops to the hip
    RightForeArm  +Z bends the elbow,  LeftForeArm  -Z bends the elbow
    UpLeg         -X swings the leg forward, +X back
    Leg           +X bends the knee
    Foot          +X points the toes

A rotation on a child composes with its parent's, so turning the hips turns everything
below them; that is how a player is laid on the grass — the hips go over by ninety
degrees and the whole body follows — and why `MOVE` then has to bring him down to it.

Every clip here is prefixed `fb_`, so football can share the character with the net
sports without arguing over a name.
"""

from badminton_clips import MOVE, STAND, lean

FPS = 24


def _with(base, **changes):
    pose = dict(base)
    pose.update(changes)
    return pose


def _moved(pose, up, forward=0.0):
    """The whole body shifted `up` and `forward`. See takraw_clips for why this cannot
    go through `_with`."""
    shifted = dict(pose)
    shifted[MOVE] = (0.0, -forward, up)
    return shifted


# A referee at rest: standing tall, arms down, weight even.
REF_STAND = dict(STAND)

# A player at rest in open play: knees soft, arms loose and a little away from the body.
PLAYER_IDLE = lean({
    "LeftUpLeg": (-7, 0, -3), "LeftLeg": (13, 0, 0),
    "RightUpLeg": (-7, 0, 3), "RightLeg": (13, 0, 0),
    "LeftArm": (0, 66, -12), "LeftForeArm": (0, 0, -24),
    "RightArm": (0, -66, 12), "RightForeArm": (0, 0, 24),
}, 5)

# The kick, in four moments. The standing leg is the left and stays planted and a little
# bent; the right swings from behind the body to in front of it, the knee folding on the
# way back and straightening through the ball; the arms swing against the leg for balance.
KICK_BACK = lean({
    "LeftUpLeg": (-10, 0, -3), "LeftLeg": (20, 0, 0),
    "RightUpLeg": (38, 0, 4), "RightLeg": (95, 0, 0), "RightFoot": (25, 0, 0),
    "LeftArm": (0, 28, 44), "LeftForeArm": (0, 0, -30),
    "RightArm": (0, -40, -30), "RightForeArm": (0, 0, 20),
}, 10)

KICK_STRIKE = lean({
    "LeftUpLeg": (-6, 0, -3), "LeftLeg": (16, 0, 0),
    "RightUpLeg": (-42, 0, 2), "RightLeg": (22, 0, 0), "RightFoot": (35, 0, 0),
    "LeftArm": (0, 34, -10), "LeftForeArm": (0, 0, -24),
    "RightArm": (0, -34, 34), "RightForeArm": (0, 0, 24),
}, 4)

KICK_THROUGH = lean({
    "LeftUpLeg": (-2, 0, -3), "LeftLeg": (10, 0, 0),
    "RightUpLeg": (-78, 0, 0), "RightLeg": (8, 0, 0), "RightFoot": (30, 0, 0),
    "LeftArm": (0, 38, -24), "LeftForeArm": (0, 0, -20),
    "RightArm": (0, -30, 46), "RightForeArm": (0, 0, 30),
}, -6)

# A slide tackle: down on the left hip, leaning back, the right leg shot out straight
# along the grass, the left folded under. The hips go back over, which throws both legs
# forward, and the body drops. It does not travel inside the clip: the game moves the
# body itself, and travel baked in here snapped the player back 1.6 m when it ended.
SLIDE = _moved({
    "Hips": (-58, 0, 0),
    "LeftUpLeg": (8, 0, -10), "LeftLeg": (100, 0, 0),
    "RightUpLeg": (-26, 0, 6), "RightLeg": (4, 0, 0), "RightFoot": (30, 0, 0),
    "Spine02": (14, 0, 0),
    "LeftArm": (0, 40, -40), "LeftForeArm": (0, 0, -20),
    "RightArm": (0, -30, -48), "RightForeArm": (0, 0, 16),
}, -0.74, 0.5)

# Down, face first, arms out to break the fall — and lying there.
FALLING = _moved(_with(lean(PLAYER_IDLE, 38),
    LeftArm=(0, 20, 60), RightArm=(0, -20, 60), LeftForeArm=(0, 0, -30), RightForeArm=(0, 0, 30)),
    -0.25, 0.25)

LYING = _moved({
    "Hips": (86, 0, 0),
    "LeftUpLeg": (-4, 0, -6), "LeftLeg": (22, 0, 0),
    "RightUpLeg": (-10, 0, 6), "RightLeg": (38, 0, 0),
    "Spine02": (-8, 0, 0),
    "LeftArm": (0, -10, 70), "LeftForeArm": (0, 0, -80),
    "RightArm": (0, 10, 70), "RightForeArm": (0, 0, 80),
}, -0.84, 0.35)

LYING_HURT = _with(LYING, RightUpLeg=(-38, 0, 8), RightLeg=(96, 0, 0), Hips=(84, 0, 10))

# The throw-in: both hands on the ball behind the head, arch the back, and bring it over.
THROW_BACK = lean({
    "LeftUpLeg": (-4, 0, -3), "LeftLeg": (8, 0, 0),
    "RightUpLeg": (6, 0, 3), "RightLeg": (10, 0, 0),
    "RightArm": (0, 96, -44), "RightForeArm": (0, 0, 110),
    "LeftArm": (0, -96, -44), "LeftForeArm": (0, 0, -110),
    "Spine02": (-10, 0, 0),
}, -8)

THROW_RELEASE = lean({
    "LeftUpLeg": (-8, 0, -3), "LeftLeg": (14, 0, 0),
    "RightUpLeg": (10, 0, 3), "RightLeg": (12, 0, 0),
    "RightArm": (0, 70, 50), "RightForeArm": (0, 0, 10),
    "LeftArm": (0, -70, 50), "LeftForeArm": (0, 0, -10),
    "Spine02": (8, 0, 0),
}, 10)


CLIPS = {
    "fb_stand": {
        "loop": True,
        "keys": [
            (0, REF_STAND),
            (30, _with(REF_STAND, Spine02=(2, 0, 0), LeftArm=(0, 74, -4), RightArm=(0, -74, 4))),
            (60, REF_STAND),
        ],
    },
    "fb_idle": {
        "loop": True,
        "keys": [
            (0, PLAYER_IDLE),
            (24, _with(PLAYER_IDLE, LeftLeg=(16, 0, 0), RightLeg=(16, 0, 0))),
            (48, PLAYER_IDLE),
        ],
    },
    "fb_kick": {
        "loop": False,
        "keys": [
            (0, PLAYER_IDLE),
            (5, KICK_BACK),
            (8, KICK_STRIKE),
            (12, KICK_THROUGH),
            (18, PLAYER_IDLE),
        ],
    },
    "fb_pass": {
        "loop": False,
        "keys": [
            (0, PLAYER_IDLE),
            (4, _with(KICK_BACK, RightUpLeg=(22, 0, 8), RightLeg=(60, 0, 0))),
            (7, _with(KICK_STRIKE, RightUpLeg=(-28, 0, -6))),
            (10, _with(KICK_THROUGH, RightUpLeg=(-44, 0, -8), RightLeg=(12, 0, 0))),
            (15, PLAYER_IDLE),
        ],
    },
    "fb_slide": {
        "loop": False,
        "keys": [
            (0, lean(PLAYER_IDLE, 12)),
            (4, _moved(_with(SLIDE, Hips=(-30, 0, 0)), -0.4, 0.3)),
            (7, SLIDE),
            (22, SLIDE),
            (30, _moved(lean(PLAYER_IDLE, 20), -0.2, 0.2)),
            (36, _moved(PLAYER_IDLE, 0.0, 0.0)),
        ],
    },
    "fb_fall": {
        "loop": False,
        "keys": [
            (0, lean(PLAYER_IDLE, 10)),
            (5, FALLING),
            (10, LYING),
        ],
    },
    "fb_lie": {
        "loop": True,
        "keys": [
            (0, LYING),
            (20, LYING_HURT),
            (40, LYING),
        ],
    },
    "fb_throw_in": {
        "loop": False,
        "keys": [
            (0, THROW_BACK),
            (6, _with(THROW_BACK, Spine02=(-16, 0, 0))),
            (11, THROW_RELEASE),
            (18, _with(PLAYER_IDLE)),
        ],
    },
}

## The poses the preview row shows, for looking at them in one picture.
SHOTS = [
    ("fb_stand", 0), ("fb_idle", 0), ("fb_kick", 1), ("fb_kick", 2), ("fb_kick", 3),
    ("fb_pass", 2), ("fb_slide", 2), ("fb_fall", 1), ("fb_lie", 0), ("fb_lie", 1),
    ("fb_throw_in", 0), ("fb_throw_in", 2),
]
