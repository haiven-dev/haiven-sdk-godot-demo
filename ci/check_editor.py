#!/usr/bin/env python3
"""Run the credentials-free Godot demo scripts that ship in this repository."""

from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PINNED_VERSION = "4.5.1"
STAGES = (
    ("offline", ["--script", "offline_quickstart.gd"], "HAIVEN_TEST_PASS readiness 12"),
    ("demo", ["--script", "demo_test.gd"], "HAIVEN_TEST_PASS demo 30"),
    ("sign-in", ["--script", "demo_sign_in_test.gd"], "HAIVEN_TEST_PASS demo_sign_in 36"),
)


def main() -> None:
    logs = Path(os.environ.get("GODOT_LOG_DIR", ROOT / "build/godot-results")).resolve()
    logs.mkdir(parents=True, exist_ok=True)
    engine = shutil.which(os.environ.get("GODOT_BIN", "godot"))
    if not engine:
        raise RuntimeError("Godot editor is required; set GODOT_BIN or install godot")
    version = subprocess.check_output([engine, "--version"], text=True, timeout=15).strip()
    (logs / "engine.log").write_text(version + "\n", encoding="utf-8")
    expected = os.environ.get("GODOT_EXPECTED_VERSION", PINNED_VERSION)
    if not version.startswith(expected + ".stable."):
        raise RuntimeError(f"expected Godot {expected} stable, got {version}")
    for name, args, marker in STAGES:
        log = logs / f"{name}.log"
        with log.open("w") as output:
            try:
                result = subprocess.run(
                    [engine, "--headless", "--path", str(ROOT), *args],
                    stdout=output,
                    stderr=subprocess.STDOUT,
                    timeout=float(os.environ.get("GODOT_TIMEOUT_SECONDS", "120")),
                    env={**os.environ, "NO_COLOR": "1"},
                    check=False,
                )
            except subprocess.TimeoutExpired as error:
                raise RuntimeError(f"{name} timed out; see {log}") from error
        text = log.read_text(encoding="utf-8", errors="replace")
        print(text, end="", flush=True)
        if result.returncode != 0 or re.search(r"(?:SCRIPT ERROR:|ERROR:|^FAIL\b)", text, re.M):
            raise RuntimeError(f"{name} failed; see {log}")
        if text.splitlines().count(marker) != 1:
            raise RuntimeError(f"{name} did not complete the expected assertions; see {log}")
    print("ok   Godot demo headless checks", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from error
