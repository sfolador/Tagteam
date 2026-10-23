#!/usr/bin/env python3
"""Re-export Tagteam artwork using macOS AppKit, without building the app."""
from pathlib import Path
import shutil
import subprocess

BRAND = Path(__file__).resolve().parent
ROOT = BRAND.parent.parent
ICONS = ROOT / "CCSwitcher/Resources/Assets.xcassets/AppIcon.appiconset"
SWIFT = ["swift", "-module-cache-path", "/private/tmp/tagteam-swift-cache", str(BRAND / "render.swift")]


def render(source, target, size):
    subprocess.run(SWIFT + [str(source), str(target), str(size)], check=True)


for size in [16, 32, 64, 128, 256, 512, 1024]:
    source = "tagteam-icon-small.svg" if size <= 32 else "tagteam-icon.svg"
    render(BRAND / source, ICONS / f"icon_{size}.png", size)
shutil.copyfile(ICONS / "icon_1024.png", ROOT / "assets/Tagteam-icon.png")
for scale in [1, 2]:
    render(BRAND / "tagteam-menubar.svg", BRAND / f"tagteam-menubar@{scale}x.png", 18 * scale)
for concept in ["alt-relay", "alt-link"]:
    render(BRAND / f"{concept}.svg", BRAND / f"{concept}.png", 512)
subprocess.run(SWIFT + ["--preview", str(ROOT), str(BRAND / "preview.png")], check=True)
print("Exported seven app icons, two menu-bar glyphs, two alternatives, and preview.png.")
