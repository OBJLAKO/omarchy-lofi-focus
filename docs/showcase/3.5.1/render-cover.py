#!/usr/bin/env python3
"""Render the editable SVG composition; the QML captures remain unmodified."""
from pathlib import Path
import shutil
import subprocess


folder = Path(__file__).resolve().parent
repo = folder.parents[2]
subprocess.run(
    ["rsvg-convert", "--output", str(folder / "cover.png"), str(folder / "cover.svg")],
    check=True,
)
shutil.copyfile(folder / "cover.png", repo / "preview.png")
print(folder / "cover.png")
