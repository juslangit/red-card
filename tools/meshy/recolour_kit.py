#!/usr/bin/env python3
"""Repaints the shirt on a Meshy character's texture, leaving skin and shorts alone.

    tools/meshy/recolour_kit.py player_red  libero 52
    tools/meshy/recolour_kit.py player_blue libero 52 220

Why this exists
---------------
The libero has to be identifiable at a glance — that is the entire reason the
different-shirt rule exists in the sport. The game used to do it by strapping a
`BoxMesh` to the chest bone (`Models.wear_bib`), and it looked like exactly what it
was: a block. Luqman, 2026-09-17, on a screenshot of it: "change to different cloth,
dont put block like that".

The comment above `wear_bib` gives the reason it was a box: a material tint multiplies
the whole texture, so tinting a red kit yellow gives a dirty red rather than a yellow
shirt — and it would stain the skin and the shorts with it too.

The answer is to repaint the shirt in the texture rather than tint the model. The kit
is painted into one 2048x2048 PNG in clearly separated regions — the shirt sits around
rgb(186, 62, 61), the shorts around rgb(59, 60, 70), the skin around rgb(239, 196, 170)
— so the shirt can be selected on its own and given a new hue.

Hue only. Saturation and value are kept exactly as they were, so every fold, seam and
shadow painted into the fabric survives the change; the shirt looks like the same
garment in another colour rather than a flat patch of paint. Selecting on "much more
red than green or blue" is what keeps the skin out of it: skin is only 1.2x redder
than it is green, while the shirt is 3x.
"""

import colorsys
import pathlib
import sys

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
ASSETS = HERE.parent.parent / "assets" / "meshy"

## A shirt is found by its hue and by being a proper colour rather than a shade.
##
## The first version selected "much redder than green or blue", which worked on the red
## kit and found 318 pixels of the blue one — the rule described red rather than
## describing a shirt. Hue plus saturation describes a shirt: the red kit sits near 0
## degrees, the blue at 220, and the things that must not be repainted are all excluded
## by saturation alone — skin is 0.32, the white trim and the grey shoes are under 0.05.
## Measured, not guessed. At 32 degrees the red kit left 1,541 pixels of its own colour
## behind in the warm shading of the folds. At 45 it catches all 68,417 shirt pixels and
## puts **zero** skin pixels at risk, because skin sits at saturation 0.32 and the floor
## below is 0.45 — the two are separated by how colourful they are, not by hue.
HUE_TOLERANCE = 45.0
MIN_SATURATION = 0.45
MIN_VALUE = 0.12

## There is deliberately no region mask any more.
##
## The first version excluded the bottom fifth of the sheet, on the theory that the feet
## live there and the red shoe flashes were being repainted with the shirt. What it
## actually did was cut straight through the shirt's own UV island: 15,724 pixels of the
## kit, at exactly its own hue and saturation, kept the old colour because they happened
## to be mapped below the line. On the model that read as a shirt torn in half — yellow
## across the shoulders, blue down one side, a hard ragged edge between them.
##
## UV layout is not geography. A band of the sheet is not a band of the body, and nothing
## may be selected by where it sits in texture space. Hue and saturation describe the
## garment wherever its island happens to lie, and they already exclude the shoes on the
## blue kit, which are grey. On the red kit the shoe flashes do change colour with the
## shirt, and that is left alone: a libero whose trim matches their shirt looks like a
## kit, which is the point.

## A rotated hue alone is not enough. The kit's red is deep, and keeping its saturation
## and value gives a deep version of the new hue — a red shirt turned to hue 48 comes out
## orange rather than yellow, which is no use to a libero who has to be told apart from a
## team-mate in red at a glance. So saturation and value are pulled towards a floor as
## well, which lifts the garment to a kit colour while the *relative* light and shade of
## every fold is preserved.
LIFT_TO_VALUE = 0.92
LIFT_TO_SATURATION = 0.88
LIFT = 0.6

## Telling the teams apart without colour.
##
## Measured on 2026-09-18: the red kit has a luminance of 88.3 out of 255 and the blue
## kit 77.4. Eleven apart. Hue is the only thing separating them, so to a colour-blind
## player — and in a photograph printed in black and white, and on a bad projector —
## the two sides are wearing the same shirt. The whole game is deciding which side a
## rally went to, so that is not a cosmetic problem.
##
## Passing a target value lifts or drops the kit's brightness while leaving its hue
## alone, so red stays red and blue stays blue and the two separate by how light they
## are. `LIFT` applies here too, so the folds keep their relative shading.


def _apart(a: float, b: float) -> float:
    """Degrees between two hues, the short way round the wheel."""
    gap = abs(a - b) % 360.0
    return min(gap, 360.0 - gap)


def repaint(source: Image.Image, hue: float, from_hue: float,
            value: float = -1.0) -> tuple[Image.Image, int]:
    out = source.copy().convert("RGB")
    px = out.load()
    w, h = out.size
    touched = 0
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            hue_here, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if s < MIN_SATURATION or v < MIN_VALUE:
                continue
            if _apart(hue_here * 360.0, from_hue) > HUE_TOLERANCE:
                continue
            # Towards a kit colour, not merely rotated. The lerp keeps the difference
            # between a lit fold and a shadowed one, so the fabric still reads as fabric.
            if value >= 0.0:
                # Brightness is the point of this pass; saturation is left alone so the
                # kit stays the colour it was rather than washing out.
                v = v + (value - v) * LIFT
            else:
                s = s + (LIFT_TO_SATURATION - s) * LIFT
                v = v + (LIFT_TO_VALUE - v) * LIFT
            nr, ng, nb = colorsys.hsv_to_rgb(hue, min(1.0, s), min(1.0, v))
            px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255))
            touched += 1
    return out, touched


def main() -> None:
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    name, label, degrees = sys.argv[1], sys.argv[2], float(sys.argv[3])
    # Which kit is being repainted. Red sits at 0, the blue kit at 220.
    from_hue = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0
    # Optional fifth argument: the brightness to move the kit towards, 0 to 1.
    value = float(sys.argv[5]) if len(sys.argv) > 5 else -1.0
    source = ASSETS / name / f"{name}_animated_texture_0.png"
    if not source.exists():
        sys.exit(f"no texture at {source}")
    out_dir = ASSETS / f"{name}_{label}"
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / f"{name}_{label}_texture.png"

    image = Image.open(source)
    painted, touched = repaint(image, degrees / 360.0, from_hue, value)
    painted.save(target)
    share = 100.0 * touched / (image.size[0] * image.size[1])
    print(f"repainted {touched} pixels ({share:.1f}% of the sheet) to hue {degrees:.0f}")
    print(f"wrote {target.relative_to(ASSETS.parent.parent)}")


if __name__ == "__main__":
    main()
