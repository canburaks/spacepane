#!/usr/bin/env python3
"""Build-map link selection using isolated fixtures; no Swift build required."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from package_link import package_objects


class PackageLinkTests(unittest.TestCase):
    def package(self, *names):
        return json.dumps({
            "targets": [{"name": name, "type": "regular", "dependencies": []} for name in names],
            "products": [{"targets": list(names)}],
        }).encode()

    def test_current_output_map_excludes_deleted_source_objects_and_stale_aggregate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "Example.build"
            target.mkdir()
            active = target / "Current.swift.o"
            active.touch()
            (target / "Removed.swift.o").touch()
            (root / "Example.o").touch()
            (target / "output-file-map.json").write_text(json.dumps({
                "": {"swift-dependencies": str(target / "primary.swiftdeps")},
                "Current.swift": {"object": str(active)},
            }))
            with patch("package_link.subprocess.check_output", return_value=self.package("Example")):
                self.assertEqual(package_objects(root), [active])

    def test_missing_current_object_fails_instead_of_falling_back_to_old_objects(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "Example.build"
            target.mkdir()
            (target / "Removed.swift.o").touch()
            (target / "output-file-map.json").write_text(json.dumps({
                "Current.swift": {"object": str(target / "Current.swift.o")},
            }))
            with patch("package_link.subprocess.check_output", return_value=self.package("Example")):
                with self.assertRaises(SystemExit):
                    package_objects(root)

    def test_whole_module_output_and_duplicate_map_entries_link_once(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "Example.build"
            target.mkdir()
            active = target / "Example.swift.o"
            active.touch()
            (target / "output-file-map.json").write_text(json.dumps({
                "": {"object": str(active)}, "Current.swift": {"object": str(active)},
            }))
            with patch("package_link.subprocess.check_output", return_value=self.package("Example")):
                self.assertEqual(package_objects(root), [active])

    def test_release_build_description_excludes_inactive_whole_module_placeholder(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "Example.build"
            target.mkdir()
            active = target / "Current.swift.o"
            active.touch()
            (target / "output-file-map.json").write_text(json.dumps({
                "": {"object": str(target / "Example.o")},
                "Current.swift": {"object": str(active)},
            }))
            (root / "description.json").write_text(json.dumps({"swiftCommands": {
                "C.Example-release.module": {"moduleName": "Example", "objects": [str(active)]}
            }}))
            with patch("package_link.subprocess.check_output", return_value=self.package("Example")):
                self.assertEqual(package_objects(root), [active])

    def test_build_description_excludes_stale_objects_even_when_both_modes_exist(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "Example.build"
            target.mkdir()
            whole = target / "Example.o"
            stale = target / "Old.swift.o"
            whole.touch(); stale.touch()
            (target / "output-file-map.json").write_text(json.dumps({
                "": {"object": str(whole)}, "Old.swift": {"object": str(stale)},
            }))
            (root / "description.json").write_text(json.dumps({"swiftCommands": {
                "C.Example-release.module": {"moduleName": "Example", "objects": [str(whole)]}
            }}))
            with patch("package_link.subprocess.check_output", return_value=self.package("Example")):
                self.assertEqual(package_objects(root), [whole])
                whole.unlink()
                with self.assertRaises(SystemExit):
                    package_objects(root)

    def test_legacy_aggregate_and_clang_target_layouts_remain_supported(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            aggregate = root / "Legacy.o"
            aggregate.touch()
            target = root / "Shim.build"
            target.mkdir()
            shim = target / "shim.c.o"
            shim.touch()
            with patch("package_link.subprocess.check_output", return_value=self.package("Legacy", "Shim")):
                self.assertEqual(package_objects(root), [aggregate, shim])


if __name__ == "__main__":
    unittest.main()
