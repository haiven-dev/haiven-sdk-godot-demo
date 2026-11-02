#!/usr/bin/env python3
"""Copy the SDK's GDScript addon into this demo, so the project opens in Godot."""

from __future__ import annotations

import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent
ADDON = HERE.parents[1] / "sdks/godot/gdscript/addons/haiven"


def install(project: Path = HERE) -> Path:
    target = project / "addons/haiven"
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(ADDON, target, ignore=shutil.ignore_patterns("*.uid", "*.import"))
    return target


if __name__ == "__main__":
    print(f"installed {install()}")
