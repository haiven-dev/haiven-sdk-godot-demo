#!/usr/bin/env python3
"""Copy the Haiven GDScript addon into a Godot project.

The addon already ships in this repository at addons/haiven. Installing into
this project is a no-op unless HAIVEN_SDK_GODOT names another checkout. A
missing override does not delete the packaged addon.
"""

from __future__ import annotations

import os
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent


def packaged_addon() -> Path:
    return HERE / "addons/haiven"


def addon_source() -> Path:
    """Packaged addon, or HAIVEN_SDK_GODOT/addons/haiven when that variable is set."""
    configured = os.environ.get("HAIVEN_SDK_GODOT")
    if configured:
        return Path(configured).expanduser().resolve() / "addons/haiven"
    return packaged_addon()


def install(project: Path = HERE) -> Path:
    target = (project / "addons/haiven").resolve()
    source = addon_source().resolve()
    if not (source / "plugin.cfg").is_file() or not (source / "plugin.gd").is_file():
        raise SystemExit(f"Haiven addon not found at {source}")
    if source == target:
        return target
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target, ignore=shutil.ignore_patterns("*.uid", "*.import"))
    return target


if __name__ == "__main__":
    print(f"installed {install()}")
