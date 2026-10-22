#!/usr/bin/env python3
"""Unit tests for script/check_host_matrix.py (decision 027, Q-170).

    python3 -I script/test_check_host_matrix.py

Every matrix here is synthetic and lives in a temporary directory together with the records it cites, so the rules
are tested without the repository's data. The last class reads the repository's real matrix and catalog, so a catalog
format without a row, or a claim whose record was renamed, fails here without a Mac.
"""
import contextlib
import copy
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIRECTORY = Path(__file__).resolve().parent
ROOT = SCRIPT_DIRECTORY.parent
sys.path.insert(0, str(SCRIPT_DIRECTORY))

import check_host_matrix as matrix_check  # noqa: E402

RECORD = "docs/validation/finder-test-2026-10-04.md"
OTHER_RECORD = "docs/validation/other-test-2026-10-05.md"

CATALOG = {"formats": [
    {"id": "text.alpha", "thumbnail": "content"},
    {"id": "data.beta", "thumbnail": "generic"},
    {"id": "model.gamma", "thumbnail": "none"},
]}


def not_observed():
    return {"outcome": "notObserved"}


def observed(outcome="provider", host="mac-a", **extra):
    cell = {"outcome": outcome, "host": host}
    cell.update(extra)
    return cell


def format_entry(identifier, **cells):
    surfaces = {name: not_observed() for name in matrix_check.SURFACES}
    surfaces.update(cells)
    return {"id": identifier, "surfaces": surfaces}


def valid_matrix():
    return {
        "schemaVersion": 1,
        "generated": "2026-10-07",
        "hosts": [{"id": "mac-a", "os": "macOS 27.2", "hardware": "Apple M5 Pro", "signing": "development",
                   "date": "2026-10-04", "record": RECORD}],
        "formats": [
            format_entry("text.alpha", quickLookPanel=observed(note="Concealed source.")),
            format_entry("data.beta"),
            format_entry("model.gamma", finderPreview=observed("generic")),
        ],
    }


class SyntheticRepository:
    """A temporary root with two records and the synthetic catalog."""

    def __init__(self):
        self.directory = tempfile.TemporaryDirectory(prefix="host-matrix-test-")
        self.root = Path(self.directory.name)
        records = self.root / "docs" / "validation"
        records.mkdir(parents=True)
        (self.root / RECORD).write_text("# Finder test\n\n## Rebuilt-artifact follow-up\n\ntext\n\n"
                                        "```\n# not a heading\n```\n\n### `Code` heading, with punctuation!\n")
        (self.root / OTHER_RECORD).write_text("# Other\n")
        (self.root / "docs" / "notes.md").write_text("# Not a validation record\n")
        self.thumbnails, _ = matrix_check.catalog_thumbnails(CATALOG)

    def problems(self, matrix):
        return matrix_check.validate(matrix, self.thumbnails, self.root)

    def close(self):
        self.directory.cleanup()


class MatrixTestCase(unittest.TestCase):
    def setUp(self):
        self.repository = SyntheticRepository()
        self.addCleanup(self.repository.close)

    def problems(self, matrix):
        return self.repository.problems(matrix)

    def assertProblem(self, matrix, fragment):
        problems = self.problems(matrix)
        self.assertTrue(any(fragment in problem for problem in problems),
                        f"expected a problem containing {fragment!r}, got {problems}")

    def mutated(self, change):
        matrix = copy.deepcopy(valid_matrix())
        change(matrix)
        return matrix

    def cell(self, matrix, identifier="text.alpha", surface="quickLookPanel"):
        entry = next(item for item in matrix["formats"] if item["id"] == identifier)
        return entry["surfaces"][surface]


class ValidMatrixTests(MatrixTestCase):
    def test_a_complete_consistent_matrix_has_no_problems(self):
        self.assertEqual(self.problems(valid_matrix()), [])

    def test_an_empty_host_list_is_valid_when_nothing_is_claimed(self):
        matrix = valid_matrix()
        matrix["hosts"] = []
        matrix["formats"] = [format_entry(entry["id"]) for entry in matrix["formats"]]
        self.assertEqual(self.problems(matrix), [])

    def test_the_summary_counts_the_claims(self):
        text = matrix_check.summary(valid_matrix())
        self.assertIn("3 formats, 1 host(s)", text)
        self.assertIn("7 cells notObserved", text)
        self.assertIn("1 provider, 1 generic", text)

    def test_a_note_may_be_empty_or_absent(self):
        matrix = self.mutated(lambda m: self.cell(m).update(note=""))
        self.assertEqual(self.problems(matrix), [])
        matrix = self.mutated(lambda m: self.cell(m).pop("note"))
        self.assertEqual(self.problems(matrix), [])


class SchemaTests(MatrixTestCase):
    def test_the_matrix_must_be_an_object(self):
        self.assertEqual(self.problems([]), ["the matrix is not a JSON object"])

    def test_the_schema_version_is_one_and_not_true(self):
        for version in (0, 2, "1", True, None):
            with self.subTest(version=version):
                self.assertProblem(self.mutated(lambda m: m.update(schemaVersion=version)), "schemaVersion must be 1")

    def test_top_level_keys_are_exact(self):
        self.assertProblem(self.mutated(lambda m: m.pop("hosts")), "missing key `hosts`")
        self.assertProblem(self.mutated(lambda m: m.update(extra=1)), "unknown key `extra`")

    def test_generated_must_be_a_calendar_date(self):
        for value in ("2026-13-01", "2026-02-30", "26-10-07", 20261007, None, "2026-10-07T00:00"):
            with self.subTest(value=value):
                self.assertProblem(self.mutated(lambda m: m.update(generated=value)), "generated must be a calendar date")

    def test_a_host_cannot_be_dated_after_the_matrix(self):
        self.assertProblem(self.mutated(lambda m: m.update(generated="2026-10-03")), "later than `generated`")

    def test_hosts_and_formats_must_be_lists(self):
        self.assertProblem(self.mutated(lambda m: m.update(hosts={})), "hosts: not a list")
        self.assertProblem(self.mutated(lambda m: m.update(formats={})), "formats: not a list")


class HostTests(MatrixTestCase):
    def host(self, matrix):
        return matrix["hosts"][0]

    def test_host_keys_are_exact_and_the_identity_is_optional(self):
        self.assertProblem(self.mutated(lambda m: self.host(m).pop("record")), "missing key `record`")
        self.assertProblem(self.mutated(lambda m: self.host(m).update(extra="x")), "unknown key `extra`")
        self.assertEqual(self.problems(self.mutated(lambda m: self.host(m).update(identity="a retired identity"))), [])

    def test_host_ids_are_unique_and_well_formed(self):
        self.assertProblem(self.mutated(lambda m: m["hosts"].append(copy.deepcopy(self.host(m)))), "used twice")
        for value in ("", "Mac A", "-mac", None, 4):
            with self.subTest(value=value):
                self.assertProblem(self.mutated(lambda m: self.host(m).update(id=value)), "`id` must match")

    def test_signing_comes_from_the_closed_vocabulary(self):
        self.assertProblem(self.mutated(lambda m: self.host(m).update(signing="signed")), "`signing` must be one of")
        for value in matrix_check.SIGNINGS:
            self.assertEqual(self.problems(self.mutated(lambda m: self.host(m).update(signing=value))), [])

    def test_text_fields_are_one_line(self):
        for key in ("os", "hardware", "identity"):
            for value in ("", " padded ", "two\nlines", "x" * 201, 7):
                with self.subTest(key=key, value=value):
                    self.assertProblem(self.mutated(lambda m: self.host(m).update({key: value})), f"`{key}` must be one line")

    def test_host_date_must_be_a_calendar_date(self):
        self.assertProblem(self.mutated(lambda m: self.host(m).update(date="2026-02-30")), "`date` must be a calendar date")


class RecordTests(MatrixTestCase):
    def host_record(self, value):
        return self.mutated(lambda m: m["hosts"][0].update(record=value))

    def test_a_record_must_be_an_existing_markdown_file_under_docs_validation(self):
        self.assertEqual(self.problems(self.host_record(OTHER_RECORD)), [])
        for value, fragment in (("docs/validation/missing.md", "does not exist"),
                                ("docs/notes.md", "not a Markdown file under docs/validation/"),
                                ("/etc/passwd", "not a Markdown file"),
                                ("docs/validation/../notes.md", "not a Markdown file"),
                                ("docs/validation/finder-test-2026-10-04.txt", "not a Markdown file"),
                                ("docs\\validation\\x.md", "not a Markdown file"),
                                ("", "not a non-empty string"), (None, "not a non-empty string")):
            with self.subTest(value=value):
                self.assertProblem(self.host_record(value), fragment)

    def test_an_anchor_must_match_a_heading_of_the_record(self):
        self.assertEqual(self.problems(self.host_record(RECORD + "#rebuilt-artifact-follow-up")), [])
        self.assertEqual(self.problems(self.host_record(RECORD + "#code-heading-with-punctuation")), [])
        self.assertProblem(self.host_record(RECORD + "#no-such-heading"), "no heading for the anchor")
        self.assertProblem(self.host_record(RECORD + "#not-a-heading"), "no heading for the anchor")
        self.assertProblem(self.host_record(RECORD + "#"), "malformed anchor")
        self.assertProblem(self.host_record(RECORD + "#a#b"), "malformed anchor")

    def test_heading_slugs_follow_the_hosting_convention(self):
        self.assertEqual(matrix_check.heading_slug("Rebuilt-artifact follow-up"), "rebuilt-artifact-follow-up")
        self.assertEqual(matrix_check.heading_slug("`Code` heading, with punctuation!"), "code-heading-with-punctuation")
        self.assertEqual(matrix_check.heading_slugs("# One\n```\n# Two\n```\n## Three Four #\n"), {"one", "three-four"})


class FormatTests(MatrixTestCase):
    def test_every_catalog_format_needs_exactly_one_row(self):
        self.assertProblem(self.mutated(lambda m: m["formats"].pop(1)), "without a row: data.beta")
        self.assertProblem(self.mutated(lambda m: m["formats"].append(format_entry("data.beta"))), "appears more than once")
        self.assertProblem(self.mutated(lambda m: m["formats"].append(format_entry("data.delta"))), "not in the catalog")

    def test_a_row_needs_its_keys_and_a_well_formed_id(self):
        self.assertProblem(self.mutated(lambda m: m["formats"][0].pop("surfaces")), "missing key `surfaces`")
        self.assertProblem(self.mutated(lambda m: m["formats"][0].update(extra=1)), "unknown key `extra`")
        self.assertProblem(self.mutated(lambda m: m["formats"][0].update(id="Text Alpha")), "`id` must be a catalog format id")
        self.assertProblem(self.mutated(lambda m: m["formats"].append("text")), "not an object")

    def test_a_resolved_type_needs_an_observation_and_a_type_identifier(self):
        self.assertEqual(self.problems(self.mutated(lambda m: m["formats"][0].update(resolvedType="public.plain-text"))), [])
        self.assertProblem(self.mutated(lambda m: m["formats"][1].update(resolvedType="public.json")),
                           "needs at least one observed surface")
        for value in ("", "public json", 5, "-x"):
            with self.subTest(value=value):
                self.assertProblem(self.mutated(lambda m: m["formats"][0].update(resolvedType=value)),
                                   "`resolvedType` must be a type identifier")


class SurfaceTests(MatrixTestCase):
    def test_all_three_surfaces_and_no_others(self):
        for surface in matrix_check.SURFACES:
            with self.subTest(surface=surface):
                self.assertProblem(self.mutated(lambda m: m["formats"][1]["surfaces"].pop(surface)), f"missing `{surface}`")
        self.assertProblem(self.mutated(lambda m: m["formats"][1]["surfaces"].update(gallery=not_observed())),
                           "unknown surface `gallery`")
        self.assertProblem(self.mutated(lambda m: m["formats"][1].update(surfaces=[])), "surfaces: not an object")

    def test_an_outcome_comes_from_the_closed_vocabulary(self):
        for outcome in ("works", "", None, 1):
            with self.subTest(outcome=outcome):
                self.assertProblem(self.mutated(lambda m: self.cell(m).update(outcome=outcome)), "`outcome` must be one of")
        for outcome in ("provider", "otherProvider", "generic", "declined"):
            self.assertEqual(self.problems(self.mutated(lambda m: self.cell(m).update(outcome=outcome))), [])

    def test_a_not_observed_cell_carries_no_host_and_no_record(self):
        self.assertProblem(self.mutated(lambda m: self.cell(m, "data.beta", "finderPreview").update(host="mac-a")),
                           "notObserved cell cannot carry `host`")
        self.assertProblem(self.mutated(lambda m: self.cell(m, "data.beta", "finderPreview").update(record=RECORD)),
                           "notObserved cell cannot carry `record`")

    def test_an_observation_must_cite_a_listed_host(self):
        self.assertProblem(self.mutated(lambda m: self.cell(m).pop("host")), "must cite a host that is listed")
        self.assertProblem(self.mutated(lambda m: self.cell(m).update(host="mac-z")), "must cite a host that is listed")
        for outcome in ("otherProvider", "generic", "declined"):
            with self.subTest(outcome=outcome):
                self.assertProblem(self.mutated(lambda m: self.cell(m).update(outcome=outcome, host=None)),
                                   "must cite a host that is listed")

    def test_a_cell_record_overrides_the_hosts_and_is_checked(self):
        self.assertEqual(self.problems(self.mutated(lambda m: self.cell(m).update(record=OTHER_RECORD))), [])
        self.assertProblem(self.mutated(lambda m: self.cell(m).update(record="docs/validation/missing.md")), "does not exist")

    def test_a_cell_key_must_be_known_and_a_note_must_be_short_and_single_line(self):
        self.assertProblem(self.mutated(lambda m: self.cell(m).update(date="2026-10-04")), "unknown key `date`")
        for note in ("two\nlines", "x" * 241, " padded", 5):
            with self.subTest(note=note):
                self.assertProblem(self.mutated(lambda m: self.cell(m).update(note=note)), "`note` must be one line")

    def test_a_format_without_a_thumbnail_cannot_claim_a_provider_thumbnail(self):
        claim = self.mutated(lambda m: self.cell(m, "model.gamma", "finderThumbnail").update(outcome="provider", host="mac-a"))
        self.assertProblem(claim, "gives this format no thumbnail")
        generic = self.mutated(lambda m: self.cell(m, "model.gamma", "finderThumbnail").update(outcome="generic", host="mac-a"))
        self.assertEqual(self.problems(generic), [])
        other = self.mutated(lambda m: self.cell(m, "text.alpha", "finderThumbnail").update(outcome="provider", host="mac-a"))
        self.assertEqual(self.problems(other), [])


class CatalogAndCommandTests(MatrixTestCase):
    def test_catalog_problems_are_reported(self):
        self.assertIsNotNone(matrix_check.catalog_thumbnails({})[1])
        self.assertIsNotNone(matrix_check.catalog_thumbnails({"formats": [{"id": "a"}, {"id": "a"}]})[1])
        self.assertIsNotNone(matrix_check.catalog_thumbnails({"formats": [{"name": "a"}]})[1])

    def write(self, matrix=None, catalog=CATALOG):
        (self.repository.root / "matrix.json").write_text(json.dumps(matrix if matrix is not None else valid_matrix()))
        (self.repository.root / "catalog.json").write_text(json.dumps(catalog))

    def run_main(self, *extra):
        argv = ["--root", str(self.repository.root), "--matrix", str(self.repository.root / "matrix.json"),
                "--catalog", str(self.repository.root / "catalog.json"), *extra]
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = matrix_check.main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_the_command_prints_a_summary_and_exits_zero(self):
        self.write()
        code, out, err = self.run_main()
        self.assertEqual((code, err), (0, ""))
        self.assertIn("host matrix ok: 3 formats", out)

    def test_the_command_lists_the_problems_and_exits_one(self):
        self.write(self.mutated(lambda m: m["formats"].pop()))
        code, out, err = self.run_main()
        self.assertEqual((code, out), (1, ""))
        self.assertIn("without a row: model.gamma", err)
        self.assertIn("1 problem(s)", err)

    def test_unreadable_and_invalid_inputs_exit_one(self):
        code, _, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("cannot read", err)
        self.write()
        (self.repository.root / "matrix.json").write_text("{")
        code, _, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("is not valid JSON", err)

    def test_the_default_paths_are_the_repositorys(self):
        self.assertEqual(matrix_check.MATRIX_PATH, "docs/validation/host-matrix.json")
        self.assertTrue((ROOT / matrix_check.CATALOG_PATH).is_file())


class RepositoryMatrixTests(unittest.TestCase):
    """The real matrix against the real catalog and records."""

    @classmethod
    def setUpClass(cls):
        cls.matrix, error = matrix_check.read_json(ROOT / matrix_check.MATRIX_PATH)
        assert error is None, error
        catalog, error = matrix_check.read_json(ROOT / matrix_check.CATALOG_PATH)
        assert error is None, error
        cls.thumbnails, error = matrix_check.catalog_thumbnails(catalog)
        assert error is None, error

    def test_the_repository_matrix_is_complete_and_consistent(self):
        self.assertEqual(matrix_check.validate(self.matrix, self.thumbnails, ROOT), [])

    def test_every_catalog_format_has_exactly_one_row(self):
        identifiers = [entry["id"] for entry in self.matrix["formats"]]
        self.assertEqual(sorted(identifiers), sorted(self.thumbnails))

    def test_the_command_passes_on_the_repository(self):
        code, lines = matrix_check.run(ROOT, ROOT / matrix_check.MATRIX_PATH, ROOT / matrix_check.CATALOG_PATH)
        self.assertEqual(code, 0, lines)

    def test_observations_name_only_the_recorded_host_and_nothing_stronger_than_the_records(self):
        # Facts the validation records state: no Finder thumbnail surface and no macOS 15 host were observed.
        for entry in self.matrix["formats"]:
            self.assertEqual(entry["surfaces"]["finderThumbnail"]["outcome"], "notObserved", entry["id"])
        self.assertEqual([host["id"] for host in self.matrix["hosts"]],
                         ["mac-2026-10-04", "mac-quality-2026-10-08", "mac-quality-info-2026-10-08", "mac-build6-2026-10-17"])
        self.assertTrue(all("macOS 15" not in host["os"] for host in self.matrix["hosts"]))

    def test_historical_and_current_artifact_claims_stay_with_their_own_records(self):
        hosts = {host["id"]: host for host in self.matrix["hosts"]}
        self.assertIn("com.canburaksofyalioglu.filepreview", hosts["mac-2026-10-04"]["identity"])
        current = hosts["mac-quality-2026-10-08"]
        self.assertEqual(current["identity"], "org.webmeister.spacepane; source 603e0d08efb4b361724bc4a7c408e74134cb1327")
        self.assertEqual(current["signing"], "development")
        claims = {(entry["id"], surface, cell["outcome"])
                  for entry in self.matrix["formats"] for surface, cell in entry["surfaces"].items()
                  if cell.get("host") == current["id"]}
        self.assertEqual(claims, {
            ("data.json-lines", "quickLookPanel", "provider"),
            ("text.jupyter-notebook", "finderPreview", "provider"),
            ("text.jupyter-notebook", "quickLookPanel", "provider"),
        })
        information = hosts["mac-quality-info-2026-10-08"]
        self.assertEqual(information["identity"], "org.webmeister.spacepane; source 3a97e4fab6a3ac36c97f95df39cce90c63273191")
        self.assertEqual(information["signing"], "development")
        self.assertEqual(information["record"],
                         "docs/validation/quality-program-signed-host-2026-10-08.md#information-and-facts-in-the-signed-3a97e4f-artifact")
        claims = {(entry["id"], surface, cell["outcome"])
                  for entry in self.matrix["formats"] for surface, cell in entry["surfaces"].items()
                  if cell.get("host") == information["id"]}
        self.assertEqual(claims, {
            ("data.json", "finderPreview", "provider"),
            ("data.json", "quickLookPanel", "provider"),
            ("data.json-lines", "finderPreview", "provider"),
        })


if __name__ == "__main__":
    unittest.main()
