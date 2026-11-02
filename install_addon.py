#!/usr/bin/env python3
"""Copy the SDK's GDScript addon into this demo, so the project opens in Godot."""

from __future__ import annotations

import os
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent


def addon_source() -> Path:
    """Sibling haiven-sdk-godot addon, or HAIVEN_SDK_GODOT when that value is non-empty."""
    configured = os.environ.get("HAIVEN_SDK_GODOT")
    if configured:
        return Path(configured).expanduser().resolve() / "addons/haiven"
    return (HERE.parent / "haiven-sdk-godot" / "addons/haiven").resolve()


ADDON = addon_source()


def install(project: Path = HERE) -> Path:
    target = project / "addons/haiven"
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(ADDON, target, ignore=shutil.ignore_patterns("*.uid", "*.import"))
    return target


if __name__ == "__main__":
    print(f"installed {install()}")
