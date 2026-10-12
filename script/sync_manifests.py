#!/usr/bin/env python3
"""Derive the Info.plist content-type lists from FormatCatalog.json.

    python3 script/sync_manifests.py           # rewrite the three manifests in place
    python3 script/sync_manifests.py --check   # fail if any manifest differs from the catalog

The catalog is the single source of supported types. This rewrites only the preview and
thumbnail `QLSupportedContentTypes` and every `UTImportedTypeDeclarations`, keeping all other
keys and their order. validate_project.py remains the independent consistency check.
"""
from __future__ import annotations

import json
from pathlib import Path
import plistlib
import sys

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json'
CONFIGURATION = ROOT / 'Configuration'


def derived() -> tuple[list[str], list[str], list[dict]]:
    formats = json.loads(CATALOG.read_text())['formats']
    preview = list(dict.fromkeys(t for item in formats for t in item['contentTypes']))
    thumbnail = list(dict.fromkeys(t for item in formats if item['thumbnail'] != 'none' for t in item['contentTypes']))
    imported = []
    for item in formats:
        for declaration in item.get('importedContentTypes', []):
            imported.append({
                'UTTypeIdentifier': declaration['identifier'],
                'UTTypeConformsTo': [declaration['conformsTo']],
                'UTTypeDescription': declaration['descriptionKey'],
                'UTTypeReferenceURL': declaration['referenceURL'],
                'UTTypeTagSpecification': {'public.filename-extension': declaration['extensions']},
            })
    return preview, thumbnail, imported


def updated(filename: str, preview: list[str], thumbnail: list[str], imported: list[dict]) -> tuple[bytes, bytes]:
    path = CONFIGURATION / filename
    original = path.read_bytes()
    info = plistlib.loads(original)
    if imported:
        info['UTImportedTypeDeclarations'] = imported
    else:
        info.pop('UTImportedTypeDeclarations', None)
    if filename == 'Preview-Info.plist':
        info['NSExtension']['NSExtensionAttributes']['QLSupportedContentTypes'] = preview
    elif filename == 'Thumbnail-Info.plist':
        info['NSExtension']['NSExtensionAttributes']['QLSupportedContentTypes'] = thumbnail
    return original, plistlib.dumps(info, sort_keys=False)


def main() -> int:
    check = '--check' in sys.argv[1:]
    preview, thumbnail, imported = derived()
    stale = []
    for filename in ['App-Info.plist', 'Preview-Info.plist', 'Thumbnail-Info.plist']:
        original, content = updated(filename, preview, thumbnail, imported)
        if original == content:
            continue
        stale.append(filename)
        if not check:
            (CONFIGURATION / filename).write_bytes(content)
    if check and stale:
        print(f'Manifests differ from FormatCatalog.json: {stale}. Run script/sync_manifests.py.', file=sys.stderr)
        return 1
    print(f'Manifests {"verified" if check else "synchronized"}: {len(preview)} preview and {len(thumbnail)} thumbnail '
          f'content types, {len(imported)} imported declarations.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
