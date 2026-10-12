#!/usr/bin/env python3
r"""Compare schema-1 Release pipeline or native-renderer benchmark reports (Q-24).

Run the baseline and candidate alternately, saving a separate report each time:

    python3 -I script/compare_benchmarks.py A1.json B1.json A2.json B2.json \
        A3.json B3.json A4.json B4.json A5.json B5.json > comparison.json

Argument order declares the actual A/B execution order. Reports must have strictly
increasing measuredAtUTC values, matching hardware/OS/toolchain, Release/-O,
budget, sample counts, renderer scope, fixture sizes and outcomes. Five pairs
with at least 50 warm samples per run satisfy the recorded sampling method.
Two-file comparisons work for exploration but cannot pass its evidence check.
Current runners add source/build fingerprints, fixture hashes and end times.
When present these must match, remain stable within each A or B group, and show
nonoverlapping execution. Legacy schema-1 reports remain readable and explicitly
mark this provenance unavailable; their operator must establish it separately.
No report can prove the full required fixture set or operator-declared A/B order.

Use only the existing raw coldRuns and warmRun payloads; raw integer Nanoseconds
are converted to milliseconds, and runner summaries are checked against them.
The first warm-process sample initializes that process and is excluded. Cold
first requests and parent-measured process wall time stay separate from warm
requests. Native wholePath sums pipeline + construction + initialDisplayDraw
within each sample; initialDisplayCall is already inside initialDisplayDraw and
must not be added again. These offscreen timings are not hosted first-screen
timings. Missing secondary-mode/log-append timings are unavailable, never zero.

The statistic is the difference between pooled candidate and baseline medians.
A seeded, paired cluster bootstrap resamples whole A/B run pairs together, not
individual requests as independent experiments. Its nearest-rank 2.5/97.5
percentiles form the 95% interval. The amended gate-11 median criterion passes
only when its upper endpoint is strictly below max(10 ms, 5% baseline median);
a lower endpoint above the bound identifies a regression, otherwise evidence is
inconclusive. Separately report nearest-rank p95, maximum, the p95 difference
and its max(10 ms, 5% baseline p95) guard. Gate 13 still requires hosted warm
first-screen p95, the <=256 KiB 200 ms target, deterministic work-count guards
and physical footprint in that host. Current workers record actual process
physical footprint separately from RSS: sampled maxima and kernel lifetime
peaks are distinct. Neither establishes hosted request peak memory.

JSON goes to stdout, a human summary to stderr; --output also saves the JSON.
Exit 0: the selected recorded median and p95 criteria pass with enough runs.
Exit 1: a recorded median or p95 regression with enough runs. Exit 2: malformed
or incompatible evidence, insufficient runs, or an inconclusive median interval.
Exit 0 never establishes the full gates 11/13 or Finder/release readiness.
Recorded build/compile flags must match after removing checkout, SDK, include,
output and link-input paths; SDK/toolchain versions still have to match.
No Mac, compiler, worker invocation or third-party library is needed here.
"""
import argparse
from datetime import datetime, timedelta
import json
import math
from pathlib import Path
import random
import statistics
import sys


DEFAULT_SEED = 20261006
DEFAULT_ITERATIONS = 10_000
MAXIMUM_NANOSECONDS = 2**63 - 1  # The Swift workers serialize Int64 durations.
MINIMUM_PAIRS = 5
MINIMUM_WARM_SAMPLES = 50
ENVIRONMENT_FIELDS = ("architecture", "model", "cpu", "physicalMemoryBytes", "os", "swift", "xcode", "sdkVersion")
CONFIGURATION_FIELDS = ("package", "workerOptimization", "deploymentTarget", "coldSamples", "warmSamples",
                        "budget", "percentileMethod", "buildCommand", "workerCompileCommand")
NATIVE_STAGES = ("pipeline", "construction", "initialDisplayDraw", "initialDisplayCall", "secondaryModeDraw",
                 "restyleDraw", "scrollDraw", "logAppendDraw")
OPTIONAL_NATIVE_STAGES = ("secondaryModeDraw", "logAppendDraw")
OBSERVED_STAGES = ("preferences", "pipeline", "modes", "tokens", "lineIndex", "storage", "styling", "layout", "firstDraw", "handler")
METRIC_SCOPES = {
    "request": "core pipeline request; excludes renderer and host",
    "pipeline": "core pipeline request in the renderer worker",
    "construction": "offscreen NativePreviewView construction",
    "initialDisplayDraw": "offscreen initial display, layout and bitmap draw",
    "initialDisplayCall": "offscreen display call; part of initialDisplayDraw",
    "secondaryModeDraw": "offscreen secondary-mode switch and bitmap draw",
    "restyleDraw": "offscreen appearance change and bitmap draw",
    "scrollDraw": "offscreen last-viewport scroll and bitmap draw",
    "logAppendDraw": "offscreen display/draw of an immutable appended log snapshot after its predecessor",
    "wholePath": "core pipeline + view construction + offscreen initial display and bitmap draw",
    "processWall": "cold process launch through exit; includes assertions and probes",
}


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _object(value, location):
    _require(isinstance(value, dict), f"{location} must be an object")
    return value


def _integer(value, location, *, minimum=0):
    _require(type(value) is int and value >= minimum, f"{location} must be an integer >= {minimum}")
    return value


def _nanoseconds(value, location):
    _require(type(value) is int and 0 <= value <= MAXIMUM_NANOSECONDS,
             f"{location} must contain nonnegative Int64 integer nanoseconds")
    return value / 1_000_000


def _finite_samples(values):
    _require(bool(values), "statistics require nonempty samples")
    _require(all(type(value) in (int, float) and 0 <= value <= sys.float_info.max / 2
                 and math.isfinite(value) for value in values),
             "statistics require finite nonnegative numeric samples")


def percentile(values, fraction):
    """Nearest rank, matching the recorded runner summaries (not interpolation)."""
    _finite_samples(values)
    _require(0 < fraction <= 1, "percentile fraction must be in (0, 1]")
    return sorted(values)[math.ceil(len(values) * fraction) - 1]


def distribution(values):
    _finite_samples(values)
    return {"sampleCount": len(values), "medianMilliseconds": statistics.median(values),
            "p95Milliseconds": percentile(values, .95), "maxMilliseconds": max(values)}


def bootstrap_interval(pairs, *, iterations=DEFAULT_ITERATIONS, seed=DEFAULT_SEED):
    """Percentile CI for a median difference, resampling paired process clusters."""
    _require(type(iterations) is int and 200 <= iterations <= 100_000,
             "bootstrap iterations must be between 200 and 100000")
    _require(type(seed) is int, "bootstrap seed must be an integer")
    _require(bool(pairs), "bootstrap requires baseline/candidate pairs")
    for before, after in pairs:
        _finite_samples(before)
        _finite_samples(after)
        _require(len(before) == len(after), "paired runs must have equal sample counts")
    generator = random.Random(seed)
    deltas, cache = [], {}
    # Five pairs have only 126 possible count vectors. Cache each pooled median
    # difference without changing the seeded bootstrap draw or its statistic.
    for _ in range(iterations):
        counts = [0] * len(pairs)
        for _ in pairs:
            counts[generator.randrange(len(pairs))] += 1
        key = tuple(counts)
        if key not in cache:
            baseline, candidate = [], []
            for count, (before, after) in zip(counts, pairs):
                baseline.extend(before * count)
                candidate.extend(after * count)
            cache[key] = statistics.median(candidate) - statistics.median(baseline)
        deltas.append(cache[key])
    # Differences may be negative, unlike elapsed-time samples.
    ordered = sorted(deltas)
    return {"lower": ordered[math.ceil(iterations * .025) - 1],
            "upper": ordered[math.ceil(iterations * .975) - 1]}


def _scope(report):
    return "offscreenNativeRenderer" if "rendererScope" in report["configuration"] else "corePipeline"


def _metrics(scope):
    return (*NATIVE_STAGES, "wholePath", "processWall") if scope == "offscreenNativeRenderer" else ("request", "processWall")


def _timestamp(value, location):
    _require(isinstance(value, str), f"{location}.measuredAtUTC must be a UTC timestamp")
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError(f"{location}.measuredAtUTC is invalid") from error
    _require(result.tzinfo is not None and result.utcoffset() == timedelta(0),
             f"{location}.measuredAtUTC must include a UTC timezone")
    return result


def _raw_samples(case, phase):
    return ([run["samples"][0] for run in case["coldRuns"]] if phase == "cold"
            else case["warmRun"]["samples"][1:])


def _values(case, phase, metric, location):
    if metric == "processWall":
        _require(phase == "cold", "processWall has no warm per-request phase")
        return [_nanoseconds(run.get("processWallNanoseconds"), f"{location}.processWallNanoseconds")
                for run in case["coldRuns"]]
    values = []
    for sample in _raw_samples(case, phase):
        if metric == "wholePath":
            stages = ("pipeline", "construction", "initialDisplayDraw")
            nanoseconds = [sample.get(stage + "Nanoseconds") for stage in stages]
            for stage, value in zip(stages, nanoseconds):
                _nanoseconds(value, f"{location}.{stage}Nanoseconds")
            values.append(sum(nanoseconds) / 1_000_000)
        else:
            key = metric + "Nanoseconds"
            value = sample.get(key)
            values.append(None if metric in OPTIONAL_NATIVE_STAGES and value is None
                          else _nanoseconds(value, f"{location}.{key}"))
    if all(value is None for value in values):
        return None
    _require(all(value is not None for value in values), f"{location}.{metric} has partially missing samples")
    return values


def _summary(case, phase, metric, scope):
    if metric == "processWall":
        return case.get("coldProcessWallMilliseconds")
    if scope == "corePipeline":
        return case.get("coldFirstRequestMilliseconds" if phase == "cold" else "warmRequestMilliseconds")
    if metric == "logAppendDraw" and case.get(metric + "Milliseconds") is None:
        return None  # This additive metric is absent in legacy schema-1 reports.
    entry = _object(case.get(metric + "Milliseconds"), f"{metric}Milliseconds")
    return entry.get("firstProcess" if phase == "cold" else "warmProcess")


def _validate_summary(summary, values, location):
    if values is None:
        _require(summary is None, f"{location} milliseconds summary must be unavailable for missing samples")
        return
    summary = _object(summary, f"{location} milliseconds summary")
    expected = {"count": len(values), "min": min(values), "p50": percentile(values, .5),
                "p95": percentile(values, .95), "max": max(values)}
    for key, value in expected.items():
        recorded = summary.get(key)
        valid = (type(recorded) is int and recorded == value if key == "count" else
                 type(recorded) in (int, float) and math.isfinite(recorded)
                 and math.isclose(recorded, value, rel_tol=1e-9, abs_tol=1e-9))
        _require(valid, f"{location} milliseconds summary {key} is inconsistent with raw nanosecond samples")


def _validate_report(report, index):
    location = f"report[{index}]"
    report = _object(report, location)
    _require(type(report.get("schemaVersion")) is int and report["schemaVersion"] == 1,
             f"{location}.schemaVersion must be 1")
    timestamp = _timestamp(report.get("measuredAtUTC"), location)
    if "measurementEndedAtUTC" in report:
        end = _timestamp(report["measurementEndedAtUTC"], f"{location}.measurementEndedAtUTC")
        _require(end >= timestamp, f"{location} execution interval ends before it starts")
    if "sourceState" in report:
        _validate_source_state(report["sourceState"], f"{location}.sourceState")
    if "sourceStateAtMeasurementEnd" in report:
        _validate_source_state(report["sourceStateAtMeasurementEnd"], f"{location}.sourceStateAtMeasurementEnd")
        _require(report["sourceStateAtMeasurementEnd"] == report.get("sourceState"),
                 f"{location}.sourceState changed during measurement")
    if "workerBuild" in report:
        worker = _object(report["workerBuild"], f"{location}.workerBuild")
        _validate_source_state(worker.get("sourceState"), f"{location}.workerBuild.sourceState")
        _require(worker["sourceState"] == report.get("sourceState"), f"{location}.workerBuild.sourceState is stale")
        for key in ("executableSHA256", "buildContextSHA256"):
            _hash(worker.get(key), 64, f"{location}.workerBuild.{key}")
    environment = _object(report.get("environment"), f"{location}.environment")
    for key in ENVIRONMENT_FIELDS:
        value = environment.get(key)
        if key == "physicalMemoryBytes":
            _integer(value, f"{location}.environment.{key}", minimum=1)
        else:
            _require(isinstance(value, str) and bool(value.strip()), f"{location}.environment.{key} is required")
    configuration = _object(report.get("configuration"), f"{location}.configuration")
    for key in CONFIGURATION_FIELDS:
        _require(key in configuration, f"{location}.configuration.{key} is required")
    for key in ("coldSamples", "warmSamples"):
        _integer(configuration[key], f"{location}.configuration.{key}", minimum=1)
        _require(configuration[key] <= 200, f"{location}.configuration.{key} exceeds runner limit 200")
    for key in ("deploymentTarget", "budget"):
        _require(isinstance(configuration[key], str) and bool(configuration[key].strip()),
                 f"{location}.configuration.{key} is required")
    _require(configuration["package"] == "Release" and configuration["workerOptimization"] == "-O",
             f"{location}.configuration must record Release/-O")
    _require(configuration["percentileMethod"] == "nearest-rank",
             f"{location}.configuration.percentileMethod must be nearest-rank")
    for key in ("buildCommand", "workerCompileCommand"):
        _command_identity(configuration[key], f"{location}.configuration.{key}")
    build = configuration["buildCommand"]
    build_modes = [build[index + 1] for index, arg in enumerate(build[:-1]) if arg in ("-c", "--configuration")]
    _require(bool(build_modes) and all(mode == "release" for mode in build_modes),
             f"{location}.configuration.buildCommand must record a release build")
    optimizations = [arg for arg in configuration["workerCompileCommand"] if arg.startswith("-O")]
    _require(optimizations == ["-O"], f"{location}.configuration.workerCompileCommand must record only -O optimization")
    scope = _scope(report)
    if scope == "offscreenNativeRenderer":
        _require(isinstance(configuration["rendererScope"], str) and bool(configuration["rendererScope"].strip()),
                 f"{location}.configuration.rendererScope is required")
    cases = _object(report.get("cases"), f"{location}.cases")
    _require(bool(cases), f"{location}.cases must not be empty")
    for name, case in cases.items():
        _require(isinstance(name, str) and bool(name), f"{location}.cases has an invalid case name")
        case_location = f"{location}.cases.{name}"
        case = _object(case, case_location)
        _integer(case.get("inputBytes"), f"{case_location}.inputBytes")
        for key in ("inputSHA256", "relatedInputSHA256"):
            if key in case:
                _hash(case[key], 64, f"{case_location}.{key}")
        cold = case.get("coldRuns")
        _require(isinstance(cold, list) and len(cold) == configuration["coldSamples"],
                 f"{case_location}.coldRuns must match coldSamples")
        warm = _object(case.get("warmRun"), f"{case_location}.warmRun")
        for run_index, run in enumerate([*cold, warm]):
            run_location = f"{case_location}.run[{run_index}]"
            run = _object(run, run_location)
            _require(run.get("scenario") == name, f"{run_location}.scenario differs from case name")
            samples = run.get("samples")
            expected_count = 1 if run_index < len(cold) else configuration["warmSamples"] + 1
            _require(isinstance(samples, list) and len(samples) == expected_count,
                     f"{run_location}.samples must contain {expected_count} samples")
            _nanoseconds(run.get("processWallNanoseconds"), f"{run_location}.processWallNanoseconds")
            if scope == "corePipeline":
                outcome = _object(run.get("outcome"), f"{run_location}.outcome")
                _require(isinstance(outcome.get("state"), str), f"{run_location}.outcome.state is required")
                for key in ("outputUTF8Bytes", "redactions"):
                    _integer(outcome.get(key), f"{run_location}.outcome.{key}")
                _require(outcome == case.get("outcome"), f"{run_location}.outcome differs from case outcome")
            else:
                _integer(run.get("safeUTF8Bytes"), f"{run_location}.safeUTF8Bytes")
                _require(run["safeUTF8Bytes"] == case.get("safeUTF8Bytes"),
                         f"{run_location}.safeUTF8Bytes differs from case")
            # Check initialization too, although it does not enter warm statistics.
            for sample in samples:
                sample = _object(sample, f"{run_location}.samples")
                _validate_stage_observations(sample, run_location)
                for metric in NATIVE_STAGES if scope == "offscreenNativeRenderer" else ("request",):
                    value = sample.get(metric + "Nanoseconds")
                    if metric not in OPTIONAL_NATIVE_STAGES or value is not None:
                        _nanoseconds(value, f"{run_location}.{metric}Nanoseconds")
                for key in ("physicalFootprintBeforeBytes", "physicalFootprintAfterBytes",
                            "maxSampledPhysicalFootprintBytes", "lifetimePeakPhysicalFootprintBytes"):
                    if sample.get(key) is not None:
                        _memory_integer(sample[key], f"{run_location}.{key}")
            for key in ("baselinePhysicalFootprintBytes", "baselineLifetimePeakPhysicalFootprintBytes"):
                if run.get(key) is not None:
                    _memory_integer(run[key], f"{run_location}.{key}")
        memory = _object(case.get("memoryBytes"), f"{case_location}.memoryBytes")
        for key, value in _physical_summary(case).items():
            _require(memory.get(key) == value, f"{case_location}.memoryBytes.{key} differs from raw actual-footprint probes")
        for phase in ("cold", "warm"):
            for metric in _metrics(scope):
                if phase == "warm" and metric == "processWall":
                    continue
                values = _values(case, phase, metric, case_location)
                _validate_summary(_summary(case, phase, metric, scope), values, f"{case_location}.{phase}.{metric}")
    return timestamp


def _hash(value, length, location):
    _require(isinstance(value, str) and len(value) == length and all(character in "0123456789abcdef" for character in value),
             f"{location} must be a lowercase {length}-character hexadecimal hash")


def _validate_source_state(value, location):
    state = _object(value, location)
    _hash(state.get("revision"), 40, f"{location}.revision")
    _hash(state.get("sourceTreeSHA256"), 64, f"{location}.sourceTreeSHA256")
    _require(type(state.get("dirty")) is bool, f"{location}.dirty must be a boolean")


def _memory_integer(value, location):
    _integer(value, location)
    _require(value <= 2**64 - 1, f"{location} exceeds UInt64 bytes")


def _validate_stage_observations(sample, location):
    if "stageObservations" not in sample:
        _require("droppedStageObservationCount" not in sample, f"{location}.stageObservations are missing")
        return
    events = sample["stageObservations"]
    _require(isinstance(events, list) and len(events) <= 256, f"{location}.stageObservations must be a bounded array")
    dropped = _integer(sample.get("droppedStageObservationCount"), f"{location}.droppedStageObservationCount")
    _require(dropped == 0, f"{location}.droppedStageObservationCount must be zero for complete measurement evidence")
    required = {"stage", "count", "startOffsetNanoseconds", "durationNanoseconds", "threadQoS", "thermalState"}
    for event in events:
        event = _object(event, f"{location}.stageObservations")
        _require(required <= event.keys() and event.keys() <= required | {"physicalFootprintBytes"},
                 f"{location}.stageObservations may contain only the fixed measurement vocabulary")
        _require(event["stage"] in OBSERVED_STAGES, f"{location}.stageObservations.stage must be a fixed stage")
        count = _integer(event["count"], f"{location}.stageObservations.count")
        _require(count <= 2**31 - 1, f"{location}.stageObservations.count exceeds its bounded diagnostic count")
        for key in ("startOffsetNanoseconds", "durationNanoseconds"):
            _nanoseconds(event[key], f"{location}.stageObservations.{key}")
        qos = _integer(event["threadQoS"], f"{location}.stageObservations.threadQoS")
        _require(qos <= 2**32 - 1, f"{location}.stageObservations.threadQoS exceeds UInt32")
        _integer(event["thermalState"], f"{location}.stageObservations.thermalState")
        if event.get("physicalFootprintBytes") is not None:
            _memory_integer(event["physicalFootprintBytes"], f"{location}.stageObservations.physicalFootprintBytes")


def _complete_max(values):
    return max(values) if values and all(type(value) is int and value >= 0 for value in values) else None


def _physical_summary(case):
    runs = [*case["coldRuns"], case["warmRun"]]
    samples = [sample for run in runs for sample in run["samples"]]
    growth = []
    for run in runs:
        peak = _complete_max([sample.get("lifetimePeakPhysicalFootprintBytes") for sample in run["samples"]])
        baseline = run.get("baselineLifetimePeakPhysicalFootprintBytes")
        growth.append(max(0, peak - baseline) if peak is not None and type(baseline) is int and baseline >= 0 else None)
    return {"maxBaselinePhysicalFootprint": _complete_max([run.get("baselinePhysicalFootprintBytes") for run in runs]),
            "maxSampledPhysicalFootprint": _complete_max([sample.get("maxSampledPhysicalFootprintBytes") for sample in samples]),
            "maxLifetimePeakPhysicalFootprint": _complete_max([sample.get("lifetimePeakPhysicalFootprintBytes") for sample in samples]),
            "maxLifetimePeakPhysicalFootprintGrowthFromBaselinePeak": _complete_max(growth)}


def _provenance(reports, timestamps):
    statuses = {}
    for key, label in [("sourceState", "sourceStateStatus"), ("workerBuild", "workerBuildStatus"),
                       ("sourceStateAtMeasurementEnd", "sourceStateAtMeasurementEndStatus"),
                       ("measurementEndedAtUTC", "executionIntervalStatus")]:
        present = [key in report for report in reports]
        _require(all(present) or not any(present), f"{key} metadata is partially missing")
        statuses[label] = "recorded" if all(present) else "unavailable"
        if all(present) and key in ("sourceState", "workerBuild"):
            for index, report in enumerate(reports):
                _require(report[key] == reports[index % 2][key], f"report[{index}].{key} changed within its A/B version group")
    if statuses["executionIntervalStatus"] == "recorded":
        for index, report in enumerate(reports[:-1]):
            end = _timestamp(report["measurementEndedAtUTC"], f"report[{index}].measurementEndedAtUTC")
            _require(end <= timestamps[index + 1], f"report[{index}] execution interval overlaps the following run")
    hashes_recorded = True
    for name in reports[0]["cases"]:
        for key in ("inputSHA256", "relatedInputSHA256"):
            entries = [report["cases"].get(name, {}) for report in reports]
            present = [key in entry for entry in entries]
            _require(all(present) or not any(present), f"{name}.{key} metadata is partially missing")
            if all(present):
                _require(all(entry[key] == entries[0][key] for entry in entries), f"{name}.{key} differs across A/B runs")
            elif key == "inputSHA256":
                hashes_recorded = False
    statuses["fixtureHashStatus"] = "recorded" if hashes_recorded else "unavailable"
    statuses["note"] = "Recorded provenance is checked; full fixture coverage and operator-declared A/B order still need a validation record"
    return statuses


def _configuration_identity(configuration):
    identity = dict(configuration)
    for key in ("buildCommand", "workerCompileCommand"):
        identity[key] = _command_identity(configuration.get(key), f"configuration.{key}")
    return identity


def _command_identity(command, location):
    """Retain recorded flags and their non-path values across separate checkouts."""
    _require(isinstance(command, list) and bool(command) and all(isinstance(arg, str) and bool(arg) for arg in command),
             f"{location} must be a nonempty argument list")
    identity = [Path(command[0]).name]
    path_options = ("--package-path", "--scratch-path", "-sdk", "-I", "-L", "-F", "-o")
    index = 1
    while index < len(command):
        argument = command[index]
        if argument in path_options:
            _require(index + 1 < len(command), f"{location}: {argument} has no path argument")
            identity.extend((argument, "<path>"))
            index += 2
        else:
            if argument.startswith("-fmodule-map-file="):
                identity.append("-fmodule-map-file=<path>")
            elif not (argument.startswith("/") or argument.endswith((".swift", ".o", ".a"))):
                identity.append(argument)
            index += 1
    return identity


def _combine_status(statuses):
    return "regression" if "regression" in statuses else "inconclusive" if "inconclusive" in statuses else "passed"


def compare_reports(reports, *, bootstrap_iterations=DEFAULT_ITERATIONS, seed=DEFAULT_SEED,
                    cases=None, metrics=None, phases=("cold", "warm")):
    """Return JSON-compatible statistics; raise ValueError for unusable evidence."""
    _require(len(reports) >= 2 and len(reports) % 2 == 0, "supply complete ordered baseline/candidate pairs")
    timestamps = [_validate_report(report, index) for index, report in enumerate(reports)]
    _require(all(before < after for before, after in zip(timestamps, timestamps[1:])),
             "measuredAtUTC values must be strictly increasing in declared A/B execution order")
    baseline = reports[0]
    scope = _scope(baseline)
    for index, report in enumerate(reports[1:], 1):
        _require(_scope(report) == scope, f"report[{index}] measurement scope differs")
        _require(report["environment"] == baseline["environment"], f"report[{index}] environment differs")
        _require(_configuration_identity(report["configuration"]) == _configuration_identity(baseline["configuration"]),
                 f"report[{index}] configuration differs")
        _require(set(report["cases"]) == set(baseline["cases"]), f"report[{index}] case set differs")
        for name, case in report["cases"].items():
            for key in ("inputBytes", "safeUTF8Bytes" if scope == "offscreenNativeRenderer" else "outcome"):
                _require(case[key] == baseline["cases"][name][key], f"report[{index}].{name}.{key} differs")
    provenance = _provenance(reports, timestamps)
    selected_cases = sorted(baseline["cases"]) if cases is None else list(dict.fromkeys(cases))
    selected_metrics = list(_metrics(scope)) if metrics is None else list(dict.fromkeys(metrics))
    selected_phases = list(dict.fromkeys(phases))
    _require(bool(selected_cases) and all(name in baseline["cases"] for name in selected_cases), "unknown or empty case selection")
    _require(bool(selected_metrics) and all(metric in _metrics(scope) for metric in selected_metrics), "unknown or incompatible metric selection")
    _require(bool(selected_phases) and all(phase in ("cold", "warm") for phase in selected_phases), "unknown or empty phase selection")
    pair_count = len(reports) // 2
    warm_samples = baseline["configuration"]["warmSamples"]
    enough = pair_count >= MINIMUM_PAIRS and warm_samples >= MINIMUM_WARM_SAMPLES
    comparisons, unavailable = [], []
    for name in selected_cases:
        for phase in selected_phases:
            for metric in selected_metrics:
                if metric == "processWall" and phase == "warm":
                    continue
                groups = [_values(report["cases"][name], phase, metric, f"{name}.{phase}") for report in reports]
                if all(group is None for group in groups):
                    unavailable.append({"case": name, "phase": phase, "metric": metric,
                                        "reason": "optional mode/append operation not recorded; duration is unavailable"})
                    continue
                _require(all(group is not None for group in groups), f"{name}.{phase}.{metric} availability differs across runs")
                pairs = list(zip(groups[::2], groups[1::2]))
                before = distribution([value for group in groups[::2] for value in group])
                after = distribution([value for group in groups[1::2] for value in group])
                before["runCount"] = after["runCount"] = pair_count
                interval = bootstrap_interval(pairs, iterations=bootstrap_iterations, seed=seed)
                bound = max(10.0, before["medianMilliseconds"] * .05)
                status = ("passed" if interval["upper"] < bound else
                          "regression" if interval["lower"] > bound else "inconclusive")
                p95_bound = max(10.0, before["p95Milliseconds"] * .05)
                p95_delta = after["p95Milliseconds"] - before["p95Milliseconds"]
                comparisons.append({"case": name, "inputBytes": baseline["cases"][name]["inputBytes"],
                                    "phase": phase, "metric": metric, "measurementScope": METRIC_SCOPES[metric],
                                    "baseline": before, "candidate": after,
                                    "medianDifferenceMilliseconds": after["medianMilliseconds"] - before["medianMilliseconds"],
                                    "medianDifference95PercentIntervalMilliseconds": interval,
                                    "medianRegressionBoundMilliseconds": bound, "medianStatus": status,
                                    "p95DifferenceMilliseconds": p95_delta,
                                    "p95RegressionBoundMilliseconds": p95_bound,
                                    "p95WithinRegressionBound": p95_delta <= p95_bound})
    _require(bool(comparisons), "selected phase/metrics have no comparable timing samples")
    median_status = _combine_status([item["medianStatus"] for item in comparisons]) if enough else "insufficient-evidence"
    # Gate 13 concerns warm first-screen p95. This separate diagnostic uses only
    # recorded warm timings and never substitutes their scope for first screen.
    warm_comparisons = [item for item in comparisons if item["phase"] == "warm"]
    p95_status = ("regression" if any(not item["p95WithinRegressionBound"] for item in warm_comparisons) else "passed")
    if not enough:
        p95_status = "insufficient-evidence"
    elif not warm_comparisons:
        p95_status = "unavailable"
    return {
        "schemaVersion": 1, "scope": scope,
        "method": {"bootstrap": "paired run-cluster percentile bootstrap of pooled median difference",
                   "confidenceLevel": .95, "bootstrapIterations": bootstrap_iterations, "seed": seed,
                   "durationUnit": "milliseconds", "percentileMethod": "nearest-rank", "pairCount": pair_count,
                   "warmSamplesPerRun": warm_samples, "minimumPairs": MINIMUM_PAIRS,
                   "minimumWarmSamplesPerRun": MINIMUM_WARM_SAMPLES, "interleavedEvidence": enough,
                   "executionOrder": [{"label": "baseline" if index % 2 == 0 else "candidate",
                                       "measuredAtUTC": report["measuredAtUTC"]} for index, report in enumerate(reports)]},
        "environment": baseline["environment"], "provenance": provenance,
        "processPhysicalFootprint": {
            "scope": "measurement-worker process, not the Finder/Quick Look host; sampled maxima are not kernel request peaks",
            "cases": {name: {label: {key: _complete_max([_physical_summary(report["cases"][name])[key]
                                                for report in reports[offset::2]])
                                      for key in _physical_summary(baseline["cases"][name])}
                              for label, offset in [("baseline", 0), ("candidate", 1)]} for name in selected_cases}},
        "selection": {"cases": selected_cases, "metrics": selected_metrics, "phases": selected_phases},
        "medianCriterion": {"status": median_status, "criterion": "95% interval upper endpoint < max(10ms,5% baseline median)",
                            "fullGate11Status": "unavailable; required fixture coverage and baseline designation need a validation record"},
        "p95Criterion": {"status": p95_status, "criterion": "recorded warm p95 difference <= max(10ms,5% baseline p95)",
                         "scope": "diagnostic for the recorded metrics; does not establish hosted first-screen p95"},
        "worldClassPerformanceGate": {"status": "unavailable", "hostedFirstScreenP95Milliseconds": None,
                                      "physicalFootprintBytes": None, "warmTargetMilliseconds": 200,
                                      "warmTargetMaximumInputBytes": 256 * 1024,
                                      "reason": "reports do not establish hosted first screen, hosted physical footprint or layout-pass guards"},
        "comparisons": comparisons, "unavailableMetrics": unavailable,
    }


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        _require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _invalid_constant(value):
    raise ValueError(f"non-finite JSON number: {value}")


def _human_summary(result):
    method = result["method"]
    print(f"{result['scope']}: {method['pairCount']} alternating A/B pairs; "
          f"{method['warmSamplesPerRun']} warm requests per run", file=sys.stderr)
    print(f"Median criterion: {result['medianCriterion']['status']}; "
          f"recorded warm p95 guard: {result['p95Criterion']['status']}", file=sys.stderr)
    print("case / phase / metric: baseline -> candidate median ms; difference 95% CI; p95 ms; maximum ms", file=sys.stderr)
    for item in result["comparisons"]:
        before, after = item["baseline"], item["candidate"]
        interval = item["medianDifference95PercentIntervalMilliseconds"]
        print(f"{item['case']} / {item['phase']} / {item['metric']}: "
              f"{before['medianMilliseconds']:.3f} -> {after['medianMilliseconds']:.3f}; "
              f"[{interval['lower']:.3f}, {interval['upper']:.3f}]; "
              f"p95 {before['p95Milliseconds']:.3f} -> {after['p95Milliseconds']:.3f}; "
              f"max {before['maxMilliseconds']:.3f} -> {after['maxMilliseconds']:.3f}", file=sys.stderr)
    for item in result["unavailableMetrics"]:
        print(f"{item['case']} / {item['phase']} / {item['metric']}: unavailable", file=sys.stderr)
    print("Hosted first-screen gate 13 and physical footprint: unavailable. "
          "Median results do not establish the full gates 11/13.", file=sys.stderr)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("reports", nargs="+", type=Path, help="baseline, candidate, baseline, candidate ... in execution order")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--bootstrap-iterations", type=int, default=DEFAULT_ITERATIONS)
    parser.add_argument("--case", action="append", dest="cases", help="compare only this case (repeatable)")
    parser.add_argument("--metric", action="append", dest="metrics", choices=tuple(METRIC_SCOPES), help="compare only this metric (repeatable)")
    parser.add_argument("--phase", choices=("both", "cold", "warm"), default="both")
    parser.add_argument("--output", type=Path, help="also save the JSON report to this file")
    args = parser.parse_args(argv)
    try:
        reports = [json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_object,
                              parse_constant=_invalid_constant) for path in args.reports]
        result = compare_reports(reports, bootstrap_iterations=args.bootstrap_iterations, seed=args.seed,
                                 cases=args.cases, metrics=args.metrics,
                                 phases=("cold", "warm") if args.phase == "both" else (args.phase,))
        rendered = json.dumps(result, indent=2, sort_keys=True, allow_nan=False) + "\n"
        if args.output is not None:
            aliases_input = (args.output.resolve() in {path.resolve() for path in args.reports}
                             or (args.output.exists() and any(args.output.samefile(path) for path in args.reports)))
            _require(not aliases_input,
                     "output must not overwrite an input report")
            args.output.write_text(rendered, encoding="utf-8")
    except (OSError, ValueError) as error:
        print(f"Benchmark comparison rejected: {error}", file=sys.stderr)
        return 2
    _human_summary(result)
    print(rendered, end="")
    if result["medianCriterion"]["status"] == "insufficient-evidence":
        return 2
    if "regression" in (result["medianCriterion"]["status"], result["p95Criterion"]["status"]):
        return 1
    return 0 if result["medianCriterion"]["status"] == "passed" and result["p95Criterion"]["status"] == "passed" else 2


if __name__ == "__main__":
    raise SystemExit(main())
