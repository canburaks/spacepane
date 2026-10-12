#!/usr/bin/env python3
"""Deterministic synthetic RAR 4, RAR 5 and 7z containers for the archive family (decision 013).

The builders assemble the on-disk structures by hand from the public format descriptions:
members are stored (RAR) or copied (7z), header checksums are real, and the 7z builder can wrap
its header in an LZMA or LZMA2 stream made with Python's `lzma` module in FORMAT_RAW mode.
Imported by generate_host_fixtures.py and generate_appearance_samples.py; also usable directly:

    python3 script/archive_fixtures.py OUTPUT_DIRECTORY   # writes one example of each container

Every payload is synthetic and no value resembles a real credential.
"""
from __future__ import annotations

import lzma
from pathlib import Path
import struct
import sys
import zlib
from typing import List, Optional, Tuple

# One fixed modification time (2026-01-01 00:00:00 UTC) keeps every build byte-identical.
MODIFIED = 1_767_225_600
Entry = Tuple[str, Optional[bytes]]   # (path, payload); None means a directory


# --- RAR 5.0 ---------------------------------------------------------------------------------

def vint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def rar5_block(block_type: int, flags: int, fields: bytes, extra: bytes = b'', data: Optional[bytes] = None) -> bytes:
    body = vint(block_type) + vint(flags | (1 if extra else 0) | (2 if data is not None else 0))
    if extra:
        body += vint(len(extra))
    if data is not None:
        body += vint(len(data))
    body += fields + extra
    size = vint(len(body))
    return struct.pack('<I', zlib.crc32(size + body)) + size + body + (data or b'')


def rar5_archive(entries: List[Entry], *, solid: bool = False, volume: Optional[int] = None,
                 locked: bool = False, recovery: bool = False, encrypted_headers: bool = False,
                 encrypted_files: bool = False, end: bool = True) -> bytes:
    """A RAR 5 archive of stored members. `volume` is the zero-based volume number."""
    out = bytearray(b'Rar!\x1a\x07\x01\x00')
    if encrypted_headers:
        # Archive encryption header: version 0, no check value, KDF count, 16-byte salt.
        out += rar5_block(4, 0, vint(0) + vint(0) + bytes([15]) + bytes(16))
        return bytes(out)
    flags = (1 if volume is not None else 0) | (2 if volume else 0) | (4 if solid else 0) \
        | (8 if recovery else 0) | (0x10 if locked else 0)
    main = vint(flags) + (vint(volume) if volume else b'')
    out += rar5_block(1, 0, main)
    for path, payload in entries:
        name = path.encode('utf-8')
        is_directory = payload is None
        data = b'' if is_directory else payload
        fields = vint((0x01 | 0x02) if is_directory else (0x02 | 0x04))
        fields += vint(len(data)) + vint(0x10 if is_directory else 0x20)
        fields += struct.pack('<I', MODIFIED)
        if not is_directory:
            fields += struct.pack('<I', zlib.crc32(data))
        fields += vint(0) + vint(1) + vint(len(name)) + name
        extra = b''
        if encrypted_files and not is_directory:
            record = vint(1) + vint(0) + vint(0) + bytes([15]) + bytes(16) + bytes(16)
            extra = vint(len(record)) + record
        out += rar5_block(2, 0, fields, extra=extra, data=data)
    if end:
        out += rar5_block(5, 0, vint(0))
    return bytes(out)


# --- RAR 1.5-4.x -----------------------------------------------------------------------------

def rar4_block(block_type: int, flags: int, body: bytes) -> bytes:
    rest = bytes([block_type]) + struct.pack('<HH', flags, 7 + len(body)) + body
    return struct.pack('<H', zlib.crc32(rest) & 0xFFFF) + rest


def dos_time(timestamp: int) -> int:
    import time
    t = time.gmtime(timestamp)
    return ((t.tm_year - 1980) << 25 | t.tm_mon << 21 | t.tm_mday << 16
            | t.tm_hour << 11 | t.tm_min << 5 | t.tm_sec // 2)


def rar4_unicode_name(name: str) -> bytes:
    """ANSI-compatible name, a zero byte, then the compact UTF-16 encoding (two bytes per unit)."""
    ansi = name.encode('latin-1', errors='replace')
    encoded = bytearray([0])           # shared high byte
    units = name.encode('utf-16-le')
    for index in range(0, len(units), 8):
        chunk = units[index:index + 8]
        flags = 0
        for position in range(len(chunk) // 2):
            flags |= 2 << (6 - 2 * position)       # operation 2: a full little-endian unit
        encoded.append(flags)
        encoded += chunk
    return ansi + b'\0' + bytes(encoded)


def rar4_archive(entries: List[Entry], *, solid: bool = False, volume: bool = False, locked: bool = False,
                 recovery: bool = False, encrypted_headers: bool = False, encrypted_files: bool = False,
                 unicode_names: bool = False, end: bool = True) -> bytes:
    out = bytearray(b'Rar!\x1a\x07\x00')
    flags = (1 if volume else 0) | (4 if locked else 0) | (8 if solid else 0) | (0x40 if recovery else 0) \
        | (0x80 if encrypted_headers else 0)
    out += rar4_block(0x73, flags, bytes(6))
    if encrypted_headers:
        return bytes(out)
    for path, payload in entries:
        is_directory = payload is None
        data = b'' if is_directory else payload
        name = rar4_unicode_name(path) if unicode_names else path.encode('utf-8')
        file_flags = 0x8000 | (0xE0 if is_directory else 0) | (4 if encrypted_files and not is_directory else 0) \
            | (0x200 if unicode_names else 0)
        body = struct.pack('<IIBIIBBHI', len(data), len(data), 2, zlib.crc32(data), dos_time(MODIFIED),
                           29, 0x30, len(name), 0x10 if is_directory else 0x20) + name
        out += rar4_block(0x74, file_flags, body) + data
    if end:
        out += bytes.fromhex('c43d7b00400700')
    return bytes(out)


# --- 7z --------------------------------------------------------------------------------------

def sevenzip_number(value: int) -> bytes:
    first = 0
    mask = 0x80
    index = 0
    while index < 8:
        if value < (1 << (7 * (index + 1))):
            first |= value >> (8 * index)
            break
        first |= mask
        mask >>= 1
        index += 1
    out = bytes([first])
    for _ in range(index):
        out += bytes([value & 0xFF])
        value >>= 8
    return out


def bit_vector(bits: list[bool]) -> bytes:
    out = bytearray((len(bits) + 7) // 8)
    for index, bit in enumerate(bits):
        if bit:
            out[index // 8] |= 0x80 >> (index % 8)
    return bytes(out)


def sevenzip_property(identifier: int, payload: bytes) -> bytes:
    return bytes([identifier]) + sevenzip_number(len(payload)) + payload


def lzma_properties(dictionary: int = 1 << 20, lc: int = 3, lp: int = 0, pb: int = 2) -> bytes:
    return bytes([(pb * 5 + lp) * 9 + lc]) + struct.pack('<I', dictionary)


def lzma2_property(dictionary: int = 1 << 20) -> int:
    for prop in range(41):
        if ((2 | (prop & 1)) << (prop // 2 + 11)) >= dictionary:
            return prop
    return 40


def sevenzip_header(entries: List[Entry]) -> Tuple[bytes, bytes]:
    """The plain header bytes and the concatenated packed (copy-coded) file streams."""
    streams = [payload for _, payload in entries if payload]
    packed = b''.join(streams)
    header = bytearray([0x01])
    if streams:
        header += bytes([0x04])
        header += bytes([0x06]) + sevenzip_number(0) + sevenzip_number(1) + bytes([0x09]) + sevenzip_number(len(packed)) + bytes([0x00])
        header += bytes([0x07, 0x0B]) + sevenzip_number(1) + bytes([0x00])
        header += sevenzip_number(1) + bytes([0x01, 0x00])           # one coder, id size 1: Copy
        header += bytes([0x0C]) + sevenzip_number(len(packed)) + bytes([0x00])
        header += bytes([0x08, 0x0D]) + sevenzip_number(len(streams))
        if len(streams) > 1:
            header += bytes([0x09]) + b''.join(sevenzip_number(len(s)) for s in streams[:-1])
        header += bytes([0x0A, 0x01]) + b''.join(struct.pack('<I', zlib.crc32(s)) for s in streams)
        header += bytes([0x00, 0x00])
    header += bytes([0x05]) + sevenzip_number(len(entries))
    empty = [payload is None or not payload for _, payload in entries]
    if any(empty):
        header += sevenzip_property(0x0E, bit_vector(empty))
        header += sevenzip_property(0x0F, bit_vector([payload is not None for _, payload in entries if payload is None or not payload]))
    header += sevenzip_property(0x11, b'\0' + b''.join(path.encode('utf-16-le') + b'\0\0' for path, _ in entries))
    header += sevenzip_property(0x14, b'\x01\x00' + b''.join(struct.pack('<Q', (MODIFIED + 11_644_473_600) * 10_000_000) for _ in entries))
    header += sevenzip_property(0x15, b'\x01\x00' + b''.join(struct.pack('<I', 0x10 if payload is None else 0x20) for _, payload in entries))
    header += bytes([0x00, 0x00])
    return bytes(header), packed


def sevenzip_archive(entries: List[Entry], *, header_coder: str = 'plain') -> bytes:
    """A 7z archive; `header_coder` is plain, lzma, lzma2 or aes (an encrypted-header marker)."""
    header, packed = sevenzip_header(entries)
    body = packed
    if header_coder == 'plain':
        next_header = header
    else:
        if header_coder == 'lzma':
            compressed = lzma.compress(header, format=lzma.FORMAT_RAW, filters=[
                {'id': lzma.FILTER_LZMA1, 'dict_size': 1 << 20, 'lc': 3, 'lp': 0, 'pb': 2}])
            coder = bytes([0x23, 0x03, 0x01, 0x01, 0x05]) + lzma_properties()
        elif header_coder == 'lzma2':
            compressed = lzma.compress(header, format=lzma.FORMAT_RAW, filters=[
                {'id': lzma.FILTER_LZMA2, 'dict_size': 1 << 20}])
            coder = bytes([0x21, 0x21, 0x01, lzma2_property()])
        elif header_coder == 'aes':
            # A header stream that names the AES coder is encrypted; its bytes are never interpreted.
            compressed = bytes(range(32))
            coder = bytes([0x24, 0x06, 0xF1, 0x07, 0x01, 0x05]) + bytes([0x0F]) + bytes(4)
        else:
            raise ValueError(header_coder)
        packed_position = len(packed)
        body = packed + compressed
        next_header = bytes([0x17, 0x06]) + sevenzip_number(packed_position) + sevenzip_number(1)
        next_header += bytes([0x09]) + sevenzip_number(len(compressed)) + bytes([0x00])
        next_header += bytes([0x07, 0x0B]) + sevenzip_number(1) + bytes([0x00]) + sevenzip_number(1) + coder
        next_header += bytes([0x0C]) + sevenzip_number(len(header))
        next_header += bytes([0x0A, 0x01]) + struct.pack('<I', zlib.crc32(header)) + bytes([0x00, 0x00])
    start = struct.pack('<QQI', len(body), len(next_header), zlib.crc32(next_header))
    return b"7z\xbc\xaf\x27\x1c\x00\x04" + struct.pack('<I', zlib.crc32(start)) + start + body + next_header


SAMPLE_ENTRIES: List[Entry] = [
    ('Example', None),
    ('Example/readme.txt', b'A synthetic archive entry.\n'),
    ('Example/data/values.json', b'{"values": [1, 2, 3]}\n'),
    ('Example/notes.md', b'# Notes\n\nListed without extraction.\n'),
]


def tar_bytes(entries: List[Entry]) -> bytes:
    """A USTAR archive with one fixed modification time, so the compressed samples are reproducible."""
    import io
    import tarfile
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        for path, payload in entries:
            item = tarfile.TarInfo(path)
            item.mtime = MODIFIED
            if payload is None:
                item.type = tarfile.DIRTYPE
                item.mode = 0o755
                archive.addfile(item)
            else:
                item.size = len(payload)
                archive.addfile(item, io.BytesIO(payload))
    return buffer.getvalue()


def xz_bytes(data: bytes) -> bytes:
    # One LZMA2 filter with an 8 MiB-or-smaller dictionary, the shape the xz reader accepts.
    return lzma.compress(data, format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC32,
                         filters=[{'id': lzma.FILTER_LZMA2, 'dict_size': 1 << 20}])


def appearance_samples() -> List[Tuple[str, str, dict]]:
    """(format ID, root name, {path: bytes}) for the companion's Theme page samples."""
    import bz2
    text = b'Example compressed text\n\nLocal previews decompress within fixed limits.\n'
    return [
        ('archive.rar', 'example.rar', {'example.rar': rar5_archive(SAMPLE_ENTRIES)}),
        ('archive.7z', 'example.7z', {'example.7z': sevenzip_archive(SAMPLE_ENTRIES, header_coder='lzma2')}),
        ('archive.bzip2', 'example.tar.bz2', {'example.tar.bz2': bz2.compress(tar_bytes(SAMPLE_ENTRIES))}),
        ('archive.xz', 'example.txt.xz', {'example.txt.xz': xz_bytes(text)}),
    ]


def host_fixtures(secret: str) -> List[Tuple[str, str, bytes]]:
    """(format ID, file name, bytes) for the host-matrix and adversarial corpus runs.

    The RAR and 7z fixtures name one entry with a secret-like assignment: the listing must
    conceal it, exactly as it conceals a secret in a text file's content."""
    import bz2
    entries = [('example', None), ('example/readme.txt', b'synthetic archive payload\n'),
               ('example/password=%s.txt' % secret, b'synthetic archive payload\n')]
    return [
        ('archive.rar', '31-listing.rar', rar5_archive(entries)),
        ('archive.7z', '32-listing.7z', sevenzip_archive(entries, header_coder='lzma')),
        ('archive.bzip2', '33-content.bz2', bz2.compress(('password=%s\n' % secret).encode())),
        ('archive.xz', '34-content.xz', xz_bytes(('password=%s\n' % secret).encode())),
    ]


def main() -> None:
    destination = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if destination is None:
        print(__doc__)
        return
    destination.mkdir(parents=True, exist_ok=True)
    (destination / 'example5.rar').write_bytes(rar5_archive(SAMPLE_ENTRIES))
    (destination / 'example4.rar').write_bytes(rar4_archive(SAMPLE_ENTRIES))
    (destination / 'plain.7z').write_bytes(sevenzip_archive(SAMPLE_ENTRIES))
    (destination / 'lzma.7z').write_bytes(sevenzip_archive(SAMPLE_ENTRIES, header_coder='lzma'))
    (destination / 'lzma2.7z').write_bytes(sevenzip_archive(SAMPLE_ENTRIES, header_coder='lzma2'))


if __name__ == '__main__':
    main()
