#!/usr/bin/env python3
"""Measure actual native AppKit rendering in isolated Release workers with synthetic data."""
import argparse
from datetime import datetime, timezone
import json
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import time

from benchmark_release_pipeline import bounded_count, command_output, distribution, fixtures, snapshot
from package_link import ROOT, package_module_flags, package_objects
from benchmark_metadata import (capture_source_state, physical_footprint_summary, require_unchanged_sources,
                                save_prepared_worker, validate_prepared_worker)


def run_worker(executable: Path, scenario: str, path: Path, count: int, *, signposts: bool = False) -> dict:
    start = time.perf_counter_ns()
    command = [str(executable), scenario, str(path), str(count)] + (["--signposts"] if signposts else [])
    completed = subprocess.run(command,
                               check=True, capture_output=True, text=True, timeout=30 + count * 5)
    report = json.loads(completed.stdout)
    if report['scenario'] != scenario or len(report['samples']) != count:
        raise ValueError('Renderer worker returned an invalid sample set')
    report['processWallNanoseconds'] = time.perf_counter_ns() - start
    return report


def summarize(cold: list[dict], warm: dict) -> dict:
    keys = ['pipelineNanoseconds', 'constructionNanoseconds', 'initialDisplayDrawNanoseconds',
            'initialDisplayCallNanoseconds', 'secondaryModeDrawNanoseconds', 'restyleDrawNanoseconds',
            'scrollDrawNanoseconds', 'logAppendDrawNanoseconds']
    results = {}
    for key in keys:
        first = [run['samples'][0][key] / 1e6 for run in cold if run['samples'][0].get(key) is not None]
        following = [sample[key] / 1e6 for sample in warm['samples'][1:] if sample.get(key) is not None]
        results[key.removesuffix('Nanoseconds') + 'Milliseconds'] = {
            'firstProcess': distribution(first) if first else None,
            'warmProcess': distribution(following) if following else None,
        }
    # The broader useful-content metric sums stages within each raw sample before taking percentiles.
    def whole_path(sample: dict) -> float:
        return (sample['pipelineNanoseconds'] + sample['constructionNanoseconds']
                + sample['initialDisplayDrawNanoseconds']) / 1e6
    results['wholePathMilliseconds'] = {
        'firstProcess': distribution([whole_path(run['samples'][0]) for run in cold]),
        'warmProcess': distribution([whole_path(sample) for sample in warm['samples'][1:]]),
    }
    runs = cold + [warm]
    samples = [sample for run in runs for sample in run['samples']]
    results['memoryBytes'] = {
        'maxBaselineResident': max(run['baselineResidentBytes'] for run in runs),
        'maxObservedResident': max(max(sample['residentBeforeBytes'], sample['residentAfterBytes']) for sample in samples),
        'maxLifetimePeakResident': max(sample['lifetimePeakResidentBytes'] for sample in samples),
        'maxLifetimePeakGrowthFromBaselinePeak': max(max(sample['lifetimePeakResidentBytes'] for sample in run['samples'])
                                                    - run['baselineLifetimePeakResidentBytes'] for run in runs),
        **physical_footprint_summary(runs),
    }
    results['coldProcessWallMilliseconds'] = distribution([run['processWallNanoseconds'] / 1e6 for run in cold])
    results['safeUTF8Bytes'] = warm['safeUTF8Bytes']
    results['coldRuns'] = cold
    results['warmRun'] = warm
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cold-samples', type=bounded_count, default=10)
    parser.add_argument('--warm-samples', type=bounded_count, default=50)
    parser.add_argument('--output', type=Path, default=ROOT / '.build/performance/release-native-renderer-results.json')
    parser.add_argument('--case', action='append', dest='cases', help='Measure only these fixture IDs (repeatable)')
    parser.add_argument('--signposts', action='store_true', help='Opt in to fixed-name OS interval signposts')
    build_modes = parser.add_mutually_exclusive_group()
    build_modes.add_argument('--build-only', action='store_true', help='Prepare Release worker without measuring')
    build_modes.add_argument('--skip-build', action='store_true', help='Measure only if the prepared worker fingerprint is current')
    args = parser.parse_args()
    source_state = capture_source_state(ROOT)
    package = ROOT / 'Packages/PreviewCore'
    build_args = ['--package-path', str(package), '--build-system', 'native', '-c', 'release',
                  '--scratch-path', str(package / '.build/performance-renderer')]
    if not args.skip_build:
        subprocess.run(['/usr/bin/xcrun', 'swift', 'build', *build_args], check=True)
    bin_dir = Path(command_output(['/usr/bin/xcrun', 'swift', 'build', *build_args, '--show-bin-path']))
    executable = bin_dir / 'ReleaseNativeRendererBenchmark'
    sdk = command_output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'])
    compile_command = ['/usr/bin/xcrun', 'swiftc', '-O', '-parse-as-library', '-sdk', sdk,
                       '-target', f'{os.uname().machine}-apple-macosx15.0', '-swift-version', '6',
                       '-strict-concurrency=complete', '-default-isolation', 'nonisolated',
                       '-I', str(bin_dir), '-I', str(bin_dir / 'Modules'), *package_module_flags(bin_dir),
                       '-module-name', 'ReleaseNativeRendererBenchmark', '-o', str(executable),
                       str(ROOT / 'Tests/Performance/ReleaseNativeRendererBenchmark.swift'),
                       str(ROOT / 'Tests/Performance/BenchmarkInstrumentation.swift'),
                       *[str(path) for path in package_objects(bin_dir)]]
    environment = {
        'architecture': os.uname().machine,
        'model': command_output(['/usr/sbin/sysctl', '-n', 'hw.model']),
        'cpu': command_output(['/usr/sbin/sysctl', '-n', 'machdep.cpu.brand_string']),
        'physicalMemoryBytes': int(command_output(['/usr/sbin/sysctl', '-n', 'hw.memsize'])),
        'os': command_output(['/usr/bin/sw_vers']),
        'swift': command_output(['/usr/bin/xcrun', 'swift', '--version']),
        'xcode': command_output(['/usr/bin/xcrun', 'xcodebuild', '-version']),
        'sdkVersion': command_output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version']),
        'developerDirectory': os.environ.get('DEVELOPER_DIR') or command_output(['/usr/bin/xcode-select', '-p']),
    }
    context = {'environment': environment, 'buildCommand': ['/usr/bin/xcrun', 'swift', 'build', *build_args],
               'workerCompileCommand': compile_command}
    if not args.skip_build:
        subprocess.run(compile_command, check=True)
        require_unchanged_sources(ROOT, source_state)
        save_prepared_worker(executable, source_state, context)
    else:
        validate_prepared_worker(executable, source_state, context)
    if args.build_only:
        print(f'Fingerprint-checked Release worker prepared: {executable}')
        return
    if not executable.is_file():
        raise ValueError('No prepared renderer worker; run without --skip-build first')
    require_unchanged_sources(ROOT, source_state)
    worker_build = validate_prepared_worker(executable, source_state, context)
    result = {
        'schemaVersion': 1, 'measuredAtUTC': datetime.now(timezone.utc).isoformat(),
        'environment': environment, 'sourceState': source_state, 'workerBuild': worker_build,
        'configuration': {
            'package': 'Release', 'workerOptimization': '-O', 'deploymentTarget': 'macOS 15.0',
            'coldSamples': args.cold_samples, 'warmSamples': args.warm_samples,
            'budget': 'PreviewBudget.standard', 'percentileMethod': 'nearest-rank',
            'stageObservationLimit': 256, 'signposts': args.signposts,
            'memoryScope': 'TASK_VM_INFO actual physical footprint sampled at stage/draw boundaries; kernel lifetime peak when available; RSS separately',
            'buildCommand': ['/usr/bin/xcrun', 'swift', 'build', *build_args],
            'workerCompileCommand': compile_command,
            'rendererScope': 'offscreen fresh 800x600 NativePreviewView; line numbers; full layout and bitmap draw; secondary mode; restyle; last viewport draw; immutable log snapshots; excludes Finder first-visible paint',
        },
        'cases': {},
    }
    with tempfile.TemporaryDirectory(prefix='prev-native-renderer-benchmark-') as temporary:
        directory = Path(temporary)
        all_paths = fixtures(directory)
        paths = {name: all_paths[name] for name in ['text', 'json', 'json-lines', 'zip', 'sqlite', 'csv', 'listing',
                 'markdown-contents', 'environment', 'source-1mib', 'json-1mib', 'log-append']}
        paths['source'] = directory / 'source.swift'
        paths['source'].write_text('let password = "synthetic-benchmark-private-value"\n' + ''.join(
            f'// Unicode Türkçe 日本語 😀\nlet item{index} = {index} // ' + 'a' * 64 + '\n' for index in range(1200)))
        paths['markdown'] = directory / 'document.md'
        paths['markdown'].write_text('# Synthetic local Markdown\npassword: synthetic-benchmark-private-value\n\n' + ''.join(
            f'## Heading {index}\n**Local** *Unicode 日本語* and `inert code`.\n\n' for index in range(500)))
        if args.cases:
            if set(args.cases) - paths.keys():
                parser.error('unknown fixture IDs: ' + ', '.join(sorted(set(args.cases) - paths.keys())))
            paths = {name: paths[name] for name in dict.fromkeys(args.cases)}
        before = snapshot(directory)
        print('scenario             bytes    warm display p95 ms    warm restyle p95 ms    warm whole-path p95 ms    process peak MiB', flush=True)
        for scenario, path in paths.items():
            cold = [run_worker(executable, scenario, path, 1, signposts=args.signposts) for _ in range(args.cold_samples)]
            warm = run_worker(executable, scenario, path, args.warm_samples + 1, signposts=args.signposts)
            summary = summarize(cold, warm)
            summary['inputBytes'] = path.stat().st_size
            summary['inputSHA256'] = hashlib.sha256(path.read_bytes()).hexdigest()
            if scenario == 'log-append':
                summary['relatedInputSHA256'] = hashlib.sha256((directory / 'before.log').read_bytes()).hexdigest()
            result['cases'][scenario] = summary
            if snapshot(directory) != before:
                raise ValueError('Synthetic source bytes, names or modification times changed')
            print(f"{scenario:18} {summary['inputBytes']:8} "
                  f"{summary['initialDisplayDrawMilliseconds']['warmProcess']['p95']:22.3f} "
                  f"{summary['restyleDrawMilliseconds']['warmProcess']['p95']:22.3f} "
                  f"{summary['wholePathMilliseconds']['warmProcess']['p95']:25.3f} "
                  f"{summary['memoryBytes']['maxLifetimePeakResident'] / 2**20:19.2f}", flush=True)
            require_unchanged_sources(ROOT, source_state)
            validate_prepared_worker(executable, source_state, context)
    require_unchanged_sources(ROOT, source_state)
    validate_prepared_worker(executable, source_state, context)
    result['measurementEndedAtUTC'] = datetime.now(timezone.utc).isoformat()
    result['sourceStateAtMeasurementEnd'] = source_state
    result['sourceChecks'] = 'contents, file names and modification times unchanged after each scenario; temporary fixtures removed'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(f'Results including raw samples: {args.output}')


if __name__ == '__main__':
    main()
