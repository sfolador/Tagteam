#!/usr/bin/env python3
"""Re-export Tagteam v2 artwork with the existing AppKit SVG renderer."""
from pathlib import Path
import shutil
import subprocess

BRAND = Path(__file__).resolve().parent
ROOT = BRAND.parent.parent
ICONS = ROOT / "CCSwitcher/Resources/Assets.xcassets/AppIcon.appiconset"
SWIFT = ["swift", "-module-cache-path", "/private/tmp/tagteam-swift-cache"]
CONCEPTS = ["v2-a-overlap", "v2-b-handoff", "v2-c-interlock"]


def render(source, target, size):
    subprocess.run(SWIFT + [str(BRAND / "render.swift"), str(source), str(target), str(size)], check=True)


def preview():
    # Keep render.swift untouched, as required by the brief. Reuse its existing
    # AppKit preview layout with v2 labels/assets supplied in memory via stdin.
    source = (BRAND / "render.swift").read_text()
    substitutions = {
        'text("Handoff",': 'text("In tandem / v2",',
        '"assets/brand/alt-relay.png"': '"assets/brand/v2-a-overlap.png"',
        '"assets/brand/alt-link.png"': '"assets/brand/v2-c-interlock.png"',
        'text("Relay",': 'text("A / Shared ground",',
        'text("Linked",': 'text("C / Fit together",',
        'text("ALTERNATIVES",': 'text("OTHER V2 CONCEPTS",',
        'text("16 px / 8× pixel inspection", x+706, 1920, 20, muted)':
            'text("16 px / 8×", x+550, 2020, 18, muted)\n'
            '        icon(appicon+"32.png", x+900, 1880, 128, nearest: true)\n'
            '        text("32 px / 4×", x+900, 2020, 18, muted)',
    }
    for old, new in substitutions.items():
        if source.count(old) != 1:
            raise RuntimeError(f"Preview template changed: {old}")
        source = source.replace(old, new)
    subprocess.run(SWIFT + ["-", "--preview", str(ROOT), str(BRAND / "preview.png")],
                   input=source, text=True, check=True)


if __name__ == "__main__":
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        source = "tagteam-icon-small.svg" if size <= 32 else "tagteam-icon.svg"
        render(BRAND / source, ICONS / f"icon_{size}.png", size)
    shutil.copyfile(ICONS / "icon_1024.png", ROOT / "assets/Tagteam-icon.png")
    for scale in [1, 2]:
        render(BRAND / "tagteam-menubar.svg", BRAND / f"tagteam-menubar@{scale}x.png", 18 * scale)
    for concept in CONCEPTS:
        render(BRAND / f"{concept}.svg", BRAND / f"{concept}.png", 512)
    preview()
    print("Exported seven app icons, two menu-bar glyphs, three v2 concepts, and preview.png.")
