#!/usr/bin/env python3
"""Assert the ARIA ember asset is a transparent blob with no circular ring."""

from __future__ import annotations

import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError:
    print("skip: pillow/numpy not installed")
    raise SystemExit(0)

ROOT = Path(__file__).resolve().parents[1]
PATHS = [
    ROOT / "shared" / "brand" / "aria-mark.png",
    ROOT / "public" / "aria-mark.png",
    ROOT / "ForgeSwift" / "ForgeSwift" / "Assets.xcassets" / "AriaLogo.imageset" / "AriaLogo.png",
]


def check(path: Path) -> list[str]:
    errors: list[str] = []
    if not path.exists():
        return [f"missing {path}"]
    im = Image.open(path)
    if im.mode != "RGBA":
        errors.append(f"{path}: expected RGBA, got {im.mode}")
    arr = np.array(im)
    alpha = arr[:, :, 3]
    if float((alpha < 8).mean()) < 0.25:
        errors.append(f"{path}: background is not transparent enough")
    rgb = arr[:, :, :3].astype(np.float32)
    luma = 0.2126 * rgb[:, :, 0] + 0.7152 * rgb[:, :, 1] + 0.0722 * rgb[:, :, 2]
    chroma = rgb.max(axis=2) - rgb.min(axis=2)
    opaque = alpha > 20
    if not opaque.any():
        errors.append(f"{path}: mark disappeared")
        return errors
    ys, xs = np.where(opaque)
    cy, cx = float(ys.mean()), float(xs.mean())
    yy, xx = np.indices(alpha.shape)
    dist = np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2)
    white = (luma > 220) & (chroma < 18) & opaque
    if white.any():
        radii = dist[white]
        r_med = float(np.median(radii))
        span = float(np.percentile(radii, 90) - np.percentile(radii, 10))
        if span < 8 and r_med > min(alpha.shape) * 0.28:
            errors.append(f"{path}: thin white circular ring still present")
    return errors


def main() -> int:
    errors: list[str] = []
    for jpg in ROOT.rglob("*"):
        if jpg.suffix.lower() in {".jpg", ".jpeg"} and "aria" in jpg.name.lower():
            errors.append(f"dead jpeg still in tree: {jpg}")
    for path in PATHS:
        errors.extend(check(path))
    if errors:
        print("\n".join(errors))
        return 1
    print("aria mark assets look clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
