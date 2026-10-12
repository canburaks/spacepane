#!/usr/bin/env python3
"""Portable Q-24 statistics and evidence checks: python3 -I script/test_compare_benchmarks.py.

Synthetic reports use the actual schema-1 runner summary functions. No worker,
Swift toolchain, user file, clock wait or third-party dependency is involved.
"""
import contextlib
from datetime import datetime, timedelta, timezone
import io
import json
import math
import os
from pathlib import Path
import random
import statistics
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import benchmark_release_native_renderer as renderer_runner
import benchmark_release_pipeline as pipeline_runner
import compare_benchmarks as comparison


def worker(values, *, renderer=False, secondary=True):
    samples = []
    for value in values:
        sample = {"residentBeforeBytes": 100, "residentAfterBytes": 200,
                  "lifetimePeakResidentBytes": 300}
        if renderer:
            sample.update({"pipelineNanoseconds": value * 1_000_000,
                           "constructionNanoseconds": 2_000_000,
                           "initialDisplayDrawNanoseconds": 3_000_000,
                           "initialDisplayCallNanoseconds": 1_000_000,
                           "restyleDrawNanoseconds": 4_000_000,
                           "scrollDrawNanoseconds": 5_000_000})
            if secondary:
                sample["secondaryModeDrawNanoseconds"] = 6_000_000
        else:
            sample["requestNanoseconds"] = value * 1_000_000
        samples.append(sample)
    result = {"scenario": "text", "samples": samples, "baselineResidentBytes": 100,
              "baselineLifetimePeakResidentBytes": 100, "processWallNanoseconds": 50_000_000}
    if renderer:
        result["safeUTF8Bytes"] = 200
    else:
        result.update({"pipelineConstructionNanoseconds": 1_000_000,
                       "outcome": {"state": "ready-text", "outputUTF8Bytes": 200, "redactions": 0}})
    return result


def report(values=None, *, index=0, renderer=False, secondary=True, cold_count=2):
    if values is None:
        values = [100] * 50
    cold = [worker([values[0]], renderer=renderer, secondary=secondary) for _ in range(cold_count)]
    # The actual runners discard this first warm-process request.
    warm = worker([9999, *values], renderer=renderer, secondary=secondary)
    summary = (renderer_runner if renderer else pipeline_runner).summarize(cold, warm)
    summary["inputBytes"] = 230_000
    configuration = {"package": "Release", "workerOptimization": "-O",
                     "deploymentTarget": "macOS 15.0", "coldSamples": cold_count,
                     "warmSamples": len(values), "budget": "PreviewBudget.standard",
                     "percentileMethod": "nearest-rank", "buildCommand": ["swift", "build", "-c", "release"],
                     "workerCompileCommand": ["swiftc", "-O"]}
    if renderer:
        configuration["rendererScope"] = "fresh 800x600 NativePreviewView; layout and bitmap draw"
    return {"schemaVersion": 1,
            "measuredAtUTC": (datetime(2026, 10, 7, tzinfo=timezone.utc)
                              + timedelta(minutes=index)).isoformat(),
            "environment": {"architecture": "arm64", "model": "SyntheticMac", "cpu": "SyntheticCPU",
                            "physicalMemoryBytes": 16 * 2**30, "os": "macOS synthetic",
                            "swift": "Swift synthetic", "xcode": "Xcode synthetic", "sdkVersion": "synthetic"},
            "configuration": configuration, "cases": {"text": summary},
            "sourceChecks": "contents, file names and modification times unchanged"}


def interleaved(before=None, after=None, **kwargs):
    return [report(before if index % 2 == 0 else after, index=index, **kwargs) for index in range(10)]


def compare(reports, **kwargs):
    return comparison.compare_reports(reports, bootstrap_iterations=200, seed=42, **kwargs)


def timing(result, metric="request", phase="warm"):
    return next(item for item in result["comparisons"] if item["metric"] == metric and item["phase"] == phase)


class StatisticsTests(unittest.TestCase):
    def test_even_sample_median_and_nearest_rank_p95(self):
        stats = comparison.distribution([4, 1, 3, 2])
        self.assertEqual(stats["medianMilliseconds"], 2.5)
        self.assertEqual(stats["p95Milliseconds"], 4)
        self.assertEqual(stats["maxMilliseconds"], 4)

    def test_nearest_rank_p95_is_not_interpolated(self):
        self.assertEqual(comparison.distribution(list(range(1, 21)))["p95Milliseconds"], 19)

    def test_paired_cluster_bootstrap_preserves_common_run_drift(self):
        pairs = [([value] * 50, [value + 5] * 50) for value in [10, 100, 200, 300, 400]]
        interval = comparison.bootstrap_interval(pairs, iterations=200, seed=77)
        self.assertEqual(interval, {"lower": 5.0, "upper": 5.0})

    def test_bootstrap_is_seeded_and_order_independent_within_a_run(self):
        pairs = [([1, 2, 3], [2, 4, 8]), ([9, 5, 7], [7, 8, 9]), ([10, 11, 12], [11, 13, 14])]
        first = comparison.bootstrap_interval(pairs, iterations=200, seed=9)
        self.assertEqual(first, comparison.bootstrap_interval(pairs, iterations=200, seed=9))
        reversed_samples = [(list(reversed(a)), list(reversed(b))) for a, b in pairs]
        self.assertEqual(first, comparison.bootstrap_interval(reversed_samples, iterations=200, seed=9))

    def test_bootstrap_rejects_empty_samples_and_too_few_iterations(self):
        with self.assertRaises(ValueError):
            comparison.bootstrap_interval([([], [1])], iterations=200, seed=1)
        with self.assertRaises(ValueError):
            comparison.bootstrap_interval([([1], [2])], iterations=10, seed=1)

    def test_cluster_bootstrap_matches_an_independent_uncached_calculation(self):
        pairs = [([1, 2], [4, 8]), ([6, 7], [7, 9]), ([8, 12], [6, 8])]
        generator = random.Random(31)
        deltas = []
        for _ in range(250):
            draws = [pairs[generator.randrange(len(pairs))] for _ in pairs]
            deltas.append(statistics.median([value for _, group in draws for value in group])
                          - statistics.median([value for group, _ in draws for value in group]))
        deltas.sort()
        expected = {"lower": deltas[math.ceil(250 * .025) - 1],
                    "upper": deltas[math.ceil(250 * .975) - 1]}
        self.assertEqual(comparison.bootstrap_interval(pairs, iterations=250, seed=31), expected)

    def test_statistics_reject_nonfinite_negative_and_empty_samples(self):
        for values in [[], [-1], [True], [float("inf")], [float("nan")], [10**400]]:
            with self.subTest(values=values), self.assertRaises(ValueError):
                comparison.distribution(values)


class ComparisonTests(unittest.TestCase):
    def test_actual_footprint_remains_separate_from_resident_and_lifetime_peak(self):
        reports = interleaved()
        for entry in reports:
            case = entry["cases"]["text"]
            for run in [*case["coldRuns"], case["warmRun"]]:
                run.update(baselinePhysicalFootprintBytes=125, baselineLifetimePeakPhysicalFootprintBytes=500)
                for sample in run["samples"]:
                    sample.update(physicalFootprintBeforeBytes=150, physicalFootprintAfterBytes=250,
                                  maxSampledPhysicalFootprintBytes=450, lifetimePeakPhysicalFootprintBytes=700)
            case.update(pipeline_runner.summarize(case["coldRuns"], case["warmRun"]))
        result = compare(reports)
        memory = result["processPhysicalFootprint"]["cases"]["text"]["baseline"]
        self.assertEqual(memory["maxSampledPhysicalFootprint"], 450)
        self.assertEqual(memory["maxLifetimePeakPhysicalFootprint"], 700)
        self.assertIsNone(result["worldClassPerformanceGate"]["physicalFootprintBytes"])

    def test_optional_log_append_is_compared_from_actual_samples(self):
        reports = interleaved(renderer=True)
        for entry in reports:
            case = entry["cases"]["text"]
            for run in [*case["coldRuns"], case["warmRun"]]:
                for sample in run["samples"]:
                    sample["logAppendDrawNanoseconds"] = 7_000_000
            case.update(renderer_runner.summarize(case["coldRuns"], case["warmRun"]))
        result = compare(reports, metrics=["logAppendDraw"])
        self.assertEqual(timing(result, "logAppendDraw")["baseline"]["medianMilliseconds"], 7)

    def test_legacy_metadata_is_explicitly_unavailable(self):
        result = compare(interleaved())
        self.assertEqual(result["provenance"]["sourceStateStatus"], "unavailable")
        self.assertEqual(result["provenance"]["fixtureHashStatus"], "unavailable")
        self.assertEqual(result["provenance"]["executionIntervalStatus"], "unavailable")
    def test_five_alternating_pairs_pass_the_median_criterion(self):
        result = compare(interleaved(after=[105] * 50))
        item = timing(result)
        self.assertEqual(item["baseline"]["sampleCount"], 250)
        self.assertEqual(item["baseline"]["medianMilliseconds"], 100)
        self.assertEqual(item["candidate"]["maxMilliseconds"], 105)
        self.assertEqual(item["medianDifference95PercentIntervalMilliseconds"], {"lower": 5.0, "upper": 5.0})
        self.assertEqual(item["medianRegressionBoundMilliseconds"], 10)
        self.assertEqual(result["medianCriterion"]["status"], "passed")
        self.assertTrue(result["method"]["interleavedEvidence"])

    def test_five_percent_bound_above_two_hundred_ms(self):
        item = timing(compare(interleaved([400] * 50, [419] * 50)))
        self.assertEqual(item["medianRegressionBoundMilliseconds"], 20)
        self.assertEqual(item["medianStatus"], "passed")

    def test_interval_upper_bound_must_be_strictly_under_the_bound(self):
        self.assertEqual(timing(compare(interleaved(after=[110] * 50)))["medianStatus"], "inconclusive")
        self.assertEqual(compare(interleaved(after=[111] * 50))["medianCriterion"]["status"], "regression")

    def test_interval_crossing_bound_is_inconclusive(self):
        reports = interleaved()
        for pair, delta in enumerate([-20, -10, 5, 30, 50]):
            reports[2 * pair + 1] = report([100 + delta] * 50, index=2 * pair + 1)
        item = timing(compare(reports))
        interval = item["medianDifference95PercentIntervalMilliseconds"]
        self.assertLess(interval["lower"], 10)
        self.assertGreater(interval["upper"], 10)
        self.assertEqual(item["medianStatus"], "inconclusive")

    def test_two_file_results_are_exploratory_even_with_a_zero_width_interval(self):
        result = compare([report(index=0), report(index=1)])
        self.assertFalse(result["method"]["interleavedEvidence"])
        self.assertEqual(result["medianCriterion"]["status"], "insufficient-evidence")
        self.assertEqual(timing(result)["medianStatus"], "passed")

    def test_fewer_than_fifty_warm_samples_cannot_satisfy_the_method(self):
        result = compare(interleaved([100] * 49, [100] * 49))
        self.assertEqual(result["medianCriterion"]["status"], "insufficient-evidence")

    def test_warm_discards_only_initialization_and_keeps_cold_separate(self):
        result = compare(interleaved())
        self.assertEqual(timing(result)["baseline"]["maxMilliseconds"], 100)
        self.assertEqual(timing(result, phase="cold")["baseline"]["sampleCount"], 10)
        self.assertEqual(timing(result, "processWall", "cold")["baseline"]["medianMilliseconds"], 50)
        self.assertFalse(any(item["metric"] == "processWall" and item["phase"] == "warm"
                             for item in result["comparisons"]))

    def test_native_whole_path_sums_each_sample_before_statistics(self):
        reports = interleaved(renderer=True)
        for entry in reports:
            case = entry["cases"]["text"]
            for sample in case["warmRun"]["samples"][1:]:
                sample["constructionNanoseconds"] = 200_000_000 - sample["pipelineNanoseconds"]
            case.update(renderer_runner.summarize(case["coldRuns"], case["warmRun"]))
        result = compare(reports)
        self.assertEqual(timing(result, "wholePath")["baseline"]["medianMilliseconds"], 203)
        self.assertEqual(result["scope"], "offscreenNativeRenderer")
        self.assertEqual(result["worldClassPerformanceGate"]["status"], "unavailable")
        self.assertIsNone(result["worldClassPerformanceGate"]["hostedFirstScreenP95Milliseconds"])
        self.assertIsNone(result["worldClassPerformanceGate"]["physicalFootprintBytes"])

    def test_p95_regression_is_distinct_from_median_confidence_interval(self):
        result = compare(interleaved([100] * 47 + [150] * 3, [100] * 47 + [180] * 3))
        item = timing(result)
        self.assertEqual(item["medianStatus"], "passed")
        self.assertEqual(item["p95DifferenceMilliseconds"], 30)
        self.assertEqual(item["p95RegressionBoundMilliseconds"], 10)
        self.assertFalse(item["p95WithinRegressionBound"])
        self.assertEqual(result["p95Criterion"]["status"], "regression")
        self.assertEqual(result["worldClassPerformanceGate"]["status"], "unavailable")

    def test_unavailable_secondary_mode_is_not_a_zero_duration(self):
        result = compare(interleaved(renderer=True, secondary=False))
        self.assertFalse(any(item["metric"] == "secondaryModeDraw" for item in result["comparisons"]))
        self.assertTrue(any(item["metric"] == "secondaryModeDraw" for item in result["unavailableMetrics"]))

    def test_selection_retains_scope_and_only_requested_metrics(self):
        result = compare(interleaved(renderer=True), metrics=["initialDisplayCall"], phases=["warm"], cases=["text"])
        self.assertEqual(len(result["comparisons"]), 1)
        self.assertEqual(timing(result, "initialDisplayCall")["baseline"]["medianMilliseconds"], 1)


class EvidenceValidationTests(unittest.TestCase):
    def test_rejects_fake_actual_footprint_summary_or_nonbyte_values(self):
        self.reject(lambda r: r[1]["cases"]["text"]["memoryBytes"].update(maxSampledPhysicalFootprint=200),
                    "actual-footprint")
        for value in [True, -1, 1.5, "100", 2**64]:
            with self.subTest(value=value):
                self.reject(lambda r: r[1]["cases"]["text"]["warmRun"]["samples"][1].update(physicalFootprintAfterBytes=value),
                            "physicalFootprintAfterBytes")

    def test_rejects_invalid_or_source_bearing_stage_observations(self):
        event = {"stage": "pipeline", "count": 1, "startOffsetNanoseconds": 0, "durationNanoseconds": 1,
                 "threadQoS": 21, "thermalState": 0, "physicalFootprintBytes": 450}
        for change in [{"stage": "file-name.swift"}, {"count": 2**31}, {"count": -1},
                       {"durationNanoseconds": 1.5}, {"source": "private"}, {"threadQoS": "main"}]:
            reports = interleaved()
            sample = reports[1]["cases"]["text"]["warmRun"]["samples"][1]
            sample["stageObservations"] = [{**event, **change}]
            sample["droppedStageObservationCount"] = 0
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, "stageObservations"):
                compare(reports)

    def test_rejects_dropped_stage_events_from_a_complete_measurement(self):
        reports = interleaved()
        sample = reports[1]["cases"]["text"]["warmRun"]["samples"][1]
        sample.update(stageObservations=[], droppedStageObservationCount=1)
        with self.assertRaisesRegex(ValueError, "droppedStage"):
            compare(reports)
    def recorded(self):
        reports = interleaved()
        for index, entry in enumerate(reports):
            entry["sourceState"] = {"revision": ("a" if index % 2 == 0 else "b") * 40, "dirty": True,
                                    "sourceTreeSHA256": ("c" if index % 2 == 0 else "d") * 64}
            entry["measurementEndedAtUTC"] = (datetime.fromisoformat(entry["measuredAtUTC"])
                                                 + timedelta(seconds=30)).isoformat()
            entry["cases"]["text"]["inputSHA256"] = "e" * 64
            entry["sourceStateAtMeasurementEnd"] = dict(entry["sourceState"])
            entry["workerBuild"] = {"sourceState": dict(entry["sourceState"]),
                                    "executableSHA256": ("f" if index % 2 == 0 else "a") * 64,
                                    "buildContextSHA256": "b" * 64}
        return reports

    def test_additive_metadata_allows_different_baseline_and_candidate_source_states(self):
        result = compare(self.recorded())
        self.assertEqual(result["provenance"]["sourceStateStatus"], "recorded")
        self.assertEqual(result["provenance"]["fixtureHashStatus"], "recorded")
        self.assertEqual(result["provenance"]["executionIntervalStatus"], "recorded")

    def test_rejects_source_state_change_within_same_version(self):
        reports = self.recorded()
        reports[2]["sourceState"]["sourceTreeSHA256"] = "f" * 64
        with self.assertRaisesRegex(ValueError, "sourceState"):
            compare(reports)

    def test_rejects_source_change_during_measurement_and_stale_worker(self):
        for field in ["sourceStateAtMeasurementEnd", "workerBuild"]:
            reports = self.recorded()
            state = reports[1][field]["sourceState"] if field == "workerBuild" else reports[1][field]
            state["sourceTreeSHA256"] = "e" * 64
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "sourceState"):
                compare(reports)

    def test_rejects_worker_binary_changes_within_same_version(self):
        reports = self.recorded()
        reports[2]["workerBuild"]["executableSHA256"] = "e" * 64
        with self.assertRaisesRegex(ValueError, "workerBuild"):
            compare(reports)

    def test_rejects_same_size_fixture_changes_and_partial_hash_metadata(self):
        for action in [lambda case: case.update(inputSHA256="f" * 64), lambda case: case.pop("inputSHA256")]:
            reports = self.recorded()
            action(reports[1]["cases"]["text"])
            with self.assertRaisesRegex(ValueError, "inputSHA256"):
                compare(reports)

    def test_rejects_overlapping_or_reversed_execution_intervals(self):
        for timestamp in ["2026-10-06T00:00:00+00:00", "2026-10-07T00:02:00+00:00"]:
            reports = self.recorded()
            reports[0]["measurementEndedAtUTC"] = timestamp
            with self.assertRaisesRegex(ValueError, "interval"):
                compare(reports)

    def test_rejects_partial_source_state_and_invalid_hashes(self):
        for action in [lambda r: r[1].pop("sourceState"),
                       lambda r: r[1]["sourceState"].update(dirty="true"),
                       lambda r: r[1]["sourceState"].update(revision="unknown"),
                       lambda r: r[1]["cases"]["text"].update(inputSHA256="not a hash")]:
            reports = self.recorded()
            action(reports)
            with self.assertRaises(ValueError):
                compare(reports)
    def reject(self, change, fragment, *, renderer=False):
        reports = interleaved(renderer=renderer)
        change(reports)
        with self.assertRaisesRegex(ValueError, fragment):
            compare(reports)

    def test_rejects_unpaired_files(self):
        with self.assertRaisesRegex(ValueError, "baseline/candidate pairs"):
            compare([report()])

    def test_rejects_unknown_schema(self):
        self.reject(lambda r: r[1].update(schemaVersion=2), "schemaVersion")

    def test_rejects_different_hardware_toolchain_os_and_deployment(self):
        for key in ["architecture", "model", "cpu", "physicalMemoryBytes", "os", "swift", "xcode", "sdkVersion"]:
            with self.subTest(field=key):
                self.reject(lambda r: r[1]["environment"].update({key: "different"}), "environment")
        self.reject(lambda r: r[1]["configuration"].update(deploymentTarget="macOS 26"), "configuration")

    def test_rejects_missing_required_metadata(self):
        self.reject(lambda r: r[1]["environment"].pop("model"), "environment.*model")

    def test_rejects_nonrelease_nonoptimized_budget_and_percentile_changes(self):
        for key, value in [("package", "Debug"), ("workerOptimization", "-Onone"),
                           ("budget", "relaxed"), ("percentileMethod", "interpolated")]:
            with self.subTest(field=key):
                self.reject(lambda r: r[1]["configuration"].update({key: value}), "configuration")

    def test_build_paths_may_differ_without_changing_measurement_configuration(self):
        reports = interleaved()
        reports[1]["configuration"].update(buildCommand=["/different/worktree/swift", "build", "-c", "release"],
                                           workerCompileCommand=["/different/worktree/swiftc", "-O"])
        self.assertEqual(compare(reports)["medianCriterion"]["status"], "passed")

    def test_command_flags_are_compared_while_worktree_and_sdk_paths_are_ignored(self):
        reports = interleaved()
        for index, entry in enumerate(reports):
            root = f"/worktree/{index}"
            entry["configuration"]["workerCompileCommand"] = [
                "/usr/bin/xcrun", "swiftc", "-O", "-sdk", root + "/SDK",
                "-target", "arm64-apple-macosx15.0", "-I", root + "/Modules", "-o", root + "/worker",
                "-Xcc", "-fmodule-map-file=" + root + "/module.modulemap",
                "-default-isolation", "nonisolated", root + "/Worker.swift", root + "/Core.o"]
        self.assertEqual(compare(reports)["medianCriterion"]["status"], "passed")
        reports[1]["configuration"]["workerCompileCommand"][2] = "-Onone"
        with self.assertRaisesRegex(ValueError, "configuration"):
            compare(reports)

    def test_missing_or_malformed_command_metadata_is_rejected(self):
        self.reject(lambda r: r[1]["configuration"].pop("workerCompileCommand"), "configuration")
        self.reject(lambda r: r[1]["configuration"].update(buildCommand="swift build"), "configuration")
        self.reject(lambda r: r[1]["configuration"].update(workerCompileCommand=["swiftc", "-sdk"]), "configuration")

    def test_commands_cannot_contradict_release_optimization_metadata(self):
        for key, command in [("workerCompileCommand", ["swiftc", "-Onone"]),
                             ("workerCompileCommand", ["swiftc", "-O", "-Osize"]),
                             ("buildCommand", ["swift", "build", "-c", "debug"])]:
            reports = interleaved()
            for entry in reports:
                entry["configuration"][key] = command
            with self.subTest(command=command), self.assertRaisesRegex(ValueError, "configuration"):
                compare(reports)

    def test_renderer_safe_output_must_match_the_baseline_and_cold_runs(self):
        self.reject(lambda r: r[1]["cases"]["text"]["coldRuns"][0].update(safeUTF8Bytes=201),
                    "safeUTF8Bytes", renderer=True)
        reports = interleaved(renderer=True)
        case = reports[1]["cases"]["text"]
        case["safeUTF8Bytes"] = 201
        for run in [*case["coldRuns"], case["warmRun"]]:
            run["safeUTF8Bytes"] = 201
        with self.assertRaisesRegex(ValueError, "safeUTF8Bytes"):
            compare(reports)

    def test_rejects_timestamps_reuse_order_and_naive_timezone(self):
        self.reject(lambda r: r[1].update(measuredAtUTC=r[0]["measuredAtUTC"]), "strictly increasing")
        self.reject(lambda r: r[1].update(measuredAtUTC="2026-10-07T00:01:00"), "UTC")
        self.reject(lambda r: r[1].update(measuredAtUTC="not a time"), "measuredAtUTC")

    def test_rejects_case_size_and_outcome_changes(self):
        self.reject(lambda r: r[1]["cases"].update(other=r[1]["cases"]["text"]), "case")
        self.reject(lambda r: r[1]["cases"]["text"].update(inputBytes=230001), "inputBytes")
        self.reject(lambda r: r[1]["cases"]["text"]["warmRun"]["outcome"].update(state="unavailable"), "outcome")

    def test_rejects_renderer_scope_or_core_and_renderer_mix(self):
        self.reject(lambda r: r[1]["configuration"].update(rendererScope="different"), "configuration", renderer=True)
        reports = interleaved()
        reports[1] = report(index=1, renderer=True)
        with self.assertRaisesRegex(ValueError, "scope"):
            compare(reports)

    def test_rejects_empty_missing_and_incorrect_sample_counts(self):
        self.reject(lambda r: r[1]["cases"]["text"]["warmRun"]["samples"].pop(), "samples")
        self.reject(lambda r: r[1]["cases"]["text"].update(coldRuns=[]), "coldRuns")
        self.reject(lambda r: r[1]["cases"]["text"]["coldRuns"][0].update(samples=[]), "samples")
        self.reject(lambda r: r[1]["cases"]["text"]["warmRun"].pop("samples"), "samples")
        self.reject(lambda r: r[1]["cases"]["text"]["warmRun"].update(scenario="other"), "scenario")

    def test_rejects_missing_invalid_or_other_unit_durations(self):
        self.reject(lambda r: r[1]["cases"]["text"]["warmRun"]["samples"][1].pop("requestNanoseconds"), "requestNanoseconds")
        for value in [-1, True, 100.0, float("nan"), float("inf"), "100000000", 2**63, 10**400]:
            with self.subTest(value=value):
                self.reject(lambda r: r[1]["cases"]["text"]["warmRun"]["samples"][1].update(requestNanoseconds=value), "nanosecond")
        self.reject(lambda r: r[1]["cases"]["text"]["warmRequestMilliseconds"].update(p95=100_000_000), "milliseconds")

    def test_rejects_partially_missing_optional_stage(self):
        self.reject(lambda r: r[1]["cases"]["text"]["warmRun"]["samples"][1].pop("secondaryModeDrawNanoseconds"),
                    "secondaryModeDraw", renderer=True)

    def test_rejects_unknown_metric_or_case_instead_of_silent_omission(self):
        with self.assertRaisesRegex(ValueError, "metric"):
            compare(interleaved(), metrics=["firstVisible"])
        with self.assertRaisesRegex(ValueError, "case"):
            compare(interleaved(), cases=["absent"])
        with self.assertRaisesRegex(ValueError, "phase"):
            compare(interleaved(), phases=["unknown"])


class CommandLineTests(unittest.TestCase):
    def run_tool(self, reports, *args):
        with tempfile.TemporaryDirectory(prefix="compare-benchmark-test-") as directory:
            paths = []
            for index, entry in enumerate(reports):
                path = Path(directory) / f"run-{index}.json"
                path.write_text(json.dumps(entry), encoding="utf-8")
                paths.append(str(path))
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                status = comparison.main([*args, *paths])
            return status, stdout.getvalue(), stderr.getvalue()

    def test_machine_json_stdout_human_summary_stderr_and_success(self):
        status, stdout, stderr = self.run_tool(interleaved(), "--bootstrap-iterations", "200")
        self.assertEqual(status, 0)
        self.assertEqual(json.loads(stdout)["medianCriterion"]["status"], "passed")
        self.assertIn("p95", stderr)
        self.assertIn("Hosted first-screen", stderr)

    def test_exit_codes_for_exploratory_inconclusive_and_regressions(self):
        for reports, expected in [([report(index=0), report(index=1)], 2),
                                  (interleaved(after=[110] * 50), 2),
                                  (interleaved(after=[111] * 50), 1),
                                  (interleaved([100] * 47 + [150] * 3, [100] * 47 + [180] * 3), 1)]:
            with self.subTest(expected=expected):
                self.assertEqual(self.run_tool(reports, "--bootstrap-iterations", "200")[0], expected)

    def test_invalid_report_returns_two_and_never_emits_success_json(self):
        reports = interleaved()
        reports[1]["environment"]["model"] = "different"
        status, stdout, stderr = self.run_tool(reports, "--bootstrap-iterations", "200")
        self.assertEqual(status, 2)
        self.assertEqual(stdout, "")
        self.assertIn("environment", stderr)

    def test_malformed_or_duplicate_json_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="compare-benchmark-test-") as directory:
            path = Path(directory) / "bad.json"
            for content in ["not json", '{"schemaVersion":1,"schemaVersion":1}']:
                with self.subTest(content=content):
                    path.write_text(content, encoding="utf-8")
                    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                        self.assertEqual(comparison.main([str(path), str(path)]), 2)

    def test_cli_refuses_to_overwrite_a_raw_input_report(self):
        with tempfile.TemporaryDirectory(prefix="compare-benchmark-test-") as directory:
            paths = []
            for index, entry in enumerate(interleaved()):
                path = Path(directory) / f"run-{index}.json"
                path.write_text(json.dumps(entry), encoding="utf-8")
                paths.append(str(path))
            original = Path(paths[0]).read_bytes()
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(comparison.main(["--bootstrap-iterations", "200", "--output", paths[0], *paths]), 2)
            self.assertEqual(Path(paths[0]).read_bytes(), original)

    def test_cli_output_cannot_overwrite_an_input_through_a_hard_link(self):
        with tempfile.TemporaryDirectory(prefix="compare-benchmark-test-") as directory:
            paths = []
            for index, entry in enumerate(interleaved()):
                path = Path(directory) / f"run-{index}.json"
                path.write_text(json.dumps(entry), encoding="utf-8")
                paths.append(str(path))
            output = Path(directory) / "output.json"
            os.link(paths[0], output)
            original = Path(paths[0]).read_bytes()
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(comparison.main(["--bootstrap-iterations", "200", "--output", str(output), *paths]), 2)
            self.assertEqual(Path(paths[0]).read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
