#!/usr/bin/env python3
"""Finds the sun in an HDRI and prints the direction its light comes from.

    python3 tools/sky/sun_from_hdri.py assets/sky/*.hdr

A photographed sky only looks right if the scene's own light comes from where the sun is
in the photograph: otherwise the shadows on the grass fall one way and the clouds are lit
another, and the eye notices immediately even when it cannot say why. So the sun is
measured rather than guessed — the brightest patch of the panorama, converted into the
direction Godot's sky puts it.

The numbers it prints are pasted into `Venue.LEVELS` as `sun_dir`.

Radiance .hdr is read here directly (no Python packages): a text header, a resolution
line, then scanlines that are either new-style RLE (four bytes 2, 2, hi, lo) or flat RGBE
pixels. Brightness is the usual luminance of the decoded floats.
"""

import math
import pathlib
import sys


def read_hdr(path):
    """Returns (width, height, [float luminance per pixel, row-major])."""
    data = pathlib.Path(path).read_bytes()
    at = 0
    # Header: text lines until a blank one.
    while True:
        end = data.index(b"\n", at)
        line = data[at:end]
        at = end + 1
        if line.strip() == b"":
            break
    end = data.index(b"\n", at)
    resolution = data[at:end].split()
    at = end + 1
    if resolution[0] != b"-Y" or resolution[2] != b"+X":
        raise SystemExit(f"{path}: unexpected scanline order {resolution}")
    height, width = int(resolution[1]), int(resolution[3])

    luminance = []
    for _row in range(height):
        if width < 8 or width > 0x7FFF or data[at] != 2 or data[at + 1] != 2:
            # Flat scanline: RGBE per pixel.
            row = []
            for _x in range(width):
                r, g, b, e = data[at:at + 4]
                at += 4
                row.append(_lum(r, g, b, e))
            luminance.extend(row)
            continue
        if (data[at + 2] << 8 | data[at + 3]) != width:
            raise SystemExit(f"{path}: scanline width mismatch")
        at += 4
        # New-style RLE: each of the four channels is run-length encoded across the row.
        channels = [[], [], [], []]
        for channel in channels:
            while len(channel) < width:
                count = data[at]
                at += 1
                if count > 128:
                    channel.extend([data[at]] * (count - 128))
                    at += 1
                else:
                    channel.extend(data[at:at + count])
                    at += count
        for x in range(width):
            luminance.append(_lum(channels[0][x], channels[1][x], channels[2][x], channels[3][x]))
    return width, height, luminance


def _lum(r, g, b, e):
    if e == 0:
        return 0.0
    scale = math.ldexp(1.0, e - 136)   # 2^(e-128) / 256
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) * scale


def sun_direction(path):
    width, height, luminance = read_hdr(path)
    # The brightest patch, not the brightest pixel: a single hot pixel can be noise.
    step = 4
    best, best_at = -1.0, (0, 0)
    for y in range(0, height, step):
        row = y * width
        for x in range(0, width, step):
            value = luminance[row + x]
            if value > best:
                best, best_at = value, (x, y)
    x, y = best_at
    u = (x + step * 0.5) / width
    v = (y + step * 0.5) / height
    # Godot's panorama sky maps u to atan2(dir.x, -dir.z) and v to acos(dir.y).
    azimuth = (u - 0.5) * 2.0 * math.pi
    polar = v * math.pi
    direction = (math.sin(azimuth) * math.sin(polar), math.cos(polar), -math.cos(azimuth) * math.sin(polar))
    return direction, best, math.degrees(math.pi / 2 - polar)


if __name__ == "__main__":
    for name in sys.argv[1:]:
        (dx, dy, dz), brightness, elevation = sun_direction(name)
        print(f"{pathlib.Path(name).stem}")
        print(f"    sun_dir Vector3({dx:.3f}, {dy:.3f}, {dz:.3f})   "
              f"elevation {elevation:.1f} deg, brightness {brightness:.0f}")
