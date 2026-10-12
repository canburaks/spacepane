#!/usr/bin/env python3
"""Exercise real CAD adapters while verifying sources are not modified or copied."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
from package_link import ROOT, package_module_flags, package_objects

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('package_bin', type=Path)
parser.add_argument('sources', nargs='+', type=Path)
args = parser.parse_args()
worker = ROOT / '.build/cad' / ('worker-' + os.uname().machine) / 'CADWorker'
paths = [p.resolve() for p in args.sources]
def snapshot():
    return [(p.stat().st_size, p.stat().st_mtime_ns, hashlib.sha256(p.read_bytes()).hexdigest()) for p in paths]
before = snapshot()
sdk = subprocess.check_output(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
executable = args.package_bin / 'CADFixtureChecks'
subprocess.run(['/usr/bin/xcrun', 'swiftc', '-O', '-parse-as-library', '-sdk', sdk,
    '-target', f'{os.uname().machine}-apple-macosx15.0', '-swift-version', '6',
    '-strict-concurrency=complete', '-default-isolation', 'nonisolated',
    '-I', str(args.package_bin), '-I', str(args.package_bin / 'Modules'),
    *package_module_flags(args.package_bin), '-o', str(executable),
    str(ROOT / 'Tests/Integration/CADFixtureChecks.swift'), *map(str, package_objects(args.package_bin))], check=True)
completed = subprocess.run([str(executable.resolve()), str(worker), *map(str, paths)], timeout=len(paths)*25)
if before != snapshot():
    raise ValueError('CAD source content or modification time changed')
if completed.returncode:
    raise SystemExit('CAD integration checks failed; source hashes remain unchanged.')
print('CAD sources unchanged; private filenames and document metadata omitted from report.')
