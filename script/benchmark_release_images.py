#!/usr/bin/env python3
"""Measure real ImageIO decoder footprint in fresh Release processes, using synthetic complete images."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'script'))
from benchmark_metadata import (capture_source_state, require_unchanged_sources,
                                save_prepared_worker, validate_prepared_worker)
from package_link import package_module_flags, package_objects

FIXTURES = {
    'rgba40.png': (8000, 5000), 'rgb40.jpg': (8000, 5000), 'rgba16.png': (4000, 4000),
    'rgba100.png': (10000, 10000), 'tiny.avif': (32, 24),
}
SCENARIO_FIXTURES = {
    'png40-rgba': ['rgba40.png'], 'jpeg40-rgb': ['rgb40.jpg'],
    'png16-pair': ['rgba16.png', 'rgba16.png'],
    'png40-plus16-pair': ['rgba40.png', 'rgba16.png', 'rgba16.png'],
    'refused100-rgba': ['rgba100.png'], 'tiny-avif': ['tiny.avif'],
    'cancel-replace': ['rgba40.png', 'rgba40.png', 'rgba16.png', 'rgba16.png'],
}
SCENARIOS = list(SCENARIO_FIXTURES)
ENCODED_LIMIT = 8 * 1_048_576
AFTER_RELEASE_SCOPE = 'Swift image/source references dropped; immediate footprint may retain allocator/framework memory'
FOOTPRINT_METRICS = ['baselinePhysicalFootprintBytes', 'baselineLifetimePeakPhysicalFootprintBytes',
                     'physicalFootprintHoldingBitmapsBytes', 'physicalFootprintAfterReleaseBytes',
                     'lifetimePeakPhysicalFootprintBytes', 'maximumSampledPhysicalFootprintBytes',
                     'sampledIncrementalPeakBytes']


def command_output(arguments):
    return subprocess.check_output(arguments, text=True).strip()


def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))


def rgba_png(path, width, height):
    # Only 64 short rows are retained; no full-size bitmap is generated in this or the measured worker.
    rows = [b'\0' + bytes(component for x in range(width)
                         for component in (((x % 64) * 3), y * 3, ((x + y) % 64) * 3, 255))
            for y in range(64)]
    compressor = zlib.compressobj(9)
    encoded = bytearray()
    for y in range(height):
        encoded.extend(compressor.compress(rows[y % 64]))
        if len(encoded) > 8 * 1_048_576:
            raise ValueError('Synthetic PNG exceeds the encoded image ceiling')
    encoded.extend(compressor.flush())
    header = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', encoded) + chunk(b'IEND', b''))


def generate_fixtures(directory):
    descriptions = {}
    for name, width, height in [('rgba40.png', 8_000, 5_000), ('rgba16.png', 4_000, 4_000),
                                ('rgba100.png', 10_000, 10_000)]:
        rgba_png(directory / name, width, height)
        descriptions[name] = {'width': width, 'height': height, 'bitsPerComponent': 8, 'color': 'RGBA'}
    # The encoder runs in a different process before any measured worker starts. Its full-size allocation
    # cannot contaminate that worker's baseline or kernel lifetime peak.
    subprocess.run(['/usr/bin/sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '65',
                    str(directory / 'rgba40.png'), '--out', str(directory / 'rgb40.jpg')],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=60)
    descriptions['rgb40.jpg'] = {'width': 8_000, 'height': 5_000, 'bitsPerComponent': 8, 'color': 'RGB'}
    rgba_png(directory / 'tiny.png', 32, 24)
    subprocess.run(['/usr/bin/sips', '-s', 'format', 'avif', str(directory / 'tiny.png'), '--out', str(directory / 'tiny.avif')],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=60)
    descriptions['tiny.avif'] = {'width': 32, 'height': 24, 'bitsPerComponent': 8, 'color': 'RGB'}
    for name, description in descriptions.items():
        data = (directory / name).read_bytes()
        if len(data) > 8 * 1_048_576:
            raise ValueError('Synthetic fixture exceeds the encoded image ceiling')
        description.update(encodedBytes=len(data), sha256=hashlib.sha256(data).hexdigest())
    return descriptions


def integer(value, name, minimum=0, maximum=None):
    # bool is an int subclass; floats, NaN, infinity, absent and null metrics are never evidence.
    if type(value) is not int or value < minimum or (maximum is not None and value > maximum):
        raise ValueError(f'Invalid or unavailable {name}')
    return value


def requested_side(width, height):
    # Independent oracle for the normal page request at 2048 points / 2x backing scale.
    factor = min(1, 4096 / width, 4096 / max(width, height))
    area = width * height * factor * factor
    if area > 8_000_000:
        factor *= math.sqrt(8_000_000 / area)
    return max(16, min(4096, math.ceil(max(width, height) * factor)))


def validate_report(report, scenario, phase, count, manifest=None):
    if scenario not in SCENARIO_FIXTURES or phase not in ('cold', 'warm'):
        raise ValueError('Unknown image scenario or phase')
    integer(count, 'sample count', 1, 21)
    if phase == 'cold' and count != 1:
        raise ValueError('Cold sample must run in a fresh process')
    if not isinstance(report, dict) or type(report.get('schemaVersion')) is not int or report['schemaVersion'] != 1:
        raise ValueError('Worker returned an invalid schema')
    samples = report.get('samples')
    if report.get('scenario') != scenario or not isinstance(samples, list) or len(samples) != count:
        raise ValueError('Worker returned an invalid scenario/sample set')
    if report.get('phase') != phase or report.get('unmeasuredWarmupPerformed') is not (phase == 'warm'):
        raise ValueError('Worker omitted explicit cold/warm phase or warmup')
    if report.get('sampleIntervalMilliseconds') != 2 or type(report.get('sampleIntervalMilliseconds')) is not int:
        raise ValueError('Worker used a different sample interval')
    if report.get('afterReleaseScope') != AFTER_RELEASE_SCOPE:
        raise ValueError('Worker omitted allocator/framework retention scope')
    for key in FOOTPRINT_METRICS[:2]:
        integer(report.get(key), key)
    if 'warmupLifetimePeakPhysicalFootprintBytes' not in report:
        raise ValueError('Missing warmup lifetime peak')
    if phase == 'warm':
        integer(report['warmupLifetimePeakPhysicalFootprintBytes'], 'warmup lifetime peak')
    elif report['warmupLifetimePeakPhysicalFootprintBytes'] is not None:
        raise ValueError('Cold process cannot have an unmeasured warmup')
    names = SCENARIO_FIXTURES[scenario]
    sizes = [FIXTURES[name] for name in names]
    cancelled = scenario == 'cancel-replace'
    refused = scenario == 'refused100-rgba'
    previous_peak = report.get('warmupLifetimePeakPhysicalFootprintBytes') or report['baselineLifetimePeakPhysicalFootprintBytes']
    for sample in samples:
        if not isinstance(sample, dict):
            raise ValueError('Invalid image sample')
        for key in FOOTPRINT_METRICS:
            integer(sample.get(key), key)
        integer(sample.get('durationNanoseconds'), 'duration', 1)
        integer(sample.get('physicalSampleCount'), 'physical sample count', 3)
        integer(sample.get('maximumActiveLeases'), 'active leases', 0, 0 if refused else 1)
        integer(sample.get('maximumWaitingDecodes'), 'waiting decodes', 0, len(names))
        integer(sample.get('thermalState'), 'thermal state', 0, 3)
        if sample.get('sourceWidths') != [w for w, h in sizes] or sample.get('sourceHeights') != [h for w, h in sizes]:
            raise ValueError('Scenario has incorrect source dimensions')
        for key in ('sourceWidths', 'sourceHeights', 'requestedDecodeSides', 'sourceEncodedBytes'):
            if not isinstance(sample.get(key), list) or len(sample[key]) != len(names):
                raise ValueError('Scenario has incorrect source inventory')
            for value in sample[key]:
                integer(value, key, 1)
        if sample['requestedDecodeSides'] != [requested_side(w, h) for w, h in sizes]:
            raise ValueError('Scenario did not use the production page request size')
        for name, size in zip(names, sample['sourceEncodedBytes']):
            integer(size, 'encoded image size', 1, ENCODED_LIMIT)
            if manifest is not None and size != manifest[name]['encodedBytes']:
                raise ValueError('Worker fixture size disagrees with its fingerprint')
        if type(sample.get('refusedImageCount')) is not int or sample['refusedImageCount'] != int(refused):
            raise ValueError('Incorrect refused image count')
        if sample.get('cancelledAfterAdmission') is not cancelled:
            raise ValueError('Incorrect admission cancellation claim')
        for key in ('retiredTaskReturnedBitmap', 'cancellationInsideNativeCallObserved'):
            if key not in sample:
                raise ValueError('Missing cancellation observation')
        if (cancelled and type(sample['retiredTaskReturnedBitmap']) is not bool) or (not cancelled and sample['retiredTaskReturnedBitmap'] is not None):
            raise ValueError('Incorrect retired task observation')
        if sample['cancellationInsideNativeCallObserved'] is not None:
            raise ValueError('This probe cannot observe cancellation inside the native C call')
        bitmaps = sample.get('decodedBitmaps')
        expected_sizes = [] if refused else sizes[int(cancelled):]
        if not isinstance(bitmaps, list) or len(bitmaps) != len(expected_sizes):
            raise ValueError('Incorrect decoded image count')
        for bitmap, (width, height) in zip(bitmaps, expected_sizes):
            if not isinstance(bitmap, dict):
                raise ValueError('Invalid decoded bitmap')
            side = min(requested_side(width, height), max(width, height))
            w = integer(bitmap.get('width'), 'bitmap width', 1, min(width, side))
            h = integer(bitmap.get('height'), 'bitmap height', 1, min(height, side))
            bits = integer(bitmap.get('bitsPerComponent'), 'component depth', 1, 32)
            row = integer(bitmap.get('bytesPerRow'), 'row stride', math.ceil(w * bits / 8))
            storage = integer(bitmap.get('storageBytes'), 'bitmap storage', 1)
            if storage != row * h or max(w, h) < side - 1 or abs(w * height - h * width) > max(width, height):
                raise ValueError('Incorrect bitmap geometry or storage accounting')
        base = sample['baselinePhysicalFootprintBytes']
        maximum = sample['maximumSampledPhysicalFootprintBytes']
        if maximum < max(base, sample['physicalFootprintHoldingBitmapsBytes'], sample['physicalFootprintAfterReleaseBytes']):
            raise ValueError('Sampled maximum omits an explicit probe')
        if sample['sampledIncrementalPeakBytes'] != max(0, maximum - base):
            raise ValueError('Incorrect sampled incremental footprint')
        peak = sample['lifetimePeakPhysicalFootprintBytes']
        if peak < max(maximum, previous_peak, sample['baselineLifetimePeakPhysicalFootprintBytes']):
            raise ValueError('Kernel lifetime peak is inconsistent with process chronology')
        previous_peak = peak


def require_fixture_integrity(directory, manifest):
    for name, description in manifest.items():
        data = (directory / name).read_bytes()
        if len(data) != description['encodedBytes'] or hashlib.sha256(data).hexdigest() != description['sha256']:
            raise ValueError('Synthetic fixture changed during measurement')



def bounded_count(value):
    count = int(value)
    if not 1 <= count <= 21:
        raise argparse.ArgumentTypeError('Sample count must be from 1 to 21')
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cold-samples', type=bounded_count, default=3)
    parser.add_argument('--warm-samples', type=bounded_count, default=5)
    parser.add_argument('--case', choices=SCENARIOS, action='append', dest='cases')
    parser.add_argument('--output', type=Path, default=ROOT / '.build/performance/release-images.json')
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--build-only', action='store_true')
    modes.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    source_state = capture_source_state(ROOT)
    package = ROOT / 'Packages/PreviewCore'
    # Testability exposes internal decoder seams only in this measurement build. Optimization stays -O;
    # no new shipping public API is introduced for the probe.
    build_args = ['--package-path', str(package), '--build-system', 'native', '-c', 'release',
                  '--scratch-path', str(package / '.build/performance-images'), '-Xswiftc', '-enable-testing']
    build_command = ['/usr/bin/xcrun', 'swift', 'build', *build_args]
    if not args.skip_build:
        subprocess.run(build_command, check=True)
    bin_dir = Path(command_output([*build_command, '--show-bin-path']))
    executable = bin_dir / 'ReleaseImageDecodeBenchmark'
    sdk = command_output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'])
    compile_command = ['/usr/bin/xcrun', 'swiftc', '-O', '-parse-as-library', '-sdk', sdk,
                       '-target', f'{os.uname().machine}-apple-macosx15.0', '-swift-version', '6',
                       '-strict-concurrency=complete', '-enable-testing', '-default-isolation', 'nonisolated',
                       '-I', str(bin_dir), '-I', str(bin_dir / 'Modules'), *package_module_flags(bin_dir),
                       '-module-name', 'ReleaseImageDecodeBenchmark', '-o', str(executable),
                       str(ROOT / 'Tests/Performance/ReleaseImageDecodeBenchmark.swift'),
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
    }
    context = {'environment': environment, 'buildCommand': build_command, 'workerCompileCommand': compile_command,
               'runnerSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    if not args.skip_build:
        subprocess.run(compile_command, check=True)
        require_unchanged_sources(ROOT, source_state)
        save_prepared_worker(executable, source_state, context)
    identity = validate_prepared_worker(executable, source_state, context)
    if args.build_only:
        print(f'Fingerprint-checked Release image worker prepared: {executable}')
        return
    result = {'schemaVersion': 1, 'measuredAtUTC': datetime.now(timezone.utc).isoformat(),
              'environment': environment, 'sourceState': source_state, 'workerBuild': identity,
              'configuration': {'package': 'Release', 'workerOptimization': '-O', 'testabilityEnabled': True,
                                'deploymentTarget': 'macOS15.0', 'sampleIntervalMilliseconds': 2,
                                'coldSamples': args.cold_samples, 'warmSamples': args.warm_samples,
                                'memoryScope': 'Actual worker TASK_VM_INFO footprint during production ImageIO decoding; kernel lifetime peak separately',
                                'processScope': 'Standalone worker; launches no child processes; Finder and shared OS services are not measured',
                                'admissionScope': 'Production processWide admission; cancellation injects the same production gate with an acquisition observer',
                                'startingIncrementalTargetBytes': 100 * 1_048_576, 'closesMemoryTarget': False},
              'fixtures': {}, 'cases': {}}
    with tempfile.TemporaryDirectory(prefix='prev-image-footprint-') as temporary:
        directory = Path(temporary)
        manifest = generate_fixtures(directory)
        result['fixtures'] = manifest
        def require_inputs():
            require_unchanged_sources(ROOT, source_state)
            validate_prepared_worker(executable, source_state, context)
            if hashlib.sha256(Path(__file__).read_bytes()).hexdigest() != context['runnerSHA256']:
                raise ValueError('Image benchmark runner changed during measurement')
            require_fixture_integrity(directory, manifest)
        for scenario in args.cases or SCENARIOS:
            require_inputs()
            cold = []
            for _ in range(args.cold_samples):
                report = json.loads(subprocess.check_output([str(executable), scenario, str(directory), 'cold', '1'], timeout=60))
                validate_report(report, scenario, 'cold', 1, manifest); cold.append(report)
                require_inputs()
            warm = json.loads(subprocess.check_output([str(executable), scenario, str(directory), 'warm', str(args.warm_samples)], timeout=60))
            validate_report(warm, scenario, 'warm', args.warm_samples, manifest)
            require_inputs()
            result['cases'][scenario] = {'cold': cold, 'warm': warm}
            print(f'Measured {scenario}', flush=True)
        require_inputs()
    require_unchanged_sources(ROOT, source_state)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True, allow_nan=False) + '\n')
    print(f'Recorded image footprint: {args.output}')


if __name__ == '__main__':
    main()
