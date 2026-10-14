#!/usr/bin/env python3
"""Deterministic synthetic fixtures for the installable-package formats of decision 030.

A Python wheel (.whl) and an npm tarball (.tgz), assembled here with the standard library only, for
script/generate_appearance_samples.py (the Theme page's built-in wheel sample) and the Finder host-matrix
generator. Everything is authored here: the wheel holds one module and the metadata files a build tool
writes, and no .pth file; the tarball holds a package.json with one `postinstall` script that runs a file
the tarball also holds. Nothing is installed or run, no value resembles a real credential, and every
function is pure: the same arguments always give the same bytes (fixed times, no randomness).
"""
from __future__ import annotations

import base64
import gzip
import hashlib
from io import BytesIO
import json
import tarfile
import zipfile

# One fixed modification time, so the archives are reproducible.
MODIFIED = (2026, 1, 1, 0, 0, 0)
MODIFIED_SECONDS = 1767225600  # 2026-01-01T00:00:00Z

WHEEL_NAME = 'example-1.0-py3-none-any.whl'
NPM_NAME = 'example-npm-1.0.0.tgz'

MODULE = '''"""A tiny example module."""

VALUE = 1


def main() -> None:
    print("example")
'''

WHEEL_FILE = '''Wheel-Version: 1.0
Generator: bdist_wheel (0.43.0)
Root-Is-Purelib: true
Tag: py3-none-any
'''

ENTRY_POINTS = '''[console_scripts]
example = example:main
'''


def _metadata(summary: str, home_page: str | None) -> str:
    lines = ['Metadata-Version: 2.1', 'Name: example', 'Version: 1.0', 'Summary: ' + summary]
    if home_page:
        lines.append('Home-page: ' + home_page)
    lines += ['Requires-Python: >=3.8', 'License-Expression: MIT', 'Requires-Dist: requests (>=2.31)', '',
              'A tiny example package.', '']
    return '\n'.join(lines)


def _record(files: list[tuple[str, bytes]], record_path: str) -> str:
    rows = []
    for path, data in files:
        digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b'=').decode()
        rows.append('%s,sha256=%s,%d' % (path, digest, len(data)))
    rows.append('%s,,' % record_path)
    return '\n'.join(rows) + '\n'


def wheel_bytes(summary: str = 'A tiny example package', home_page: str | None = None) -> bytes:
    """A pure-Python wheel: one module, one console script and the usual .dist-info files."""
    info = 'example-1.0.dist-info'
    files = [
        ('example/__init__.py', MODULE.encode()),
        (info + '/METADATA', _metadata(summary, home_page).encode()),
        (info + '/WHEEL', WHEEL_FILE.encode()),
        (info + '/entry_points.txt', ENTRY_POINTS.encode()),
    ]
    files.append((info + '/RECORD', _record(files, info + '/RECORD').encode()))
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path, data in files:
            member = zipfile.ZipInfo(path, MODIFIED)
            member.compress_type = zipfile.ZIP_DEFLATED
            member.create_system = 3
            member.external_attr = 0o100644 << 16
            archive.writestr(member, data)
    return buffer.getvalue()


def npm_tarball_bytes(config: dict | None = None) -> bytes:
    """An npm tarball in `npm pack`'s layout: package/package.json with a postinstall script, and the file it runs."""
    manifest = {
        'name': 'example-npm',
        'version': '1.0.0',
        'description': 'A tiny example package.',
        'scripts': {'postinstall': 'node install.js'},
    }
    if config is not None:
        manifest['config'] = config
    files = [
        ('package/package.json', (json.dumps(manifest, indent=2) + '\n').encode()),
        ('package/install.js', b'console.log("example-npm is installed");\n'),
    ]
    tar_buffer = BytesIO()
    with tarfile.open(fileobj=tar_buffer, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        for path, data in files:
            item = tarfile.TarInfo(path)
            item.mtime = MODIFIED_SECONDS
            item.mode = 0o644
            item.size = len(data)
            archive.addfile(item, BytesIO(data))
    compressed = BytesIO()
    # mtime 0 and no file name keep the gzip header reproducible.
    with gzip.GzipFile(filename='', mode='wb', fileobj=compressed, mtime=0) as stream:
        stream.write(tar_buffer.getvalue())
    return compressed.getvalue()


def appearance_samples() -> list[tuple[str, str, bytes]]:
    """(format ID, file name, bytes) for the companion's Theme page samples: a benign wheel with no .pth file."""
    return [('package.python-wheel', WHEEL_NAME, wheel_bytes())]


def host_fixtures(secret: str) -> list[tuple[str, str, bytes]]:
    """(format ID, file name, bytes) for the Finder host-matrix runs.

    The wheel's Summary holds a secret-like assignment, which the summary must conceal, and its Home-page
    header holds the secret in a URL, which the summary never shows. The npm tarball keeps a secret-like
    value in its package.json; its listing shows neither the file's text nor the value."""
    return [
        ('package.python-wheel', WHEEL_NAME,
         wheel_bytes(summary='Example package (api_key=%s)' % secret,
                     home_page='https://example.invalid/?token=%s' % secret)),
        ('archive.gzip', NPM_NAME, npm_tarball_bytes(config={'api_key': secret})),
    ]
