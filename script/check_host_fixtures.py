#!/usr/bin/env python3
"""Validate generated fixtures against already-built package objects; not a Finder test."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from package_link import ROOT, package_module_flags, package_objects


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package_bin', type=Path, help='Built SwiftPM bin directory, e.g. from swift build --show-bin-path')
    parser.add_argument('fixture_directory', type=Path)
    args = parser.parse_args()
    manifest_path = args.fixture_directory / 'manifest.json'
    manifest = json.loads(manifest_path.read_text())
    before = {str(path.relative_to(args.fixture_directory)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in args.fixture_directory.rglob('*') if path.is_file()}
    for relative, expected in manifest['sha256'].items():
        if before.get(relative) != expected:
            raise ValueError('Fixture content differs from its creation manifest')
    output = args.package_bin / 'HostFixtureChecks'
    sdk = subprocess.check_output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    command = ['/usr/bin/xcrun', 'swiftc', '-parse-as-library', '-sdk', sdk,
               '-target', f'{os.uname().machine}-apple-macosx15.0', '-swift-version', '6',
               '-strict-concurrency=complete', '-default-isolation', 'nonisolated',
               '-I', str(args.package_bin), '-I', str(args.package_bin / 'Modules'),
               *package_module_flags(args.package_bin), '-module-name', 'HostFixtureChecks',
               '-o', str(output), str(ROOT / 'Tests/Integration/HostFixtureChecks.swift'),
               *[str(path) for path in package_objects(args.package_bin)]]
    subprocess.run(command, check=True)
    subprocess.run([str(output.resolve()), str(args.fixture_directory.resolve())], check=True, timeout=90)
    after = {str(path.relative_to(args.fixture_directory)): hashlib.sha256(path.read_bytes()).hexdigest()
             for path in args.fixture_directory.rglob('*') if path.is_file()}
    if before != after:
        raise ValueError('Fixture contents or directory file entries changed')
    print('All catalog fixtures parsed; synthetic source bytes and file entries unchanged.', file=sys.stderr)


if __name__ == '__main__':
    main()
