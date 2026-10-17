#!/usr/bin/env python3
"""Unit tests for the build-time pruning of draft languages from nested resource bundles.

    python3 script/test_prune_resource_languages.py

Finding 16 of the 2026-10-17 rejection-risk review: `PreviewCore_PreviewRenderers.bundle` carries every chosen
language, and the host bundles carry the ship list only. Each test builds a synthetic Resources folder in a
temporary directory and runs the script's function or command line over it; no Xcode build is involved.
"""
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIRECTORY = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIRECTORY))

import prune_resource_languages as prune  # noqa: E402

SCRIPT = SCRIPT_DIRECTORY / "prune_resource_languages.py"
NESTED = "PreviewCore_PreviewRenderers.bundle"
CHOSEN = ["en", "tr", "de", "zh-Hans", "ku-Latn"]


def policy(directory, shipped=("en",), development="en", chosen=CHOSEN):
    path = Path(directory) / "languages.json"
    path.write_text(json.dumps({"developmentLanguage": development, "languages": chosen, "shipped": list(shipped),
                                "reviews": {}}))
    return path


def resources(directory, languages=CHOSEN, nested=NESTED, layout="Contents/Resources"):
    """A host's Resources folder holding one nested bundle with an .lproj per language."""
    root = Path(directory) / "Host.app/Contents/Resources"
    bundle = root / nested / layout
    for language in languages:
        (bundle / f"{language}.lproj").mkdir(parents=True)
        (bundle / f"{language}.lproj/Localizable.strings").write_text('"key" = "value";\n')
    (bundle / "FormatCatalog.json").write_text("{}")
    return root


def lprojs(root, nested=NESTED, layout="Contents/Resources"):
    return sorted(item.name[:-len(".lproj")] for item in (root / nested / layout).glob("*.lproj"))


class PruneTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def test_every_language_outside_the_ship_list_is_removed_from_the_nested_bundle(self):
        root = resources(self.directory)
        removed = prune.prune(root, ["en"], "en")
        self.assertEqual(lprojs(root), ["en"])
        self.assertEqual(sorted(path.name for path in removed), sorted(f"{language}.lproj" for language in CHOSEN if language != "en"))

    def test_the_shipped_languages_keep_their_strings(self):
        root = resources(self.directory)
        prune.prune(root, ["en", "de"], "en")
        self.assertEqual(lprojs(root), ["de", "en"])
        self.assertTrue((root / NESTED / "Contents/Resources/de.lproj/Localizable.strings").is_file())

    def test_files_that_are_not_language_folders_stay(self):
        root = resources(self.directory)
        prune.prune(root, ["en"], "en")
        self.assertTrue((root / NESTED / "Contents/Resources/FormatCatalog.json").is_file())

    def test_a_bundle_with_the_flat_layout_is_pruned_too(self):
        root = resources(self.directory, layout=".")
        prune.prune(root, ["en"], "en")
        self.assertEqual(lprojs(root, layout="."), ["en"])

    def test_the_hosts_own_language_folders_are_never_touched(self):
        root = resources(self.directory)
        for language in ("en", "de"):
            (root / f"{language}.lproj").mkdir()
        prune.prune(root, ["en"], "en")
        self.assertTrue((root / "de.lproj").is_dir(), "the archive check owns the host's own language folders")

    def test_every_nested_bundle_is_pruned(self):
        root = resources(self.directory)
        resources(self.directory, nested="Other_Module.bundle")
        prune.prune(root, ["en"], "en")
        self.assertEqual(lprojs(root, "Other_Module.bundle"), ["en"])

    def test_only_the_named_bundles_are_pruned(self):
        root = resources(self.directory)
        resources(self.directory, nested="Other_Module.bundle")
        prune.prune(root, ["en"], "en", bundles=[NESTED])
        self.assertEqual(lprojs(root), ["en"])
        self.assertEqual(lprojs(root, "Other_Module.bundle"), sorted(CHOSEN))

    def test_a_named_bundle_that_is_absent_is_an_error_and_nothing_is_pruned(self):
        root = resources(self.directory)
        with self.assertRaisesRegex(ValueError, "Absent.bundle"):
            prune.prune(root, ["en"], "en", bundles=[NESTED, "Absent.bundle"])
        self.assertEqual(lprojs(root), sorted(CHOSEN))

    def test_a_second_run_removes_nothing(self):
        root = resources(self.directory)
        prune.prune(root, ["en"], "en")
        self.assertEqual(prune.prune(root, ["en"], "en"), [])

    def test_a_host_without_nested_bundles_is_left_alone(self):
        root = self.directory / "Resources"
        (root / "en.lproj").mkdir(parents=True)
        self.assertEqual(prune.prune(root, ["en"], "en"), [])
        self.assertTrue((root / "en.lproj").is_dir())

    def test_a_symbolic_link_is_unlinked_and_its_target_survives(self):
        root = resources(self.directory)
        target = self.directory / "elsewhere"
        target.mkdir()
        (target / "keep.txt").write_text("keep")
        (root / NESTED / "Contents/Resources/fr.lproj").symlink_to(target)
        prune.prune(root, ["en"], "en")
        self.assertFalse((root / NESTED / "Contents/Resources/fr.lproj").exists())
        self.assertTrue((target / "keep.txt").is_file())

    def test_a_bundle_that_loses_its_development_language_is_refused_and_left_unchanged(self):
        root = resources(self.directory, languages=["de", "tr"])
        with self.assertRaisesRegex(ValueError, "development language"):
            prune.prune(root, ["en"], "en")
        self.assertEqual(lprojs(root), ["de", "tr"])

    def test_a_missing_resources_folder_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "Resources"):
            prune.prune(self.directory / "absent", ["en"], "en")


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def test_the_ship_list_and_development_language_come_from_the_policy_file(self):
        shipped, development = prune.load_policy(policy(self.directory, shipped=("en", "de")))
        self.assertEqual((shipped, development), (["en", "de"], "en"))

    def test_a_ship_list_without_the_development_language_is_refused(self):
        with self.assertRaisesRegex(ValueError, "development language"):
            prune.load_policy(policy(self.directory, shipped=("de",)))

    def test_an_empty_ship_list_is_refused(self):
        with self.assertRaisesRegex(ValueError, "ship"):
            prune.load_policy(policy(self.directory, shipped=()))

    def test_the_repository_policy_is_readable(self):
        shipped, development = prune.load_policy(prune.DEFAULT_POLICY)
        self.assertIn(development, shipped)


class CommandLineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def run_script(self, *arguments):
        return subprocess.run([sys.executable, str(SCRIPT), *map(str, arguments)], capture_output=True, text=True)

    def test_the_command_line_prunes_and_reports_each_removal(self):
        root = resources(self.directory)
        result = self.run_script(root, "--policy", policy(self.directory))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(lprojs(root), ["en"])
        for language in ("de", "tr", "zh-Hans", "ku-Latn"):
            self.assertIn(f"{language}.lproj", result.stdout)

    def test_the_command_line_prunes_only_the_bundles_it_is_given(self):
        root = resources(self.directory)
        resources(self.directory, nested="Other_Module.bundle")
        result = self.run_script(root, "--bundle", NESTED, "--policy", policy(self.directory))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(lprojs(root), ["en"])
        self.assertEqual(lprojs(root, "Other_Module.bundle"), sorted(CHOSEN))

    def test_the_command_line_fails_with_a_message_for_a_missing_folder(self):
        result = self.run_script(self.directory / "absent", "--policy", policy(self.directory))
        self.assertEqual(result.returncode, 1)
        self.assertIn("Resources", result.stderr)

    def test_the_command_line_leaves_the_tree_alone_when_nothing_is_to_remove(self):
        root = resources(self.directory, languages=["en"])
        result = self.run_script(root, "--policy", policy(self.directory))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(lprojs(root), ["en"])


class ProjectWiringTests(unittest.TestCase):
    """The Xcode phases run the script in the user-script sandbox, so they must declare what it deletes.

    The sandbox lets a script write only to declared outputs and never conflicts with the copy of the nested
    bundle, so the outputs are the files of every draft language, listed in script/prune-outputs.xcfilelist.
    """
    ROOT = SCRIPT_DIRECTORY.parent
    RESOURCES = ROOT / "Packages/PreviewCore/Sources/PreviewRenderers/Resources"
    NESTED_OUTPUT = "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/PreviewCore_PreviewRenderers.bundle/Contents/Resources"

    def phases(self):
        text = (self.ROOT / "Prev.xcodeproj/project.pbxproj").read_text()
        return re.findall(r"\{\s*isa = PBXShellScriptBuildPhase;(?:(?!\n\t\t\};).)*?name = \"Prune draft languages\";.*?\n\t\t\};",
                          text, flags=re.S)

    def test_the_output_list_names_every_file_of_every_draft_language(self):
        policy_file = json.loads((self.ROOT / "tools/localization/languages.json").read_text())
        expected = []
        for language in policy_file["languages"]:
            if language == policy_file["developmentLanguage"]:
                continue
            folder = self.RESOURCES / f"{language}.lproj"
            expected.append(f"{self.NESTED_OUTPUT}/{language}.lproj")
            expected += [f"{self.NESTED_OUTPUT}/{language}.lproj/{item.name}" for item in sorted(folder.iterdir())]
        listed = (self.ROOT / "script/prune-outputs.xcfilelist").read_text().split()
        self.assertEqual(sorted(listed), sorted(expected))

    def test_the_app_and_both_extensions_run_the_script_with_declared_inputs_and_outputs(self):
        phases = self.phases()
        self.assertEqual(len(phases), 3, "the companion and each extension need one pruning phase")
        for phase in phases:
            self.assertIn('"$(SRCROOT)/script/prune_resource_languages.py"', phase)
            self.assertIn('"$(SRCROOT)/tools/localization/languages.json"', phase)
            self.assertIn('"$(SRCROOT)/script/prune-outputs.xcfilelist"', phase)
            self.assertIn("outputFileListPaths", phase)
            self.assertIn("--bundle PreviewCore_PreviewRenderers.bundle", phase)

    def test_each_target_runs_its_phase_after_the_resources_are_copied(self):
        text = (self.ROOT / "Prev.xcodeproj/project.pbxproj").read_text()
        ids = re.findall(r"(\w{24}) /\* Prune draft languages \*/ = \{", text)
        self.assertEqual(len(ids), 3)
        for target in ("Prev", "PrevPreviewExtension", "PrevThumbnailExtension"):
            body = re.search(rf"/\* {target} \*/ = \{{\s*isa = PBXNativeTarget;.*?buildPhases = \((.*?)\);", text, re.S).group(1)
            phases = re.findall(r"/\* (.*?) \*/", body)
            self.assertIn("Prune draft languages", phases, target)
            self.assertLess(phases.index("Resources"), phases.index("Prune draft languages"), target)

    def test_script_sandboxing_stays_on(self):
        self.assertIn("ENABLE_USER_SCRIPT_SANDBOXING = YES", (self.ROOT / "Configuration/Base.xcconfig").read_text())


if __name__ == "__main__":
    unittest.main()
