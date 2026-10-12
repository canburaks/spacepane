"""Shared schema-1 additive measurement provenance and actual-footprint summaries.

Fingerprints cover the Swift package source/resources/manifest and benchmark
sources and build scripts, including untracked inputs. No source contents or
diffs are emitted. A prepared worker is valid only for these exact bytes, build
context and executable bytes. Physical footprint is never inferred from RSS;
legacy reports or failed probes leave the corresponding summary unavailable.
"""
import hashlib
import json
from pathlib import Path
import subprocess


def source_fingerprint(root: Path) -> str:
    paths = set()
    for relative in ["Packages/PreviewCore/Sources", "Tests/Performance"]:
        directory = root / relative
        if directory.is_symlink():
            raise ValueError("benchmark source inputs must not be symlinks")
        for path in directory.rglob("*"):
            if path.is_symlink():
                raise ValueError("benchmark source inputs must not be symlinks")
            if path.is_file():
                paths.add(path)
    for relative in ["Packages/PreviewCore/Package.swift", "script/package_link.py",
                     "script/benchmark_metadata.py", "script/benchmark_release_pipeline.py",
                     "script/benchmark_release_native_renderer.py"]:
        path = root / relative
        if path.is_symlink():
            raise ValueError("benchmark source inputs must not be symlinks")
        if path.is_file():
            paths.add(path)
    if not paths:
        raise ValueError("benchmark source inputs are missing")
    digest = hashlib.sha256()
    for path in sorted(paths, key=lambda item: item.relative_to(root).as_posix()):
        name = path.relative_to(root).as_posix().encode("utf-8")
        contents = path.read_bytes()
        # Length prefixes make the stream unambiguous even with unusual file names/contents.
        digest.update(len(name).to_bytes(8, "big")); digest.update(name)
        digest.update(len(contents).to_bytes(8, "big")); digest.update(contents)
    return digest.hexdigest()


def capture_source_state(root: Path) -> dict:
    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(root), *arguments], text=True).strip()
    return {"revision": git("rev-parse", "HEAD"), "dirty": bool(git("status", "--porcelain")),
            "sourceTreeSHA256": source_fingerprint(root)}


def require_unchanged_sources(root: Path, expected: dict) -> None:
    if capture_source_state(root) != expected:
        raise ValueError("benchmark sources changed during build/measurement; discard this run and rebuild")


def _prepared_path(executable: Path) -> Path:
    return executable.with_name(executable.name + ".build.json")


def _prepared_identity(executable: Path, source_state: dict, context: dict) -> dict:
    return {"schemaVersion": 1, "sourceState": source_state, "buildContext": context,
            "executableSHA256": hashlib.sha256(executable.read_bytes()).hexdigest()}


def save_prepared_worker(executable: Path, source_state: dict, context: dict) -> None:
    identity = _prepared_identity(executable, source_state, context)
    _prepared_path(executable).write_text(json.dumps(identity, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def validate_prepared_worker(executable: Path, source_state: dict, context: dict) -> dict:
    try:
        recorded = json.loads(_prepared_path(executable).read_text(encoding="utf-8"))
        current = _prepared_identity(executable, source_state, context)
    except (OSError, ValueError) as error:
        raise ValueError("no valid prepared benchmark worker; run --build-only first") from error
    if recorded != current:
        raise ValueError("prepared benchmark worker is stale; rebuild before measuring")
    return {"sourceState": recorded["sourceState"], "executableSHA256": recorded["executableSHA256"],
            "buildContextSHA256": hashlib.sha256(json.dumps(context, sort_keys=True, separators=(",", ":")).encode()).hexdigest()}


def physical_footprint_summary(runs: list[dict]) -> dict:
    samples = [sample for run in runs for sample in run["samples"]]
    def complete_max(values):
        return max(values) if values and all(type(value) is int and value >= 0 for value in values) else None
    growth = []
    for run in runs:
        baseline = run.get("baselineLifetimePeakPhysicalFootprintBytes")
        peak = complete_max([sample.get("lifetimePeakPhysicalFootprintBytes") for sample in run["samples"]])
        growth.append(max(0, peak - baseline) if peak is not None and type(baseline) is int and baseline >= 0 else None)
    return {"maxBaselinePhysicalFootprint": complete_max([run.get("baselinePhysicalFootprintBytes") for run in runs]),
            "maxSampledPhysicalFootprint": complete_max([sample.get("maxSampledPhysicalFootprintBytes") for sample in samples]),
            "maxLifetimePeakPhysicalFootprint": complete_max([sample.get("lifetimePeakPhysicalFootprintBytes") for sample in samples]),
            "maxLifetimePeakPhysicalFootprintGrowthFromBaselinePeak": complete_max(growth)}
