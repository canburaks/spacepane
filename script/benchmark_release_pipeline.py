#!/usr/bin/env python3
"""Measure the Release core pipeline with bounded, synthetic local fixtures only."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time
import zipfile

from package_link import ROOT, package_module_flags, package_objects
from benchmark_metadata import (capture_source_state, physical_footprint_summary, require_unchanged_sources,
                                save_prepared_worker, source_fingerprint, validate_prepared_worker)


def command_output(command: list[str]) -> str:
    return subprocess.check_output(command, text=True).strip()


def bounded_count(value: str) -> int:
    count = int(value)
    if not 1 <= count <= 200:
        raise argparse.ArgumentTypeError("sample counts must be between 1 and 200")
    return count


def fixtures(directory: Path) -> dict[str, Path]:
    secret = "synthetic-benchmark-private-value"
    paths = {name: directory / filename for name, filename in [
        ("text", "ordinary.txt"), ("json", "ordinary.json"), ("json-lines", "ordinary.jsonl"),
        ("malformed-json", "malformed.json"), ("malformed-json-lines", "malformed.jsonl"),
        ("oversized-text", "oversized.txt"), ("zip", "directory.zip"), ("sqlite", "snapshot.sqlite"),
        ("dense-secrets", "dense-secrets.txt"),
        ("csv", "records.csv"), ("listing", "large-directory.zip"),
        ("markdown-contents", "contents.md"), ("environment", ".env"),
        ("source-1mib", "large-source.swift"), ("json-1mib", "large.json"),
        ("log-before", "before.log"), ("log-append", "appended.log"),
    ]}
    paths["text"].write_text("password=" + secret + "\n" + "".join(
        f"Line {index:04}: local synthetic text Türkçe 日本語 🌍 " + "a" * 64 + "\n"
        for index in range(1500)), encoding="utf-8")
    rows = [{"id": index, "message": "Türkçe 日本語 🌍", "padding": "a" * 96} for index in range(1200)]
    paths["json"].write_text(json.dumps({"password": secret, "rows": rows}, ensure_ascii=False, indent=2), encoding="utf-8")
    paths["json-lines"].write_text("\n".join(json.dumps({**row, "password": secret}, ensure_ascii=False)
                                            for row in rows) + "\n", encoding="utf-8")
    paths["malformed-json"].write_text('{"password":"' + secret + '" "missing":"comma"}', encoding="utf-8")
    paths["malformed-json-lines"].write_text('{"value":1}\n{"password":"' + secret + '" missing}\n{"value":3}\n', encoding="utf-8")
    # Exercise the current production standard input limit (1 MiB), not a relaxed benchmark budget.
    paths["oversized-text"].write_bytes(b"a\n" * 524_289)
    # The cost of concealment itself (decision 027, Q-43): one short secret per line, 16,000 lines in about 780 KB.
    # That is inside the standard 20,000-line, 20,000-match and 1 MiB limits, so every value is concealed and none is capped.
    paths["dense-secrets"].write_text("".join(f"password={secret}-{index:05}\n" for index in range(16_000)), encoding="utf-8")
    with zipfile.ZipFile(paths["zip"], "w", compression=zipfile.ZIP_STORED) as archive:
        for index in range(200):
            entry = zipfile.ZipInfo(f"synthetic/日本語-{index:03}.txt", date_time=(2026, 1, 1, 0, 0, 0))
            archive.writestr(entry, b"synthetic-payload-must-not-be-previewed")
    with sqlite3.connect(paths["sqlite"]) as database:
        database.execute("CREATE TABLE records (id INTEGER PRIMARY KEY, message TEXT, password TEXT)")
        database.executemany("INSERT INTO records VALUES (?, ?, ?)",
                             [(index, "Türkçe 日本語 🌍 " + "a" * 96, secret) for index in range(1200)])
    paths["csv"].write_text("id,message,password\n" + "".join(
        f'{index},"local synthetic {"a" * 55}",{secret}\n' for index in range(2300)), encoding="utf-8")
    with zipfile.ZipFile(paths["listing"], "w", compression=zipfile.ZIP_STORED) as archive:
        for index in range(2000):
            entry = zipfile.ZipInfo(f"synthetic/item-{index:04}.txt", date_time=(2026, 1, 1, 0, 0, 0))
            archive.writestr(entry, b"synthetic-payload-must-not-be-previewed")
    paths["markdown-contents"].write_text(
        "# Local synthetic document\npassword: " + secret + "\n\n" + "".join(
            f"## Section {index}\n**Local** content and `inert code`.\n\n" for index in range(40)), encoding="utf-8")
    paths["environment"].write_text("PASSWORD=" + secret + "\nLOCAL_LABEL=synthetic\u200b-label\n", encoding="utf-8")
    limit = 1_048_576
    source = ('let password = "' + secret + '"\n' + "// bounded synthetic source " + "a" * 100 + "\n").encode()
    line = b"// " + b"a" * 124 + b"\n"
    whole, remainder = divmod(limit - len(source), len(line))
    paths["source-1mib"].write_bytes(source + line * whole + (b"a" * (remainder - 1) + b"\n" if remainder else b""))
    # 3500 two-field rows stay inside the 20,000-node limit. Padding is spread
    # over short logical lines rather than one pathological megabyte string.
    header = ('{"password":"' + secret + '","rows":[\n').encode()
    suffix = b"\n]}\n"
    row_count = 3500
    rows = [('{"id":%d,"message":""}' % index).encode() for index in range(row_count)]
    padding = limit - len(header) - len(suffix) - sum(map(len, rows)) - (row_count - 1) * 2
    quotient, remainder = divmod(padding, row_count)
    rows = [row[:-2] + b"a" * (quotient + (index < remainder)) + row[-2:] for index, row in enumerate(rows)]
    paths["json-1mib"].write_bytes(header + b",\n".join(rows) + suffix)
    log = ("password=" + secret + "\n" + "".join(f"2026-01-01 local synthetic line {index:04}\n" for index in range(500))).encode()
    paths["log-before"].write_bytes(log)
    paths["log-append"].write_bytes(log + b"2026-01-01 local synthetic appended line\n")
    return paths


def snapshot(directory: Path) -> dict:
    # Contents/names and modification times are checked outside the timed worker.
    if any(not path.is_file() or path.is_symlink() for path in directory.iterdir()):
        raise RuntimeError("an unexpected directory or symlink appeared among the synthetic fixtures")
    return {path.name: (hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mtime_ns)
            for path in directory.iterdir()}


def percentile(values: list[float], fraction: float) -> float:
    # Nearest rank; p95 for ten cold samples is their maximum. Preserve raw samples.
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def distribution(values: list[float]) -> dict:
    return {"count": len(values), "min": min(values), "p50": percentile(values, 0.50),
            "p95": percentile(values, 0.95), "max": max(values)}


def run_worker(executable: Path, scenario: str, path: Path, count: int, *, signposts: bool = False) -> dict:
    start = time.perf_counter_ns()
    command = [str(executable), scenario, str(path), str(count)] + (["--signposts"] if signposts else [])
    completed = subprocess.run(command,
                               check=True, capture_output=True, text=True, timeout=15 + count * 3)
    elapsed = time.perf_counter_ns() - start
    report = json.loads(completed.stdout)
    if report["scenario"] != scenario or len(report["samples"]) != count:
        raise RuntimeError("measurement worker returned an invalid sample set")
    report["processWallNanoseconds"] = elapsed
    return report


def summarize(cold: list[dict], warm: dict) -> dict:
    all_runs = cold + [warm]
    all_samples = [sample for run in all_runs for sample in run["samples"]]
    if any(run["outcome"] != warm["outcome"] for run in cold):
        raise RuntimeError("cold and warm outcomes differ")
    return {
        "outcome": warm["outcome"],
        "coldFirstRequestMilliseconds": distribution([run["samples"][0]["requestNanoseconds"] / 1e6 for run in cold]),
        "coldProcessWallMilliseconds": distribution([run["processWallNanoseconds"] / 1e6 for run in cold]),
        "warmRequestMilliseconds": distribution([sample["requestNanoseconds"] / 1e6 for sample in warm["samples"][1:]]),
        "memoryBytes": {
            "maxBaselineResident": max(run["baselineResidentBytes"] for run in all_runs),
            "maxObservedResident": max(max(sample["residentBeforeBytes"], sample["residentAfterBytes"]) for sample in all_samples),
            "maxLifetimePeakResident": max(sample["lifetimePeakResidentBytes"] for sample in all_samples),
            "maxLifetimePeakGrowthFromBaselinePeak": max(
                max(sample["lifetimePeakResidentBytes"] for sample in run["samples"]) - run["baselineLifetimePeakResidentBytes"]
                for run in all_runs),
            **physical_footprint_summary(all_runs),
        },
        "coldRuns": cold, "warmRun": warm,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cold-samples", type=bounded_count, default=10)
    parser.add_argument("--warm-samples", type=bounded_count, default=50)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/performance/release-pipeline-results.json")
    parser.add_argument("--case", action="append", dest="cases", help="Measure only these fixture IDs (repeatable)")
    parser.add_argument("--signposts", action="store_true", help="Opt in to fixed-name OS interval signposts")
    build_modes = parser.add_mutually_exclusive_group()
    build_modes.add_argument("--build-only", action="store_true", help="Prepare a fingerprinted Release worker without measuring")
    build_modes.add_argument("--skip-build", action="store_true", help="Measure only if the prepared worker fingerprint is current")
    args = parser.parse_args()
    source_state = capture_source_state(ROOT)
    package = ROOT / "Packages/PreviewCore"
    build_args = ["--package-path", str(package), "--build-system", "native", "-c", "release",
                  "--scratch-path", str(package / ".build/performance")]
    if not args.skip_build:
        subprocess.run(["/usr/bin/xcrun", "swift", "build", *build_args], check=True)
    bin_dir = Path(command_output(["/usr/bin/xcrun", "swift", "build", *build_args, "--show-bin-path"]))
    executable = bin_dir / "ReleasePipelineBenchmark"
    sdk = command_output(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"])
    compile_command = ["/usr/bin/xcrun", "swiftc", "-O", "-parse-as-library", "-sdk", sdk,
                       "-target", f"{os.uname().machine}-apple-macosx15.0", "-swift-version", "6",
                       "-strict-concurrency=complete", "-default-isolation", "nonisolated",
                       "-I", str(bin_dir), "-I", str(bin_dir / "Modules"),
                       *package_module_flags(bin_dir), "-module-name", "ReleasePipelineBenchmark",
                       "-o", str(executable), str(ROOT / "Tests/Performance/ReleasePipelineBenchmark.swift"),
                       str(ROOT / "Tests/Performance/BenchmarkInstrumentation.swift"),
                       *[str(path) for path in package_objects(bin_dir)]]
    environment = {
        "architecture": os.uname().machine,
        "model": command_output(["/usr/sbin/sysctl", "-n", "hw.model"]),
        "cpu": command_output(["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"]),
        "physicalMemoryBytes": int(command_output(["/usr/sbin/sysctl", "-n", "hw.memsize"])),
        "os": command_output(["/usr/bin/sw_vers"]),
        "swift": command_output(["/usr/bin/xcrun", "swift", "--version"]),
        "xcode": command_output(["/usr/bin/xcrun", "xcodebuild", "-version"]),
        "sdkVersion": command_output(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-version"]),
        "developerDirectory": os.environ.get("DEVELOPER_DIR") or command_output(["/usr/bin/xcode-select", "-p"]),
    }
    context = {"environment": environment, "buildCommand": ["/usr/bin/xcrun", "swift", "build", *build_args],
               "workerCompileCommand": compile_command}
    if args.skip_build:
        validate_prepared_worker(executable, source_state, context)
    else:
        subprocess.run(compile_command, check=True)
        require_unchanged_sources(ROOT, source_state)
        save_prepared_worker(executable, source_state, context)
    if args.build_only:
        print(f"Fingerprint-checked Release worker prepared: {executable}")
        return
    require_unchanged_sources(ROOT, source_state)
    worker_build = validate_prepared_worker(executable, source_state, context)
    result = {
        "schemaVersion": 1, "measuredAtUTC": datetime.now(timezone.utc).isoformat(),
        "environment": environment, "sourceState": source_state, "workerBuild": worker_build,
        "configuration": {"package": "Release", "workerOptimization": "-O", "deploymentTarget": "macOS 15.0",
                          "coldSamples": args.cold_samples, "warmSamples": args.warm_samples,
                          "budget": "PreviewBudget.standard", "percentileMethod": "nearest-rank",
                          "stageObservationLimit": 256, "signposts": args.signposts,
                          "memoryScope": "TASK_VM_INFO actual physical footprint sampled at stage/draw boundaries; kernel lifetime peak when available; RSS separately",
                          "buildCommand": ["xcrun", "swift", "build", *build_args],
                          "workerCompileCommand": compile_command},
        "cases": {},
    }
    with tempfile.TemporaryDirectory(prefix="prev-release-benchmark-") as temporary:
        directory = Path(temporary)
        paths = fixtures(directory)
        paths.pop("log-before")  # Immutable producer predecessor is setup, never its own case.
        if args.cases:
            if set(args.cases) - paths.keys():
                parser.error("unknown fixture IDs: " + ", ".join(sorted(set(args.cases) - paths.keys())))
            paths = {name: paths[name] for name in dict.fromkeys(args.cases)}
        before = snapshot(directory)
        print("scenario                 bytes    cold request p95 ms    warm p95 ms    process peak MiB", flush=True)
        for scenario, path in paths.items():
            cold = [run_worker(executable, scenario, path, 1, signposts=args.signposts) for _ in range(args.cold_samples)]
            # One untallied first request initializes this new process and retained
            # pipeline; only its following requests enter the warm distribution.
            warm = run_worker(executable, scenario, path, args.warm_samples + 1, signposts=args.signposts)
            summary = summarize(cold, warm)
            summary["inputBytes"] = path.stat().st_size
            summary["inputSHA256"] = hashlib.sha256(path.read_bytes()).hexdigest()
            if scenario == "log-append":
                summary["relatedInputSHA256"] = hashlib.sha256((directory / "before.log").read_bytes()).hexdigest()
            result["cases"][scenario] = summary
            if snapshot(directory) != before:
                raise RuntimeError("synthetic fixture contents, names or modification times changed")
            print(f"{scenario:23} {summary['inputBytes']:8} "
                  f"{summary['coldFirstRequestMilliseconds']['p95']:22.3f} "
                  f"{summary['warmRequestMilliseconds']['p95']:14.3f} "
                  f"{summary['memoryBytes']['maxLifetimePeakResident'] / 2**20:19.2f}", flush=True)
            require_unchanged_sources(ROOT, source_state)
            validate_prepared_worker(executable, source_state, context)
    require_unchanged_sources(ROOT, source_state)
    validate_prepared_worker(executable, source_state, context)
    result["measurementEndedAtUTC"] = datetime.now(timezone.utc).isoformat()
    result["sourceStateAtMeasurementEnd"] = source_state
    result["sourceChecks"] = "contents, file names and modification times unchanged after each scenario; temporary fixtures removed"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Results including raw samples: {args.output}")


if __name__ == "__main__":
    main()
