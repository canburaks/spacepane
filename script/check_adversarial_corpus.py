#!/usr/bin/env python3
"""Check deterministic synthetic mutations with the production pipeline, without source writes."""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import stat
import subprocess
import tempfile

from generate_host_fixtures import generate
from package_link import ROOT, package_module_flags, package_objects

SEED = 0x50524556


def snapshot(directory: Path) -> dict:
    result = {}
    for path in sorted(directory.rglob('*')):
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode): value = os.readlink(path)
        elif stat.S_ISREG(metadata.st_mode): value = hashlib.sha256(path.read_bytes()).hexdigest()
        else: value = None  # Do not open FIFOs or follow directory links.
        result[str(path.relative_to(directory))] = (metadata.st_mode, metadata.st_mtime_ns, value)
    return result


def variants(data: bytes, rng: random.Random) -> list[tuple[str, bytes]]:
    result = [('original', data), ('empty', b''), ('one-byte', data[:1]),
              ('half-prefix', data[:len(data) // 2]), ('missing-last-byte', data[:-1])]
    changed = bytearray(data)
    if changed: changed[rng.randrange(len(changed))] ^= 1 << rng.randrange(8)
    result.append(('seeded-bit-flip', bytes(changed)))
    changed = bytearray(data)
    if changed:
        start = rng.randrange(len(changed))
        changed[start:min(len(changed), start + 8)] = b'\xff' * min(8, len(changed) - start)
    result.append(('seeded-maximum-word', bytes(changed)))
    result.append(('seeded-invalid-prefix', bytes(rng.randrange(256) for _ in range(32)) + data))
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package_bin', type=Path, help='Already-built SwiftPM bin directory')
    parser.add_argument('--output', type=Path, default=ROOT / '.build/performance/adversarial-corpus-results.json')
    args = parser.parse_args()
    bin_dir = args.package_bin.resolve()
    executable = bin_dir / 'AdversarialCorpusChecks'
    sdk = subprocess.check_output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    command = ['/usr/bin/xcrun', 'swiftc', '-O', '-parse-as-library', '-sdk', sdk,
               '-target', f'{os.uname().machine}-apple-macosx15.0', '-swift-version', '6',
               '-strict-concurrency=complete', '-default-isolation', 'nonisolated',
               '-I', str(bin_dir), '-I', str(bin_dir / 'Modules'), *package_module_flags(bin_dir),
               '-module-name', 'AdversarialCorpusChecks', '-o', str(executable),
               str(ROOT / 'Tests/Integration/AdversarialCorpusChecks.swift'),
               *[str(path) for path in package_objects(bin_dir)]]
    subprocess.run(command, check=True)
    seed_directory = generate()  # Unique owned synthetic seed set, not installed Finder fixtures.
    try:
        manifest = json.loads((seed_directory / 'manifest.json').read_text())
        rng = random.Random(SEED)
        with tempfile.TemporaryDirectory(prefix='prev-adversarial-corpus-') as temporary:
            directory = Path(temporary)
            entries = []
            for index, fixture in enumerate(manifest['fixtures']):
                original = seed_directory / fixture['path']
                if original.is_file():
                    mutations = variants(original.read_bytes(), rng)
                    for variant, data in mutations:
                        case = directory / f'case-{index:02}-{variant}'
                        case.mkdir()
                        path = case / original.name
                        path.write_bytes(data)
                        entries.append({'formatID': fixture['formatID'], 'path': str(path), 'variant': variant})
                else:
                    for variant in ['original', 'empty', 'nested', 'symlink', 'unicode', 'secret-name', 'fifo', 'many-children']:
                        case = directory / f'case-{index:02}-{variant}'
                        case.mkdir()
                        path = case / original.name
                        path.mkdir()
                        if variant == 'original': shutil.copytree(original, path, dirs_exist_ok=True)
                        elif variant == 'nested':
                            nested = path / 'nested'; nested.mkdir(); (nested / 'never-read.txt').write_bytes(b'synthetic private child payload')
                        elif variant == 'symlink': (path / 'link').symlink_to(original, target_is_directory=True)
                        elif variant == 'unicode': (path / '日本語-😀.txt').write_bytes(b'synthetic private child payload')
                        elif variant == 'secret-name': (path / 'password=synthetic-host-matrix-secret.txt').write_bytes(b'synthetic private child payload')
                        elif variant == 'fifo': os.mkfifo(path / 'never-opened-fifo')
                        elif variant == 'many-children':
                            for child in range(64): (path / f'child-{child:02}.txt').write_bytes(b'synthetic private child payload')
                        entries.append({'formatID': fixture['formatID'], 'path': str(path), 'variant': variant})
            corpus_manifest = directory / 'cases.json'
            corpus_manifest.write_text(json.dumps(entries))
            before = snapshot(directory)
            completed = subprocess.run([str(executable), str(corpus_manifest)], check=True,
                                       capture_output=True, text=True, timeout=len(entries) * 3)
            results = json.loads(completed.stdout)
            if snapshot(directory) != before: raise ValueError('Corpus contents, entries, modes or modification times changed')
            if len(results) != len(entries): raise ValueError('Unexpected result count')
            report = {'schemaVersion': 1, 'seed': SEED, 'caseCount': len(results), 'formatCount': len(manifest['fixtures']),
                      'states': dict(Counter(result['state'] for result in results)), 'results': results,
                      'sourceChecks': 'contents, entries, modes and modification times unchanged; synthetic directories removed',
                      'compileCommand': command}
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
            print(f"{report['caseCount']} deterministic cases across {report['formatCount']} formats: {report['states']}")
            print(f'Raw results: {args.output}')
    finally:
        shutil.rmtree(seed_directory)  # Only this call's uniquely owned synthetic seeds.


if __name__ == '__main__':
    main()
