#!/usr/bin/env python3
"""Create a fresh, bounded synthetic Finder test set; never overwrite existing files."""
from __future__ import annotations

from io import BytesIO
import gzip
import hashlib
import json
import lzma
from pathlib import Path
import plistlib
import sqlite3
import struct
import tarfile
import tempfile
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
SECRET = 'synthetic-host-matrix-secret'


def cpio_entry(name: str, payload: bytes) -> bytes:
    encoded = name.encode('utf-8') + b'\0'
    fields = [1, 0o100644, 0, 0, 1, 0, len(payload), 0, 0, 0, 0, len(encoded), 0]
    header = ('070701' + ''.join(f'{field:08x}' for field in fields)).encode('ascii') + encoded
    return header + b'\0' * (-len(header) % 4) + payload + b'\0' * (-len(payload) % 4)


def xip() -> bytes:
    inner = cpio_entry('example.txt', b'synthetic archive payload\n') + cpio_entry('TRAILER!!!', b'')
    compressed = lzma.compress(inner, format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC32,
                               filters=[{'id': lzma.FILTER_LZMA2, 'dict_size': 1 << 20}])
    pbzx = b'pbzx' + struct.pack('>QQQ', 0x01000000, 0, len(compressed)) + compressed
    toc = ('<xar><toc><file id="1"><name>Content</name><type>file</type><data>'
           f'<offset>0</offset><length>{len(pbzx)}</length><size>{len(pbzx)}</size>'
           '<encoding style="application/octet-stream"/></data></file></toc></xar>').encode()
    packed = zlib.compress(toc)
    return struct.pack('>4sHHQQI', b'xar!', 28, 1, len(packed), len(toc), 0) + packed + pbzx


def generate() -> Path:
    parent = ROOT / '.build/host-validation'
    parent.mkdir(parents=True, exist_ok=True)
    destination = Path(tempfile.mkdtemp(prefix='matrix-', dir=parent))
    records = []

    def add(format_id: str, filename: str, contents: str | bytes) -> Path:
        path = destination / filename
        path.write_bytes(contents.encode('utf-8') if isinstance(contents, str) else contents)
        records.append({'formatID': format_id, 'path': filename})
        return path

    add('text.plain', '01-plain.txt', f'Preview fixture\npassword={SECRET}\nUnicode: Türkçe 日本語 😀\n')
    add('text.source-code', '02-source.swift', f'let count = 42\nlet password = "{SECRET}"\n')
    add('data.json', '03-data.json', json.dumps({'name': 'Preview fixture', 'password': SECRET, 'values': [1, 2]}))
    add('data.json-lines', '04-records.jsonl', json.dumps({'password': SECRET, 'value': 1}) + '\n{"value":2}\n')
    add('data.yaml', '05-config.yaml', f'name: Preview fixture\npassword: {SECRET}\ncount: 42\n')
    add('data.toml', '06-config.toml', f'name = "Preview fixture"\npassword = "{SECRET}"\ncount = 42\n')
    add('config.environment', '.env', f'NAME=PreviewFixture\nPASSWORD={SECRET}\n')
    add('config.package-json', 'package.json', json.dumps({'name': 'preview-fixture', 'version': '1.0.0', 'password': SECRET}))
    add('text.markdown', '09-document.md', f'# Preview fixture\n\n**Safe local rendering**\n\npassword: {SECRET}\n')
    add('text.diff', '10-change.patch', f'--- before\n+++ after\n@@ -1 +1 @@\n-old value\n+password={SECRET}\n')
    add('data.xml', '11-document.xml', f'<root><name>Preview fixture</name><password>{SECRET}</password></root>')
    add('data.property-list', '12-properties.plist', plistlib.dumps({'name': 'Preview fixture', 'password': SECRET}, fmt=plistlib.FMT_BINARY))
    add('config.strings', '13-localization.strings', f'"name" = "Preview fixture";\n"password" = "{SECRET}";\n')
    add('config.strings-dictionary', '14-localization.stringsdict', plistlib.dumps({'name': 'Preview fixture', 'password': SECRET}))
    add('data.opml', '15-outline.opml', '<opml version="2.0"><body><outline text="Preview fixture"/></body></opml>')
    database = destination / '16-database.sqlite'
    with sqlite3.connect(database) as connection:
        connection.execute('CREATE TABLE records (name TEXT, password TEXT)')
        connection.execute('INSERT INTO records VALUES (?, ?)', ('Preview fixture', SECRET))
    records.append({'formatID': 'database.sqlite', 'path': database.name})
    zip_bytes = BytesIO()
    with zipfile.ZipFile(zip_bytes, 'w') as archive:
        archive.writestr('example.txt', b'synthetic archive payload\n')
    add('archive.zip', '17-listing.zip', zip_bytes.getvalue())
    tar_bytes = BytesIO()
    with tarfile.open(fileobj=tar_bytes, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        payload = b'synthetic archive payload\n'
        item = tarfile.TarInfo('example.txt'); item.size = len(payload)
        archive.addfile(item, BytesIO(payload))
    add('archive.tar', '18-listing.tar', tar_bytes.getvalue())
    add('archive.gzip', '19-content.gz', gzip.compress(f'password={SECRET}\n'.encode(), mtime=0))
    add('archive.xip', '20-listing.xip', xip())
    folder = destination / '21-folder'; folder.mkdir()
    (folder / 'example.txt').write_text('synthetic folder payload\n')
    records.append({'formatID': 'container.folder', 'path': folder.name})
    # Silent, five-second SMF 0: controller volume 0 and an end-of-track at tick 960.
    track = bytes.fromhex('00 ff 51 03 07 a1 20 00 b0 07 00 87 40 ff 2f 00')
    add('audio.midi', '22-silent.mid', b'MThd' + struct.pack('>IHHH', 6, 0, 1, 96)
        + b'MTrk' + struct.pack('>I', len(track)) + track)
    for format_id, extension in [('cad.iges', 'iges'), ('cad.step', 'step')]:
        add(format_id, '23-box.' + extension, (ROOT / 'Native/CADWorker/Tests/Fixtures' / ('box.' + extension)).read_bytes())
    add('data.csv', '24-table.csv', f'name,password,count\nPreview fixture,{SECRET},42\n"Quoted, value",{SECRET},7\n')
    add('data.tsv', '25-table.tsv', f'name\tpassword\tcount\nPreview fixture\t{SECRET}\t42\n')
    add('text.subrip', '26-captions.srt', '1\n00:00:01,000 --> 00:00:04,000\nPreview fixture\n\n'
        f'2\n00:00:05,000 --> 00:00:08,000\npassword: {SECRET}\n')
    add('text.webvtt', '27-captions.vtt', 'WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nPreview fixture\n\n'
        f'00:00:05.000 --> 00:00:08.000\npassword: {SECRET}\n')
    # Code page 437 box drawing around an ASCII title; the assignment remains concealable text.
    add('text.nfo', '28-release.nfo', b'\xc9\xcd\xcd\xcd\xbb\r\n\xba Preview fixture \xba\r\n\xc8\xcd\xcd\xcd\xbc\r\n'
        + f'password={SECRET}\r\n'.encode('ascii'))
    add('text.jupyter-notebook', '29-notebook.ipynb', json.dumps({
        'nbformat': 4, 'nbformat_minor': 5, 'metadata': {'language_info': {'name': 'python'}},
        'cells': [
            {'cell_type': 'markdown', 'metadata': {}, 'source': ['# Preview fixture\n', 'Synthetic notebook.']},
            {'cell_type': 'code', 'metadata': {}, 'execution_count': 1,
             'source': [f'password = "{SECRET}"\n', 'print(42)\n'],
             'outputs': [{'output_type': 'stream', 'name': 'stdout', 'text': ['42\n']}]},
        ]}, indent=1))
    # No suffix and no recognized name: macOS types this file as plain data.
    add('text.extensionless', '30-notes', f'Preview fixture without an extension\npassword={SECRET}\n')
    # [workstream fixtures] Add one synthetic fixture per new format below your own marker,
    # numbered from your family's range (archives 31-, markup 41-, diagrams 51-, packages 61-,
    # data 71-, code 81-, ebooks 91-, mesh 101-) so names never collide.
    # [archives]
    import archive_fixtures
    for format_id, filename, contents in archive_fixtures.host_fixtures(SECRET):
        add(format_id, filename, contents)
    # [markup]
    from markup_samples import HOST_FIXTURES as markup_fixtures
    for format_id, (name, text) in markup_fixtures.items():
        add(format_id, name, text.replace('@SECRET@', SECRET))
    # [diagrams]
    def drawio_compressed(model_xml: str) -> bytes:
        import base64
        from urllib.parse import quote
        encoded = quote(model_xml, safe="-_.!~*'()").encode('ascii')
        engine = zlib.compressobj(9, zlib.DEFLATED, -15)
        packed = engine.compress(encoded) + engine.flush()
        return ('<mxfile><diagram id="page-1" name="Page-1">' + base64.b64encode(packed).decode('ascii')
                + '</diagram></mxfile>').encode('utf-8')

    add('text.mermaid', '51-diagram.mmd', 'flowchart TD\n    A[Preview fixture] --> B[Safe local drawing]\n'
        f'    B --> C[api_key: {SECRET}]\n    %% password={SECRET}\n')
    add('data.drawio', '52-diagram.drawio', drawio_compressed(
        '<mxGraphModel><root><mxCell id="0"/><mxCell id="1" parent="0"/>'
        '<mxCell id="2" value="Preview fixture" style="rounded=1;" vertex="1" parent="1">'
        '<mxGeometry x="20" y="20" width="140" height="50" as="geometry"/></mxCell>'
        f'<mxCell id="3" value="password: {SECRET}" vertex="1" parent="1">'
        '<mxGeometry x="220" y="20" width="140" height="50" as="geometry"/></mxCell>'
        '<mxCell id="4" edge="1" parent="1" source="2" target="3"><mxGeometry relative="1" as="geometry"/></mxCell>'
        '</root></mxGraphModel>'))
    # [packages]
    # Package, certificate, disk-image and torrent fixtures come from one family module.
    import package_fixtures as packages
    app = '61-example.app'
    for relative, data in packages.app_bundle_files(SECRET, root=app).items():
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    records.append({'formatID': 'package.application', 'path': app})
    add('package.ios-app', '62-example.ipa', packages.ios_app(SECRET))
    add('package.android', '63-example.apk', packages.android_package(SECRET))
    add('config.provisioning-profile', '64-example.mobileprovision', packages.provisioning_profile(SECRET))
    add('security.certificate', '65-certificate.pem', packages.certificate_file(SECRET))
    add('package.installer', '66-installer.pkg', packages.installer_package(SECRET))
    add('disk.image', '67-image.dmg', packages.disk_image(SECRET))
    add('data.torrent', '68-example.torrent', packages.torrent(SECRET))
    # [data]
    import data_fixtures
    for number, (format_id, suffix, data) in enumerate([
            ('data.parquet', 'parquet', data_fixtures.parquet()), ('data.avro', 'avro', data_fixtures.avro('deflate')),
            ('data.arrow', 'arrow', data_fixtures.arrow_file()), ('data.numpy', 'npy', data_fixtures.npy_matrix()),
            ('data.numpy-archive', 'npz', data_fixtures.npz()), ('data.har', 'har', data_fixtures.har().encode()),
            ('data.geojson', 'geojson', data_fixtures.geojson().encode()), ('data.gpx', 'gpx', data_fixtures.gpx().encode()),
            ('data.kml', 'kml', data_fixtures.kml().encode())], start=71):
        add(format_id, f'{number}-data.{suffix}', data)
    # [code]
    add('config.ini', '81-config.ini', f'[server]\nhost = localhost\npassword = {SECRET}\nport = 8080\n')
    add('text.log', '82-service.log', f'2026-10-05T12:00:00Z INFO service started\n2026-10-05T12:00:01Z ERROR request failed\n'
        f'\tat example.Service.run(Service.java:42)\nAuthorization: Bearer {SECRET}\n')
    add('data.jsonc', '83-config.jsonc', f'// Synthetic settings\n{{\n  "name": "Preview fixture", /* note */\n  "password": "{SECRET}",\n  "values": [1, 2,],\n}}\n')
    add('text.substation-alpha', '84-captions.ass', '[Script Info]\nTitle: Preview fixture\nScriptType: v4.00+\n\n[V4+ Styles]\n'
        'Format: Name, Fontname, Fontsize\nStyle: Default,Arial,20\n\n[Events]\n'
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
        'Dialogue: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,{\\i1}Preview fixture{\\i0}\\Nsecond line\n'
        f'Dialogue: 0,0:00:05.00,0:00:08.00,Default,,0,0,0,,password: {SECRET}\n')
    add('text.ttml', '85-captions.ttml', '<?xml version="1.0" encoding="UTF-8"?>\n<tt xmlns="http://www.w3.org/ns/ttml"><body><div>\n'
        '<p begin="00:00:01.000" end="00:00:04.000">Preview fixture<br/>second line</p>\n'
        f'<p begin="5s" dur="3s">password: {SECRET}</p>\n</div></body></tt>\n')
    add('text.sbv', '86-captions.sbv', '0:00:01.000,0:00:04.000\nPreview fixture\n\n'
        f'0:00:05.000,0:00:08.000\npassword: {SECRET}\n')
    add('text.lrc', '87-lyrics.lrc', f'[ti:Preview fixture]\n[ar:Synthetic]\n[00:01.00]Preview fixture\n[00:05.00][00:09.50]password: {SECRET}\n')
    add('text.microdvd', '88-captions.sub', '{1}{1}25\n{25}{100}Preview fixture|second line\n'
        f'{{150}}{{200}}password: {SECRET}\n')
    # [ebooks]
    import base64  # Used only by the ebook fixtures below.

    def ebooks_png(width: int, height: int, shade: int) -> bytes:
        """A small synthetic block-pattern image; never a user file."""
        def chunk(tag: bytes, data: bytes) -> bytes:
            return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
        rows = b''.join(b'\x00' + bytes(value for x in range(width) for value in
                                        (((x // 8) * 36 + shade) % 256, ((y // 8) * 28) % 256, 160))
                        for y in range(height))
        return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))

    def ebooks_zip(members: list[tuple[str, bytes, bool]]) -> bytes:
        buffer = BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive:
            for name, payload, stored in members:
                info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED
                archive.writestr(info, payload)
        return buffer.getvalue()

    comic_info = (f'<?xml version="1.0" encoding="utf-8"?>\n<ComicInfo><Title>Preview fixture password={SECRET}</Title>'
                  '<Series>Fixture series</Series><Number>1</Number><Writer>Fixture writer</Writer><PageCount>2</PageCount></ComicInfo>\n')
    add('archive.comic-book', '91-comic.cbz', ebooks_zip([
        ('ComicInfo.xml', comic_info.encode('utf-8'), False),
        ('page1.png', ebooks_png(48, 64, 0), True), ('page2.png', ebooks_png(48, 64, 90), True)]))
    epub_package = ('<?xml version="1.0" encoding="utf-8"?>\n<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
                    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:example:fixture</dc:identifier>'
                    '<dc:title>Preview fixture</dc:title><dc:creator>Fixture author</dc:creator><dc:language>en</dc:language></metadata>'
                    '<manifest><item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>'
                    '<item id="c1" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest>'
                    '<spine><itemref idref="c1"/></spine></package>')
    epub_chapter = ('<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Fixture chapter</h1><p>Synthetic text &amp; entities&nbsp;here.</p>'
                    f'<p>password: {SECRET}</p></body></html>')
    add('document.epub', '92-book.epub', ebooks_zip([
        ('mimetype', b'application/epub+zip', True),
        ('META-INF/container.xml', b'<container><rootfiles><rootfile full-path="OEBPS/content.opf" '
                                   b'media-type="application/oebps-package+xml"/></rootfiles></container>', False),
        ('OEBPS/content.opf', epub_package.encode(), False), ('OEBPS/cover.png', ebooks_png(48, 64, 20), True),
        ('OEBPS/chapter.xhtml', epub_chapter.encode(), False)]))
    add('document.fictionbook', '93-book.fb2', (
        '<?xml version="1.0" encoding="utf-8"?>\n<FictionBook xmlns:l="http://www.w3.org/1999/xlink"><description><title-info>'
        '<author><first-name>Fixture</first-name><last-name>Author</last-name></author><book-title>Preview fixture</book-title>'
        '<lang>en</lang><coverpage><image l:href="#cover.png"/></coverpage></title-info></description>'
        f'<body><section><title><p>Fixture section</p></title><p>Synthetic story text.</p><p>password: {SECRET}</p></section></body>'
        f'<binary id="cover.png" content-type="image/png">{base64.b64encode(ebooks_png(24, 32, 5)).decode("ascii")}</binary>'
        '</FictionBook>\n'))
    add('document.web-archive', '94-page.mhtml', (
        'From: <Saved by fixture>\r\nSubject: Preview fixture\r\nMIME-Version: 1.0\r\n'
        'Content-Type: multipart/related; type="text/html"; boundary="fixture-boundary"\r\n\r\n'
        '--fixture-boundary\r\nContent-Type: text/html; charset="utf-8"\r\nContent-Location: https://example.com/\r\n\r\n'
        f'<html><head><title>Preview fixture</title></head><body><h1>Fixture page</h1><p>Synthetic saved page.</p><p>password: {SECRET}</p>'
        '<script>never()</script></body></html>\r\n--fixture-boundary\r\nContent-Type: image/png\r\n'
        'Content-Location: https://example.com/logo.png\r\n\r\nnot an image\r\n--fixture-boundary--\r\n'))
    # [mesh]
    import mesh_samples
    mesh_vertices, mesh_quads = mesh_samples.torus()
    mesh_triangles = mesh_samples.triangles(mesh_quads)
    # A binary STL whose header starts with "solid" must still be read as binary.
    add('model.stl', '101-binary.stl', mesh_samples.stl_binary(mesh_vertices, mesh_triangles, header=f'solid {SECRET}'.encode()))
    add('model.stl', '102-ascii.stl', mesh_samples.stl_ascii(mesh_vertices, mesh_triangles, name=SECRET))
    add('model.obj', '103-model.obj', mesh_samples.obj_text(mesh_vertices, mesh_quads, comment=f'password={SECRET}'))
    add('model.obj', '104-relative.obj', mesh_samples.obj_relative(mesh_vertices, mesh_quads, comment=f'password={SECRET}'))
    add('model.ply', '105-ascii.ply', mesh_samples.ply_ascii(mesh_vertices, mesh_quads, comment=f'password={SECRET}'))
    add('model.ply', '106-little-endian.ply', mesh_samples.ply_binary(mesh_vertices, mesh_quads, comment=f'password={SECRET}'))
    add('model.ply', '107-big-endian.ply', mesh_samples.ply_binary(mesh_vertices, mesh_quads, big_endian=True, comment=f'password={SECRET}'))
    add('model.3mf', '108-model.3mf', mesh_samples.threemf(mesh_vertices, mesh_triangles, title=f'password={SECRET}'))
    add('model.3mf', '109-composed.3mf', mesh_samples.threemf(mesh_vertices, mesh_triangles, unit='inch', composed=True, title=f'password={SECRET}'))
    catalog =json.loads((ROOT / 'Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json').read_text())
    expected = {entry['id'] for entry in catalog['formats']}
    actual = {entry['formatID'] for entry in records}
    if actual != expected:
        raise ValueError(f'Fixture/catalog IDs differ: {sorted(actual ^ expected)}')
    hashes = {str(path.relative_to(destination)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in destination.rglob('*') if path.is_file()}
    manifest = {'fixtures': records, 'sha256': hashes,
                'notes': 'Synthetic data only. MIDI has no notes. XIP signature not verified. Routing remains unproven until observed.'}
    (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return destination


if __name__ == '__main__':
    print(generate())
