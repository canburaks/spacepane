#!/usr/bin/env python3
"""Build the companion's bundled appearance samples: one synthetic item per catalog format.

The Theme page shows these through the normal preview pipeline, so every supported
type can be seen with the current appearance. All content is authored here; nothing
is copied from a user file and no value resembles a real credential.

    python3 script/generate_appearance_samples.py            # rewrite the manifest
    python3 script/generate_appearance_samples.py --check    # verify it against the catalog
"""
from __future__ import annotations

import base64
from io import BytesIO
import gzip
import json
import lzma
from pathlib import Path
import sqlite3
import struct
import sys
import tarfile
import tempfile
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json'
MANIFEST = ROOT / 'Apps/PrevApp/Resources/AppearanceSamples.json'
VERSION = 1
# The companion enforces the same bounds before it writes a sample.
MAXIMUM_MANIFEST_BYTES = 1_048_576
MAXIMUM_FILE_BYTES = 65_536
MAXIMUM_FILES_PER_SAMPLE = 16

SWIFT = '''import Foundation

/// A point on the preview canvas.
struct Point: Equatable {
    var x: Double
    var y: Double
}

func distance(from a: Point, to b: Point) -> Double {
    let dx = b.x - a.x, dy = b.y - a.y
    return (dx * dx + dy * dy).squareRoot() // never negative
}

let origin = Point(x: 0, y: 0)
let corner = Point(x: 3, y: 4)
if distance(from: origin, to: corner) >= 5 {
    print("Distance: \\(distance(from: origin, to: corner))")
}
'''

JSON = '''{
\t"message": "Local previews, your preferred style.",
\t"unicode": "café • 日本語 • 🙂",
\t"count": 42,
\t"ratio": 0.75,
\t"enabled": true,
\t"optional": null,
\t"operators": "=> != <= ->",
\t"items": [1, 2, 3]
}
'''

MARKDOWN = '''# Example document

A short **Markdown** sample with *emphasis*, `inline code` and a [link](https://example.com).

## Checklist

- Rendered offline
- No remote images or scripts
  - Nested items keep their indentation

1. First step
2. Second step

> Quoted text keeps its own style.

```swift
let greeting = "Hello, preview"
```
'''

NOTEBOOK = {
    'nbformat': 4, 'nbformat_minor': 5,
    'metadata': {'language_info': {'name': 'python'}},
    'cells': [
        {'cell_type': 'markdown', 'metadata': {}, 'source': ['# Example notebook\n', 'Cells are shown read-only and never run.']},
        {'cell_type': 'code', 'metadata': {}, 'execution_count': 1,
         'source': ['values = [1, 2, 3]\n', 'print(sum(values))\n'],
         'outputs': [{'output_type': 'stream', 'name': 'stdout', 'text': ['6\n']}]},
        {'cell_type': 'code', 'metadata': {}, 'execution_count': 2,
         'source': ['total = sum(values) / len(values)\n', 'total\n'],
         'outputs': [{'output_type': 'execute_result', 'execution_count': 2, 'metadata': {},
                      'data': {'text/plain': ['2.0']}}]},
    ],
}

PROPERTY_LIST = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>Name</key>
\t<string>Example</string>
\t<key>Version</key>
\t<integer>3</integer>
\t<key>Enabled</key>
\t<true/>
\t<key>Tags</key>
\t<array>
\t\t<string>sample</string>
\t\t<string>preview</string>
\t</array>
</dict>
</plist>
'''

STRINGS_DICTIONARY = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>files.count</key>
\t<dict>
\t\t<key>NSStringLocalizedFormatKey</key>
\t\t<string>%#@files@</string>
\t\t<key>files</key>
\t\t<dict>
\t\t\t<key>NSStringFormatSpecTypeKey</key>
\t\t\t<string>NSStringPluralRuleType</string>
\t\t\t<key>NSStringFormatValueTypeKey</key>
\t\t\t<string>d</string>
\t\t\t<key>one</key>
\t\t\t<string>%d file</string>
\t\t\t<key>other</key>
\t\t\t<string>%d files</string>
\t\t</dict>
\t</dict>
</dict>
</plist>
'''

TEXT_SAMPLES = {
    'text.plain': ('example.txt', 'Example text\n\nPlain text is shown as written, with your font, spacing and wrapping.\n'
                                  'Unicode: café • Türkçe • 日本語 • 🙂\n\tA tab indents this line.\n'),
    # No suffix and no recognized name, so the file is identified only as plain data.
    'text.extensionless': ('example', '# A file without an extension\n\nText is shown when the content is text.\n'
                                      'PATH_PREFIX=/usr/local/bin\nEDITOR=vim\n'),
    'text.source-code': ('example.swift', SWIFT),
    'data.json': ('example.json', JSON),
    'data.json-lines': ('example.jsonl', '{"id": 1, "name": "First record", "tags": ["a", "b"]}\n'
                                         '{"id": 2, "name": "Second record", "active": true}\n'
                                         '{"id": 3, "name": "Third record", "ratio": 0.5}\n'),
    'data.yaml': ('example.yaml', '# Example configuration\nname: Example\nversion: 3\nenabled: true\n'
                                  'server:\n  host: localhost\n  port: 8080\ntags:\n  - sample\n  - preview\n'),
    'data.toml': ('example.toml', '# Example configuration\nname = "Example"\nversion = 3\nenabled = true\n\n'
                                  '[server]\nhost = "localhost"\nport = 8080\n\n[[tags]]\nlabel = "sample"\n'),
    'config.environment': ('example.env', '# Example environment\nAPP_NAME=Example\nPORT=8080\nDEBUG=false\nLOCALE=en_US\n'),
    'config.package-json': ('package.json', json.dumps({
        'name': 'example-package', 'version': '1.0.0', 'description': 'A synthetic package manifest.',
        'scripts': {'build': 'tsc', 'test': 'node --test'}, 'dependencies': {'example-library': '^2.1.0'}}, indent=2) + '\n'),
    'text.markdown': ('example.md', MARKDOWN),
    'text.diff': ('example.patch', '--- a/greeting.txt\n+++ b/greeting.txt\n@@ -1,4 +1,4 @@\n Example file\n'
                                   '-Hello, world\n+Hello, preview\n unchanged line\n another unchanged line\n'),
    'data.xml': ('example.xml', '<?xml version="1.0" encoding="UTF-8"?>\n<!-- Example document -->\n<catalog version="3">\n'
                                '  <item id="1" enabled="true">\n    <name>First item</name>\n    <price currency="EUR">9.50</price>\n'
                                '  </item>\n  <item id="2" enabled="false">\n    <name>Second item</name>\n  </item>\n</catalog>\n'),
    'data.property-list': ('example.plist', PROPERTY_LIST),
    'config.strings': ('example.strings', '/* Example localization */\n"greeting" = "Hello, preview";\n'
                                          '"files.title" = "Files";\n"action.open" = "Open…";\n'),
    'config.strings-dictionary': ('example.stringsdict', STRINGS_DICTIONARY),
    'data.opml': ('example.opml', '<?xml version="1.0" encoding="UTF-8"?>\n<opml version="2.0">\n  <head><title>Example outline</title></head>\n'
                                  '  <body>\n    <outline text="Planning">\n      <outline text="Collect notes"/>\n'
                                  '      <outline text="Draft summary"/>\n    </outline>\n    <outline text="Review"/>\n  </body>\n</opml>\n'),
    'data.csv': ('example.csv', 'name,category,count,ratio\nFirst item,sample,42,0.75\n"Second, quoted",preview,7,0.10\nThird item,sample,13,0.33\n'),
    'data.tsv': ('example.tsv', 'name\tcategory\tcount\nFirst item\tsample\t42\nSecond item\tpreview\t7\nThird item\tsample\t13\n'),
    'text.subrip': ('example.srt', '1\n00:00:01,000 --> 00:00:04,000\nCaptions are listed with their times.\n\n'
                                   '2\n00:00:05,000 --> 00:00:08,500\nFormatting tags are not applied.\n'),
    'text.webvtt': ('example.vtt', 'WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nCaptions are listed with their times.\n\n'
                                   '00:00:05.000 --> 00:00:08.500\nStyles and regions are not applied.\n'),
    'text.jupyter-notebook': ('example.ipynb', json.dumps(NOTEBOOK, indent=1) + '\n'),
}


def nfo() -> bytes:
    """Code page 437 box drawing around an ASCII title."""
    title = b' Example release notes '
    return (b'\xc9' + b'\xcd' * len(title) + b'\xbb\r\n\xba' + title + b'\xba\r\n\xc8' + b'\xcd' * len(title) + b'\xbc\r\n'
            + b'\r\nVersion ....: 1.0\r\nContents ...: synthetic text art\r\n\xb0\xb1\xb2\xdb\xb2\xb1\xb0\r\n')


def cpio_entry(name: str, payload: bytes) -> bytes:
    encoded = name.encode('utf-8') + b'\0'
    fields = [1, 0o100644, 0, 0, 1, 0, len(payload), 0, 0, 0, 0, len(encoded), 0]
    header = ('070701' + ''.join(f'{field:08x}' for field in fields)).encode('ascii') + encoded
    return header + b'\0' * (-len(header) % 4) + payload + b'\0' * (-len(payload) % 4)


ARCHIVE_ENTRIES = [('Example/readme.txt', b'A synthetic archive entry.\n'),
                   ('Example/data/values.json', b'{"values": [1, 2, 3]}\n'),
                   ('Example/notes.md', b'# Notes\n\nListed without extraction.\n')]


def zip_archive() -> bytes:
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, payload in ARCHIVE_ENTRIES:
            archive.writestr(zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0)), payload)
    return buffer.getvalue()


def tar_archive() -> bytes:
    buffer = BytesIO()
    with tarfile.open(fileobj=buffer, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        for name, payload in ARCHIVE_ENTRIES:
            item = tarfile.TarInfo(name)
            item.size = len(payload)
            archive.addfile(item, BytesIO(payload))
    return buffer.getvalue()


def xip_archive() -> bytes:
    inner = b''.join(cpio_entry(name, payload) for name, payload in ARCHIVE_ENTRIES) + cpio_entry('TRAILER!!!', b'')
    compressed = lzma.compress(inner, format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC32,
                               filters=[{'id': lzma.FILTER_LZMA2, 'dict_size': 1 << 20}])
    pbzx = b'pbzx' + struct.pack('>QQQ', 0x01000000, 0, len(compressed)) + compressed
    toc = ('<xar><toc><file id="1"><name>Content</name><type>file</type><data>'
           f'<offset>0</offset><length>{len(pbzx)}</length><size>{len(pbzx)}</size>'
           '<encoding style="application/octet-stream"/></data></file></toc></xar>').encode()
    packed = zlib.compress(toc)
    return struct.pack('>4sHHQQI', b'xar!', 28, 1, len(packed), len(toc), 0) + packed + pbzx


def sqlite_database() -> bytes:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'example.sqlite'
        connection = sqlite3.connect(path)
        try:
            connection.execute('CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, count INTEGER, ratio REAL)')
            connection.executemany('INSERT INTO items (name, count, ratio) VALUES (?, ?, ?)',
                                   [('First item', 42, 0.75), ('Second item', 7, 0.1), ('Third item', 13, 0.33)])
            connection.execute('CREATE TABLE tags (item_id INTEGER REFERENCES items(id), label TEXT)')
            connection.executemany('INSERT INTO tags VALUES (?, ?)', [(1, 'sample'), (2, 'preview')])
            connection.execute('CREATE INDEX tags_by_item ON tags (item_id)')
            connection.commit()
        finally:
            connection.close()
        return path.read_bytes()


def midi() -> bytes:
    """Format 0, 96 ticks per quarter: tempo 120, then a quiet C major arpeggio."""
    track = bytes.fromhex('00 ff 51 03 07 a1 20') + bytes.fromhex('00 c0 00')
    for note in (60, 64, 67, 72):
        track += bytes([0x00, 0x90, note, 0x40, 0x60, 0x80, note, 0x00])
    track += bytes.fromhex('00 ff 2f 00')
    return b'MThd' + struct.pack('>IHHH', 6, 0, 1, 96) + b'MTrk' + struct.pack('>I', len(track)) + track


def cad_samples(add) -> None:
    """The IGES and STEP samples, kept for when those formats return to the catalog (not called in version 1.0).

    Analytic boxes authored for this repository; see Native/CADWorker/Tests/Fixtures/README.md.
    """
    for format_id, suffix in (('cad.iges', 'iges'), ('cad.step', 'step')):
        add(format_id, 'example.' + suffix, {'example.' + suffix: (ROOT / 'Native/CADWorker/Tests/Fixtures' / ('box.' + suffix)).read_bytes()})


def samples() -> list[dict]:
    built = []

    def add(format_id: str, root: str, files: dict[str, bytes]):
        built.append({'formatID': format_id, 'root': root,
                      'files': [{'path': path, 'data': base64.b64encode(data).decode('ascii')}
                                for path, data in files.items()]})

    for format_id, (name, text) in TEXT_SAMPLES.items():
        add(format_id, name, {name: text.encode('utf-8')})
    add('text.nfo', 'example.nfo', {'example.nfo': nfo()})
    add('database.sqlite', 'example.sqlite', {'example.sqlite': sqlite_database()})
    add('archive.zip', 'example.zip', {'example.zip': zip_archive()})
    add('archive.tar', 'example.tar', {'example.tar': tar_archive()})
    add('archive.gzip', 'example.txt.gz', {'example.txt.gz': gzip.compress(TEXT_SAMPLES['text.plain'][1].encode('utf-8'), mtime=0)})
    add('archive.xip', 'example.xip', {'example.xip': xip_archive()})
    add('container.folder', 'Example Folder', {'Example Folder/' + name.split('/', 1)[1]: payload for name, payload in ARCHIVE_ENTRIES})
    add('audio.midi', 'example.mid', {'example.mid': midi()})
    # Version 1.0 ships without the IGES and STEP previews (cad.iges, cad.step), so the catalog has no CAD
    # entry and no sample is required for one: this check demands exactly one sample per catalog format.
    # When the formats return, call `cad_samples(add)` here, below the MIDI sample.
    # [workstream samples] Add your formats' samples below your own marker; keep helpers in
    # functions named after your family so additions never touch another family's lines.
    # [archives]
    import archive_fixtures
    for format_id, root, files in archive_fixtures.appearance_samples():
        add(format_id, root, files)
    # [markup]
    from markup_samples import APPEARANCE as markup_samples
    for format_id, (name, text) in markup_samples.items():
        add(format_id, name, {name: text.encode('utf-8')})
    # [diagrams]
    def drawio_compressed(model_xml: str) -> bytes:
        # draw.io's compressed page: percent-encoded XML, raw DEFLATE, then base64.
        from urllib.parse import quote
        encoded = quote(model_xml, safe="-_.!~*'()").encode('ascii')
        engine = zlib.compressobj(9, zlib.DEFLATED, -15)
        packed = engine.compress(encoded) + engine.flush()
        page = base64.b64encode(packed).decode('ascii')
        return ('<mxfile host="app.diagrams.net"><diagram id="page-1" name="Page-1">' + page + '</diagram></mxfile>\n').encode('utf-8')

    mermaid_sample = (
        'flowchart LR\n'
        '    A[Start] --> B{Is it ready?}\n'
        '    B -->|Yes| C([Preview])\n'
        '    B -->|No| D[Wait]\n'
        '    D -.-> B\n'
        '    subgraph Review\n'
        '        C --> E[(Archive)]\n'
        '    end\n')
    add('text.mermaid', 'example.mmd', {'example.mmd': mermaid_sample.encode('utf-8')})
    drawio_model = (
        '<mxGraphModel dx="800" dy="400" grid="1" gridSize="10"><root>'
        '<mxCell id="0"/><mxCell id="1" parent="0"/>'
        '<mxCell id="2" value="Start" style="ellipse;whiteSpace=wrap;html=1;" vertex="1" parent="1">'
        '<mxGeometry x="40" y="40" width="100" height="60" as="geometry"/></mxCell>'
        '<mxCell id="3" value="Process" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">'
        '<mxGeometry x="220" y="40" width="120" height="60" as="geometry"/></mxCell>'
        '<mxCell id="4" value="Done?" style="rhombus;whiteSpace=wrap;html=1;" vertex="1" parent="1">'
        '<mxGeometry x="420" y="30" width="100" height="80" as="geometry"/></mxCell>'
        '<mxCell id="5" value="" style="endArrow=classic;html=1;" edge="1" parent="1" source="2" target="3">'
        '<mxGeometry relative="1" as="geometry"/></mxCell>'
        '<mxCell id="6" value="next" style="endArrow=classic;html=1;" edge="1" parent="1" source="3" target="4">'
        '<mxGeometry relative="1" as="geometry"/></mxCell>'
        '</root></mxGraphModel>')
    add('data.drawio', 'example.drawio', {'example.drawio': drawio_compressed(drawio_model)})
    # [packages]
    # Package, certificate, disk-image and torrent samples; their builders live in one family module.
    import package_fixtures as packages
    add('package.application', 'Example.app', packages.app_bundle_files(None, root='Example.app'))
    add('package.ios-app', 'Example.ipa', {'Example.ipa': packages.ios_app(None)})
    add('package.android', 'Example.apk', {'Example.apk': packages.android_package(None)})
    add('config.provisioning-profile', 'Example.mobileprovision', {'Example.mobileprovision': packages.provisioning_profile(None)})
    add('security.certificate', 'example.pem', {'example.pem': packages.certificate_file(None)})
    add('package.installer', 'Example.pkg', {'Example.pkg': packages.installer_package(None)})
    add('disk.image', 'Example.dmg', {'Example.dmg': packages.disk_image(None)})
    add('data.torrent', 'Example.torrent', {'Example.torrent': packages.torrent(None)})
    # [data]
    import data_fixtures
    for format_id, name, data in data_fixtures.appearance_samples():
        add(format_id, name, {name: data})
    # [code]
    def code_samples() -> dict[str, tuple[str, str]]:
        return {
            'config.ini': ('example.ini', '; Example configuration\n[server]\nhost = localhost\nport = 8080\n\n'
                                          '[logging]\nlevel = info\nfile = "app.log"\nrotate = true\n'),
            'text.log': ('example.log', '2026-10-05T09:15:02Z INFO  Service started on port 8080\n'
                                        '2026-10-05T09:15:07Z WARN  Cache miss for key "greeting"\n'
                                        '2026-10-05T09:15:09Z ERROR Request failed: timeout after 30s\n'
                                        '\tat example.Service.fetch(Service.java:42)\n'
                                        '\tat example.Service.run(Service.java:17)\n'
                                        '2026-10-05T09:15:10Z DEBUG Retrying in 2s\n'),
            'data.jsonc': ('example.jsonc', '// Example settings with comments\n{\n  "name": "Example", /* shown in the title */\n'
                                            '  "version": 3,\n  "enabled": true,\n  "tags": ["sample", "preview",],\n}\n'),
            'text.substation-alpha': ('example.ass', '[Script Info]\nTitle: Example\nScriptType: v4.00+\n\n[V4+ Styles]\n'
                'Format: Name, Fontname, Fontsize\nStyle: Default,Arial,20\n\n[Events]\n'
                'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
                'Dialogue: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,Captions are listed with their times.\n'
                'Dialogue: 0,0:00:05.00,0:00:08.50,Default,,0,0,0,,{\\i1}Override tags are removed{\\i0} here.\n'),
            'text.ttml': ('example.ttml', '<?xml version="1.0" encoding="UTF-8"?>\n<tt xmlns="http://www.w3.org/ns/ttml">\n  <body>\n    <div>\n'
                '      <p begin="00:00:01.000" end="00:00:04.000">Captions are listed with their times.</p>\n'
                '      <p begin="00:00:05.000" end="00:00:08.500">Styles and regions<br/>are not applied.</p>\n    </div>\n  </body>\n</tt>\n'),
            'text.sbv': ('example.sbv', '0:00:01.000,0:00:04.000\nCaptions are listed with their times.\n\n'
                                        '0:00:05.000,0:00:08.500\nMarkup is not applied.\n'),
            'text.lrc': ('example.lrc', '[ti:Example song]\n[ar:Example artist]\n[00:01.00]First lyric line\n'
                                        '[00:05.50]Second lyric line\n[00:09.00][00:20.00]A repeated chorus line\n'),
            'text.microdvd': ('example.sub', '{1}{1}25\n{25}{100}Captions are listed|with their times.\n{125}{200}Frames become clock times.\n'),
        }
    for format_id, (name, content) in code_samples().items():
        add(format_id, name, {name: content.encode('utf-8')})
    # [ebooks]
    def ebooks_png(width: int, height: int, shade: int) -> bytes:
        """A small synthetic block-pattern page, authored here and never copied from a user file."""
        def chunk(tag: bytes, data: bytes) -> bytes:
            return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
        rows = b''.join(b'\x00' + bytes(value for x in range(width) for value in
                                        (((x // 8) * 36 + shade) % 256, ((y // 8) * 28) % 256, 160))
                        for y in range(height))
        return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))

    def ebooks_zip(members: list[tuple[str, bytes, bool]]) -> bytes:
        """ZIP members as (name, payload, stored); an EPUB lists its stored `mimetype` first."""
        buffer = BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive:
            for name, payload, stored in members:
                info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED
                archive.writestr(info, payload)
        return buffer.getvalue()

    def ebooks_comic() -> bytes:
        info = ('<?xml version="1.0" encoding="utf-8"?>\n<ComicInfo><Title>Example comic</Title><Series>Example series</Series>'
                '<Number>1</Number><Writer>Example writer</Writer><PageCount>3</PageCount></ComicInfo>\n')
        pages = [(f'Example comic/page{number:02d}.png', ebooks_png(96, 128, number * 70), True) for number in (1, 2, 3)]
        return ebooks_zip([('ComicInfo.xml', info.encode('utf-8'), False)] + pages)

    def ebooks_epub() -> bytes:
        container = ('<?xml version="1.0"?>\n<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
                     '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        package = ('<?xml version="1.0" encoding="utf-8"?>\n<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
                   '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:example:synthetic-book</dc:identifier>'
                   '<dc:title>Example book</dc:title><dc:creator>Example author</dc:creator><dc:language>en</dc:language>'
                   '<dc:publisher>Example press</dc:publisher><dc:date>2026-01-01</dc:date>'
                   '<dc:description>A short synthetic book for the appearance preview.</dc:description></metadata>'
                   '<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
                   '<item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>'
                   '<item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
                   '<item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/></manifest>'
                   '<spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>')
        navigation = ('<?xml version="1.0" encoding="utf-8"?>\n<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
                      '<head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="chapter1.xhtml">First chapter</a></li>'
                      '<li><a href="chapter2.xhtml">Second chapter</a></li></ol></nav></body></html>')
        first = ('<?xml version="1.0" encoding="utf-8"?>\n<html xmlns="http://www.w3.org/1999/xhtml"><head><title>First</title>'
                 '<style>p { color: red }</style></head><body><h1>First chapter</h1>'
                 '<p>Books are shown as <em>readable text</em> with <strong>local styling</strong>&nbsp;only.</p>'
                 '<p>Scripts, styles and remote resources are never loaded.</p>'
                 '<blockquote><p>Quotations keep their own block.</p></blockquote></body></html>')
        second = ('<?xml version="1.0" encoding="utf-8"?>\n<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Second</title></head>'
                  '<body><h1>Second chapter</h1><ul><li>Lists stay lists</li><li>Tables become rows</li></ul>'
                  '<table><tr><th>Name</th><th>Value</th></tr><tr><td>Chapters</td><td>2</td></tr></table>'
                  '<pre>code stays literal\n    with indentation</pre></body></html>')
        return ebooks_zip([('mimetype', b'application/epub+zip', True), ('META-INF/container.xml', container.encode(), False),
                           ('OEBPS/content.opf', package.encode(), False), ('OEBPS/nav.xhtml', navigation.encode(), False),
                           ('OEBPS/cover.png', ebooks_png(120, 180, 40), True), ('OEBPS/chapter1.xhtml', first.encode(), False),
                           ('OEBPS/chapter2.xhtml', second.encode(), False)])

    def ebooks_fictionbook() -> bytes:
        cover = base64.b64encode(ebooks_png(60, 90, 10)).decode('ascii')
        return ('<?xml version="1.0" encoding="utf-8"?>\n<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" '
                'xmlns:l="http://www.w3.org/1999/xlink"><description><title-info><genre>prose</genre>'
                '<author><first-name>Example</first-name><last-name>Author</last-name></author><book-title>Example story</book-title>'
                '<annotation><p>A short synthetic story for the appearance preview.</p></annotation><date>2026</date><lang>en</lang>'
                '<coverpage><image l:href="#cover.png"/></coverpage></title-info><publish-info><publisher>Example press</publisher></publish-info>'
                '</description><body><title><p>Example story</p></title><section><title><p>Part one</p></title>'
                '<p>Stories keep <emphasis>emphasis</emphasis> and <strong>strong text</strong>.</p><empty-line/>'
                '<poem><stanza><v>Poems keep their lines</v><v>one verse at a time</v></stanza></poem></section></body>'
                f'<binary id="cover.png" content-type="image/png">{cover}</binary></FictionBook>\n').encode('utf-8')

    def ebooks_web_archive() -> bytes:
        html = ('<!DOCTYPE html><html><head><title>Example page</title><style>body { color: red }</style></head><body>'
                '<h1>Example page</h1><p>Saved pages show their text only. Scripts and remote resources are never loaded.</p>'
                '<ul><li>Lists stay lists</li><li>Images become text</li></ul><img src="logo.png" alt="Site logo">'
                '<script>document.write("never run")</script></body></html>')
        return ('From: <Saved by example>\r\nSubject: Example page\r\nDate: Thu, 01 Jan 2026 00:00:00 +0000\r\n'
                'MIME-Version: 1.0\r\nContent-Type: multipart/related; type="text/html"; boundary="example-boundary"\r\n\r\n'
                '--example-boundary\r\nContent-Type: text/html; charset="utf-8"\r\nContent-Transfer-Encoding: 7bit\r\n'
                'Content-Location: https://example.com/index.html\r\n\r\n' + html + '\r\n'
                '--example-boundary\r\nContent-Type: image/png\r\nContent-Transfer-Encoding: base64\r\n'
                'Content-Location: https://example.com/logo.png\r\n\r\n'
                + base64.b64encode(ebooks_png(16, 16, 0)).decode('ascii') + '\r\n'
                '--example-boundary\r\nContent-Type: text/css\r\nContent-Location: https://cdn.example.net/site.css\r\n\r\n'
                'body { margin: 0 }\r\n--example-boundary--\r\n').encode('utf-8')

    add('archive.comic-book', 'example.cbz', {'example.cbz': ebooks_comic()})
    add('document.epub', 'example.epub', {'example.epub': ebooks_epub()})
    add('document.fictionbook', 'example.fb2', {'example.fb2': ebooks_fictionbook()})
    add('document.web-archive', 'example.mhtml', {'example.mhtml': ebooks_web_archive()})
    # [mesh]
    import mesh_samples
    mesh_vertices, mesh_quads = mesh_samples.torus()
    mesh_triangles = mesh_samples.triangles(mesh_quads)
    add('model.stl', 'example.stl', {'example.stl': mesh_samples.stl_binary(mesh_vertices, mesh_triangles)})
    add('model.obj', 'example.obj', {'example.obj': mesh_samples.obj_text(mesh_vertices, mesh_quads)})
    add('model.ply', 'example.ply', {'example.ply': mesh_samples.ply_binary(mesh_vertices, mesh_quads)})
    add('model.3mf', 'example.3mf', {'example.3mf': mesh_samples.threemf(mesh_vertices, mesh_triangles)})
    order =[entry['id'] for entry in json.loads(CATALOG.read_text())['formats']]
    built.sort(key=lambda sample: order.index(sample['formatID']))
    return built


def validate(manifest: dict) -> list[str]:
    errors = []
    expected = [entry['id'] for entry in json.loads(CATALOG.read_text())['formats']]
    if manifest.get('version') != VERSION:
        errors.append('Unsupported sample manifest version')
    listed = [sample.get('formatID') for sample in manifest.get('samples', [])]
    if sorted(listed) != sorted(expected):
        errors.append(f'Samples and catalog differ: {sorted(set(listed) ^ set(expected))}')
    for sample in manifest.get('samples', []):
        files = sample.get('files', [])
        root = sample.get('root', '')
        if not files or len(files) > MAXIMUM_FILES_PER_SAMPLE or not root or '/' in root:
            errors.append(f"{sample.get('formatID')}: invalid root or file count")
        for item in files:
            parts = item.get('path', '').split('/')
            if parts[0] != root or any(part in ('', '.', '..') for part in parts):
                errors.append(f"{sample.get('formatID')}: path must stay inside its root: {item.get('path')}")
            try:
                size = len(base64.b64decode(item.get('data', ''), validate=True))
            except ValueError:
                errors.append(f"{sample.get('formatID')}: invalid data")
                continue
            if size > MAXIMUM_FILE_BYTES:
                errors.append(f"{sample.get('formatID')}: {item.get('path')} exceeds the sample size limit")
    return errors


def encoded(manifest: dict) -> str:
    return json.dumps(manifest, ensure_ascii=True, indent=1) + '\n'


def main() -> int:
    if sys.argv[1:] == ['--check']:
        if not MANIFEST.is_file():
            print(f'Missing {MANIFEST.relative_to(ROOT)}; run script/generate_appearance_samples.py', file=sys.stderr)
            return 1
        text = MANIFEST.read_text()
        errors = validate(json.loads(text))
        if len(text.encode('utf-8')) > MAXIMUM_MANIFEST_BYTES:
            errors.append('Sample manifest exceeds its size limit')
        if errors:
            print('\n'.join(errors), file=sys.stderr)
            return 1
        print(f"Appearance samples verified: {len(json.loads(text)['samples'])} catalog formats, {len(text.encode('utf-8'))} bytes.")
        return 0
    if sys.argv[1:]:
        print(__doc__, file=sys.stderr)
        return 2
    manifest = {'version': VERSION, 'samples': samples()}
    errors = validate(manifest)
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(encoded(manifest))
    print(f"Wrote {len(manifest['samples'])} samples to {MANIFEST.relative_to(ROOT)}.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
