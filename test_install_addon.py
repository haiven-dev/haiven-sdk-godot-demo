#!/usr/bin/env python3

import importlib.util
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("install_addon", HERE / "install_addon.py")
assert SPEC and SPEC.loader
install_addon = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(install_addon)


class InstallAddonTest(unittest.TestCase):
    def test_copies_the_sibling_godot_addon(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            installed = install_addon.install(project)
            self.assertEqual(installed, project / "addons/haiven")
            self.assertTrue((installed / "plugin.cfg").is_file())
            self.assertTrue((installed / "plugin.gd").is_file())


if __name__ == "__main__":
    unittest.main()
