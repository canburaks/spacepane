#!/usr/bin/env python3
"""Deterministic synthetic fixtures for the package, certificate, disk-image and torrent formats.

Shared by script/generate_host_fixtures.py (the adversarial corpus input) and
script/generate_appearance_samples.py (the Theme page's built-in samples). Everything is authored
here from the public formats; no real application, profile, certificate or device appears, and the
only certificate is a self-signed example whose private key was discarded when it was created.
"""
from __future__ import annotations

import base64
from datetime import datetime
from io import BytesIO
import plistlib
import struct
import zipfile
import zlib

# A self-signed ECDSA P-256 example certificate (CN "Example Sample Certificate", valid 2026-2036).
EXAMPLE_CERTIFICATE_PEM = """-----BEGIN CERTIFICATE-----
MIIB/jCCAaSgAwIBAgICEjQwCgYIKoZIzj0EAwIwSDELMAkGA1UEBhMCVVMxFDAS
BgNVBAoMC0V4YW1wbGUgT3JnMSMwIQYDVQQDDBpFeGFtcGxlIFNhbXBsZSBDZXJ0
aWZpY2F0ZTAeFw0yNjEwMDUxNTM0MzFaFw0zNjEwMDIxNTM0MzFaMEgxCzAJBgNV
BAYTAlVTMRQwEgYDVQQKDAtFeGFtcGxlIE9yZzEjMCEGA1UEAwwaRXhhbXBsZSBT
YW1wbGUgQ2VydGlmaWNhdGUwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQHz5YP
aBz+HKi5BNI9uS3+coSc32Owi7F6Aqlm+trJjFldRP1Vwh59a/1EfhmlaVpsD1aC
pVqtmnBPOd3HR681o34wfDAdBgNVHQ4EFgQUXpnX5g5Li3/EtFtYNuHsclk/p00w
HwYDVR0jBBgwFoAUXpnX5g5Li3/EtFtYNuHsclk/p00wDwYDVR0TAQH/BAUwAwEB
/zApBgNVHREEIjAgggxleGFtcGxlLnRlc3SCEHd3dy5leGFtcGxlLnRlc3QwCgYI
KoZIzj0EAwIDSAAwRQIgEOYhzP5Sdn9trpqCp4+v0oGGImLzXmUAN/OfJCkMULEC
IQCJThgjNIyDlB9aGmP45Xt6v6OevZ/uzW3dp2Aj55EkwA==
-----END CERTIFICATE-----
"""


def certificate_der() -> bytes:
    body = ''.join(line for line in EXAMPLE_CERTIFICATE_PEM.splitlines() if not line.startswith('-----'))
    return base64.b64decode(body)


# --- Images ----------------------------------------------------------------------------------

def png(width: int, height: int, rgb: tuple[int, int, int] = (51, 128, 230)) -> bytes:
    """A solid-color RGB PNG."""
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xFFFFFFFF)
    row = b'\x00' + bytes(rgb) * width
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(row * height, 9)) + chunk(b'IEND', b''))


def icns(png_data: bytes, kind: bytes = b'ic07') -> bytes:
    element = kind + struct.pack('>I', 8 + len(png_data)) + png_data
    return b'icns' + struct.pack('>I', 8 + len(element)) + element


# --- Mach-O ----------------------------------------------------------------------------------

def universal_mach_o() -> bytes:
    """A fat header naming arm64 and x86_64 slices; the slices themselves are not included."""
    table = b''.join(struct.pack('>IIIII', cpu, 0, 0x4000, 0x1000, 14) for cpu in (0x0100000C, 0x01000007))
    return b'\xca\xfe\xba\xbe' + struct.pack('>I', 2) + table + b'\0' * 64


# --- DER and CMS -----------------------------------------------------------------------------

def _length(count: int) -> bytes:
    if count < 0x80:
        return bytes([count])
    encoded = count.to_bytes((count.bit_length() + 7) // 8, 'big')
    return bytes([0x80 | len(encoded)]) + encoded


def _tlv(tag: int, content: bytes) -> bytes:
    return bytes([tag]) + _length(len(content)) + content


def _oid(dotted: str) -> bytes:
    arcs = [int(part) for part in dotted.split('.')]
    out = bytearray([arcs[0] * 40 + arcs[1]])
    for arc in arcs[2:]:
        chunk = [arc & 0x7F]
        arc >>= 7
        while arc:
            chunk.insert(0, (arc & 0x7F) | 0x80)
            arc >>= 7
        out += bytes(chunk)
    return _tlv(0x06, bytes(out))


def signed_message(content: bytes) -> bytes:
    """A CMS SignedData envelope around `content`. The signature bytes are placeholders: the previews
    decode the envelope and never verify it."""
    sha256 = _tlv(0x30, _oid('2.16.840.1.101.3.4.2.1'))
    name = _tlv(0x30, _tlv(0x31, _tlv(0x30, _oid('2.5.4.3') + _tlv(0x0C, b'Synthetic Signer'))))
    signer = _tlv(0x30, _tlv(0x02, b'\x01') + _tlv(0x30, name + _tlv(0x02, b'\x07')) + sha256
                  + _tlv(0x30, _oid('1.2.840.10045.4.3.2')) + _tlv(0x04, b'\0' * 8))
    signed = _tlv(0x30, _tlv(0x02, b'\x01') + _tlv(0x31, sha256)
                  + _tlv(0x30, _oid('1.2.840.113549.1.7.1') + _tlv(0xA0, _tlv(0x04, content)))
                  + _tlv(0x31, signer))
    return _tlv(0x30, _oid('1.2.840.113549.1.7.2') + _tlv(0xA0, signed))


def _label(text: str, secret: str | None) -> str:
    """`text`, followed by a secret-like assignment only when the fixture is meant to test concealment."""
    return f'{text} password={secret}' if secret else text


def provisioning_profile(secret: str | None) -> bytes:
    entitlements = {'application-identifier': 'ABCDE12345.com.example.app', 'get-task-allow': True}
    if secret:
        entitlements['com.example.api-secret'] = secret
    plist = plistlib.dumps({
        'Name': 'Example Development Profile', 'UUID': '00000000-0000-4000-8000-000000000001',
        'AppIDName': 'Example App', 'TeamName': 'Example Team', 'TeamIdentifier': ['ABCDE12345'], 'Platform': ['iOS'],
        'CreationDate': datetime(2026, 1, 1), 'ExpirationDate': datetime(2036, 1, 1),
        'Entitlements': entitlements,
        'ProvisionedDevices': ['synthetic-device-1', 'synthetic-device-2'],
        'DeveloperCertificates': [certificate_der()],
    })
    return signed_message(plist)


# --- Applications ----------------------------------------------------------------------------

def app_bundle_files(secret: str | None, root: str = 'Example.app') -> dict[str, bytes]:
    info = {
        'CFBundleName': _label('Example', secret), 'CFBundleDisplayName': 'Example', 'CFBundleIdentifier': 'com.example.app',
        'CFBundleShortVersionString': '1.4', 'CFBundleVersion': '14', 'LSMinimumSystemVersion': '13.0',
        'LSApplicationCategoryType': 'public.app-category.developer-tools', 'CFBundleExecutable': 'Example',
        'CFBundleIconFile': 'AppIcon', 'CFBundleDocumentTypes': [{'CFBundleTypeName': 'Example Document'}],
        'CFBundleURLTypes': [{'CFBundleURLSchemes': ['example']}], 'NSCameraUsageDescription': 'Used for scanning.',
    }
    return {
        f'{root}/Contents/Info.plist': plistlib.dumps(info),
        f'{root}/Contents/MacOS/Example': universal_mach_o(),
        f'{root}/Contents/Resources/AppIcon.icns': icns(png(128, 128)),
    }


def ios_app(secret: str | None) -> bytes:
    info = {
        'CFBundleName': _label('Example', secret), 'CFBundleDisplayName': 'Example', 'CFBundleIdentifier': 'com.example.app',
        'CFBundleShortVersionString': '2.0', 'CFBundleVersion': '200', 'MinimumOSVersion': '16.0', 'CFBundleExecutable': 'Example',
        'CFBundleSupportedPlatforms': ['iPhoneOS'], 'UIDeviceFamily': [1, 2], 'NSCameraUsageDescription': 'Used for scanning.',
        'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconFiles': ['AppIcon60x60']}},
    }
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as archive:
        stamp = (2026, 1, 1, 0, 0, 0)
        archive.writestr(zipfile.ZipInfo('Payload/Example.app/Info.plist', date_time=stamp), plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
        archive.writestr(zipfile.ZipInfo('Payload/Example.app/embedded.mobileprovision', date_time=stamp), provisioning_profile(secret))
        archive.writestr(zipfile.ZipInfo('Payload/Example.app/AppIcon60x60@2x.png', date_time=stamp), png(120, 120))
        archive.writestr(zipfile.ZipInfo('Payload/Example.app/Example', date_time=stamp), b'synthetic executable placeholder')
    return buffer.getvalue()


# --- Android ---------------------------------------------------------------------------------

def _axml(secret: str | None) -> bytes:
    """Compiled Android XML: a manifest with SDK levels, one permission, two activities and a service."""
    ids = {'name': 0x01010003, 'label': 0x01010001, 'minSdkVersion': 0x0101020C, 'targetSdkVersion': 0x01010270,
           'versionCode': 0x0101021B, 'versionName': 0x0101021C}
    strings = list(ids)  # resource-mapped attribute names come first, in id order of this list
    resource_ids = [ids[name] for name in strings]

    def index(text: str) -> int:
        if text not in strings:
            strings.append(text)
        return strings.index(text)

    def element(name: str, attributes: list[tuple[str, int | str, str]], children: bytes = b'') -> bytes:
        name_index = index(name)
        packed = b''
        for attribute, value, kind in attributes:
            slot = strings.index(attribute) if attribute in ids else index(attribute)
            if kind == 'string':
                raw = index(str(value))
                packed += struct.pack('<IIIHBBI', 0xFFFFFFFF, slot, raw, 8, 0, 0x03, raw)
            else:
                packed += struct.pack('<IIIHBBI', 0xFFFFFFFF, slot, 0xFFFFFFFF, 8, 0, 0x10, int(value))
        start = struct.pack('<HHIIIIIHHHHHH', 0x0102, 16, 36 + len(packed), 1, 0xFFFFFFFF, 0xFFFFFFFF, name_index,
                            0x14, 0x14, len(attributes), 0, 0, 0)
        end = struct.pack('<HHIIIII', 0x0103, 16, 24, 1, 0xFFFFFFFF, 0xFFFFFFFF, name_index)
        return start + packed + children + end

    activity = lambda: element('activity', [('name', '.Main', 'string')])
    body = element('manifest', [('package', 'com.example.app', 'string'), ('versionCode', 7, 'int'),
                                ('versionName', _label('1.0', secret), 'string')],
                   element('uses-sdk', [('minSdkVersion', 24, 'int'), ('targetSdkVersion', 34, 'int')])
                   + element('uses-permission', [('name', 'android.permission.INTERNET', 'string')])
                   + element('application', [], activity() + activity() + element('service', [('name', '.Work', 'string')])))
    offsets, data = b'', b''
    for text in strings:
        offsets += struct.pack('<I', len(data))
        units = text.encode('utf-16-le')
        data += struct.pack('<H', len(text)) + units + b'\0\0'
    data += b'\0' * (-len(data) % 4)
    pool = struct.pack('<HHIIIIII', 0x0001, 28, 28 + len(offsets) + len(data), len(strings), 0, 0, 28 + len(offsets), 0) + offsets + data
    mapping = b''.join(struct.pack('<I', value) for value in resource_ids)
    resource_map = struct.pack('<HHI', 0x0180, 8, 8 + len(mapping)) + mapping
    payload = pool + resource_map + body
    return struct.pack('<HHI', 0x0003, 8, 8 + len(payload)) + payload


def android_package(secret: str | None) -> bytes:
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as archive:
        stamp = (2026, 1, 1, 0, 0, 0)
        archive.writestr(zipfile.ZipInfo('AndroidManifest.xml', date_time=stamp), _axml(secret))
        archive.writestr(zipfile.ZipInfo('classes.dex', date_time=stamp), b'dex\n035\0synthetic')
        archive.writestr(zipfile.ZipInfo('res/layout/main.xml', date_time=stamp), b'\x01\x02\x03')
    return buffer.getvalue()


# --- Certificates ----------------------------------------------------------------------------

def certificate_file(secret: str | None) -> bytes:
    """A PEM file holding the example certificate and a private-key block whose body is a marker that
    must never be decoded or shown."""
    if not secret:
        return EXAMPLE_CERTIFICATE_PEM.encode()
    key_body = base64.b64encode(f'private-key-{secret}'.encode()).decode()
    return (EXAMPLE_CERTIFICATE_PEM + f'-----BEGIN PRIVATE KEY-----\n{key_body}\n-----END PRIVATE KEY-----\n').encode()


# --- Installer packages ----------------------------------------------------------------------

def installer_package(secret: str | None) -> bytes:
    heap = bytearray()
    counter = [0]

    def file_node(name: str, data: bytes) -> str:
        counter[0] += 1
        packed = zlib.compress(data)
        offset = len(heap)
        heap.extend(packed)
        return (f'<file id="{counter[0]}"><name>{name}</name><type>file</type><mtime>2026-01-01T00:00:00Z</mtime>'
                f'<data><offset>{offset}</offset><length>{len(packed)}</length><size>{len(data)}</size>'
                f'<encoding style="application/x-gzip"/></data></file>')

    def directory(name: str, children: list[str]) -> str:
        counter[0] += 1
        return f'<file id="{counter[0]}"><name>{name}</name><type>directory</type>{"".join(children)}</file>'

    distribution = (f'<?xml version="1.0" encoding="utf-8"?><installer-gui-script minSpecVersion="1"><title>{_label("Example", secret)}</title>'
                    '<product id="com.example.product" version="3.4"/><options customize="never" hostArchitectures="x86_64,arm64"/>'
                    '<volume-check><allowed-os-versions><os-version min="12.0"/></allowed-os-versions></volume-check>'
                    '<pkg-ref id="com.example.app" version="3.4" installKBytes="2048"/></installer-gui-script>').encode()
    info = ('<?xml version="1.0" encoding="utf-8"?><pkg-info format-version="2" identifier="com.example.app" version="3.4" '
            'install-location="/Applications" auth="root"><payload numberOfFiles="12" installKBytes="2048"/>'
            '<scripts><preinstall file="./preinstall"/><postinstall file="./postinstall"/></scripts></pkg-info>').encode()
    nodes = [file_node('Distribution', distribution),
             directory('Example.pkg', [file_node('PackageInfo', info), file_node('Bom', b'BOMStore'),
                                       file_node('Payload', b'\x42' * 256),
                                       file_node('Scripts', f'#!/bin/sh\necho {secret or "done"}\n'.encode())])]
    toc = ('<xar><toc>' + ''.join(nodes) + '</toc></xar>').encode()
    packed = zlib.compress(toc)
    return struct.pack('>4sHHQQI', b'xar!', 28, 1, len(packed), len(toc), 0) + packed + bytes(heap)


# --- Disk images -----------------------------------------------------------------------------

def disk_image(secret: str | None) -> bytes:
    fork = b'\xab' * 2048
    runs = [(0x80000005, 0, 100), (0xFFFFFFFF, 100, 0)]
    block_map = b'mish' + struct.pack('>I', 1) + struct.pack('>QQQ', 0, 100, 0) + struct.pack('>II', 0, 1) + b'\0' * 24 + b'\0' * 136
    block_map += struct.pack('>I', len(runs))
    for kind, sector, count in runs:
        block_map += struct.pack('>IIQQQQ', kind, 0, sector, count, 0, 0)
    xml = plistlib.dumps({'resource-fork': {'blkx': [
        {'Attributes': '0x0050', 'CFName': _label('disk image', secret), 'Data': block_map, 'ID': '0',
         'Name': _label('disk image', secret)}]}})
    trailer = (b'koly' + struct.pack('>III', 4, 512, 1) + struct.pack('>QQQQQ', 0, 0, len(fork), 0, 0)
               + struct.pack('>II', 1, 1) + b'\0' * 16 + struct.pack('>II', 0, 0) + b'\0' * 128
               + struct.pack('>QQ', len(fork), len(xml)) + b'\0' * 120 + struct.pack('>II', 0, 0) + b'\0' * 128
               + struct.pack('>IQ', 1, 100) + b'\0' * 12)
    assert len(trailer) == 512, len(trailer)
    return fork + xml + trailer


# --- Torrents --------------------------------------------------------------------------------

def _bencode(value) -> bytes:
    if isinstance(value, int):
        return b'i%de' % value
    if isinstance(value, str):
        value = value.encode()
    if isinstance(value, bytes):
        return b'%d:%s' % (len(value), value)
    if isinstance(value, list):
        return b'l' + b''.join(_bencode(item) for item in value) + b'e'
    return b'd' + b''.join(_bencode(key) + _bencode(value[key]) for key in sorted(value)) + b'e'


def torrent(secret: str | None) -> bytes:
    info = {'name': 'Example Data', 'piece length': 16384, 'pieces': b'\x5a' * 40,
            'files': [{'length': 20000, 'path': ['docs', 'readme.txt']}, {'length': 12000, 'path': ['data.bin']}]}
    announce = 'udp://tracker.example.test:6969/announce' + (f'?passkey={secret}' if secret else '')
    return _bencode({'announce': announce, 'comment': _label('Example comment', secret),
                     'created by': 'Example Tool 1.0', 'creation date': 1767225600, 'info': info})
