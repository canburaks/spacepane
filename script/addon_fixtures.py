#!/usr/bin/env python3
"""Deterministic synthetic packages for the MCP bundle, editor extension and browser extension formats.

Shared by script/generate_appearance_samples.py (the Theme page's built-in samples) and by the host-matrix
and adversarial-corpus generators. Everything is authored here from the public manifest formats with the
standard library only: no real bundle, extension or add-on appears, the scripts inside are one inert line
of comment text that nothing ever runs, and every function is pure.

    python3 script/addon_fixtures.py DESTINATION    # write the three Theme samples for a manual look
"""
from __future__ import annotations

from io import BytesIO
import json
from pathlib import Path
import sys
import zipfile

# A fixed timestamp keeps every archive byte-for-byte reproducible.
STAMP = (2026, 1, 1, 0, 0, 0)


def _manifest(value: dict) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode('utf-8')


def _zip(members: list[tuple[str, bytes, bool]]) -> bytes:
    """A ZIP archive of (path, bytes, deflated) members in the given order."""
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, 'w') as archive:
        for path, data, deflated in members:
            info = zipfile.ZipInfo(path, date_time=STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED if deflated else zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = 0o644 << 16
            archive.writestr(info, data)
    return buffer.getvalue()


# --- MCP bundle ---------------------------------------------------------------------------------

def mcp_bundle(secret: str | None = None) -> bytes:
    """A small Node.js bundle with two ordinary tools and one prompt. With `secret`, the server's
    environment names API_KEY and gives it that value, which a preview must never show."""
    environment = {'DEBUG': 'false'}
    if secret is not None:
        environment['API_KEY'] = secret
    manifest = {
        'manifest_version': '0.3',
        'name': 'example-notes',
        'display_name': 'Example Notes',
        'version': '1.0.0',
        'description': 'Searches a few example notes.' if secret is None else 'Searches a few example notes. Needs a key.',
        'author': {'name': 'Example Author'},
        'license': 'MIT',
        'server': {
            'type': 'node',
            'entry_point': 'server/index.js',
            'mcp_config': {'command': 'node', 'args': ['${__dirname}/server/index.js'], 'env': environment},
        },
        'tools': [
            {'name': 'search_notes', 'description': 'Search the example notes by keyword.'},
            {'name': 'read_note', 'description': 'Return the text of one example note.'},
        ],
        'prompts': [{'name': 'summarize', 'description': 'Summarize a note.', 'text': 'Summarize the note in three sentences.'}],
        'compatibility': {'platforms': ['darwin', 'linux', 'win32'], 'runtimes': {'node': '>=18.0.0'}},
    }
    return _zip([
        ('manifest.json', _manifest(manifest), True),
        ('server/index.js', b'// Example server entry point; this sample is never run.\n', True),
    ])


# --- Visual Studio Code extension ---------------------------------------------------------------

def vscode_extension(secret: str | None = None) -> bytes:
    """A small editor extension that starts on a command. With `secret`, its description carries an
    assignment to a credential-looking name, which the summary must conceal."""
    description = 'Adds an example command.'
    if secret is not None:
        description += ' (token: %s)' % secret
    manifest = {
        'name': 'example-helper',
        'publisher': 'example',
        'displayName': 'Example Helper',
        'version': '0.1.0',
        'description': description,
        'engines': {'vscode': '^1.85.0'},
        'main': './out/extension',
        'activationEvents': ['onCommand:example.hello'],
        'categories': ['Other'],
        'contributes': {'commands': [{'command': 'example.hello', 'title': 'Example: Say Hello'}]},
        'capabilities': {'untrustedWorkspaces': {'supported': 'limited'}},
    }
    return _zip([
        ('[Content_Types].xml', b'<?xml version="1.0" encoding="utf-8"?><Types/>\n', True),
        ('extension.vsixmanifest', b'<?xml version="1.0" encoding="utf-8"?><PackageManifest/>\n', True),
        ('extension/package.json', _manifest(manifest), True),
        ('extension/out/extension.js', b'// Example extension entry point; this sample is never run.\n', True),
    ])


# --- Browser extension --------------------------------------------------------------------------

def firefox_addon(secret: str | None = None) -> bytes:
    """A small Firefox add-on that reaches one site. With `secret`, its description carries an
    assignment to a credential-looking name and its update address carries the secret in the query,
    which the summary must reduce to the address's host."""
    description = 'Adds a note to one example page.'
    gecko = {'id': 'example-notes@example.test', 'strict_min_version': '109.0'}
    if secret is not None:
        description += ' (api_key: %s)' % secret
        gecko['update_url'] = 'https://updates.example.test/notes.json?key=%s' % secret
    manifest = {
        'manifest_version': 2,
        'name': 'Example Page Notes',
        'version': '1.0',
        'description': description,
        'browser_specific_settings': {'gecko': gecko},
        'permissions': ['storage', 'https://notes.example.test/*'],
        'background': {'scripts': ['background.js']},
        'content_scripts': [{'matches': ['https://notes.example.test/*'], 'js': ['content.js']}],
    }
    return _zip([
        ('manifest.json', _manifest(manifest), True),
        ('background.js', b'// Example background script; this sample is never run.\n', True),
        ('content.js', b'// Example content script; this sample is never run.\n', True),
    ])


# --- Entry points -------------------------------------------------------------------------------

def appearance_samples() -> list[tuple[str, str, bytes]]:
    """(format id, file name, bytes) for the Theme page: tiny, neutral, ordinary and free of
    credential-like values and of broad access."""
    return [
        ('package.mcp-bundle', 'example.mcpb', mcp_bundle()),
        ('package.editor-extension', 'example.vsix', vscode_extension()),
        ('package.browser-extension', 'example.xpi', firefox_addon()),
    ]


def host_fixtures(secret: str) -> list[tuple[str, str, bytes]]:
    """(format id, file name, bytes) for the host-matrix and adversarial corpus runs. Each package
    carries `secret` where its summary must not show it: the MCP bundle as the value of its API_KEY
    environment variable (names only are shown), the extensions in a description that the summary
    conceals, and the add-on also in the query of its update address (only the host is shown)."""
    return [
        ('package.mcp-bundle', 'example-secret.mcpb', mcp_bundle(secret)),
        ('package.editor-extension', 'example-secret.vsix', vscode_extension(secret)),
        ('package.browser-extension', 'example-secret.xpi', firefox_addon(secret)),
    ]


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        return
    destination = Path(sys.argv[1])
    destination.mkdir(parents=True, exist_ok=True)
    for _, name, data in appearance_samples():
        (destination / name).write_bytes(data)


if __name__ == '__main__':
    main()
