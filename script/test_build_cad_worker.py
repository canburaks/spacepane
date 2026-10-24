#!/usr/bin/env python3
"""Portable regression checks for the CAD worker's minimal OCCT manifests.

    python3 -I script/test_build_cad_worker.py

Synthetic package manifests reproduce the pinned shape reader's public-header
dependency. No OCCT download, compiler or private/user CAD model is used.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_cad_worker as builder

REPO = Path(__file__).resolve().parents[1]
EMBED_SCRIPT = REPO / "script/embed_cad_worker.py"
STAGE_SCRIPT = REPO / "script/stage_companion.py"
BUNDLED_NOTICES_SWIFT = REPO / "Apps/PrevApp/Models/BundledNotices.swift"


TOOLKITS = ("TKDESTEP", "TKDEIGES", "TKXSBase", "TKernel", "TKBRep")
BASE_FILES = {
    "src/TKXSBase/PACKAGES": "XSAlgo\n",
    "src/TKXSBase/EXTERNLIB": "TKernel\nTKBRep\n",
    "src/XSAlgo/FILES": "XSAlgo_ShapeProcessor.hxx\nXSAlgo_ShapeProcessor.cxx\n",
    "src/XSAlgo/XSAlgo_ShapeProcessor.hxx": "#include <DE_ShapeFixParameters.hxx>\n// Synthetic header.\n",
    "src/XSAlgo/XSAlgo_ShapeProcessor.cxx": "// Synthetic shape processor; keep unchanged.\n",
    "src/TKDE/PACKAGES": "DE\n",
    "src/TKDE/EXTERNLIB": "TKernel\nTKMath\nTKBRep\n",
    "src/DE/FILES": "DE_ShapeFixParameters.hxx\nDE_Provider.hxx\nDE_Provider.cxx\nDE_Wrapper.hxx\nDE_Wrapper.cxx\n",
    "src/DE/DE_ShapeFixParameters.hxx": "#include <Standard_Macro.hxx>\n#include <TopAbs_ShapeEnum.hxx>\n// Synthetic value-type header.\n",
    "src/DE/DE_Provider.hxx": "// Synthetic provider, outside the worker's scope.\n",
    "src/DE/DE_Provider.cxx": "// Synthetic provider implementation.\n",
    "src/DE/DE_Wrapper.hxx": "// Synthetic registry wrapper.\n",
    "src/DE/DE_Wrapper.cxx": "// Synthetic registry implementation.\n",
    "src/TKernel/PACKAGES": "Standard\n",
    "src/Standard/FILES": "Standard_Macro.hxx\n",
    "src/Standard/Standard_Macro.hxx": "// Synthetic foundational header.\n",
    "src/TKBRep/PACKAGES": "TopAbs\n",
    "src/TopAbs/FILES": "TopAbs_ShapeEnum.hxx\n",
    "src/TopAbs/TopAbs_ShapeEnum.hxx": "// Synthetic foundational header.\n",
    "LICENSE_LGPL_21.txt": "Synthetic license notice; retain verbatim.\n",
    "OCCT_LGPL_EXCEPTION.txt": "Synthetic exception notice; retain verbatim.\n",
}


def make_source(root):
    files = dict(BASE_FILES)
    for suffix, control in (("STEP", "STEP"), ("IGES", "IGES")):
        toolkit, parameters = "TKDE" + suffix, "DE" + suffix
        files.update({
            f"src/{toolkit}/PACKAGES": f"{control}Control\n{control}CAFControl\n{parameters}\n",
            f"src/{toolkit}/EXTERNLIB": "TKXSBase\nTKernel\nTKCAF\nTKCDF\nTKLCAF\nTKXCAF\nTKDE\n",
            f"src/{control}Control/FILES": f"{control}Control_Reader.hxx\n",
            f"src/{control}Control/{control}Control_Reader.hxx": f"#include <{parameters}_Parameters.hxx>\n",
            f"src/{control}CAFControl/FILES": f"{control}CAFControl_Reader.cxx\n",
            f"src/{control}CAFControl/{control}CAFControl_Reader.cxx": "// Synthetic CAF reader, omitted.\n",
            f"src/{parameters}/FILES": f"{parameters}_Parameters.hxx\n{parameters}_Parameters.cxx\n{parameters}_Provider.hxx\n{parameters}_Provider.cxx\n",
            f"src/{parameters}/{parameters}_Parameters.hxx": "#include <DE_ShapeFixParameters.hxx>\n",
            f"src/{parameters}/{parameters}_Parameters.cxx": "// Synthetic parameters implementation.\n",
            f"src/{parameters}/{parameters}_Provider.hxx": "// Synthetic provider wrapper, omitted.\n",
            f"src/{parameters}/{parameters}_Provider.cxx": "// Synthetic provider implementation, omitted.\n",
        })
    for relative, contents in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
    return root


def selected_files(root):
    """OCCT collects only FILES named by packages in its selected toolkits."""
    result = set()
    for toolkit in TOOLKITS:
        for package in (root / "src" / toolkit / "PACKAGES").read_text().splitlines():
            for filename in (root / "src" / package / "FILES").read_text().splitlines():
                result.add(root / "src" / package / filename)
    return result


def snapshot(root):
    return {str(path.relative_to(root)): path.read_bytes() for path in root.rglob("*") if path.is_file()}


class MinimalManifestTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="cad-manifest-test-")
        self.addCleanup(directory.cleanup)
        self.root = make_source(Path(directory.name))

    def test_shape_reader_public_header_closure_survives_a_clean_build(self):
        builder.narrow_manifests(self.root)
        selected = selected_files(self.root)
        exported = {path.name for path in selected if path.suffix == ".hxx"}
        self.assertIn("DE_ShapeFixParameters.hxx", exported)
        for path in selected:
            includes = re.findall(r"#include\s+<([^>]+)>", path.read_text())
            with self.subTest(path=path.name):
                self.assertEqual(set(includes) - exported, set())

    def test_only_header_only_de_parameters_are_retained(self):
        builder.narrow_manifests(self.root)
        self.assertEqual((self.root / "src/DE/FILES").read_text(), "DE_ShapeFixParameters.hxx\n")
        selected = selected_files(self.root)
        self.assertFalse(any(path.parent.name == "DE" and path.suffix == ".cxx" for path in selected))
        self.assertFalse(any("Provider" in path.name or "Wrapper" in path.name for path in selected))

    def test_reader_caf_packages_and_dependencies_stay_excluded(self):
        builder.narrow_manifests(self.root)
        for suffix in ("STEP", "IGES"):
            toolkit = self.root / "src" / ("TKDE" + suffix)
            self.assertNotIn(suffix + "CAFControl", (toolkit / "PACKAGES").read_text().splitlines())
            self.assertEqual((toolkit / "EXTERNLIB").read_text().splitlines(), ["TKXSBase", "TKernel"])
        # The full DE toolkit is never added to the compiled dependency closure.
        self.assertEqual((self.root / "src/TKXSBase/EXTERNLIB").read_text(), BASE_FILES["src/TKXSBase/EXTERNLIB"])
        self.assertEqual((self.root / "src/TKDE/PACKAGES").read_text(), BASE_FILES["src/TKDE/PACKAGES"])

    def test_repeated_narrowing_is_idempotent_and_does_not_duplicate_de(self):
        builder.narrow_manifests(self.root)
        first = snapshot(self.root)
        builder.narrow_manifests(self.root)
        self.assertEqual(snapshot(self.root), first)
        self.assertEqual((self.root / "src/TKXSBase/PACKAGES").read_text().splitlines().count("DE"), 1)

    def test_upstream_headers_implementations_and_notices_remain_verbatim(self):
        first = snapshot(self.root)
        builder.narrow_manifests(self.root)
        allowed = {"src/TKXSBase/PACKAGES", "src/DE/FILES", "PREV_BUILD_MANIFEST_CHANGES.txt"}
        for suffix in ("STEP", "IGES"):
            allowed.update({f"src/TKDE{suffix}/PACKAGES", f"src/TKDE{suffix}/EXTERNLIB", f"src/DE{suffix}/FILES"})
        for relative, contents in snapshot(self.root).items():
            if relative not in allowed:
                with self.subTest(path=relative):
                    self.assertEqual(contents, first[relative])

    def test_provenance_describes_header_only_package_without_source_edits(self):
        builder.narrow_manifests(self.root)
        provenance = (self.root / "PREV_BUILD_MANIFEST_CHANGES.txt").read_text()
        self.assertIn("DE_ShapeFixParameters.hxx", provenance)
        self.assertIn("TKXSBase", provenance)
        self.assertIn("No source implementation changes", provenance)
        self.assertIn("SHA256-pinned archive", provenance)


class BundledNoticeTests(unittest.TestCase):
    """The notice folders reach the app through the file lists, the embed script, the prototype stager and a Swift
    enum that the About page opens them by. A synthetic Xcode phase runs the real embed script, so a folder the script
    writes without declaring (which the user-script sandbox refuses) or a name that drifts shows here, not in a build."""

    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="cad-notices-test-")
        self.addCleanup(directory.cleanup)
        base = Path(directory.name)
        self.srcroot = base / "src"
        self.build = base / "build"
        self.temp = base / "temp"
        self.temp.mkdir()
        shutil.copytree(REPO / "ThirdPartyNotices", self.srcroot / "ThirdPartyNotices")
        self.workspace = self.srcroot / ".build" / "cad"
        helper = self.workspace / "worker-arm64" / "CADWorker"
        helper.parent.mkdir(parents=True)
        helper.write_bytes(b"synthetic helper, not a program\n")
        self.resources = self.build / "Synthetic.app" / "Contents" / "Resources"
        self.resources.mkdir(parents=True)
        patcher = mock.patch.object(builder, "ROOT", self.srcroot)
        patcher.start()
        self.addCleanup(patcher.stop)
        builder.refresh_bundle_filelists(self.workspace)

    def expand(self, name):
        """The lines of a generated file list with the build settings Xcode expands, as a set of strings."""
        text = (self.workspace / name).read_text()
        for setting, value in (("$(TARGET_BUILD_DIR)", str(self.build)),
                               ("$(CONTENTS_FOLDER_PATH)", "Synthetic.app/Contents"),
                               ("$(UNLOCALIZED_RESOURCES_FOLDER_PATH)", "Synthetic.app/Contents/Resources")):
            text = text.replace(setting, value)
        return set(text.splitlines())

    def run_embed_script(self):
        environment = {"PATH": os.environ.get("PATH", ""), "SRCROOT": str(self.srcroot), "ARCHS": "arm64",
                       "TARGET_BUILD_DIR": str(self.build), "CONTENTS_FOLDER_PATH": "Synthetic.app/Contents",
                       "UNLOCALIZED_RESOURCES_FOLDER_PATH": "Synthetic.app/Contents/Resources",
                       "TARGET_TEMP_DIR": str(self.temp), "CODE_SIGNING_ALLOWED": "NO"}
        subprocess.run([sys.executable, "-I", str(EMBED_SCRIPT)], env=environment, check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)

    def written_paths(self, before):
        return {str(path) for path in self.build.rglob("*")} - before

    def test_the_color_scheme_notice_ships_beside_the_occt_notices(self):
        self.run_embed_script()
        notice = self.resources / "ColorSchemes-Notices" / "NOTICE.md"
        self.assertEqual(notice.read_bytes(), (REPO / "ThirdPartyNotices/ColorSchemes/NOTICE.md").read_bytes())
        self.assertTrue((self.resources / "OCCT-Notices" / "LICENSE_LGPL_21.txt").is_file())
        self.assertTrue((self.build / "Synthetic.app/Contents/Helpers/CADWorker").is_file())

    def test_every_notice_file_the_script_copies_is_a_declared_input(self):
        inputs = self.expand("bundle-inputs.xcfilelist")
        for source, _ in builder.NOTICE_FOLDERS:
            files = [path for path in (self.srcroot / "ThirdPartyNotices" / source).iterdir() if path.is_file()]
            self.assertTrue(files, source)
            for path in files:
                with self.subTest(path=path.name):
                    self.assertIn(str(path), inputs)

    def test_what_the_script_writes_is_exactly_what_the_phase_declares_as_outputs(self):
        before = {str(path) for path in self.build.rglob("*")}
        self.run_embed_script()
        self.assertEqual(self.written_paths(before), self.expand("bundle-outputs.xcfilelist"))

    def test_a_relink_from_the_published_source_bundle_still_refreshes_the_lists(self):
        # That bundle mirrors the repository's layout but carries only ThirdPartyNotices/OCCT; the helper build ends by
        # refreshing the lists, so a missing folder must not fail the recipient's build.
        shutil.rmtree(self.srcroot / "ThirdPartyNotices" / "ColorSchemes")
        builder.refresh_bundle_filelists(self.workspace)
        outputs = self.expand("bundle-outputs.xcfilelist")
        self.assertTrue(any(line.endswith("/OCCT-Notices/LICENSE_LGPL_21.txt") for line in outputs))
        self.assertFalse(any("ColorSchemes-Notices" in line for line in outputs))

    def test_the_prototype_stager_copies_the_same_folders(self):
        text = STAGE_SCRIPT.read_text()
        self.assertTrue("import NOTICE_FOLDERS" in text and "in NOTICE_FOLDERS" in text,
                        "stage_companion.py must copy build_cad_worker.NOTICE_FOLDERS")
        self.assertFalse("ThirdPartyNotices/OCCT" in text, "stage_companion.py must not name a notice folder itself")

    def test_the_about_page_opens_the_folders_the_scripts_create(self):
        swift = BUNDLED_NOTICES_SWIFT.read_text()
        names = re.findall(r'case\s+\w+\s*=\s*"([^"]+)"', swift)
        # The app's About page names only the folders every build carries; the OCCT notices belong to a build with
        # CAD, whose About section returns with it (decision 028, "Bringing CAD back").
        self.assertEqual(sorted(names), sorted(name for _, name in builder.NOTICE_FOLDERS if name != "OCCT-Notices"))


if __name__ == "__main__":
    unittest.main()
