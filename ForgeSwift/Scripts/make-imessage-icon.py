#!/usr/bin/env python3
"""Generate the iMessage App Icon set for ForgeMessagesExtension.

Committed binaries with no source are a maintenance trap — nobody can tweak the
mark or re-export a size without redrawing it. This renders every slot in the
set from one description, so the icon is reproducible and a change is a diff in
this file rather than a new opaque blob.

Written against `zlib` and `struct` only. There is no Pillow on the build box,
and adding an image dependency to generate nine flat gradients would be a poor
trade.

Usage:  python3 ForgeSwift/Scripts/make-imessage-icon.py
"""

from __future__ import annotations

import json
import math
import os
import struct
import zlib

# Ember, matching ForgeColor.ember (FF4D00) through emberDark (C43A00).
EMBER = (0xFF, 0x4D, 0x00)
EMBER_DARK = (0xC4, 0x3A, 0x00)

# Every slot Xcode's iMessage App Icon set fills, as (idiom, size, scale).
# Sizes are in points; the rendered pixel size is size * scale.
SLOTS = [
    ("universal", (27, 20), 2),
    ("universal", (27, 20), 3),
    ("universal", (32, 24), 2),
    ("universal", (32, 24), 3),
    ("iphone", (60, 45), 2),
    ("iphone", (60, 45), 3),
    ("ipad", (67, 50), 2),
    ("ipad", (74, 55), 2),
    ("ios-marketing", (1024, 768), 1),
]

SUPERSAMPLE = 3


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def shade(u: float, v: float) -> tuple[float, float, float]:
    """Colour at normalised position (u, v), both in 0...1.

    A diagonal ember ramp with an off-centre bloom. The bloom is what stops the
    icon reading as a flat orange rectangle at 54x40, which is the size that
    actually matters — the Messages app drawer.
    """
    t = max(0.0, min(1.0, (u * 0.62 + v * 0.38)))
    r = lerp(EMBER[0], EMBER_DARK[0], t)
    g = lerp(EMBER[1], EMBER_DARK[1], t)
    b = lerp(EMBER[2], EMBER_DARK[2], t)

    dx, dy = u - 0.26, v - 0.24
    bloom = max(0.0, 1.0 - math.sqrt(dx * dx + dy * dy) / 0.78) ** 2
    r = min(255.0, r + 74 * bloom)
    g = min(255.0, g + 46 * bloom)
    b = min(255.0, b + 26 * bloom)
    return r, g, b


def spark_coverage(u: float, v: float, aspect: float) -> float:
    """1 inside the spark mark, 0 outside.

    An astroid (|x|^(2/3) + |y|^(2/3) <= r^(2/3)) — a four-pointed spark. Chosen
    because it stays legible at 40 pixels tall, where a wordmark or a flame
    silhouette turns to mush. Coordinates are corrected for the icon's aspect so
    the mark is not stretched by the 4:3 canvas.
    """
    x = (u - 0.5) * 2.0 * aspect
    y = (v - 0.5) * 2.0
    radius = 0.62
    ax, ay = abs(x) / radius, abs(y) / radius
    # Guard the cube root against the exact centre.
    value = (ax ** (2.0 / 3.0) if ax > 1e-6 else 0.0) + (ay ** (2.0 / 3.0) if ay > 1e-6 else 0.0)
    return 1.0 if value <= 1.0 else 0.0


def render(width: int, height: int) -> bytes:
    """Render one icon and return raw RGB rows, supersampled for smooth edges."""
    ss = SUPERSAMPLE
    aspect = width / height
    rows = []

    for py in range(height):
        row = bytearray()
        for px in range(width):
            acc_r = acc_g = acc_b = 0.0
            for sy in range(ss):
                for sx in range(ss):
                    u = (px + (sx + 0.5) / ss) / width
                    v = (py + (sy + 0.5) / ss) / height
                    r, g, b = shade(u, v)
                    if spark_coverage(u, v, aspect):
                        # The mark is warm white rather than pure white so it
                        # sits in the gradient instead of punching a hole in it.
                        r, g, b = 255.0, 248.0, 242.0
                    acc_r += r
                    acc_g += g
                    acc_b += b
            n = ss * ss
            row += bytes((int(acc_r / n + 0.5), int(acc_g / n + 0.5), int(acc_b / n + 0.5)))
        rows.append(bytes(row))
    return b"".join(b"\x00" + r for r in rows)


def write_png(path: str, width: int, height: int, raw: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    # Colour type 2 = truecolour RGB, 8 bits per channel. App icons must not
    # carry alpha — iOS rejects icons with an alpha channel.
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", header)
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(png)


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "ForgeMessagesExtension",
                       "Assets.xcassets", "iMessage App Icon.stickersiconset")
    out = os.path.normpath(out)
    os.makedirs(out, exist_ok=True)

    images = []
    for idiom, (w, h), scale in SLOTS:
        pixel_w, pixel_h = w * scale, h * scale
        name = f"icon-{w}x{h}@{scale}x.png"
        write_png(os.path.join(out, name), pixel_w, pixel_h, render(pixel_w, pixel_h))
        images.append({
            "filename": name,
            "idiom": idiom,
            "scale": f"{scale}x",
            "size": f"{w}x{h}",
        })
        print(f"  {name}  ({pixel_w}x{pixel_h})")

    with open(os.path.join(out, "Contents.json"), "w") as handle:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}},
                  handle, indent=2)
        handle.write("\n")

    # The catalog itself needs a Contents.json or actool ignores the folder.
    catalog = os.path.dirname(out)
    with open(os.path.join(catalog, "Contents.json"), "w") as handle:
        json.dump({"info": {"author": "xcode", "version": 1}}, handle, indent=2)
        handle.write("\n")

    print(f"wrote {len(images)} icons to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
