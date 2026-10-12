#!/usr/bin/env python3
"""Portable synthetic fixture/summary/fingerprint checks; no Swift build or user files."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import benchmark_release_pipeline as pipeline
import benchmark_release_native_renderer as renderer


def run(values, *, native=False, physical=True):
    samples = []
    for value in values:
        sample = {"residentBeforeBytes": 100, "residentAfterBytes": 200,
                  "lifetimePeakResidentBytes": 300}
        if native:
            sample.update({key + "Nanoseconds": value for key in
                           ["pipeline", "construction", "initialDisplayDraw", "initialDisplayCall",
                            "restyleDraw", "scrollDraw"]})
            sample["secondaryModeDrawNanoseconds"] = None
            sample["logAppendDrawNanoseconds"] = value * 2
        else:
            sample["requestNanoseconds"] = value
        if physical:
            sample.update(physicalFootprintBeforeBytes=150, physicalFootprintAfterBytes=250,
                          maxSampledPhysicalFootprintBytes=450, lifetimePeakPhysicalFootprintBytes=700)
        samples.append(sample)
    result = {"scenario": "text", "samples": samples, "baselineResidentBytes": 100,
              "baselineLifetimePeakResidentBytes": 200, "processWallNanoseconds": 50}
    if physical:
        result.update(baselinePhysicalFootprintBytes=125, baselineLifetimePeakPhysicalFootprintBytes=500)
    if native:
        result["safeUTF8Bytes"] = 12
    else:
        result["outcome"] = {"state": "ready"}
    return result


class FixtureTests(unittest.TestCase):
    def test_quality_fixtures_are_bounded_and_cover_required_presentations(self):
        with tempfile.TemporaryDirectory() as temporary:
            paths = pipeline.fixtures(Path(temporary))
            expected = {"csv", "listing", "markdown-contents", "environment", "source-1mib",
                        "json-1mib", "log-append", "log-before"}
            self.assertTrue(expected <= paths.keys(), expected - paths.keys())
            self.assertGreaterEqual(paths["csv"].stat().st_size, 250_000)
            self.assertLessEqual(paths["csv"].stat().st_size, 262_144)
            with zipfile.ZipFile(paths["listing"]) as archive:
                self.assertEqual(len(archive.infolist()), 2000)
                self.assertTrue(all(entry.date_time == (2026, 1, 1, 0, 0, 0) for entry in archive.infolist()))
            markdown = paths["markdown-contents"].read_text()
            self.assertGreaterEqual(sum(line.startswith("#") for line in markdown.splitlines()), 2)
            environment = paths["environment"].read_text()
            self.assertIn("synthetic-benchmark-private-value", environment)
            self.assertIn("\u200b", environment)
            for name in ["source-1mib", "json-1mib"]:
                content = paths[name].read_bytes()
                self.assertEqual(len(content), 1_048_576)
                self.assertLess(len(content.splitlines()), 20_000)
                self.assertLess(max(map(len, content.splitlines())), 32_768)
            self.assertIsInstance(json.loads(paths["json-1mib"].read_bytes()), dict)
            before, after = paths["log-before"].read_bytes(), paths["log-append"].read_bytes()
            self.assertTrue(after.startswith(before))
            self.assertEqual(after[len(before):].count(b"\n"), 1)

    def test_fixture_bytes_are_reproducible_and_snapshot_is_read_only(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            a, b = pipeline.fixtures(Path(first)), pipeline.fixtures(Path(second))
            self.assertEqual(a.keys(), b.keys())
            self.assertEqual({key: hashlib.sha256(path.read_bytes()).hexdigest() for key, path in a.items()},
                             {key: hashlib.sha256(path.read_bytes()).hexdigest() for key, path in b.items()})
            snapshot = pipeline.snapshot(Path(first))
            self.assertEqual(snapshot, pipeline.snapshot(Path(first)))


class SummaryTests(unittest.TestCase):
    def test_actual_physical_footprint_is_not_rss_and_includes_stage_samples(self):
        for native, module in [(False, pipeline), (True, renderer)]:
            with self.subTest(native=native):
                result = module.summarize([run([10], native=native)], run([999, 20, 30], native=native))
                memory = result["memoryBytes"]
                self.assertEqual(memory["maxBaselinePhysicalFootprint"], 125)
                self.assertEqual(memory["maxSampledPhysicalFootprint"], 450)
                self.assertEqual(memory["maxLifetimePeakPhysicalFootprint"], 700)
                self.assertEqual(memory["maxLifetimePeakPhysicalFootprintGrowthFromBaselinePeak"], 200)
                self.assertEqual(memory["maxObservedResident"], 200)

    def test_missing_legacy_physical_footprint_is_unavailable_not_zero(self):
        for native, module in [(False, pipeline), (True, renderer)]:
            result = module.summarize([run([10], native=native, physical=False)],
                                      run([999, 20], native=native, physical=False))
            self.assertIsNone(result["memoryBytes"]["maxSampledPhysicalFootprint"])
            self.assertIsNone(result["memoryBytes"]["maxLifetimePeakPhysicalFootprint"])

    def test_partially_failed_probe_does_not_claim_complete_memory_coverage(self):
        cold, warm = run([10]), run([999, 20])
        warm["samples"][1]["maxSampledPhysicalFootprintBytes"] = None
        self.assertIsNone(pipeline.summarize([cold], warm)["memoryBytes"]["maxSampledPhysicalFootprint"])

    def test_native_log_append_preserves_cold_warm_separation(self):
        result = renderer.summarize([run([10], native=True)], run([999, 20, 30], native=True))
        metric = result["logAppendDrawMilliseconds"]
        self.assertEqual(metric["firstProcess"]["max"], 20 / 1e6)
        self.assertEqual(metric["warmProcess"]["max"], 60 / 1e6)
        self.assertEqual(metric["warmProcess"]["count"], 2)


class FingerprintTests(unittest.TestCase):
    def inputs(self, directory):
        root = Path(directory)
        source = root / "Packages/PreviewCore/Sources/Test/value.swift"
        source.parent.mkdir(parents=True)
        source.write_text("let value = 1\n")
        (root / "Packages/PreviewCore/Package.swift").write_text("// manifest\n")
        return root, source

    def test_content_and_new_input_change_fingerprint_even_with_same_size(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, source = self.inputs(temporary)
            first = pipeline.source_fingerprint(root)
            source.write_text("let value = 2\n")
            second = pipeline.source_fingerprint(root)
            self.assertNotEqual(first, second)
            source.with_name("new.swift").write_text("// new input\n")
            self.assertNotEqual(second, pipeline.source_fingerprint(root))

    def test_fingerprint_is_independent_of_checkout_path_and_mtime(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            a, _ = self.inputs(first)
            b, _ = self.inputs(second)
            self.assertEqual(pipeline.source_fingerprint(a), pipeline.source_fingerprint(b))

    def test_prepared_worker_rejects_changed_sources_build_context_or_executable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, source = self.inputs(temporary)
            binary = root / "worker"
            binary.write_bytes(b"synthetic executable")
            state = {"revision": "a" * 40, "dirty": True, "sourceTreeSHA256": pipeline.source_fingerprint(root)}
            context = {"swift": "synthetic", "optimization": "-O"}
            pipeline.save_prepared_worker(binary, state, context)
            pipeline.validate_prepared_worker(binary, state, context)
            with self.assertRaisesRegex(ValueError, "stale"):
                pipeline.validate_prepared_worker(binary, state, {**context, "optimization": "-Onone"})
            source.write_text("let value = 2\n")
            with self.assertRaisesRegex(ValueError, "stale"):
                pipeline.validate_prepared_worker(binary, {**state, "sourceTreeSHA256": pipeline.source_fingerprint(root)}, context)
            binary.write_bytes(b"changed executable")
            with self.assertRaisesRegex(ValueError, "stale"):
                pipeline.validate_prepared_worker(binary, state, context)

    def test_missing_build_metadata_cannot_validate_skip_build(self):
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / "worker"
            binary.write_bytes(b"synthetic")
            with self.assertRaisesRegex(ValueError, "prepared"):
                pipeline.validate_prepared_worker(binary, {}, {})


if __name__ == "__main__":
    unittest.main()
