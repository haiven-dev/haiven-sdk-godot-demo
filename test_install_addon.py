#!/usr/bin/env python3

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("install_addon", HERE / "install_addon.py")
assert SPEC and SPEC.loader
install_addon = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(install_addon)


class InstallAddonTest(unittest.TestCase):
    def test_copies_the_packaged_addon(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            installed = install_addon.install(project)
            self.assertEqual(installed, (project / "addons/haiven").resolve())
            self.assertTrue((installed / "plugin.cfg").is_file())
            self.assertTrue((installed / "plugin.gd").is_file())

    def test_missing_override_does_not_delete_the_packaged_addon(self) -> None:
        packaged = HERE / "addons/haiven/plugin.cfg"
        self.assertTrue(packaged.is_file())
        previous = os.environ.get("HAIVEN_SDK_GODOT")
        with tempfile.TemporaryDirectory() as temporary:
            os.environ["HAIVEN_SDK_GODOT"] = temporary
            try:
                with self.assertRaises(SystemExit):
                    install_addon.install(HERE)
            finally:
                if previous is None:
                    os.environ.pop("HAIVEN_SDK_GODOT", None)
                else:
                    os.environ["HAIVEN_SDK_GODOT"] = previous
        self.assertTrue(packaged.is_file())
        self.assertTrue((HERE / "addons/haiven/plugin.gd").is_file())


if __name__ == "__main__":
    unittest.main()
