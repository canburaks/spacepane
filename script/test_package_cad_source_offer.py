#!/usr/bin/env python3
"""Unit tests for script/package_cad_source_offer.py (decision 027, Q-171).

    python3 -I script/test_package_cad_source_offer.py

Most tests assemble a bundle from a small synthetic repository in a temporary directory, so every rule can be broken
on its own. The last class assembles the real repository, so a changed pin, a missing notice or a file the helper's
CMake file names but the tree lacks fails here without a Mac. Nothing here touches the network: the socket calls are
replaced by ones that fail the test.
"""
import contextlib
import hashlib
import io
import os
import socket
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT_DIRECTORY = Path(__file__).resolve().parent
ROOT = SCRIPT_DIRECTORY.parent
sys.path.insert(0, str(SCRIPT_DIRECTORY))

import package_cad_source_offer as offer  # noqa: E402

REVISION = "0123456789abcdef0123456789abcdef01234567"
ARCHIVE_BYTES = b"synthetic occt archive"
CHECKSUM = hashlib.sha256(ARCHIVE_BYTES).hexdigest()
URL = offer.ARCHIVE_URL_PREFIX + REVISION

BUILD_SCRIPT = f'''#!/usr/bin/env python3
"""Synthetic build script."""
REVISION = "{REVISION}"  # official V0_0_1
ARCHIVE_SHA256 = "{CHECKSUM}"
ARCHIVE_URL = "{offer.ARCHIVE_URL_PREFIX}" + REVISION


def narrow_manifests(source):
    # Build-manifest changes only.
    return source


def main():
    configure = ["cmake", "-S", "x"]
    return configure


if __name__ == "__main__":
    main()
'''

OFFER_TEXT = f"""# Offer

Status: draft, pending legal review.

OCCT 7.9.3, commit {REVISION}, archive {URL}, SHA-256 {CHECKSUM}.
See ThirdPartyNotices/OCCT, build_cad_worker.py and MANIFEST.sha256.
"""

LICENSE_TEXT = "MIT License\n\nPermission is hereby granted, free of charge, to any person obtaining a copy.\n"
NOTICE = f"This product uses OCCT 7.9.3, official commit {REVISION}.\nArchive {URL}\nSHA256: {CHECKSUM}\n"
RECORD = f"# Audit\nCommit `{REVISION}`, SHA256 `{CHECKSUM}`.\n"
CMAKE = "project(X)\nadd_executable(CADWorker main.cpp Other.cpp)\n"


def make_root(directory: Path) -> Path:
    files = {
        offer.BUILD_SCRIPT: BUILD_SCRIPT,
        offer.EMBED_SCRIPT: "print('embed')\n",
        offer.ENTITLEMENTS: "<plist/>\n",
        offer.OFFER: OFFER_TEXT,
        offer.LICENSE_SOURCE: LICENSE_TEXT,
        offer.NOTICE_SUMMARY: NOTICE,
        offer.DEPENDENCY_RECORD: RECORD,
        offer.WORKER_CMAKE: CMAKE,
        "Native/CADWorker/main.cpp": "int main() { return 0; }\n",
        "Native/CADWorker/Other.cpp": "// other\n",
        "Native/CADWorker/Tests/test.py": "# test\n",
        "Native/CADWorker/Tests/Fixtures/box.step": "ISO-10303-21;\n",
    }
    files.update({f"{offer.NOTICE_DIRECTORY}/{name}": f"notice {name}\n" for name in offer.REQUIRED_NOTICES
                  if name != "NOTICE.txt"})
    for relative, text in files.items():
        path = directory / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return directory


class NetworkForbidden(unittest.TestCase):
    """Replaces every way this script could reach the network with a failure."""

    def setUp(self):
        def refuse(*arguments, **keywords):
            raise AssertionError("the packaging script used the network")
        for target in ("socket.socket.connect", "socket.create_connection", "socket.getaddrinfo"):
            patcher = mock.patch(target, side_effect=refuse)
            patcher.start()
            self.addCleanup(patcher.stop)


class RepositoryCase(NetworkForbidden):
    def setUp(self):
        super().setUp()
        self.directory = tempfile.TemporaryDirectory(prefix="cad-offer-test-")
        self.addCleanup(self.directory.cleanup)
        self.scratch = Path(self.directory.name)
        self.root = make_root(self.scratch / "repository")
        self.output = self.scratch / "bundle"

    def edit(self, relative, change):
        path = self.root / relative
        path.write_text(change(path.read_text(encoding="utf-8")), encoding="utf-8")

    def assemble(self, **keywords):
        return offer.assemble(self.root, self.output, **keywords)

    def pinned(self):
        return offer.pinned_reference(self.root)

    def bundle_problems(self):
        return offer.bundle_problems(self.output, self.pinned())

    def assertInputProblem(self, fragment):
        problems = offer.input_problems(self.root)
        self.assertTrue(any(fragment in problem for problem in problems), f"{fragment!r} not in {problems}")

    def assertBundleProblem(self, fragment):
        problems = self.bundle_problems()
        self.assertTrue(any(fragment in problem for problem in problems), f"{fragment!r} not in {problems}")


class PinnedReferenceTests(RepositoryCase):
    def test_the_pin_is_read_from_the_build_script_without_running_it(self):
        pinned = self.pinned()
        self.assertEqual((pinned.revision, pinned.sha256, pinned.url, pinned.version), (REVISION, CHECKSUM, URL, "7.9.3"))
        self.assertEqual(pinned.archive_path, f".build/cad/occt-{REVISION}.tar.gz")

    def test_a_build_script_that_does_not_pin_is_rejected(self):
        cases = (("REVISION =", "RENAMED ="), ('"' + REVISION + '"', '"abc"'), ('"' + CHECKSUM + '"', '"xyz"'),
                 ('+ REVISION', '+ "other"'))
        for old, new in cases:
            with self.subTest(old=old):
                (self.root / offer.BUILD_SCRIPT).write_text(BUILD_SCRIPT.replace(old, new, 1), encoding="utf-8")
                self.assertTrue(offer.input_problems(self.root))

    def test_a_build_script_without_the_manifest_function_cannot_be_excerpted(self):
        (self.root / offer.BUILD_SCRIPT).write_text(BUILD_SCRIPT.replace("def narrow_manifests(source):",
                                                                         "def narrow(source):"), encoding="utf-8")
        self.assertEqual(offer.input_problems(self.root), [])
        with self.assertRaises(offer.OfferError):
            offer.assemble(self.root, self.scratch / "never")

    def test_a_script_that_does_not_parse_is_reported(self):
        (self.root / offer.BUILD_SCRIPT).write_text("def broken(:\n", encoding="utf-8")
        self.assertInputProblem("does not parse")

    def test_a_computed_pin_is_refused(self):
        (self.root / offer.BUILD_SCRIPT).write_text(BUILD_SCRIPT.replace(f'REVISION = "{REVISION}"', "REVISION = str(1)"),
                                                    encoding="utf-8")
        self.assertInputProblem("not a plain string")

    def test_the_notice_must_name_a_version(self):
        (self.root / offer.NOTICE_SUMMARY).write_text(f"commit {REVISION} {URL} {CHECKSUM}\n", encoding="utf-8")
        self.assertInputProblem("names no OCCT version")


class InputTests(RepositoryCase):
    def test_a_consistent_repository_has_no_problems(self):
        self.assertEqual(offer.input_problems(self.root), [])

    def test_each_required_file_is_required(self):
        required = [offer.EMBED_SCRIPT, offer.ENTITLEMENTS, offer.OFFER, offer.DEPENDENCY_RECORD, offer.WORKER_CMAKE,
                    f"{offer.NOTICE_DIRECTORY}/LICENSE_LGPL_21.txt", f"{offer.NOTICE_DIRECTORY}/OCCT_LGPL_EXCEPTION.txt",
                    f"{offer.NOTICE_DIRECTORY}/BISON_NOTICE.txt"]
        for relative in required:
            with self.subTest(relative=relative):
                backup = (self.root / relative).read_bytes()
                (self.root / relative).unlink()
                self.assertInputProblem(f"missing {relative}")
                (self.root / relative).write_bytes(backup)

    def test_the_three_statements_must_agree_with_the_build_script(self):
        for relative in (offer.NOTICE_SUMMARY, offer.DEPENDENCY_RECORD, offer.OFFER):
            for value in (REVISION, CHECKSUM):
                with self.subTest(relative=relative, value=value[:8]):
                    original = (self.root / relative).read_text(encoding="utf-8")
                    self.edit(relative, lambda text: text.replace(value, "f" * len(value)))
                    self.assertInputProblem(f"{relative} does not state the pinned value")
                    (self.root / relative).write_text(original, encoding="utf-8")

    def test_the_offer_states_the_url_and_the_version_and_is_marked_pending(self):
        self.edit(offer.OFFER, lambda text: text.replace(URL, "https://example.org/elsewhere"))
        self.assertInputProblem("does not state the pinned value https://")
        self.edit(offer.OFFER, lambda text: text.replace("7.9.3", "7.8.0"))
        self.assertInputProblem("does not state the pinned value 7.9.3")

    def test_a_missing_or_empty_helper_license_is_a_problem(self):
        (self.root / offer.LICENSE_SOURCE).write_text("  \n", encoding="utf-8")
        self.assertInputProblem(f"{offer.LICENSE_SOURCE} is empty")
        (self.root / offer.LICENSE_SOURCE).unlink()
        self.assertInputProblem(f"missing {offer.LICENSE_SOURCE}")

    def test_an_unfilled_placeholder_in_the_offer_is_a_problem(self):
        for gap in ("[support address, to be supplied before release]",
                    "[designated download location, to be published with the release]"):
            with self.subTest(gap=gap):
                original = (self.root / offer.OFFER).read_text(encoding="utf-8")
                self.edit(offer.OFFER, lambda text: text + f"\nRequests go to {gap}.\n")
                self.assertInputProblem(f"still has the placeholder {gap}")
                (self.root / offer.OFFER).write_text(original, encoding="utf-8")

    def test_the_offer_must_be_marked_pending_legal_review(self):
        self.edit(offer.OFFER, lambda text: text.replace("pending legal review", "approved"))
        self.assertInputProblem("is not marked 'pending legal review'")

    def test_the_offer_must_point_at_what_it_promises(self):
        for needed in ("build_cad_worker.py", "ThirdPartyNotices/OCCT", "MANIFEST.sha256"):
            with self.subTest(needed=needed):
                original = (self.root / offer.OFFER).read_text(encoding="utf-8")
                self.edit(offer.OFFER, lambda text: text.replace(needed, "elsewhere"))
                self.assertInputProblem(f"never mentions {needed}")
                (self.root / offer.OFFER).write_text(original, encoding="utf-8")

    def test_every_source_the_cmake_file_names_must_exist(self):
        (self.root / "Native/CADWorker/Other.cpp").unlink()
        self.assertInputProblem("names Other.cpp")
        self.edit(offer.WORKER_CMAKE, lambda text: text.replace("add_executable(CADWorker", "add_library(CADWorker"))
        self.assertInputProblem("has no add_executable(CADWorker")

    def test_a_link_in_the_worker_tree_is_refused(self):
        os.symlink("/etc/passwd", self.root / "Native/CADWorker/link.txt")
        self.assertInputProblem("symbolic link")


class AssemblyTests(RepositoryCase):
    def test_the_bundle_mirrors_the_repository_and_is_complete(self):
        names = self.assemble()
        expected = {"SOURCE-OFFER.md", "PINNED-SOURCE.txt", "MANIFEST.sha256", "LICENSE", "README.md",
                    offer.LICENSE_SOURCE, "excerpts/narrow_manifests.py.txt",
                    "excerpts/build_cad_worker_main.py.txt", offer.BUILD_SCRIPT, offer.EMBED_SCRIPT, offer.ENTITLEMENTS,
                    offer.DEPENDENCY_RECORD, offer.OFFER, offer.WORKER_CMAKE, "Native/CADWorker/main.cpp",
                    "Native/CADWorker/Other.cpp", "Native/CADWorker/Tests/test.py",
                    "Native/CADWorker/Tests/Fixtures/box.step", offer.NOTICE_SUMMARY}
        expected |= {f"{offer.NOTICE_DIRECTORY}/{name}" for name in offer.REQUIRED_NOTICES}
        self.assertEqual(set(names), expected)
        self.assertEqual(self.bundle_problems(), [])

    def test_files_are_copied_byte_for_byte_and_the_root_offer_is_the_worker_offer(self):
        self.assemble()
        for relative in (offer.BUILD_SCRIPT, offer.WORKER_CMAKE, "Native/CADWorker/main.cpp", offer.NOTICE_SUMMARY):
            self.assertEqual((self.output / relative).read_bytes(), (self.root / relative).read_bytes(), relative)
        self.assertEqual((self.output / "SOURCE-OFFER.md").read_bytes(), (self.root / offer.OFFER).read_bytes())

    def test_the_manifest_lists_every_other_file_with_its_hash_in_sorted_order(self):
        names = self.assemble()
        lines = (self.output / "MANIFEST.sha256").read_text(encoding="utf-8").splitlines()
        listed = [line.split("  ", 1)[1] for line in lines]
        self.assertEqual(listed, sorted(name for name in names if name != "MANIFEST.sha256"))
        for line in lines:
            digest, name = line.split("  ", 1)
            self.assertEqual(digest, hashlib.sha256((self.output / name).read_bytes()).hexdigest())

    def test_the_pinned_source_file_states_the_reference_and_the_missing_archive(self):
        self.assemble()
        text = (self.output / "PINNED-SOURCE.txt").read_text(encoding="utf-8")
        for value in (REVISION, CHECKSUM, URL, "7.9.3", "pending legal review", "Not included in this bundle"):
            self.assertIn(value, text)

    def test_the_excerpts_are_the_scripts_own_functions(self):
        self.assemble()
        self.assertIn("def narrow_manifests(source):", (self.output / offer.EXCERPT_MANIFESTS).read_text(encoding="utf-8"))
        self.assertIn("def main():", (self.output / offer.EXCERPT_BUILD).read_text(encoding="utf-8"))

    def test_build_artifacts_are_left_out(self):
        for name in ("Native/CADWorker/main.o", "Native/CADWorker/libx.a", "Native/CADWorker/.DS_Store",
                     "Native/CADWorker/__pycache__/x.pyc", "Native/CADWorker/Tests/helper.pyc"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"x")
        names = self.assemble()
        self.assertFalse([name for name in names if name.endswith((".o", ".a", ".pyc", ".DS_Store"))])

    def test_the_output_must_be_new_or_empty(self):
        self.output.mkdir()
        (self.output / "old.txt").write_text("x")
        with self.assertRaises(offer.OfferError):
            self.assemble()
        (self.output / "old.txt").unlink()
        self.assemble()

    def test_assembly_refuses_an_inconsistent_repository(self):
        (self.root / "Native/CADWorker/Other.cpp").unlink()
        with self.assertRaises(offer.OfferError):
            self.assemble()
        self.assertFalse(self.output.exists())

    def test_the_same_repository_gives_the_same_bundle_and_tarball(self):
        first, second = self.scratch / "first", self.scratch / "second"
        offer.assemble(self.root, first)
        offer.assemble(self.root, second)
        self.assertEqual((first / "MANIFEST.sha256").read_bytes(), (second / "MANIFEST.sha256").read_bytes())
        offer.write_tarball(first, self.scratch / "first.tar.gz")
        offer.write_tarball(first, self.scratch / "again.tar.gz")
        self.assertEqual((self.scratch / "first.tar.gz").read_bytes(), (self.scratch / "again.tar.gz").read_bytes())

    def test_the_tarball_has_one_top_folder_and_only_safe_members(self):
        self.assemble()
        offer.write_tarball(self.output, self.scratch / "bundle.tar.gz")
        with tarfile.open(self.scratch / "bundle.tar.gz") as archive:
            members = archive.getmembers()
        self.assertTrue(members)
        for member in members:
            self.assertTrue(member.isreg(), member.name)
            self.assertTrue(member.name.startswith("bundle/"), member.name)
            self.assertNotIn("..", member.name.split("/"))
            self.assertEqual((member.uid, member.gid, member.mtime, member.mode), (0, 0, 0, 0o644))
        self.assertEqual(len(members), len(offer.bundle_files(self.output)))


class ArchiveTests(RepositoryCase):
    def archive(self, data=ARCHIVE_BYTES):
        path = self.scratch / "archive.tar.gz"
        path.write_bytes(data)
        return path

    def test_a_local_archive_with_the_pinned_checksum_is_placed_where_the_build_script_looks(self):
        names = self.assemble(archive=self.archive())
        pinned = self.pinned()
        self.assertIn(pinned.archive_path, names)
        self.assertEqual((self.output / pinned.archive_path).read_bytes(), ARCHIVE_BYTES)
        self.assertIn("Included in this bundle", (self.output / "PINNED-SOURCE.txt").read_text(encoding="utf-8"))
        self.assertEqual(self.bundle_problems(), [])

    def test_an_archive_with_another_checksum_is_refused(self):
        with self.assertRaises(offer.OfferError):
            self.assemble(archive=self.archive(b"another archive"))
        self.assertFalse(self.output.exists())

    def test_a_missing_archive_is_refused(self):
        with self.assertRaises(offer.OfferError):
            self.assemble(archive=self.scratch / "absent.tar.gz")

    def test_a_tampered_archive_in_a_bundle_is_detected(self):
        self.assemble(archive=self.archive())
        (self.output / self.pinned().archive_path).write_bytes(b"tampered")
        self.assertBundleProblem("does not have the pinned SHA-256")

    def test_an_archive_that_the_pinned_file_promises_but_is_absent_is_detected(self):
        self.assemble(archive=self.archive())
        archive = self.output / self.pinned().archive_path
        archive.unlink()
        self.assertBundleProblem("is missing")


class BundleVerificationTests(RepositoryCase):
    def setUp(self):
        super().setUp()
        self.assemble()

    def test_a_pristine_bundle_passes(self):
        self.assertEqual(self.bundle_problems(), [])

    def test_a_missing_directory_fails(self):
        self.assertEqual(offer.bundle_problems(self.scratch / "nothing", self.pinned()),
                         [f"{self.scratch / 'nothing'} is not a directory"])

    def test_every_required_file_is_required_in_the_bundle(self):
        for name in ("SOURCE-OFFER.md", "PINNED-SOURCE.txt", "MANIFEST.sha256", offer.EXCERPT_MANIFESTS, offer.BUILD_SCRIPT,
                     offer.ENTITLEMENTS, f"{offer.NOTICE_DIRECTORY}/LICENSE_LGPL_21.txt"):
            with self.subTest(name=name):
                path = self.output / name
                backup = path.read_bytes()
                path.unlink()
                self.assertBundleProblem(f"lacks {name}")
                path.write_bytes(backup)

    def test_a_changed_file_is_caught_by_the_manifest(self):
        (self.output / "Native/CADWorker/main.cpp").write_text("int main() { return 1; }\n")
        self.assertBundleProblem("Native/CADWorker/main.cpp does not match its hash")

    def test_an_unlisted_file_is_caught(self):
        (self.output / "extra.txt").write_text("x")
        self.assertBundleProblem("extra.txt is in the bundle but not in MANIFEST.sha256")

    def test_a_listed_file_that_is_missing_is_caught(self):
        (self.output / "Native/CADWorker/Other.cpp").unlink()
        self.assertBundleProblem("lists Native/CADWorker/Other.cpp, which is missing")
        self.assertBundleProblem("which the helper's CMake file names")

    def test_a_malformed_manifest_is_caught(self):
        with (self.output / "MANIFEST.sha256").open("a") as stream:
            stream.write("not a manifest line\n")
        self.assertBundleProblem("is not '<sha256>  <path>'")

    def test_a_manifest_path_that_escapes_is_caught(self):
        with (self.output / "MANIFEST.sha256").open("a") as stream:
            stream.write(f"{'0' * 64}  ../outside\n")
        self.assertBundleProblem("invalid path")

    def test_a_link_in_the_bundle_is_caught(self):
        os.symlink("main.cpp", self.output / "Native/CADWorker/alias.cpp")
        self.assertBundleProblem("alias.cpp is a symbolic link")

    def test_the_pinned_values_and_the_pending_mark_must_be_in_both_texts(self):
        for name in ("PINNED-SOURCE.txt", "SOURCE-OFFER.md"):
            with self.subTest(name=name):
                path = self.output / name
                backup = path.read_text(encoding="utf-8")
                path.write_text(backup.replace(CHECKSUM, "0" * 64).replace("pending legal review", "final"), encoding="utf-8")
                self.assertBundleProblem(f"{name} does not state the pinned value {CHECKSUM}")
                self.assertBundleProblem(f"{name} is not marked 'pending legal review'")
                path.write_text(backup, encoding="utf-8")

    def test_the_root_license_must_equal_the_helper_license(self):
        (self.output / "LICENSE").write_text("MIT License, edited\n", encoding="utf-8")
        self.assertBundleProblem("LICENSE differs from")

    def test_version_control_metadata_is_not_part_of_a_bundle(self):
        (self.output / ".git").mkdir()
        (self.output / ".git" / "HEAD").write_text("ref: refs/heads/main\n", encoding="utf-8")
        self.assertEqual(self.bundle_problems(), [])

    def test_the_readme_states_the_pin_and_the_rebuild_command(self):
        text = (self.output / "README.md").read_text(encoding="utf-8")
        for value in (REVISION, CHECKSUM, URL, "7.9.3", "build_cad_worker.py --architecture arm64 --test"):
            self.assertIn(value, text)

    def test_the_root_offer_must_equal_the_worker_offer(self):
        text = (self.output / "SOURCE-OFFER.md").read_text(encoding="utf-8")
        (self.output / "SOURCE-OFFER.md").write_text(text + "\nextra\n", encoding="utf-8")
        self.assertBundleProblem("differs from")


class CommandTests(RepositoryCase):
    def run_main(self, *arguments):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                code = offer.main(["--root", str(self.root), *arguments])
            except SystemExit as stop:
                code = stop.code
        return code, out.getvalue(), err.getvalue()

    def test_check_passes_on_a_consistent_repository(self):
        code, out, err = self.run_main("--check")
        self.assertEqual((code, err), (0, ""))
        self.assertIn("CAD source offer ok", out)
        self.assertIn("pending legal review", out)

    def test_check_reports_each_problem_and_exits_one(self):
        (self.root / "Native/CADWorker/Other.cpp").unlink()
        code, out, err = self.run_main("--check")
        self.assertEqual((code, out), (1, ""))
        self.assertIn("names Other.cpp", err)
        self.assertIn("problem(s)", err)

    def test_output_writes_the_bundle_and_the_tarball(self):
        code, out, err = self.run_main("--output", str(self.output), "--tarball", str(self.scratch / "b.tar.gz"))
        self.assertEqual((code, err), (0, ""))
        self.assertIn("wrote", out)
        self.assertTrue((self.scratch / "b.tar.gz").is_file())
        code, out, err = self.run_main("--check", str(self.output))
        self.assertEqual((code, err), (0, ""))
        self.assertIn("bundle ok", out)

    def test_check_of_a_tampered_bundle_exits_one(self):
        self.run_main("--output", str(self.output))
        (self.output / "PINNED-SOURCE.txt").write_text("x")
        code, _, err = self.run_main("--check", str(self.output))
        self.assertEqual(code, 1)
        self.assertIn("PINNED-SOURCE.txt", err)

    def test_the_output_directory_must_be_empty_or_new(self):
        self.output.mkdir()
        (self.output / "x").write_text("x")
        code, _, err = self.run_main("--output", str(self.output))
        self.assertEqual(code, 1)
        self.assertIn("not an empty directory", err)

    def test_include_archive_is_verified_on_the_command_line(self):
        archive = self.scratch / "a.tar.gz"
        archive.write_bytes(b"wrong")
        code, _, err = self.run_main("--output", str(self.output), "--include-archive", str(archive))
        self.assertEqual(code, 1)
        self.assertIn("pinned SHA-256", err)
        archive.write_bytes(ARCHIVE_BYTES)
        code, _, err = self.run_main("--output", str(self.scratch / "good"), "--include-archive", str(archive))
        self.assertEqual((code, err), (0, ""))

    def test_usage_errors_exit_two(self):
        self.assertEqual(self.run_main()[0], 2)
        self.assertEqual(self.run_main("--check", "--output", str(self.output))[0], 2)
        self.assertEqual(self.run_main("--check", "--tarball", str(self.scratch / "t.tar.gz"))[0], 2)

    def test_the_script_imports_nothing_that_could_reach_the_network(self):
        source = (SCRIPT_DIRECTORY / "package_cad_source_offer.py").read_text(encoding="utf-8")
        for module in ("socket", "urllib", "http", "requests", "ssl", "ftplib", "subprocess"):
            self.assertNotRegex(source, rf"^\s*(import|from)\s+{module}\b", module)


class RepositoryBundleTests(NetworkForbidden):
    """The real repository: the pin, the notices, the worker's own file list."""

    def test_the_repository_inputs_are_consistent(self):
        self.assertEqual(offer.input_problems(ROOT), [])

    def test_the_repository_assembles_a_complete_bundle(self):
        problems, message = offer.check_repository(ROOT)
        self.assertEqual(problems, [])
        self.assertIn("pending legal review", message)

    def test_the_bundle_holds_every_source_the_helper_builds_and_the_real_pin(self):
        with tempfile.TemporaryDirectory(prefix="cad-offer-real-") as scratch:
            bundle = Path(scratch) / "bundle"
            names = set(offer.assemble(ROOT, bundle))
            for source in offer.cmake_sources(ROOT):
                self.assertIn(f"{offer.WORKER_DIRECTORY}/{source}", names)
            pinned = offer.pinned_reference(ROOT)
            self.assertEqual(len(pinned.revision), 40)
            self.assertIn(pinned.sha256, (bundle / "PINNED-SOURCE.txt").read_text(encoding="utf-8"))
            self.assertEqual(sorted(name for name in names if name.startswith(offer.NOTICE_DIRECTORY)),
                             sorted(offer.tree_files(ROOT, offer.NOTICE_DIRECTORY)))

    def test_the_pin_matches_the_documented_archive(self):
        pinned = offer.pinned_reference(ROOT)
        self.assertEqual(pinned.revision, "a016080bf6738d6aeae020badee4e888ad1540a5")
        self.assertEqual(pinned.sha256, "c533f2667b59921bd6bd40ce82e7b9900b0289ccc731af5fdeeba097de80ef0f")


if __name__ == "__main__":
    unittest.main()
