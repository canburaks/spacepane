#!/usr/bin/env python3
"""Unit tests for script/build_review_samples.py (the App Review sample archive).

    python3 -I script/test_build_review_samples.py

The archive is built for real, twice, from the repository's generators: the tests cover determinism, the README, the
cross-check between the archive, the README and the "Notes for App Review" section of
docs/release/app-store-submission.md, and the size and content limits. Rules of the cross-check are also broken on
purpose with small synthetic notes, so each failure message is exercised. Nothing here touches the network or the
Apple toolchain.
"""
import contextlib
import io
import re
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

SCRIPT_DIRECTORY = Path(__file__).resolve().parent
ROOT = SCRIPT_DIRECTORY.parent
sys.path.insert(0, str(SCRIPT_DIRECTORY))

import build_review_samples as samples  # noqa: E402

SUBMISSION = (ROOT / "docs/release/app-store-submission.md").read_text(encoding="utf-8")
FIVE_MEGABYTES = 5 * 1024 * 1024

# Notes in the shape the check reads: a heading, one quoted block, and the next heading.
SYNTHETIC_SUBMISSION = """# Worksheet

## Notes for App Review

Not pasted: the sample archive holds 07-stations.sqlite as well.

> Select 01-settings.json and press Space. See Makefile and README.txt.

## Next section
"""


def build_twice(first: Path, second: Path):
    return samples.build(first), samples.build(second)


class ArchiveTests(unittest.TestCase):
    """One real build, shared by the tests that only read it."""

    @classmethod
    def setUpClass(cls):
        cls._directory = tempfile.TemporaryDirectory()
        cls.output = Path(cls._directory.name)
        cls.folder, cls.zip_path = samples.build(cls.output)
        cls.files = {str(path.relative_to(cls.folder)): path.read_bytes()
                     for path in sorted(cls.folder.rglob("*")) if path.is_file()}

    @classmethod
    def tearDownClass(cls):
        cls._directory.cleanup()

    def test_the_output_has_a_folder_and_a_zip_with_the_agreed_names(self):
        self.assertEqual(self.folder.name, "SpacePane-Review-Samples")
        self.assertEqual(self.zip_path.name, "SpacePane-Review-Samples.zip")
        self.assertTrue((self.folder / "README.txt").is_file())

    def test_every_sample_is_present_and_nothing_else_but_the_readme(self):
        top_level = {name.split("/")[0] for name in self.files}
        self.assertEqual(top_level, {sample.name.rstrip("/") for sample in samples.SAMPLES} | {"README.txt"})
        for name, data in self.files.items():
            self.assertTrue(data or name.endswith("/"), f"{name} is empty")

    def test_the_zip_holds_exactly_the_files_of_the_folder(self):
        with zipfile.ZipFile(self.zip_path) as archive:
            self.assertIsNone(archive.testzip())
            inside = {info.filename[len("SpacePane-Review-Samples/"):]: archive.read(info) for info in archive.infolist()
                      if not info.is_dir()}
        self.assertEqual(inside, self.files)

    def test_the_zip_entries_are_sorted_with_fixed_time_mode_and_creator(self):
        with zipfile.ZipFile(self.zip_path) as archive:
            infos = archive.infolist()
        self.assertEqual([info.filename for info in infos], sorted(info.filename for info in infos))
        for info in infos:
            self.assertEqual(info.date_time, samples.ZIP_DATE_TIME, info.filename)
            self.assertEqual(info.create_system, samples.ZIP_UNIX, info.filename)
            self.assertEqual(info.compress_type, zipfile.ZIP_STORED, info.filename)
            self.assertEqual(info.external_attr >> 16, 0o40755 if info.is_dir() else 0o100644, info.filename)

    def test_every_sample_name_is_ascii_and_no_cad_file_is_present(self):
        for sample in samples.SAMPLES:
            self.assertTrue(sample.name.isascii(), sample.name)
            self.assertTrue(sample.expect.isascii() and len(sample.expect) <= 58, sample.name)
        self.assertTrue(all(not name.lower().endswith((".step", ".stp", ".iges", ".igs")) for name in self.files))
        self.assertIn("28-binary.stl", self.files)
        self.assertIn("Makefile", self.files)

    def test_the_makefile_has_no_extension_and_tab_indented_recipes(self):
        self.assertEqual(Path("Makefile").suffix, "")
        self.assertIn(b"\n\t@echo", self.files["Makefile"])

    def test_the_fake_secret_file_conceals_nothing_real(self):
        text = self.files["01-settings.json"].decode("utf-8")
        self.assertIn("not-a-real-credential", text)
        self.assertIn("-not-real", text)

    def test_no_file_or_zip_exceeds_a_sane_size(self):
        for name, data in self.files.items():
            self.assertLessEqual(len(data), samples.MAXIMUM_FILE_BYTES, name)
        size = self.zip_path.stat().st_size
        self.assertLessEqual(size, samples.MAXIMUM_ZIP_BYTES)
        self.assertLess(size, FIVE_MEGABYTES // 4, "keep the zip well under the 5 MB attachment limit")

    def test_no_file_looks_like_a_real_credential_name_email_or_phone_number(self):
        self.assertEqual(samples.content_problems(self.files), [])

    def test_the_unsafe_content_scan_catches_what_it_is_for(self):
        for label, data in (("email address", b"write to someone@example.org"),
                            ("private key block", b"-----BEGIN RSA PRIVATE KEY-----"),
                            ("AWS access key", b"AKIAABCDEFGHIJKLMNOP"),
                            ("telephone number", b"call +90 212 555 0100")):
            problems = samples.content_problems({**self.files, "99-bad.txt": data})
            self.assertTrue(any(label in problem for problem in problems), label)

    def test_an_oversized_file_is_reported(self):
        problems = samples.content_problems({**self.files, "99-big.bin": b"x" * (samples.MAXIMUM_FILE_BYTES + 1)})
        self.assertTrue(any("99-big.bin" in problem for problem in problems))

    def test_the_cross_check_passes_for_the_real_notes(self):
        self.assertEqual(samples.cross_check(self.files, SUBMISSION, self.zip_path.stat().st_size), [])

    def test_the_cross_check_names_a_file_the_notes_mention_but_the_archive_lacks(self):
        broken = SUBMISSION.replace("08-release.zip", "08-missing.zip", 1)
        problems = samples.cross_check(self.files, broken, self.zip_path.stat().st_size)
        self.assertTrue(any("08-missing.zip" in problem and "not in" in problem for problem in problems), problems)

    def test_the_cross_check_names_a_file_a_prepared_reply_mentions_but_the_archive_lacks(self):
        reply = samples.section(SUBMISSION, samples.REPLIES_HEADING)
        broken = SUBMISSION.replace(reply, reply + "\nSee 98-nowhere.txt.\n")
        problems = samples.cross_check(self.files, broken, self.zip_path.stat().st_size)
        self.assertTrue(any("98-nowhere.txt" in problem for problem in problems), problems)

    def test_the_cross_check_rejects_a_placeholder_and_an_overlong_note(self):
        placeholder = SYNTHETIC_SUBMISSION.replace("press Space.", "press Space on [tested file].")
        problems = samples.cross_check(self.files, placeholder, 1)
        self.assertTrue(any("placeholder" in problem and "[tested file]" in problem for problem in problems), problems)
        long_note = SYNTHETIC_SUBMISSION.replace("See Makefile", "x" * 4001 + " See Makefile")
        problems = samples.cross_check(self.files, long_note, 1)
        self.assertTrue(any("4000" in problem for problem in problems), problems)

    def test_the_cross_check_reports_a_missing_section_and_a_sample_the_readme_skips(self):
        with self.assertRaises(samples.ArchiveError):
            samples.cross_check(self.files, "# Worksheet\n", 1)
        readme = self.files["README.txt"].decode("ascii").replace("31-model.3mf", "31-model-renamed")
        problems = samples.cross_check({**self.files, "README.txt": readme.encode("ascii")}, SYNTHETIC_SUBMISSION, 1)
        self.assertTrue(any("does not describe 31-model.3mf" in problem for problem in problems), problems)

    def test_the_readme_is_plain_ascii_under_80_columns_and_60_lines(self):
        text = self.files["README.txt"].decode("ascii")
        lines = text.splitlines()
        self.assertLess(len(lines), 60)
        self.assertLess(max(len(line) for line in lines), 80)
        self.assertEqual(samples.readme_problems(text), [])
        self.assertTrue(samples.readme_problems(text + "café\n"))
        self.assertTrue(samples.readme_problems(text + "x" * 80 + "\n"))
        self.assertTrue(samples.readme_problems("line\n" * 60))

    def test_the_readme_has_two_steps_and_no_cad_switch_and_names_the_fake_secret_file(self):
        text = self.files["README.txt"].decode("ascii")
        self.assertEqual(re.findall(r"(?m)^([123])\. ", text), ["1", "2"])
        self.assertNotIn("STEP", text)
        self.assertNotIn("IGES", text)
        self.assertIn("01-settings.json", text.split("FILE ")[0])
        for sample in samples.SAMPLES:
            self.assertIn(sample.name, text)

    def test_the_real_notes_fit_apples_limit_and_hold_no_placeholder_or_stale_address(self):
        notes = samples.pasted_notes(samples.notes_section(SUBMISSION))
        self.assertLessEqual(len(notes.encode("utf-8")), 4000)
        self.assertIsNone(samples.PLACEHOLDER.search(notes), notes)
        self.assertNotIn("support@spacepane.com", SUBMISSION)
        self.assertIn("info@spacepane.com", notes)
        # The notes name the version and build that Base.xcconfig sets, so the two cannot drift apart.
        settings = dict(line.split(" = ", 1) for line in (ROOT / "Configuration" / "Base.xcconfig").read_text().splitlines()
                        if " = " in line and not line.startswith("//"))
        version = f"{settings['MARKETING_VERSION'].strip()} (build {settings['CURRENT_PROJECT_VERSION'].strip()})"
        for fact in (version, "macOS 27.2", "macOS 15", "public.data", "Developer Mode"):
            self.assertIn(fact, notes)
        # The identifiers belong to another developer's product and are no longer listed (decision 004, 2026-10-17).
        self.assertNotIn("quicklookpro", notes)
        for stale in ("STEP", "IGES", "CAD", "Open CASCADE", "LGPL", "spacepane-cad-source"):
            self.assertNotIn(stale, notes)

    def test_the_output_is_ignored_by_git(self):
        try:
            result = subprocess.run(["git", "check-ignore", "-q", "dist/review-samples/SpacePane-Review-Samples.zip"],
                                    cwd=ROOT, check=False)
        except OSError:
            self.skipTest("git is not available")
        self.assertEqual(result.returncode, 0, "dist/ must stay in .gitignore")


class DeterminismTests(unittest.TestCase):
    def test_two_builds_give_the_same_bytes_in_the_zip_and_the_folder(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            (folder_a, zip_a), (folder_b, zip_b) = build_twice(Path(first), Path(second))
            self.assertEqual(zip_a.read_bytes(), zip_b.read_bytes())
            tree_a = {str(p.relative_to(folder_a)): p.read_bytes() for p in sorted(folder_a.rglob("*")) if p.is_file()}
            tree_b = {str(p.relative_to(folder_b)): p.read_bytes() for p in sorted(folder_b.rglob("*")) if p.is_file()}
            self.assertEqual(tree_a, tree_b)

    def test_building_again_into_the_same_directory_replaces_the_earlier_output(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            _, zip_path = samples.build(output)
            first = zip_path.read_bytes()
            stale = output / samples.FOLDER_NAME / "stale.txt"
            stale.write_text("left over")
            samples.build(output)
            self.assertFalse(stale.exists())
            self.assertEqual(zip_path.read_bytes(), first)

    def test_a_directory_that_is_not_an_earlier_output_is_never_deleted(self):
        with tempfile.TemporaryDirectory() as directory:
            foreign = Path(directory) / samples.FOLDER_NAME
            foreign.mkdir()
            (foreign / "mine.txt").write_text("keep")
            with self.assertRaises(samples.ArchiveError):
                samples.build(Path(directory))
            self.assertTrue((foreign / "mine.txt").exists())

    def test_building_leaves_no_generated_fixture_directory_behind(self):
        import generate_host_fixtures

        made = []

        def generate_and_record():
            made.append(real_generate())
            return made[-1]

        real_generate = generate_host_fixtures.generate
        with mock.patch.object(generate_host_fixtures, "generate", generate_and_record):
            samples.collect_files()
        self.assertEqual(len(made), 1)
        self.assertFalse(made[0].exists(), "the fixture directory the generator made must be removed")


class NameExtractionTests(unittest.TestCase):
    def test_numbered_names_makefile_and_the_readme_are_file_names(self):
        text = "Open 01-settings.json, then 14-folder/. Also Makefile and README.txt. See 2026-10-12 and 5-minute."
        self.assertEqual(samples.referenced_names(text), ["01-settings.json", "14-folder", "Makefile", "README.txt"])

    def test_a_sentence_ending_full_stop_is_not_part_of_the_name(self):
        self.assertEqual(samples.referenced_names("Select 31-model.3mf."), ["31-model.3mf"])

    def test_the_notes_block_is_read_without_its_quote_marks(self):
        notes = samples.pasted_notes(samples.notes_section(SYNTHETIC_SUBMISSION))
        self.assertTrue(notes.startswith("Select 01-settings.json"))
        self.assertNotIn(">", notes)


class CheckCommandTests(unittest.TestCase):
    def run_check(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = samples.main(["--check"])
        return status, out.getvalue(), err.getvalue()

    def test_check_passes_for_the_repository_as_it_is(self):
        status, out, err = self.run_check()
        self.assertEqual((status, err), (0, ""), err)
        self.assertIn("review samples: ok", out)

    def test_check_fails_with_a_clear_message_when_the_notes_name_a_missing_file(self):
        original = samples.SUBMISSION
        with tempfile.TemporaryDirectory() as directory:
            broken = Path(directory) / "app-store-submission.md"
            broken.write_text(SUBMISSION.replace("07-stations.sqlite", "07-vanished.sqlite", 1), encoding="utf-8")
            samples.SUBMISSION = broken
            try:
                status, _, err = self.run_check()
            finally:
                samples.SUBMISSION = original
        self.assertEqual(status, 1)
        self.assertIn("review samples: FAILED", err)
        self.assertIn("07-vanished.sqlite", err)


if __name__ == "__main__":
    unittest.main()
