#!/usr/bin/env python3
"""Unit tests for the static gate and its companions (decision 027, Q-18 to Q-20).

    python3 script/test_check_static.py

Covers decision-number uniqueness (with the 006 exception), the wall-clock test-name check against a
temporary tree, the dataless-guard scan and its allowlist table (decision 027, Q-153), ownership glob
matching and classification (including the changed-file listing in a throwaway git repository) and the
pure parts of the Swift syntax gate. Every tree is temporary; nothing
reads or writes user data. Tests that need git or the tree-sitter packages skip when they are absent.
"""
import contextlib
import io
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "script"))
sys.path.insert(0, str(ROOT / "tools"))

import check_ownership  # noqa: E402
import check_static  # noqa: E402
import check_swift_syntax  # noqa: E402

HAS_GIT = shutil.which("git") is not None


def write(root, relative, text="x\n"):
    path = Path(root) / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def git(root, *arguments):
    subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                    "-c", "commit.gpgsign=false", *arguments],
                   cwd=str(root), check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def commit_everything(root, message="base"):
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", message)


def captured(function, *arguments):
    """Run function(*arguments); return (result, stdout, stderr)."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        result = function(*arguments)
    return result, out.getvalue(), err.getvalue()


class DecisionNumberTests(unittest.TestCase):
    def check(self, names, allowed=None, folders=()):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in names:
                write(root, name, "# record\n")
            for folder in folders:
                (root / folder).mkdir()
            allowed = check_static.ALLOWED_DUPLICATE_NUMBERS if allowed is None else allowed
            return check_static.check_decision_numbers(root, allowed)

    def test_unique_numbers_pass(self):
        result = self.check(["001-a.md", "002-b.md", "010-c.md"])
        self.assertEqual(result.status, check_static.PASS)
        self.assertIn("3 records", result.detail)

    def test_a_repeated_number_fails_and_names_both_files(self):
        result = self.check(["003-first.md", "003-second.md", "004-other.md"])
        self.assertEqual(result.status, check_static.FAIL)
        self.assertIn("003", result.detail)
        self.assertIn("003-first.md", result.detail)
        self.assertIn("003-second.md", result.detail)

    def test_the_two_existing_006_records_are_allowed(self):
        result = self.check(["005-a.md", "006-direct-file-drop.md", "006-opt-in-cad-previews.md", "007-b.md"])
        self.assertEqual(result.status, check_static.PASS)
        self.assertIn("006", result.detail)

    def test_a_third_006_record_fails(self):
        result = self.check(["006-direct-file-drop.md", "006-opt-in-cad-previews.md", "006-another.md"])
        self.assertEqual(result.status, check_static.FAIL)
        self.assertIn("006-another.md", result.detail)

    def test_a_new_record_cannot_borrow_an_allowed_number(self):
        result = self.check(["006-direct-file-drop.md", "006-brand-new.md"])
        self.assertEqual(result.status, check_static.FAIL)

    def test_the_exception_is_only_for_the_listed_number(self):
        result = self.check(["007-direct-file-drop.md", "007-opt-in-cad-previews.md"])
        self.assertEqual(result.status, check_static.FAIL)

    def test_file_names_without_three_leading_digits_fail(self):
        for name in ["notes.md", "27-short.md", "0027-long.md", "027_underscore.md", "027-wrong-suffix.txt", "027-.md"]:
            with self.subTest(name=name):
                self.assertEqual(self.check([name]).status, check_static.FAIL)

    def test_the_index_hidden_files_and_folders_are_not_records(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ["README.md", ".DS_Store", "001-a.md"]:
                write(root, name)
            (root / "assets").mkdir()
            result = check_static.check_decision_numbers(root, check_static.ALLOWED_DUPLICATE_NUMBERS)
        self.assertEqual(result.status, check_static.PASS)
        self.assertIn("1 records", result.detail)

    def test_a_missing_folder_fails(self):
        result = check_static.check_decision_numbers(Path("/nonexistent/decisions/folder"), {})
        self.assertEqual(result.status, check_static.FAIL)

    def test_the_repository_decisions_pass(self):
        result = check_static.check_decision_numbers()
        self.assertEqual(result.status, check_static.PASS, result.output or result.detail)


class WallClockSuiteTests(unittest.TestCase):
    def check(self, assignment="WALL_CLOCK_SUITES='First|Second'\nEXPECTED_SERIAL_TESTS=2", source=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = write(root, "build.sh", assignment)
            tests = root / "Tests"
            tests.mkdir()
            write(tests, "Suites.swift", source or "@Suite struct First {}\n@Suite struct Second {}\n")
            return check_static.check_wall_clock_tests(script, tests)

    def test_all_named_suites_exist(self):
        self.assertEqual(self.check().status, check_static.PASS)

    def test_missing_or_renamed_suite_fails(self):
        self.assertEqual(self.check(source="@Suite struct First {}\n@Suite struct SecondRenamed {}").status, check_static.FAIL)

    def test_function_name_does_not_count_as_suite(self):
        self.assertEqual(self.check(source="func First() {}\nfunc Second() {}").status, check_static.FAIL)

    def test_comment_does_not_count_as_suite(self):
        self.assertEqual(self.check(source="// struct First {}\n// struct Second {}").status, check_static.FAIL)

    def test_empty_regex_duplicate_or_missing_suite_assignment_fails(self):
        for value in ["First||Second", "First|Se.*", "First|First", ""]:
            self.assertEqual(self.check("WALL_CLOCK_SUITES='" + value + "'\nEXPECTED_SERIAL_TESTS=2").status, check_static.FAIL)
        self.assertEqual(self.check("OTHER='First'").status, check_static.FAIL)

    def test_count_guard_is_required_and_positive(self):
        for count in ["", "0", "-1", '"2"', "$COUNT"]:
            self.assertEqual(self.check("WALL_CLOCK_SUITES='First'\nEXPECTED_SERIAL_TESTS=" + count).status, check_static.FAIL)

    def test_double_quoted_names_and_repository_selection(self):
        self.assertEqual(self.check('WALL_CLOCK_SUITES="First|Second"\nEXPECTED_SERIAL_TESTS=2').status, check_static.PASS)
        self.assertEqual(check_static.check_wall_clock_tests().status, check_static.PASS)


class SerialInventoryTests(unittest.TestCase):
    def validate(self, text, suites=None, count=2):
        from check_serial_test_inventory import validate_inventory
        return validate_inventory(text, suites or ["First", "Second"], count)

    def test_built_identifiers_match_exact_suites(self):
        text = "Module.First/renamed()\nModule.Second/nested()\nModule.FirstExtra/ignored()\nOther.aFunction()\n"
        self.assertEqual(len(self.validate(text)), 2)

    def test_empty_or_missing_suite_cannot_pass(self):
        for text in ["", "Module.First/one()\nModule.First/two()"]:
            with self.assertRaises(ValueError): self.validate(text)

    def test_added_removed_or_duplicate_test_requires_review(self):
        base = "Module.First/one()\nModule.Second/two()"
        for text in [base + "\nModule.First/new()", base + "\nModule.First/one()"]:
            with self.assertRaises(ValueError): self.validate(text)
        with self.assertRaises(ValueError): self.validate(base, count=3)

    def test_plain_unique_names_and_positive_count(self):
        for suites in [["First", "First"], ["First", ""], ["Fi.*"], []]:
            from check_serial_test_inventory import validate_inventory
            with self.assertRaises(ValueError): validate_inventory("", suites, 2)
        for count in [0, -1, True]:
            with self.assertRaises(ValueError): self.validate("", count=count)


class GlobMatchingTests(unittest.TestCase):
    def matches(self, pattern, path):
        return check_ownership.glob_to_regex(pattern).match(path) is not None

    def test_star_stays_inside_one_path_component(self):
        self.assertTrue(self.matches("a/*.swift", "a/x.swift"))
        self.assertFalse(self.matches("a/*.swift", "a/b/x.swift"))
        self.assertFalse(self.matches("a/*.swift", "x.swift"))

    def test_a_trailing_double_star_is_everything_below(self):
        self.assertTrue(self.matches("a/**", "a/x"))
        self.assertTrue(self.matches("a/**", "a/b/c/d.swift"))
        self.assertFalse(self.matches("a/**", "a"))
        self.assertFalse(self.matches("a/**", "a/"))
        self.assertFalse(self.matches("a/**", "ab/x"))

    def test_a_double_star_in_the_middle_spans_zero_or_more_directories(self):
        for path in ["a/c.swift", "a/b/c.swift", "a/b/d/c.swift"]:
            self.assertTrue(self.matches("a/**/c.swift", path), path)
        self.assertFalse(self.matches("a/**/c.swift", "a/c.swiftx"))
        self.assertFalse(self.matches("a/**/c.swift", "b/c.swift"))

    def test_a_leading_double_star_matches_at_any_depth(self):
        self.assertTrue(self.matches("**/x.swift", "x.swift"))
        self.assertTrue(self.matches("**/x.swift", "a/b/x.swift"))

    def test_question_mark_is_one_character_inside_a_component(self):
        self.assertTrue(self.matches("a/?.swift", "a/x.swift"))
        self.assertFalse(self.matches("a/?.swift", "a/xy.swift"))
        self.assertFalse(self.matches("a/?swift", "a//swift"))

    def test_other_characters_are_literal(self):
        self.assertTrue(self.matches("R/NativePreviewView+Interaction.swift", "R/NativePreviewView+Interaction.swift"))
        self.assertFalse(self.matches("R/a.swift", "R/aXswift"))
        self.assertTrue(self.matches("R/a (1).swift", "R/a (1).swift"))

    def test_a_prefix_glob_matches_the_names_a_workstream_may_use(self):
        pattern = "tools/localization/additions/ux-chrome*.json"
        self.assertTrue(self.matches(pattern, "tools/localization/additions/ux-chrome.json"))
        self.assertTrue(self.matches(pattern, "tools/localization/additions/ux-chrome-extra.json"))
        self.assertFalse(self.matches(pattern, "tools/localization/additions/ux-copy.json"))
        self.assertFalse(self.matches(pattern, "tools/localization/additions/ux-chrome/x.json"))

    def test_unsupported_globs_are_rejected(self):
        for pattern in ["", "/abs/path", "a//b", "a/", "../x", "./a", "a/../b", "a\\b", "a[1].swift", "a{b,c}"]:
            with self.subTest(pattern=pattern):
                self.assertIsNotNone(check_ownership.glob_problem(pattern))
        for pattern in ["a/b.swift", "a/**", "**/x", "a/*/b", "tools/*localization*.py"]:
            with self.subTest(pattern=pattern):
                self.assertIsNone(check_ownership.glob_problem(pattern))


FAKE_TABLE = {
    "lead": ["docs/**", "tools/**", "Packages/PreviewCore/Tests/**", "src/contracts/**"],
    "alpha": ["src/alpha/**", "src/both.swift", "tools/localization/additions/alpha*.json"],
    "ux-beta": ["src/beta/**", "src/both.swift"],
}


def fake_table():
    return check_ownership.Table({name: list(globs) for name, globs in FAKE_TABLE.items()})


class SlugTests(unittest.TestCase):
    def test_aliases_drop_the_ux_and_q_prefixes(self):
        self.assertEqual(check_ownership.slug_aliases("ux-modes-structure"), ["ux-modes-structure", "modes-structure"])
        self.assertEqual(check_ownership.slug_aliases("q-a11y-l10n"), ["q-a11y-l10n", "a11y-l10n"])
        self.assertEqual(check_ownership.slug_aliases("lead"), ["lead"])

    def test_a_file_name_carries_the_slug_ignoring_case_and_punctuation(self):
        carries = check_ownership.carries_slug
        self.assertTrue(carries("ux-chrome", "Packages/PreviewCore/Tests/X/UxChromeStripTests.swift"))
        self.assertTrue(carries("ux-chrome", "Tests/ux-chrome-strip.swift"))
        self.assertTrue(carries("ux-chrome", "Tests/ChromeStripTests.swift"))
        self.assertTrue(carries("q-safety", "Tests/SafetyCanaryTests.swift"))
        self.assertFalse(carries("ux-chrome", "Tests/ModesTests.swift"))
        self.assertFalse(carries("ux-chrome", "ux-chrome/Other.swift"))  # the folder name does not count


class ClassificationTests(unittest.TestCase):
    def verdict(self, path, status="M", workstream="alpha"):
        return check_ownership.classify(check_ownership.Change(path, status), workstream, fake_table())

    def test_a_file_matching_the_workstreams_globs_is_owned(self):
        self.assertEqual(self.verdict("src/alpha/File.swift").category, "owned")

    def test_a_file_of_another_workstream_names_its_owner(self):
        verdict = self.verdict("src/beta/File.swift")
        self.assertEqual(verdict.category, "other")
        self.assertIn("ux-beta", verdict.note)

    def test_a_shared_file_fails_unless_the_lead_approved(self):
        verdict = self.verdict("docs/readme.md")
        self.assertEqual(verdict.category, "shared")
        self.assertTrue(check_ownership.is_violation(verdict, allow_shared=False))
        self.assertFalse(check_ownership.is_violation(verdict, allow_shared=True))

    def test_an_unowned_file_fails_even_with_approval(self):
        verdict = self.verdict("misc/other.txt")
        self.assertEqual(verdict.category, "unowned")
        self.assertTrue(check_ownership.is_violation(verdict, allow_shared=True))

    def test_a_file_listed_for_two_workstreams_is_owned_by_each(self):
        self.assertEqual(self.verdict("src/both.swift", workstream="alpha").category, "owned")
        self.assertEqual(self.verdict("src/both.swift", workstream="ux-beta").category, "owned")

    def test_a_workstreams_own_glob_wins_over_the_leads(self):
        self.assertEqual(self.verdict("tools/localization/additions/alpha-extra.json").category, "owned")
        self.assertEqual(self.verdict("tools/localization/additions/ux-beta.json").category, "shared")

    def test_a_new_test_file_with_the_slug_is_allowed(self):
        path = "Packages/PreviewCore/Tests/PreviewRenderersTests/AlphaStripTests.swift"
        self.assertEqual(self.verdict(path, "A").category, "new test")
        self.assertEqual(self.verdict("Tests/Integration/BetaChecks.swift", "A", "ux-beta").category, "new test")
        self.assertEqual(self.verdict("script/test_alpha_thing.py", "A").category, "new test")

    def test_a_new_test_file_without_the_slug_is_shared_and_says_why(self):
        verdict = self.verdict("Packages/PreviewCore/Tests/PreviewRenderersTests/StripTests.swift", "A")
        self.assertEqual(verdict.category, "shared")
        self.assertIn('"alpha"', verdict.note)

    def test_existing_test_files_stay_with_the_lead_even_when_the_name_has_the_slug(self):
        path = "Packages/PreviewCore/Tests/PreviewRenderersTests/AlphaStripTests.swift"
        self.assertEqual(self.verdict(path, "M").category, "shared")
        self.assertEqual(self.verdict(path, "D").category, "shared")

    def test_the_slug_does_not_open_non_test_locations(self):
        self.assertEqual(self.verdict("src/AlphaTests.swift", "A").category, "unowned")

    def test_the_lead_owns_the_shared_files_and_still_fails_unowned_ones(self):
        self.assertEqual(self.verdict("docs/readme.md", workstream="lead").category, "owned")
        self.assertEqual(self.verdict("src/alpha/File.swift", workstream="lead").category, "other")
        self.assertEqual(self.verdict("misc/other.txt", workstream="lead").category, "unowned")


class TableLoadingTests(unittest.TestCase):
    def load(self, document):
        with tempfile.TemporaryDirectory() as directory:
            path = write(directory, "ownership.json", json.dumps(document) if not isinstance(document, str) else document)
            return check_ownership.load_table(path)

    def test_annotations_are_ignored(self):
        table = self.load({"_comment": "note", "lead": ["docs/**"], "alpha": ["src/**"]})
        self.assertEqual(table.names(), ["lead", "alpha"])

    def test_invalid_tables_are_rejected(self):
        bad = [
            "not json",
            [],
            {"alpha": ["src/**"]},  # no lead
            {"lead": []},
            {"lead": "docs/**"},
            {"lead": ["docs/"]},
            {"lead": ["docs/**"], "Bad Name": ["x/**"]},
            {"lead": ["docs/**"], "alpha": [3]},
        ]
        for document in bad:
            with self.subTest(document=document):
                with self.assertRaises(check_ownership.ConfigError):
                    self.load(document)

    def test_an_unknown_workstream_is_a_usage_error_against_the_current_tree(self):
        status, _, err = captured(check_ownership.main, ["--workstream", "no-such-workstream", "--base", "HEAD"])
        self.assertEqual(status, 2)
        self.assertIn("unknown workstream", err)
        self.assertIn("ux-chrome", err)


class RepositoryTableTests(unittest.TestCase):
    """The shipped table encodes decision 026 as amended by decision 027; pin the statements that matter."""

    @classmethod
    def setUpClass(cls):
        cls.table = check_ownership.load_table(check_ownership.DEFAULT_CONFIG)

    def owners(self, path):
        return self.table.workstreams_matching(path)

    def test_the_table_names_every_workstream_of_decision_027(self):
        expected = {"lead", "ux-chrome", "ux-modes-structure", "ux-documents", "ux-containers-3d", "ux-companion", "ux-copy",
                    "ux-thumbnails", "q-performance", "q-safety", "q-a11y-l10n", "q-platform", "ux-seams", "ux-tables",
                    "ux-setup"}
        self.assertEqual(set(self.table.names()), expected)

    def test_ownership_amendments_are_encoded(self):
        renderers = "Packages/PreviewCore/Sources/PreviewRenderers/"
        self.assertEqual(self.owners(renderers + "Interaction/PreviewShortcut.swift"), ["ux-modes-structure"])
        self.assertEqual(self.owners(renderers + "NativePreviewView.swift"), ["ux-chrome"])
        self.assertEqual(self.owners(renderers + "Listings/NativeListingFilesView.swift"), ["ux-containers-3d"])
        self.assertEqual(self.owners(renderers + "Listings/SafeListingTree.swift"), ["ux-containers-3d"])
        self.assertEqual(self.owners(renderers + "GeometryMetalRenderer.swift"), ["ux-containers-3d"])
        self.assertEqual(self.owners("Apps/PrevApp/Stores/CompanionSettings.swift"), ["ux-companion"])
        self.assertEqual(self.owners("script/test_companion_models.py"), ["ux-companion"])
        self.assertEqual(self.owners("Extensions/PrevThumbnailExtension/ThumbnailProvider.swift"), ["ux-thumbnails", "q-platform"])
        self.assertEqual(self.owners("script/probe_thumbnail.swift"), ["ux-thumbnails"])
        self.assertEqual(self.owners("tools/localization/additions/ux-copy.json"), ["ux-copy"])

    def test_deliberate_overlaps_are_the_ones_the_decision_names(self):
        renderers = "Packages/PreviewCore/Sources/PreviewRenderers/"
        self.assertEqual(self.owners(renderers + "SafeStructuredText.swift"), ["ux-modes-structure", "q-performance"])
        self.assertEqual(self.owners("Packages/PreviewCore/Sources/PreviewCore/DefaultPrivacyFilter.swift"), ["q-performance", "q-safety"])

    def test_shared_contracts_and_the_extension_host_stay_with_the_lead(self):
        for path in ["Packages/PreviewCore/Package.swift",
                     "Packages/PreviewCore/Sources/PreviewContracts/PreviewModels.swift",
                     "Packages/PreviewCore/Sources/PreviewRenderers/NativePreviewPane.swift",
                     "Packages/PreviewCore/Sources/PreviewRenderers/Resources/Localizable.xcstrings",
                     "Extensions/PrevPreviewExtension/PreviewViewController.swift",
                     "CHANGELOGS.md", "PLAN.md", "AGENTS.md", "Prev.xcodeproj/project.pbxproj"]:
            with self.subTest(path=path):
                self.assertTrue(self.table.matches(check_ownership.LEAD, path))
        self.assertEqual(self.owners("Packages/PreviewCore/Sources/PreviewContracts/PreviewModels.swift"), [])
        self.assertEqual(self.owners("Packages/PreviewCore/Sources/PreviewRenderers/NativePreviewPane.swift"), [])

    def test_every_workstream_may_edit_only_its_own_additions_file(self):
        for name in self.table.names():
            if name == check_ownership.LEAD:
                continue
            with self.subTest(name=name):
                self.assertEqual([owner for owner in self.owners(f"tools/localization/additions/{name}.json")], [name])

    def test_existing_tests_are_shared_for_every_workstream(self):
        path = "Packages/PreviewCore/Tests/PreviewCoreTests/PreviewPipelineTests.swift"
        for name in self.table.names():
            if name == check_ownership.LEAD:
                continue
            with self.subTest(name=name):
                verdict = check_ownership.classify(check_ownership.Change(path, "M"), name, self.table)
                self.assertEqual(verdict.category, "shared")


@unittest.skipUnless(HAS_GIT, "git is not installed")
class ChangedFileListingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        git(self.root, "init", "-q")
        write(self.root, ".gitignore", "ignored.txt\n")
        for name in ["keep.txt", "edit.txt", "delete.txt", "rename_me.txt", "Sources/Edit.swift", "Sources/Gone.swift", "Sources/Same.swift"]:
            write(self.root, name)
        commit_everything(self.root)
        write(self.root, "edit.txt", "changed\n")
        write(self.root, "Sources/Edit.swift", "struct Edit {}\n")
        (self.root / "delete.txt").unlink()
        (self.root / "Sources/Gone.swift").unlink()
        git(self.root, "mv", "rename_me.txt", "renamed.txt")
        write(self.root, "staged_new.txt")
        git(self.root, "add", "staged_new.txt")
        write(self.root, "untracked.txt")
        write(self.root, "Sources/Untracked.swift", "struct Untracked {}\n")
        write(self.root, "ignored.txt")
        write(self.root, "notes.md")

    def test_ownership_changes_carry_a_status_and_include_untracked_files(self):
        with mock.patch.object(check_ownership, "ROOT", self.root):
            changes = {change.path: change.status for change in check_ownership.changed_files("HEAD")}
        self.assertEqual(changes, {
            "edit.txt": "M", "Sources/Edit.swift": "M",
            "delete.txt": "D", "Sources/Gone.swift": "D",
            "rename_me.txt": "D", "renamed.txt": "A",
            "staged_new.txt": "A", "untracked.txt": "A", "Sources/Untracked.swift": "A", "notes.md": "A",
        })

    def test_a_bad_base_is_an_error_not_an_empty_list(self):
        with mock.patch.object(check_ownership, "ROOT", self.root):
            with self.assertRaises(check_ownership.GitError):
                check_ownership.changed_files("no-such-ref")
            with self.assertRaises(check_ownership.GitError):
                check_ownership.changed_files("--cached")

    def test_syntax_gate_lists_changed_and_untracked_swift_files_only(self):
        with mock.patch.object(check_swift_syntax, "ROOT", self.root):
            self.assertEqual(check_swift_syntax.changed_swift_files("HEAD"), ["Sources/Edit.swift", "Sources/Untracked.swift"])
            self.assertEqual(check_swift_syntax.all_swift_files(),
                             ["Sources/Edit.swift", "Sources/Same.swift", "Sources/Untracked.swift"])

    def test_the_ownership_command_line_end_to_end(self):
        tools = self.root / "tools"
        tools.mkdir()
        shutil.copy(str(ROOT / "tools" / "check_ownership.py"), str(tools / "check_ownership.py"))
        table = {"lead": ["docs/**", "tools/**", "Tests/**"], "alpha": ["Sources/**", "tools/localization/additions/alpha*.json"],
                 "beta": ["edit.txt"]}
        write(self.root, "tools/ownership.json", json.dumps(table))
        git(self.root, "add", "tools")
        git(self.root, "commit", "-q", "-m", "tools", "--", "tools")  # only the tools; the pending changes stay pending

        def run(*arguments):
            done = subprocess.run([sys.executable, str(tools / "check_ownership.py"), *arguments], cwd=str(self.root),
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
            return done.returncode, done.stdout + done.stderr

        # Pending changes: edit.txt (beta's), delete.txt, rename_me.txt, renamed.txt, staged_new.txt, untracked.txt and notes.md
        # sit outside alpha; Sources/* belongs to alpha.
        status, output = run("--workstream", "alpha", "--base", "HEAD")
        self.assertEqual(status, 1, output)
        self.assertIn("OTHER", output)
        self.assertIn("beta", output)
        self.assertIn("UNOWNED", output)
        self.assertIn("FAILED alpha", output)
        # Drop the changes outside alpha's files; Sources/Untracked.swift (alpha's) stays.
        git(self.root, "reset", "-q", "--hard", "HEAD")
        for name in ["untracked.txt", "notes.md"]:
            (self.root / name).unlink()
        status, output = run("--workstream", "alpha", "--base", "HEAD")
        self.assertEqual(status, 0, output)
        self.assertIn("OK alpha", output)
        # A shared file needs approval; an unowned one never passes.
        write(self.root, "docs/readme.md")
        status, output = run("--workstream", "alpha", "--base", "HEAD")
        self.assertEqual(status, 1, output)
        self.assertIn("SHARED", output)
        status, output = run("--workstream", "alpha", "--base", "HEAD", "--allow-shared")
        self.assertEqual(status, 0, output)
        write(self.root, "stray/file.txt")
        status, output = run("--workstream", "alpha", "--base", "HEAD", "--allow-shared")
        self.assertEqual(status, 1, output)
        self.assertIn("UNOWNED", output)
        (self.root / "stray" / "file.txt").unlink()
        (self.root / "docs" / "readme.md").unlink()
        # A new test file that carries the workstream slug is allowed without approval; one that does not is shared.
        write(self.root, "Tests/AlphaStripTests.swift")
        status, output = run("--workstream", "alpha", "--base", "HEAD")
        self.assertEqual(status, 0, output)
        self.assertIn("1 new test", output)
        write(self.root, "Tests/StripTests.swift")
        status, output = run("--workstream", "alpha", "--base", "HEAD")
        self.assertEqual(status, 1, output)
        self.assertIn("must contain", output)
        self.assertEqual(run("--workstream", "alpha", "--base", "HEAD", "--allow-shared")[0], 0)
        # Usage errors and the listing modes.
        self.assertEqual(run("--workstream", "no-such", "--base", "HEAD")[0], 2)
        self.assertEqual(run("--workstream", "alpha")[0], 2)
        status, output = run("--list", "--workstream", "alpha")
        self.assertEqual(status, 0)
        self.assertIn("Sources/**", output)
        status, output = run("--audit")
        self.assertEqual(status, 0)
        self.assertIn("unowned files", output)


class SyntaxGateLogicTests(unittest.TestCase):
    def test_a_file_fails_only_when_it_has_more_nodes_than_its_baseline(self):
        found = {"clean.swift": [], "known.swift": [(1, 1, "ERROR")] * 3, "worse.swift": [(1, 1, "ERROR")] * 4,
                 "new.swift": [(2, 2, "MISSING }")], "better.swift": [(1, 1, "ERROR")]}
        allowed = {"known.swift": 3, "worse.swift": 3, "better.swift": 2}
        result = check_swift_syntax.evaluate(found, allowed)
        self.assertEqual(result.failures, [("new.swift", 1, 0), ("worse.swift", 4, 3)])
        self.assertEqual(result.known, [("better.swift", 1), ("known.swift", 3)])
        self.assertEqual(result.improved, [("better.swift", 1, 2)])

    def test_a_baseline_file_that_became_clean_is_reported_as_improved(self):
        result = check_swift_syntax.evaluate({"was.swift": []}, {"was.swift": 2})
        self.assertEqual(result.failures, [])
        self.assertEqual(result.improved, [("was.swift", 0, 2)])

    def test_baseline_validation(self):
        def load(document):
            with tempfile.TemporaryDirectory() as directory:
                path = write(directory, "baseline.json", document if isinstance(document, str) else json.dumps(document))
                return check_swift_syntax.load_baseline(path)

        good = load({"recordedWith": {"tree-sitter": "1"}, "files": {"a.swift": {"errorNodes": 2, "comment": "x"}}})
        self.assertEqual(good.allowed, {"a.swift": 2})
        self.assertEqual(good.recorded_with, {"tree-sitter": "1"})
        for bad in ["not json", [], {}, {"files": []}, {"files": {"a.swift": 2}}, {"files": {"a.swift": {"errorNodes": -1}}},
                    {"files": {"a.swift": {"errorNodes": True}}}, {"files": {}, "recordedWith": []}]:
            with self.subTest(bad=bad):
                with self.assertRaises(check_swift_syntax.BaselineError):
                    load(bad)

    def test_the_repository_baseline_loads_and_names_files_that_exist(self):
        baseline = check_swift_syntax.load_baseline(check_swift_syntax.DEFAULT_BASELINE)
        self.assertGreaterEqual(len(baseline.allowed), 3)
        for name, count in baseline.allowed.items():
            self.assertGreater(count, 0, name)
            self.assertTrue((ROOT / name).is_file(), name)

    def test_two_modes_at_once_are_a_usage_error(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            with self.assertRaises(SystemExit) as raised:
                check_swift_syntax.main(["--all", "--base", "HEAD"])
        self.assertEqual(raised.exception.code, 2)
        self.assertIn("only one of", err.getvalue())

    def test_a_bare_run_checks_every_file(self):
        versions = {"tree-sitter": "1", "tree-sitter-swift": "1"}
        with mock.patch.object(check_swift_syntax, "load_parser", return_value=object()), \
                mock.patch.object(check_swift_syntax, "package_versions", return_value=versions), \
                mock.patch.object(check_swift_syntax, "all_swift_files", return_value=[]) as listing:
            status, out, _ = captured(check_swift_syntax.main, [])
        self.assertEqual(status, 0)
        listing.assert_called_once_with()
        self.assertIn("0 file(s) checked", out)

    def test_without_the_packages_the_tool_skips_and_with_require_it_fails(self):
        tool = str(ROOT / "tools" / "check_swift_syntax.py")
        # -S drops site-packages; also disable the documented local-environment fallback so a
        # developer's ignored .venv-tools cannot turn this missing-dependency test into a real parse.
        environment = dict(os.environ, PREV_SYNTAX_NO_REEXEC="1")
        skipped = subprocess.run([sys.executable, "-S", tool, "--all"], cwd=str(ROOT), stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, universal_newlines=True, env=environment)
        self.assertEqual(skipped.returncode, 0, skipped.stderr)
        self.assertTrue(skipped.stdout.startswith("skipped:"), skipped.stdout)
        required = subprocess.run([sys.executable, "-S", tool, "--all", "--require"], cwd=str(ROOT), stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, universal_newlines=True, env=environment)
        self.assertEqual(required.returncode, 2)
        self.assertIn("error:", required.stderr)


def tree_sitter_available():
    try:
        check_swift_syntax.load_parser()
    except Exception:
        return False
    return True


@unittest.skipUnless(tree_sitter_available(), "the tree-sitter packages are not usable here")
class SyntaxGateParserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parser = check_swift_syntax.load_parser()

    def problems(self, source):
        return check_swift_syntax.syntax_problems(self.parser, source.encode("utf-8"))

    def test_valid_swift_has_no_error_nodes(self):
        self.assertEqual(self.problems("import Foundation\nstruct S { func f() -> Int { [1, 2].count } }\n"), [])

    def test_unbalanced_braces_and_brackets_are_reported(self):
        self.assertTrue(self.problems("struct S {\n    func f() {\n}\n"))
        self.assertTrue(self.problems("let values = [1, 2, 3\nlet x = 1\n"))

    def test_error_positions_are_one_based_and_ordered(self):
        found = self.problems("let a = 1\nlet values = [1, 2\n")
        self.assertTrue(found)
        self.assertEqual(found, sorted(found))
        self.assertTrue(all(line >= 1 and column >= 1 for line, column, _ in found))

    def test_the_known_false_positives_stay_within_the_baseline(self):
        baseline = check_swift_syntax.load_baseline(check_swift_syntax.DEFAULT_BASELINE)
        for name, allowed in baseline.allowed.items():
            with self.subTest(name=name):
                count = len(self.problems((ROOT / name).read_text(encoding="utf-8")))
                self.assertLessEqual(count, allowed, "the parser reports more nodes than the baseline tolerates; "
                                                      "regenerate it with --print-baseline if the packages were upgraded")

    def test_the_command_line_fails_on_a_broken_file_and_passes_a_clean_one(self):
        with tempfile.TemporaryDirectory() as directory:
            broken = write(directory, "Broken.swift", "struct S {\n    func f() {\n}\n")
            clean = write(directory, "Clean.swift", "struct S {}\n")
            _, out, _ = captured(check_swift_syntax.main, [str(clean)])
            self.assertIn("Swift syntax OK", out)
            status, out, _ = captured(check_swift_syntax.main, [str(broken)])
            self.assertEqual(status, 1)
            self.assertIn("Broken.swift", out)
            self.assertIn("FAILED", out)
            status, out, _ = captured(check_swift_syntax.main, ["--print-baseline", str(broken)])
            self.assertEqual(status, 0)
            self.assertGreater(list(json.loads(out)["files"].values())[0]["errorNodes"], 0)


class DatalessGuardTests(unittest.TestCase):
    """The static guard for Q-153: no file-opening API outside the checked owners (plan section 5, task A2)."""

    PATH = "Sources/Reader.swift"
    OWNER = "Sources/Owner.swift"
    OPEN_LINE = "let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC)"

    def tree(self, files):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        for relative, text in files.items():
            write(directory.name, relative, text)
        return Path(directory.name)

    def guard(self, files, allowlist=None):
        return check_static.check_dataless_guard(base=self.tree(files), roots=("Sources",),
                                                 allowlist=allowlist or {})

    def entry(self, apis=("open",), kind="guarded", reason="Runs inside the checked scope of its owner."):
        return check_static.GuardEntry(frozenset(apis), kind, reason)

    # The scan itself -----------------------------------------------------------------------------

    def test_a_file_with_an_unguarded_open_fails_and_names_its_line_and_api(self):
        result = self.guard({self.PATH: f"import Darwin\nfunc read() {{\n    {self.OPEN_LINE}\n}}\n"})
        self.assertEqual(result.status, check_static.FAIL)
        self.assertIn(f"{self.PATH}:3: open", result.output)

    def test_every_listed_api_is_flagged_by_its_own_identifier(self):
        samples = {
            "open": ["let fd = Darwin.open(path, O_RDONLY)", "let fd = open(path, O_RDONLY | O_NOFOLLOW)",
                     "let fd = Darwin.open(path, flags)", "const int fd = ::open(path, O_RDONLY);",
                     "let fd = Darwin.open(\n    path,\n    O_RDONLY)"],
            "openat": ["let fd = openat(parent, name, flags)", "let fd = Darwin.openat(parent, name, flags)"],
            "opendir": ["let handle = opendir(path)", "let handle = fdopendir(descriptor)"],
            "readdir": ["while let entry = readdir(handle) {"],
            "fopen": ["let file = fopen(path, \"r\")"],
            "contentsOf": ["let bytes = try Data(contentsOf: url)", "let text = try String(contentsOf: url)",
                           "let text = try String(contentsOfFile: path)", "let image = NSImage(contentsOf: url)",
                           "let data = try NSData(contentsOfFile: path)"],
            "FileHandle": ["let handle = try FileHandle(forReadingFrom: url)", "let handle = FileHandle(fileDescriptor: 3)"],
            "CGImageSourceCreateWithURL": ["let source = CGImageSourceCreateWithURL(url as CFURL, nil)"],
            "sqlite3_open": ["sqlite3_open(path, &database)", "sqlite3_open_v2(path, &database, flags, nil)"],
            "AVURLAsset": ["let asset = AVURLAsset(url: url)", "let file = try AVAudioFile(forReading: url)"],
            "MDLAsset": ["let asset = MDLAsset(url: url)"],
            "contentsOfDirectory": ["let names = try manager.contentsOfDirectory(atPath: path)",
                                    "let walker = manager.enumerator(at: url, includingPropertiesForKeys: nil)"],
            "SecStaticCodeCreateWithPath": ["SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code)"],
            "NSFileCoordinator": ["let coordinator = NSFileCoordinator(filePresenter: nil)"],
            "startDownloadingUbiquitousItem": ["try manager.startDownloadingUbiquitousItem(at: url)"],
            "PDFDocument": ["let document = PDFDocument(url: url)"],
            "contentsAtPath": ["let data = manager.contents(atPath: path)"],
            "InputStream": ["let stream = InputStream(url: url)", "let stream = InputStream(fileAtPath: path)"],
            "resourceBytes": ["for try await byte in url.resourceBytes {", "for try await line in sourceURL.lines {"],
        }
        self.assertEqual(set(samples), set(check_static.MATERIALIZATION_APIS))
        for api, lines in samples.items():
            for line in lines:
                with self.subTest(api=api, line=line):
                    hits = check_static.materialization_hits(line + "\n")
                    self.assertIn(api, [hit.api for hit in hits], hits)

    def test_calls_that_only_share_a_name_are_not_flagged(self):
        benign = [
            "session.open(url, preferences: settings.snapshot)", "workspace.open(application)",
            "try open(.object, depth: depth)", "private mutating func open(_ kind: Kind, depth: Int) throws {",
            "let owner = try PreviewMonitorDescriptor.open(watching: url, access: access)",
            "let descriptor = try access.open(url: url)", "queue.async { [self] in reopen(attempt: attempt + 1) }",
            "SystemSettingsDestination.open()", "let source = CGImageSourceCreateWithData(data as CFData, options)",
            "data.append(contentsOf: buffer.prefix(count))", "let data = Data(base64Encoded: text)",
            "let handle = try FileHandle.standardError", "func readdirectory() {}", "let value = Foo.fopenCount",
            "let asset = loadAsset(url: url)", "let manager = FileManager.default", "let rows = text.lines",
            "let stream = OutputStream(toMemory: ())", "let names = packages.contents(of: group)",
        ]
        for line in benign:
            with self.subTest(line=line):
                self.assertEqual(check_static.materialization_hits(line + "\n"), [])

    def test_comments_do_not_count_and_do_not_move_line_numbers(self):
        text = ("/// Every directory is opened with `openat(parent, name, O_DIRECTORY)`.\n"
                "    // fopen(path, \"r\") is not used.\n"
                "/* Data(contentsOf: url)\n   opendir(path) */\n"
                f"{self.OPEN_LINE}\n")
        hits = check_static.materialization_hits(text)
        self.assertEqual([(hit.line, hit.api) for hit in hits], [(5, "open")])

    def test_a_string_holding_two_slashes_does_not_hide_a_call_after_it(self):
        line = f'let base = "https://example.invalid"; {self.OPEN_LINE}'
        self.assertEqual([hit.api for hit in check_static.materialization_hits(line + "\n")], ["open"])

    def test_the_scan_reads_only_source_suffixes_under_the_roots_and_skips_test_folders(self):
        result = self.guard({
            "Sources/Notes.md": self.OPEN_LINE, "Sources/Tests/Helper.swift": self.OPEN_LINE,
            "Elsewhere/Other.swift": self.OPEN_LINE, "Sources/Clean.swift": "let value = 1\n"})
        self.assertEqual(result.status, check_static.PASS, result.output)

    def test_a_missing_root_fails_so_a_renamed_folder_cannot_turn_the_scan_into_a_pass(self):
        result = check_static.check_dataless_guard(base=self.tree({"Other/File.swift": "x\n"}),
                                                   roots=("Sources",), allowlist={})
        self.assertEqual(result.status, check_static.FAIL)
        self.assertIn("Sources is not a folder", result.detail)

    def test_a_root_without_source_files_fails(self):
        result = self.guard({"Sources/Notes.md": "x\n"})
        self.assertEqual(result.status, check_static.FAIL)
        self.assertIn("no source files", result.detail)

    def test_non_utf8_bytes_do_not_crash_the_scan(self):
        base = self.tree({self.PATH: "let value = 1\n"})
        (base / self.PATH).write_bytes(b"let value = 1 // \xff\xfe\n" + self.OPEN_LINE.encode() + b"\n")
        result = check_static.check_dataless_guard(base=base, roots=("Sources",), allowlist={})
        self.assertEqual(result.status, check_static.FAIL)
        self.assertIn(f"{self.PATH}:2: open", result.output)

    # The allowlist -------------------------------------------------------------------------------

    def test_an_allowlisted_file_passes_while_another_file_still_fails(self):
        files = {self.OWNER: f"{self.OPEN_LINE}\n"}
        allowlist = {self.OWNER: self.entry()}
        self.assertEqual(self.guard(files, allowlist).status, check_static.PASS)
        files[self.PATH] = f"{self.OPEN_LINE}\n"
        result = self.guard(files, allowlist)
        self.assertEqual(result.status, check_static.FAIL)
        self.assertIn(self.PATH, result.output)
        self.assertNotIn(f"{self.OWNER}:", result.output)

    def test_an_allowlisted_file_may_not_use_an_api_it_did_not_declare(self):
        files = {self.OWNER: f"{self.OPEN_LINE}\nlet bytes = try Data(contentsOf: url)\n"}
        result = self.guard(files, {self.OWNER: self.entry()})
        self.assertEqual(result.status, check_static.FAIL)
        self.assertIn(f"{self.OWNER}:2: contentsOf", result.output)
        self.assertNotIn(f"{self.OWNER}:1:", result.output)

    def test_an_entry_for_a_file_that_no_longer_uses_the_api_is_stale(self):
        result = self.guard({self.OWNER: "let value = 1\n"}, {self.OWNER: self.entry()})
        self.assertEqual(result.status, check_static.FAIL)
        self.assertIn("stale", result.output)
        self.assertIn(self.OWNER, result.output)

    def test_an_entry_for_a_missing_file_is_stale(self):
        result = self.guard({self.PATH: "let value = 1\n"}, {"Sources/Gone.swift": self.entry()})
        self.assertEqual(result.status, check_static.FAIL)
        self.assertIn("Sources/Gone.swift", result.output)

    def test_an_entry_that_declares_an_api_it_never_uses_is_stale(self):
        entry = self.entry(apis=("open", "fopen"))
        result = self.guard({self.OWNER: f"{self.OPEN_LINE}\n"}, {self.OWNER: entry})
        self.assertEqual(result.status, check_static.FAIL)
        self.assertIn("fopen", result.output)

    def test_a_malformed_entry_fails_the_step_instead_of_silently_allowing(self):
        bad = {
            "unknown kind": check_static.GuardEntry(frozenset({"open"}), "trusted", "Because."),
            "empty reason": check_static.GuardEntry(frozenset({"open"}), check_static.GUARDED, "  "),
            "multi-line reason": check_static.GuardEntry(frozenset({"open"}), check_static.GUARDED, "One.\nTwo."),
            "unknown api": check_static.GuardEntry(frozenset({"mmap"}), check_static.GUARDED, "A real reason."),
            "no api": check_static.GuardEntry(frozenset(), check_static.GUARDED, "A real reason."),
        }
        for name, entry in bad.items():
            with self.subTest(name):
                result = self.guard({self.OWNER: f"{self.OPEN_LINE}\n"}, {self.OWNER: entry})
                self.assertEqual(result.status, check_static.FAIL)
                self.assertIn("allowlist entry", result.output)

    def test_pending_entries_pass_but_are_counted_in_the_summary(self):
        pending = self.entry(kind=check_static.PENDING, reason="PENDING (request R1): not yet in a checked scope.")
        result = self.guard({self.OWNER: f"{self.OPEN_LINE}\n"}, {self.OWNER: pending})
        self.assertEqual(result.status, check_static.PASS)
        self.assertIn("1 pending", result.detail)
        self.assertIn(self.OWNER, result.output)

    def test_the_summary_counts_each_kind(self):
        files = {f"Sources/{name}.swift": f"{self.OPEN_LINE}\n" for name in ("A", "B", "C")}
        allowlist = {"Sources/A.swift": self.entry(),
                     "Sources/B.swift": self.entry(kind=check_static.RESOURCE, reason="The module's own bundled resource."),
                     "Sources/C.swift": self.entry(kind=check_static.NON_SOURCE, reason="Opens /dev/null only.")}
        result = self.guard(files, allowlist)
        self.assertEqual(result.status, check_static.PASS, result.output)
        for expected in ("3 files allowlisted", "1 guarded", "1 resource", "1 non-source", "0 pending"):
            self.assertIn(expected, result.detail)

    # The reason table ----------------------------------------------------------------------------

    EXPECTED_TABLE = {
        "Apps/PrevApp/Models/AppearanceSampleLibrary.swift": ("resource", {"FileHandle"}),
        "Apps/PrevApp/Models/QuickLookProviderScanner.swift": ("pending", {"open", "opendir", "readdir"}),
        "Native/CADWorker/main.cpp": ("non-source", {"open"}),
        "Packages/PreviewCore/Sources/PreviewCADFormats/CADWorkerProcess.swift": ("non-source", {"open"}),
        "Packages/PreviewCore/Sources/PreviewContracts/FormatCatalog.swift": ("resource", {"contentsOf"}),
        "Packages/PreviewCore/Sources/PreviewCore/BoundedReadAccess.swift": ("guarded", {"open"}),
        "Packages/PreviewCore/Sources/PreviewCore/PreviewMonitorDescriptor.swift": ("guarded", {"open"}),
        "Packages/PreviewCore/Sources/PreviewFormats/Containers/DirectoryReadAccess.swift":
            ("guarded", {"open", "openat", "opendir", "readdir"}),
        "Packages/PreviewCore/Sources/PreviewFormats/Containers/SQLiteInspectionAdapter.swift": ("guarded", {"sqlite3_open"}),
        "Packages/PreviewCore/Sources/PreviewFormats/Packages/CodeSigningSummary.swift":
            ("guarded", {"SecStaticCodeCreateWithPath"}),
        "Packages/PreviewCore/Sources/PreviewPreferences/BoundedPreferencesData.swift": ("pending", {"open"}),
    }

    def test_the_repository_table_is_pinned_so_a_new_entry_needs_a_reviewed_test_change(self):
        actual = {path: (entry.kind, set(entry.apis)) for path, entry in check_static.MATERIALIZATION_ALLOWLIST.items()}
        self.assertEqual(actual, self.EXPECTED_TABLE)

    def test_every_repository_entry_has_a_one_line_reason_and_a_known_kind_and_api(self):
        for path, entry in check_static.MATERIALIZATION_ALLOWLIST.items():
            with self.subTest(path):
                self.assertIn(entry.kind, check_static.GUARD_KINDS)
                self.assertTrue(entry.apis and entry.apis <= set(check_static.MATERIALIZATION_APIS), entry.apis)
                self.assertEqual(entry.reason, entry.reason.strip())
                self.assertNotIn("\n", entry.reason)
                self.assertGreaterEqual(len(entry.reason), 40)
                self.assertLessEqual(len(entry.reason), 220)
                if entry.kind == check_static.PENDING:
                    self.assertTrue(entry.reason.startswith("PENDING (request R"), entry.reason)
                self.assertTrue((ROOT / path).is_file(), path)

    def test_the_repository_passes_its_own_guard(self):
        result = check_static.check_dataless_guard()
        self.assertEqual(result.status, check_static.PASS, result.output)
        self.assertIn("pending", result.detail)

    def test_the_step_is_wired_into_the_gate_between_chrome_inks_and_swift_syntax(self):
        names = [step.name for step in check_static.build_steps()]
        index = names.index("dataless guard")
        self.assertEqual(names[index - 1], "chrome inks")
        self.assertEqual(names[index + 1], "swift syntax")
        step = check_static.build_steps()[index]
        self.assertIs(step.run, check_static.dataless_guard_step)


class RunnerTests(unittest.TestCase):
    def run_steps(self, steps, verbose=False):
        status, out, _ = captured(check_static.run_steps, steps, verbose)
        return status, out

    def test_all_passing_steps_exit_zero(self):
        steps = [check_static.Step("one", "x", lambda: check_static.Result(check_static.PASS, "fine"))]
        status, out = self.run_steps(steps)
        self.assertEqual(status, 0)
        self.assertIn("[ ok ] one", out)
        self.assertIn("1 passed, 0 skipped, 0 failed", out)

    def test_a_skipped_step_does_not_fail_the_gate_but_is_reported(self):
        steps = [check_static.Step("syntax", "x", lambda: check_static.Result(check_static.SKIP, "no tree-sitter"))]
        status, out = self.run_steps(steps)
        self.assertEqual(status, 0)
        self.assertIn("[skip] syntax", out)
        self.assertIn("1 skipped", out)

    def test_a_failing_step_exits_one_and_prints_its_output(self):
        steps = [check_static.Step("bad", "x", lambda: check_static.Result(check_static.FAIL, "broke", "line one\nline two")),
                 check_static.Step("good", "x", lambda: check_static.Result(check_static.PASS, "ok"))]
        status, out = self.run_steps(steps)
        self.assertEqual(status, 1)
        self.assertIn("[FAIL] bad", out)
        self.assertIn("line two", out)
        self.assertIn("[ ok ] good", out)  # later steps still run
        self.assertIn("FAILED", out)

    def test_a_crashing_step_counts_as_a_failure(self):
        def crash():
            raise RuntimeError("boom")
        status, out = self.run_steps([check_static.Step("crash", "x", crash)])
        self.assertEqual(status, 1)
        self.assertIn("internal error: RuntimeError: boom", out)

    def test_passing_output_is_hidden_unless_verbose(self):
        steps = [check_static.Step("one", "x", lambda: check_static.Result(check_static.PASS, "fine", "detail output"))]
        self.assertNotIn("detail output", self.run_steps(steps)[1])
        self.assertIn("detail output", self.run_steps(steps, verbose=True)[1])

    def test_a_long_failure_output_keeps_only_its_tail(self):
        output = "\n".join(f"line {number}" for number in range(100))
        steps = [check_static.Step("bad", "x", lambda: check_static.Result(check_static.FAIL, "broke", output))]
        _, out = self.run_steps(steps)
        self.assertIn("line 99", out)
        self.assertNotIn("line 10\n", out)
        self.assertIn("earlier line(s) not shown", out)

    def test_steps_run_in_the_documented_order(self):
        self.assertEqual([step.name for step in check_static.build_steps()], [
            "manifests", "appearance samples", "localization tests", "benchmark tests", "benchmark runners", "image benchmark tests", "package link inventory", "release archive tests", "host matrix", "host matrix tests",
            "cad source offer", "cad source offer tests", "cad worker protocol tests", "cad build tests", "review samples", "review sample tests", "localization",
            "shell syntax", "decision numbers", "wall-clock tests", "ownership tool", "chrome inks", "dataless guard",
            "swift syntax"])

    def test_unittest_output_is_summarized(self):
        self.assertEqual(check_static.unittest_summary("....\n----\nRan 13 tests in 0.2s\n\nOK\n"), "13 tests passed")
        self.assertEqual(check_static.unittest_summary("Ran 1 test in 0.0s\n\nOK"), "1 tests passed")


class LocalizationStepTests(unittest.TestCase):
    def step_with(self, code, output):
        with mock.patch.object(check_static, "run_command", return_value=(code, output)):
            return check_static.localization_step()

    def test_exit_status_is_the_result(self):
        self.assertEqual(self.step_with(0, "Localization references verified: 924 keys.").status, check_static.PASS)
        self.assertEqual(self.step_with(1, "Missing catalog key: x").status, check_static.FAIL)

    def test_a_missing_plutil_is_named_rather_than_left_to_a_traceback_line(self):
        result = self.step_with(1, "Localization validation failed: [Errno 2] No such file or directory: 'plutil'")
        self.assertEqual(result.status, check_static.FAIL)
        self.assertIn("plutil", result.detail)
        self.assertIn("not a localization defect", result.detail)

    def test_a_real_failure_is_not_blamed_on_plutil(self):
        result = self.step_with(1, "Placeholder mismatch: de/preview.x")
        self.assertNotIn("plutil", result.detail)


class SwiftSyntaxStepTests(unittest.TestCase):
    """The step runs the tool and reads its answer; the tool finds its own environment."""

    def run_step(self, code, output, require=False):
        with mock.patch.object(check_static, "run_command", return_value=(code, output)):
            return check_static.swift_syntax_step(require)()

    SKIPPED = "skipped: the tree-sitter packages are not importable (No module named 'x'). Create the ignored environment once"

    def test_a_skip_is_reported_with_its_cause_and_the_setup_command(self):
        result = self.run_step(0, self.SKIPPED)
        self.assertEqual(result.status, check_static.SKIP)
        self.assertIn("not importable (No module named 'x')", result.detail)
        self.assertIn("pip install tree-sitter tree-sitter-swift", result.detail)
        self.assertNotIn("Create the ignored", result.detail)

    def test_a_skip_fails_when_the_syntax_gate_is_required(self):
        self.assertEqual(self.run_step(0, self.SKIPPED, require=True).status, check_static.FAIL)

    def test_the_skip_line_is_found_after_other_output(self):
        self.assertEqual(self.run_step(0, "note: something\n" + self.SKIPPED + "\n").status, check_static.SKIP)

    def test_a_clean_run_passes_with_its_first_sentence(self):
        result = self.run_step(0, "Swift syntax OK: 2 file(s) checked. This is a syntax check only.\n")
        self.assertEqual(result.status, check_static.PASS)
        self.assertEqual(result.detail, "Swift syntax OK: 2 file(s) checked")

    def test_errors_fail_the_step_and_keep_the_output(self):
        result = self.run_step(1, "Swift syntax errors above the baseline:\n  A.swift: 2 error node(s)")
        self.assertEqual(result.status, check_static.FAIL)
        self.assertIn("above the baseline", result.output)

    def test_an_environment_error_fails_the_step_even_when_not_required(self):
        self.assertEqual(self.run_step(2, "error: cannot read baseline").status, check_static.FAIL)


def fake_interpreter(directory, name, body):
    path = Path(directory) / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/sh\n" + body + "\n", encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


class ToolsEnvironmentTests(unittest.TestCase):
    """tools/check_swift_syntax.py re-runs itself with .venv-tools when its own interpreter cannot parse."""

    def test_the_environment_interpreter_is_offered_only_when_it_is_a_different_existing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            candidate = fake_interpreter(directory, ".venv-tools/bin/python", "exit 0")
            with mock.patch.object(check_swift_syntax, "TOOLS_ENVIRONMENT_PYTHON", candidate), \
                    mock.patch.dict(os.environ, {}, clear=False):
                os.environ.pop(check_swift_syntax.NO_REEXEC_VARIABLE, None)
                self.assertEqual(check_swift_syntax.environment_interpreter(), str(candidate))
                with mock.patch.object(sys, "executable", str(candidate)):
                    self.assertIsNone(check_swift_syntax.environment_interpreter())
                os.environ[check_swift_syntax.NO_REEXEC_VARIABLE] = "1"
                self.assertIsNone(check_swift_syntax.environment_interpreter())
            missing = Path(directory) / "nothing" / "python"
            with mock.patch.object(check_swift_syntax, "TOOLS_ENVIRONMENT_PYTHON", missing):
                os.environ.pop(check_swift_syntax.NO_REEXEC_VARIABLE, None)
                self.assertIsNone(check_swift_syntax.environment_interpreter())

    def test_rerun_replaces_the_process_with_the_same_arguments_and_blocks_a_second_rerun(self):
        with mock.patch.object(check_swift_syntax.os, "execv") as execv, mock.patch.dict(os.environ, {}, clear=False):
            check_swift_syntax.rerun_with("/env/python", ["--base", "HEAD"])
            interpreter, arguments = execv.call_args[0]
            self.assertEqual(interpreter, "/env/python")
            self.assertEqual(arguments[0], "/env/python")
            self.assertTrue(arguments[1].endswith("check_swift_syntax.py"))
            self.assertEqual(arguments[2:], ["--base", "HEAD"])
            self.assertEqual(os.environ[check_swift_syntax.NO_REEXEC_VARIABLE], "1")

    def test_a_failed_exec_falls_through_to_the_skip_message(self):
        with mock.patch.object(check_swift_syntax, "load_parser", side_effect=ImportError("nothing")), \
                mock.patch.object(check_swift_syntax, "environment_interpreter", return_value="/broken/python"), \
                mock.patch.object(check_swift_syntax.os, "execv", side_effect=OSError("exec format error")), \
                mock.patch.dict(os.environ, {}, clear=False):
            status, out, _ = captured(check_swift_syntax.main, ["--all"])
        self.assertEqual(status, 0)
        self.assertTrue(out.startswith("skipped:"), out)

    def tool_in_a_temporary_repository(self, directory):
        """A copy of the tool whose ROOT is `directory`, so it looks for .venv-tools there."""
        tools = Path(directory) / "tools"
        tools.mkdir()
        shutil.copy(str(ROOT / "tools" / "check_swift_syntax.py"), str(tools / "check_swift_syntax.py"))
        return str(tools / "check_swift_syntax.py")

    def run_tool(self, tool, *arguments):
        # -S drops site-packages, so the tree-sitter packages are not importable in the first interpreter.
        done = subprocess.run([sys.executable, "-S", tool, *arguments], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True, env={key: value for key, value in os.environ.items()
                                                            if key != check_swift_syntax.NO_REEXEC_VARIABLE})
        return done.returncode, done.stdout, done.stderr

    def test_a_real_rerun_reaches_the_environment_interpreter(self):
        with tempfile.TemporaryDirectory() as directory:
            tool = self.tool_in_a_temporary_repository(directory)
            fake_interpreter(directory, ".venv-tools/bin/python", 'echo "environment ran: $@ guard=$' + check_swift_syntax.NO_REEXEC_VARIABLE + '"')
            status, out, err = self.run_tool(tool, "--all")
        self.assertEqual(status, 0, err)
        self.assertIn("environment ran:", out)
        self.assertIn("--all", out)
        self.assertIn("guard=1", out)

    def test_an_environment_that_cannot_parse_does_not_loop(self):
        with tempfile.TemporaryDirectory() as directory:
            tool = self.tool_in_a_temporary_repository(directory)
            # The "environment" is this interpreter without site-packages: it cannot import tree-sitter either.
            fake_interpreter(directory, ".venv-tools/bin/python", f'exec "{sys.executable}" -S "$@"')
            status, out, err = self.run_tool(tool, "--all")
        self.assertEqual(status, 0, err)
        self.assertTrue(out.startswith("skipped:"), out)


class StaticGateIntegrationTests(unittest.TestCase):
    def test_the_command_line_lists_its_steps_without_running_them(self):
        status, out, _ = captured(check_static.main, ["--list"])
        self.assertEqual(status, 0)
        self.assertIn("manifests", out)
        self.assertIn("swift syntax", out)

    def test_compile_problems_are_reported_without_writing_bytecode(self):
        with tempfile.TemporaryDirectory() as directory:
            good = write(directory, "good.py", "x = 1\n")
            bad = write(directory, "bad.py", "def broken(:\n")
            self.assertIsNone(check_static.compile_problem(good))
            self.assertIn("bad.py", check_static.compile_problem(bad))
            self.assertEqual(sorted(path.name for path in Path(directory).iterdir()), ["bad.py", "good.py"])


if __name__ == "__main__":
    unittest.main()
