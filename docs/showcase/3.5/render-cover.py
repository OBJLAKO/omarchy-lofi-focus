#!/usr/bin/env python3
"""Render the code-native cover around an unmodified real QML capture."""
from pathlib import Path
import subprocess

folder = Path(__file__).resolve().parent
repo = folder.parents[2]
subprocess.run([
    "rsvg-convert", "--output", str(folder / "cover.png"),
    str(folder / "cover.svg"),
], check=True)
subprocess.run([
    "magick", str(folder / "cover.png"), "-quality", "88",
    str(folder / "social-preview.jpg"),
], check=True)
(repo / "preview.png").write_bytes((folder / "cover.png").read_bytes())
print(folder / "cover.png")
