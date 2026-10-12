#!/usr/bin/env python3
"""Deterministic synthetic fixtures for the columnar, scientific, web-capture and geographic data formats.

Every file is assembled here from the public format specifications, with no third-party library and no
real data. The same bytes feed three consumers:

* ``script/generate_host_fixtures.py`` (Finder host matrix and the adversarial corpus),
* ``script/generate_appearance_samples.py`` (the companion's Theme page samples), and
* the Swift tests, through the one ``DataFixtures.swift`` in the test-only ``PreviewTestSupport`` target.

    python3 script/data_fixtures.py --swift    # rewrite the Swift test fixtures
    python3 script/data_fixtures.py --check    # fail when the Swift fixtures are stale

Specifications used: Apache Parquet ``parquet.thrift`` and the Thrift compact protocol; Apache Avro
object container files; Apache Arrow ``Schema.fbs``/``Message.fbs``/``File.fbs`` and the IPC format; the NumPy
``.npy`` format (``numpy.lib.format``); HAR 1.2; RFC 7946; GPX 1.1; OGC KML 2.2. The secret-looking values are
synthetic and exist so the privacy tests can prove they never reach a presentation.
"""
from __future__ import annotations

import base64
import io
import json
from pathlib import Path
import struct
import sys
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
SWIFT_FIXTURES = [ROOT / 'Packages/PreviewCore/Tests/PreviewTestSupport/Fixtures/DataFixtures.swift']
SECRET = 'synthetic-secret-value'
# Names and values that the fixtures use for secret-looking content. `appearance_samples` swaps in neutral
# ones, because bundled samples must contain nothing that resembles a credential.
SECRET_KEY = 'password'
SECRET_ARRAY = 'api_key'
SECRET_PARAM = 'token'
SECRET_COLUMN = 'api_token'
# A URL with user information and query values; the neutral sample has neither, since query values are
# always reported as concealed.
URL_USER = f'user:{SECRET}@'
SECRET_VALUE = SECRET


# --- Thrift compact protocol ------------------------------------------------------------------------------

def varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def zigzag(value: int) -> bytes:
    return varint((value << 1) ^ (value >> 63))


TYPE_CODES = {'bool_true': 1, 'bool_false': 2, 'byte': 3, 'i16': 4, 'i32': 5, 'i64': 6, 'double': 7,
              'binary': 8, 'list': 9, 'struct': 12}


def thrift_struct(fields) -> bytes:
    """``fields``: iterable of ``(id, kind, value)`` in increasing id order.

    kinds: i32, i64, byte, bool, str, list (value ``(element_kind, [values])``), struct (value is fields).
    """
    out = bytearray()
    last = 0
    for field_id, kind, value in fields:
        code, payload = thrift_value(kind, value)
        if kind == 'bool':
            code = TYPE_CODES['bool_true'] if value else TYPE_CODES['bool_false']
        delta = field_id - last
        if 0 < delta <= 15:
            out.append(delta << 4 | code)
        else:
            out.append(code)
            out += zigzag(field_id)
        out += payload
        last = field_id
    out.append(0)
    return bytes(out)


def thrift_value(kind: str, value) -> tuple[int, bytes]:
    if kind in ('i32', 'i64'):
        return TYPE_CODES[kind], zigzag(value)
    if kind == 'byte':
        return TYPE_CODES['byte'], bytes([value & 0xFF])
    if kind == 'bool':
        return TYPE_CODES['bool_true'], b''
    if kind == 'str':
        data = value.encode('utf-8')
        return TYPE_CODES['binary'], varint(len(data)) + data
    if kind == 'struct':
        return TYPE_CODES['struct'], thrift_struct(value)
    if kind == 'list':
        element, items = value
        code = {'i32': 5, 'i64': 6, 'byte': 3, 'str': 8, 'struct': 12}[element]
        header = bytes([len(items) << 4 | code]) if len(items) < 15 else bytes([0xF0 | code]) + varint(len(items))
        body = b''.join(thrift_value(element, item)[1] for item in items)
        return TYPE_CODES['list'], header + body
    raise ValueError(kind)


# --- Parquet ------------------------------------------------------------------------------------------------

def parquet() -> bytes:
    """Three leaf columns (one nested in a group), one row group, key/value metadata with a secret."""
    def element(name, *, type_=None, repetition=None, children=None, converted=None, logical=None, length=None):
        fields = []
        if type_ is not None:
            fields.append((1, 'i32', type_))
        if length is not None:
            fields.append((2, 'i32', length))
        if repetition is not None:
            fields.append((3, 'i32', repetition))
        fields.append((4, 'str', name))
        if children is not None:
            fields.append((5, 'i32', children))
        if converted is not None:
            fields.append((6, 'i32', converted))
        if logical is not None:
            fields.append((10, 'struct', logical))
        return fields

    schema = [
        element('schema', children=4),
        element('id', type_=2, repetition=0),
        element('name', type_=6, repetition=1, converted=0, logical=[(1, 'struct', [])]),
        element('amount', type_=7, repetition=1, length=16, converted=5,
                logical=[(5, 'struct', [(1, 'i32', 2), (2, 'i32', 18)])]),
        element('address', repetition=1, children=1),
        element('city', type_=6, repetition=1, converted=0),
    ]
    # `schema` above lists root + 3 flat leaves + group + 1 nested leaf: root declares 4 children.

    def chunk(path, type_, codec, values, nulls, compressed, uncompressed):
        meta = [(1, 'i32', type_), (2, 'list', ('i32', [0, 3])), (3, 'list', ('str', path)), (4, 'i32', codec),
                (5, 'i64', values), (6, 'i64', uncompressed), (7, 'i64', compressed), (9, 'i64', 4),
                (12, 'struct', [(3, 'i64', nulls)])]
        return [(2, 'i64', 0), (3, 'struct', meta)]

    columns = [chunk(['id'], 2, 1, 3, 0, 40, 60), chunk(['name'], 6, 1, 3, 1, 50, 80),
               chunk(['amount'], 7, 6, 3, 0, 70, 90), chunk(['address', 'city'], 6, 1, 3, 2, 30, 45)]
    group = [(1, 'list', ('struct', columns)), (2, 'i64', 275), (3, 'i64', 3), (6, 'i64', 190)]
    metadata = [[(1, 'str', 'writer.note'), (2, 'str', 'synthetic parquet fixture')],
                [(1, 'str', SECRET_KEY), (2, 'str', SECRET_VALUE)]]
    footer = thrift_struct([
        (1, 'i32', 2), (2, 'list', ('struct', schema)), (3, 'i64', 3), (4, 'list', ('struct', [group])),
        (5, 'list', ('struct', metadata)), (6, 'str', 'synthetic-writer version 1.0')])
    return b'PAR1' + b'\0' * 8 + footer + struct.pack('<I', len(footer)) + b'PAR1'


def snappy_literal(data: bytes) -> bytes:
    """A valid Snappy block made only of literal runs (no copies); enough to exercise a decoder."""
    out = bytearray(varint(len(data)))
    for start in range(0, len(data), 60):
        run = data[start:start + 60]
        out.append((len(run) - 1) << 2)
        out += run
    return bytes(out)


def hybrid(values: list[int], width: int) -> bytes:
    """Parquet's RLE/bit-packed hybrid, written as one bit-packed run padded to a multiple of eight values."""
    padded = list(values) + [0] * (-len(values) % 8)
    groups = len(padded) // 8
    bits = 0
    for index, value in enumerate(padded):
        bits |= value << (index * width)
    return varint(groups << 1 | 1) + bits.to_bytes(groups * width, 'little')


def plain(kind: str, values) -> bytes:
    if kind == 'int32':
        return b''.join(struct.pack('<i', v) for v in values)
    if kind == 'int64':
        return b''.join(struct.pack('<q', v) for v in values)
    if kind == 'double':
        return b''.join(struct.pack('<d', v) for v in values)
    if kind == 'string':
        return b''.join(struct.pack('<I', len(v.encode())) + v.encode() for v in values)
    if kind == 'bytes':
        return b''.join(struct.pack('<I', len(v)) + v for v in values)
    if kind == 'boolean':
        packed = 0
        for index, value in enumerate(values):
            packed |= int(value) << index
        return packed.to_bytes((len(values) + 7) // 8, 'little')
    raise ValueError(kind)


def parquet_rows() -> bytes:
    """Five rows across every supported page shape: PLAIN and dictionary pages, data page v1 and v2, the
    UNCOMPRESSED / SNAPPY / GZIP codecs, nulls, DATE, DECIMAL and TIMESTAMP_MILLIS, a secret-named column, a
    binary column, and a repeated (LIST) column that must be left out."""
    import gzip

    rows = 5
    body = bytearray(b'PAR1')
    chunks = []

    def compress(codec: int, data: bytes) -> bytes:
        return data if codec == 0 else snappy_literal(data) if codec == 1 else gzip.compress(data, mtime=0)

    def page(kind, header_fields, uncompressed, payload):
        header = thrift_struct([(1, 'i32', kind), (2, 'i32', uncompressed), (3, 'i32', len(payload))] + header_fields)
        return header + payload

    def data_page_v1(codec, count, definition, values, encoding):
        levels = b''
        if definition is not None:
            encoded = hybrid(definition, 1)
            levels = struct.pack('<I', len(encoded)) + encoded
        raw = levels + values
        return page(0, [(5, 'struct', [(1, 'i32', count), (2, 'i32', encoding), (3, 'i32', 3), (4, 'i32', 3)])],
                    len(raw), compress(codec, raw))

    def data_page_v2(codec, count, definition, values, encoding):
        levels = hybrid(definition, 1) if definition is not None else b''
        nulls = sum(1 for v in (definition or []) if v == 0)
        packed = compress(codec, values)
        header = [(8, 'struct', [(1, 'i32', count), (2, 'i32', nulls), (3, 'i32', count), (4, 'i32', encoding),
                                 (5, 'i32', len(levels)), (6, 'i32', 0), (7, 'bool', codec != 0)])]
        return page(3, header, len(levels) + len(values), levels + packed)

    def add_chunk(path, physical, codec, count, nulls, pages, encodings, dictionary_offset=None):
        first = len(body)
        offsets = []
        for blob in pages:
            offsets.append(len(body))
            body.extend(blob)
        meta = [(1, 'i32', physical), (2, 'list', ('i32', encodings)), (3, 'list', ('str', path)), (4, 'i32', codec),
                (5, 'i64', count), (6, 'i64', len(body) - first), (7, 'i64', len(body) - first),
                (9, 'i64', offsets[-1] if dictionary_offset is not None else offsets[0])]
        if dictionary_offset is not None:
            meta.append((11, 'i64', offsets[0]))
        meta.append((12, 'struct', [(3, 'i64', nulls)]))
        chunks.append([(2, 'i64', 0), (3, 'struct', meta)])

    # id: INT64 REQUIRED, PLAIN, uncompressed.
    add_chunk(['id'], 2, 0, rows, 0, [data_page_v1(0, rows, None, plain('int64', [10, 20, 30, 40, 50]), 0)], [0])
    # name: OPTIONAL string, dictionary-encoded, SNAPPY. Dictionary: alpha, gamma; indices 0 1 for present values.
    names = ['alpha', None, 'gamma', 'alpha', None]
    dictionary = ['alpha', 'gamma']
    dictionary_page = page(2, [(7, 'struct', [(1, 'i32', 2), (2, 'i32', 2)])], len(plain('string', dictionary)),
                           compress(1, plain('string', dictionary)))
    indices = bytes([1]) + hybrid([0, 1, 0], 1)
    add_chunk(['name'], 6, 1, rows, 2, [dictionary_page, data_page_v1(1, rows, [int(v is not None) for v in names], indices, 8)],
              [0, 8], dictionary_offset=True)
    # score: OPTIONAL double, PLAIN, GZIP.
    scores = [1.5, 2.5, None, 4.5, 5.5]
    add_chunk(['score'], 5, 2, rows, 1, [data_page_v1(2, rows, [int(v is not None) for v in scores],
                                                       plain('double', [v for v in scores if v is not None]), 0)], [0])
    # flag: BOOLEAN REQUIRED, data page v2, SNAPPY.
    add_chunk(['flag'], 0, 1, rows, 0, [data_page_v2(1, rows, None, plain('boolean', [True, False, True, True, False]), 0)], [0])
    # day: INT32 DATE REQUIRED. 20454 = 2026-01-01.
    add_chunk(['day'], 1, 0, rows, 0, [data_page_v1(0, rows, None, plain('int32', [20454, 20455, 20456, 20457, 20458]), 0)], [0])
    # amount: INT32 DECIMAL(9,2) REQUIRED.
    add_chunk(['amount'], 1, 0, rows, 0, [data_page_v1(0, rows, None, plain('int32', [12345, -5, 0, 100, 99999]), 0)], [0])
    # ts: INT64 TIMESTAMP_MILLIS REQUIRED (2026-01-01T00:00:00.5Z and onward).
    stamps = [1_767_225_600_500 + 1000 * i for i in range(rows)]
    add_chunk(['ts'], 2, 0, rows, 0, [data_page_v1(0, rows, None, plain('int64', stamps), 0)], [0])
    # api_token: a column whose name looks secret; every cell must be concealed.
    tokens = [SECRET_VALUE, None, SECRET_VALUE, SECRET_VALUE, SECRET_VALUE]
    add_chunk([SECRET_COLUMN], 6, 0, rows, 1, [data_page_v1(0, rows, [int(v is not None) for v in tokens],
                                                          plain('string', [v for v in tokens if v is not None]), 0)], [0])
    # blob: BYTE_ARRAY without an annotation is binary and shown only as a length.
    add_chunk(['blob'], 6, 0, rows, 0, [data_page_v1(0, rows, None, plain('bytes', [b'\x01\x02\x03'] * rows), 0)], [0])
    # tags.list.element: repeated, so it has no one-entry-per-row sample and is left out.
    add_chunk(['tags', 'list', 'element'], 1, 0, rows, 0, [data_page_v1(0, rows, None, plain('int32', [1] * rows), 0)], [0])

    def element(name, *, type_=None, repetition=None, children=None, converted=None, logical=None, scale=None, precision=None):
        fields = []
        if type_ is not None:
            fields.append((1, 'i32', type_))
        if repetition is not None:
            fields.append((3, 'i32', repetition))
        fields.append((4, 'str', name))
        if children is not None:
            fields.append((5, 'i32', children))
        if converted is not None:
            fields.append((6, 'i32', converted))
        if scale is not None:
            fields.append((7, 'i32', scale))
        if precision is not None:
            fields.append((8, 'i32', precision))
        if logical is not None:
            fields.append((10, 'struct', logical))
        return fields

    schema = [
        element('schema', children=10),
        element('id', type_=2, repetition=0),
        element('name', type_=6, repetition=1, converted=0),
        element('score', type_=5, repetition=1),
        element('flag', type_=0, repetition=0),
        element('day', type_=1, repetition=0, converted=6),
        element('amount', type_=1, repetition=0, converted=5, scale=2, precision=9),
        element('ts', type_=2, repetition=0, converted=9),
        element(SECRET_COLUMN, type_=6, repetition=1, converted=0),
        element('blob', type_=6, repetition=0),
        element('tags', repetition=1, children=1, converted=3),
        element('list', repetition=2, children=1),
        element('element', type_=1, repetition=1),
    ]
    group = [(1, 'list', ('struct', chunks)), (2, 'i64', len(body)), (3, 'i64', rows), (6, 'i64', len(body))]
    footer = thrift_struct([(1, 'i32', 2), (2, 'list', ('struct', schema)), (3, 'i64', rows),
                            (4, 'list', ('struct', [group])), (6, 'str', 'synthetic-writer rows 1.0')])
    return bytes(body) + footer + struct.pack('<I', len(footer)) + b'PAR1'


# --- Avro ---------------------------------------------------------------------------------------------------

def avro_long(value: int) -> bytes:
    return varint((value << 1) ^ (value >> 63))


def avro_string(text: str) -> bytes:
    data = text.encode('utf-8')
    return avro_long(len(data)) + data


def avro_schema() -> dict:
    return {
    'type': 'record', 'name': 'Sample', 'namespace': 'synthetic',
    'fields': [
        {'name': 'id', 'type': 'long'}, {'name': 'name', 'type': 'string'},
        {'name': SECRET_KEY, 'type': 'string'}, {'name': 'ratio', 'type': 'double'},
        {'name': 'active', 'type': 'boolean'}, {'name': 'nick', 'type': ['null', 'string']},
        {'name': 'tags', 'type': {'type': 'array', 'items': 'string'}},
        {'name': 'blob', 'type': 'bytes'},
    ],
    }


def avro_record(index: int) -> bytes:
    out = avro_long(index) + avro_string(f'item {index}') + avro_string(SECRET_VALUE)
    out += struct.pack('<d', index / 4) + bytes([index % 2])
    out += avro_long(0) if index % 2 == 0 else avro_long(1) + avro_string(f'nick{index}')
    out += avro_long(2) + avro_string('a') + avro_string('b') + avro_long(0)
    out += avro_long(4) + b'\xde\xad\xbe\xef'
    return out


def avro(codec: str = 'null', records: int = 3) -> bytes:
    sync = bytes(range(16))
    schema = json.dumps(avro_schema(), separators=(',', ':')).encode()
    meta = [(b'avro.schema', schema), (b'avro.codec', codec.encode()), (b'writer', b'synthetic')]
    header = b'Obj\x01' + avro_long(len(meta))
    for key, value in meta:
        header += avro_long(len(key)) + key + avro_long(len(value)) + value
    header += avro_long(0) + sync
    block = b''.join(avro_record(index) for index in range(records))
    if codec == 'deflate':
        compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
        block = compressor.compress(block) + compressor.flush()
    return header + avro_long(records) + avro_long(len(block)) + block + sync


# --- Arrow IPC ----------------------------------------------------------------------------------------------

class FlatBuilder:
    """Lays tables out front to back; uoffsets are unsigned and forward, so children follow parents."""

    SIZES = {'i8': 1, 'u8': 1, 'bool': 1, 'i16': 2, 'i32': 4, 'i64': 8, 'ref': 4}
    FORMATS = {'i8': '<b', 'u8': '<B', 'bool': '<B', 'i16': '<h', 'i32': '<i', 'i64': '<q'}

    def __init__(self):
        self.buffer = bytearray(4)

    def align(self, boundary: int, extra: int = 0):
        while (len(self.buffer) + extra) % boundary:
            self.buffer.append(0)

    def table(self, slots: dict) -> tuple[int, dict]:
        """``slots``: slot -> (kind, value); kind 'ref' reserves four bytes patched with `link`."""
        highest = max(slots) if slots else -1
        vtable_length = 4 + 2 * (highest + 1)
        self.align(8)
        vtable = len(self.buffer)
        self.buffer += bytes(vtable_length)
        table = len(self.buffer)
        self.buffer += struct.pack('<i', table - vtable)
        body = bytearray(4)
        offsets: dict[int, int] = {}
        for slot in sorted(slots):
            kind, value = slots[slot]
            size = self.SIZES[kind]
            while len(body) % size:
                body.append(0)
            offsets[slot] = len(body)
            body += struct.pack(self.FORMATS[kind], value) if kind != 'ref' else bytes(4)
        self.buffer += body[4:]
        struct.pack_into('<HH', self.buffer, vtable, vtable_length, len(body))
        for slot, offset in offsets.items():
            struct.pack_into('<H', self.buffer, vtable + 4 + 2 * slot, offset)
        return table, {slot: table + offset for slot, offset in offsets.items()}

    def link(self, field_position: int, target: int):
        struct.pack_into('<I', self.buffer, field_position, target - field_position)

    def string(self, text: str) -> int:
        data = text.encode('utf-8')
        self.align(4)
        position = len(self.buffer)
        self.buffer += struct.pack('<I', len(data)) + data + b'\0'
        self.align(4)
        return position

    def offset_vector(self, count: int) -> tuple[int, list[int]]:
        self.align(4)
        position = len(self.buffer)
        self.buffer += struct.pack('<I', count) + bytes(4 * count)
        return position, [position + 4 + 4 * index for index in range(count)]

    def struct_vector(self, items: list[bytes], alignment: int) -> int:
        self.align(alignment, extra=4)
        position = len(self.buffer)
        self.buffer += struct.pack('<I', len(items)) + b''.join(items)
        return position

    def finish(self, root: int) -> bytes:
        struct.pack_into('<I', self.buffer, 0, root)
        self.align(8)
        return bytes(self.buffer)


def arrow_type(kind: str, **parameters):
    """Returns (union tag, slots of the type table or None)."""
    if kind == 'int':
        return 2, {0: ('i32', parameters['bits']), 1: ('bool', parameters.get('signed', True))}
    if kind == 'float':
        return 3, {0: ('i16', parameters['precision'])}
    if kind == 'utf8':
        return 5, None
    if kind == 'timestamp':
        return 10, {0: ('i16', parameters['unit']), 1: ('ref', None)}
    if kind == 'list':
        return 12, None
    raise ValueError(kind)


def arrow_field(builder: FlatBuilder, name: str, kind: str, nullable: bool, children=(), dictionary=None, **parameters) -> int:
    tag, type_slots = arrow_type(kind, **parameters)
    slots = {0: ('ref', None), 1: ('bool', nullable), 2: ('u8', tag)}
    if type_slots is not None:
        slots[3] = ('ref', None)
    if dictionary is not None:
        slots[4] = ('ref', None)
    if children:
        slots[5] = ('ref', None)
    field, positions = builder.table(slots)
    builder.link(positions[0], builder.string(name))
    if type_slots is not None:
        table, type_positions = builder.table(type_slots)
        builder.link(positions[3], table)
        if kind == 'timestamp':
            builder.link(type_positions[1], builder.string(parameters.get('zone', 'UTC')))
    if dictionary is not None:
        encoding, encoding_positions = builder.table({0: ('i64', 7), 1: ('ref', None)})
        builder.link(positions[4], encoding)
        index_table, _ = builder.table({0: ('i32', 8), 1: ('bool', True)})
        builder.link(encoding_positions[1], index_table)
    if children:
        vector, elements = builder.offset_vector(len(children))
        builder.link(positions[5], vector)
        for element, child in zip(elements, children):
            builder.link(element, arrow_field(builder, *child[0], **child[1]))
    return field


ARROW_FIELDS = [
    (('id', 'int', False), {'bits': 64, 'signed': True}),
    (('name', 'utf8', True), {}),
    (('seen', 'timestamp', True), {'unit': 2, 'zone': 'UTC'}),
    (('items', 'list', True), {}),
    (('color', 'utf8', True), {'dictionary': True}),
]


def write_schema(builder: FlatBuilder) -> int:
    """The Schema table: five fields (one nested, one dictionary-encoded) and secret-keyed metadata."""
    schema, positions = builder.table({0: ('i16', 0), 1: ('ref', None), 2: ('ref', None)})
    vector, elements = builder.offset_vector(len(ARROW_FIELDS))
    builder.link(positions[1], vector)
    for element, ((name, kind, nullable), parameters) in zip(elements, ARROW_FIELDS):
        children = [(('item', 'float', True), {'precision': 1})] if name == 'items' else []
        builder.link(element, arrow_field(builder, name, kind, nullable, children=children, **parameters))
    meta_vector, meta_elements = builder.offset_vector(1)
    builder.link(positions[2], meta_vector)
    entry, entry_positions = builder.table({0: ('ref', None), 1: ('ref', None)})
    builder.link(meta_elements[0], entry)
    builder.link(entry_positions[0], builder.string(SECRET_ARRAY))
    builder.link(entry_positions[1], builder.string(SECRET_VALUE))
    return schema


def encapsulate(flat: bytes) -> bytes:
    """Continuation marker, metadata length and metadata padded so the body would start 8-aligned."""
    padded = flat + bytes(-(len(flat) + 8) % 8)
    return b'\xff\xff\xff\xff' + struct.pack('<i', len(padded)) + padded


def arrow_schema_message() -> bytes:
    builder = FlatBuilder()
    message, positions = builder.table({0: ('i16', 4), 1: ('u8', 1), 2: ('ref', None), 3: ('i64', 0)})
    builder.link(positions[2], write_schema(builder))
    return encapsulate(builder.finish(message))


def arrow_batch_message(length: int) -> bytes:
    builder = FlatBuilder()
    message, positions = builder.table({0: ('i16', 4), 1: ('u8', 3), 2: ('ref', None), 3: ('i64', 0)})
    header, _ = builder.table({0: ('i64', length)})
    builder.link(positions[2], header)
    return encapsulate(builder.finish(message))


def arrow_stream(batches=(4, 3)) -> bytes:
    out = arrow_schema_message()
    for length in batches:
        out += arrow_batch_message(length)
    return out + b'\xff\xff\xff\xff' + bytes(4)


def arrow_file(batches=(4, 3)) -> bytes:
    body = b'ARROW1\0\0' + arrow_schema_message()
    blocks = []
    for length in batches:
        message = arrow_batch_message(length)
        blocks.append(struct.pack('<qi4xq', len(body), len(message), 0))
        body += message
    builder = FlatBuilder()
    footer, positions = builder.table({0: ('i16', 4), 1: ('ref', None), 2: ('ref', None), 3: ('ref', None)})
    builder.link(positions[1], write_schema(builder))
    builder.link(positions[2], builder.struct_vector([], 8))
    builder.link(positions[3], builder.struct_vector(blocks, 8))
    flat = builder.finish(footer)
    return body + bytes(-len(body) % 8) + flat + struct.pack('<i', len(flat)) + b'ARROW1'


def arrow_sharing_bomb(levels: int = 14, fan: int = 4) -> bytes:
    """A stream whose schema is a small DAG: every field lists the same child `fan` times, so a naive walk
    visits fan**levels fields. FlatBuffers offsets only point forward, so a cycle cannot be written, but shared
    subtrees can; the reader's field budget must stop this."""
    builder = FlatBuilder()
    message, positions = builder.table({0: ('i16', 4), 1: ('u8', 1), 2: ('ref', None), 3: ('i64', 0)})
    schema, schema_positions = builder.table({0: ('i16', 0), 1: ('ref', None)})
    builder.link(positions[2], schema)
    vector, elements = builder.offset_vector(1)
    builder.link(schema_positions[1], vector)
    pending = elements
    for level in range(levels):
        field, field_positions = builder.table({0: ('ref', None), 1: ('bool', True), 2: ('u8', 6), 5: ('ref', None)})
        for link in pending:
            builder.link(link, field)
        builder.link(field_positions[0], builder.string(f'level{level}'))
        children, pending = builder.offset_vector(fan)
        builder.link(field_positions[5], children)
    leaf, leaf_positions = builder.table({0: ('ref', None), 1: ('bool', True), 2: ('u8', 6)})
    for link in pending:
        builder.link(link, leaf)
    builder.link(leaf_positions[0], builder.string('leaf'))
    return encapsulate(builder.finish(message)) + b'\xff\xff\xff\xff' + bytes(4)


# --- NumPy --------------------------------------------------------------------------------------------------

def npy(shape: tuple, dtype: str, values: bytes, fortran: bool = False, version: int = 1) -> bytes:
    shape_text = '(' + ', '.join(str(n) for n in shape) + (',)' if len(shape) == 1 else ')')
    header = f"{{'descr': '{dtype}', 'fortran_order': {fortran}, 'shape': {shape_text}, }}"
    preamble = 10 if version == 1 else 12
    padding = -(preamble + len(header) + 1) % 64
    header = (header + ' ' * padding + '\n').encode('latin1')
    length = struct.pack('<H', len(header)) if version == 1 else struct.pack('<I', len(header))
    return b'\x93NUMPY' + bytes([version, 0]) + length + header + values


def npy_matrix() -> bytes:
    return npy((3, 4), '<f8', struct.pack('<12d', *[row + column / 10 for row in range(3) for column in range(4)]))


def npz() -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w') as archive:
        weights = npy((2, 3), '<f4', struct.pack('<6f', 0.5, 1.5, 2.5, 3.5, 4.5, 5.5))
        secret = npy((3,), '<i4', struct.pack('<3i', 11, 22, 33))
        labels = npy((4,), '<i8', struct.pack('<4q', 1, 2, 3, 4))
        for name, data, method in (('weights.npy', weights, zipfile.ZIP_STORED),
                                   (f'{SECRET_ARRAY}.npy', secret, zipfile.ZIP_STORED),
                                   ('labels.npy', labels, zipfile.ZIP_DEFLATED)):
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = method
            archive.writestr(info, data)
    return buffer.getvalue()


# --- Text formats -------------------------------------------------------------------------------------------

def url_query() -> str:
    return f'?{SECRET_PARAM}={SECRET_VALUE}&page=2' if URL_USER else ''


def har() -> str:
    entries = []
    for index, (method, url, status, mime, size, time) in enumerate([
            ('GET', f'https://{URL_USER}example.com/api/items{url_query()}#section', 200, 'application/json; charset=utf-8', 1234, 56.78),
            ('POST', 'https://example.com/login', 302, 'text/html', 0, 12.5),
            ('GET', 'https://cdn.example.com/app.js', 304, 'text/javascript', -1, 3.0)]):
        entries.append({
            'startedDateTime': f'2026-01-01T00:00:0{index}.000Z', 'time': time,
            'request': {'method': method, 'url': url, 'httpVersion': 'HTTP/1.1',
                        'headers': [{'name': 'Authorization', 'value': f'Bearer {SECRET_VALUE}'}] if URL_USER else [{'name': 'Accept', 'value': 'text/html'}],
                        'cookies': [{'name': 'session', 'value': SECRET_VALUE}] if URL_USER else [], 'queryString': [],
                        'postData': {'mimeType': 'application/json', 'text': f'{{"{SECRET_KEY}": "{SECRET_VALUE}"}}'} if URL_USER else {'mimeType': 'text/plain', 'text': 'example'},
                        'headersSize': -1, 'bodySize': 0},
            'response': {'status': status, 'statusText': 'OK', 'httpVersion': 'HTTP/1.1',
                         'headers': [{'name': 'Set-Cookie', 'value': f'sid={SECRET_VALUE}'}] if URL_USER else [], 'cookies': [],
                         'content': {'size': size, 'mimeType': mime, 'text': f'secret body {SECRET_VALUE}' if URL_USER else 'example body'},
                         'redirectURL': '', 'headersSize': -1, 'bodySize': size},
            'cache': {}, 'timings': {'send': 1, 'wait': 2, 'receive': 3}})
    return json.dumps({'log': {
        'version': '1.2', 'creator': {'name': 'Synthetic Capture', 'version': '1.0'},
        'browser': {'name': 'Synthetic Browser', 'version': '2.0'},
        'pages': [{'startedDateTime': '2026-01-01T00:00:00.000Z', 'id': 'page_1', 'title': 'Home', 'pageTimings': {}}],
        'entries': entries}}, indent=1)


def geojson() -> str:
    return json.dumps({
        'type': 'FeatureCollection',
        'features': [
            {'type': 'Feature', 'properties': {'name': 'Pin', SECRET_KEY: SECRET_VALUE}, 'geometry': {'type': 'Point', 'coordinates': [12.4964, 41.9028]}},
            {'type': 'Feature', 'properties': {'name': 'Walk', 'length': 12}, 'geometry': {'type': 'LineString', 'coordinates': [[12.49, 41.89], [12.5, 41.9], [12.51, 41.91]]}},
            {'type': 'Feature', 'properties': {'name': 'Park'}, 'geometry': {'type': 'Polygon', 'coordinates': [[[12.48, 41.88], [12.5, 41.88], [12.5, 41.9], [12.48, 41.9], [12.48, 41.88]]]}},
            {'type': 'Feature', 'properties': {'name': 'Nowhere'}, 'geometry': None}]}, indent=1)


def gpx() -> str:
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Synthetic Tracker" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>Morning loop</name></metadata>
  <wpt lat="41.9028" lon="12.4964"><ele>21.0</ele><name>Start</name></wpt>
  <trk><name>Loop</name><trkseg>
    <trkpt lat="41.9000" lon="12.4900"><ele>20.0</ele><time>2026-01-01T08:00:00Z</time></trkpt>
    <trkpt lat="41.9010" lon="12.4950"><ele>24.5</ele><time>2026-01-01T08:05:00Z</time></trkpt>
    <trkpt lat="41.9030" lon="12.5000"><ele>22.0</ele><time>2026-01-01T08:10:00Z</time></trkpt>
  </trkseg></trk>
  <extensions><{SECRET_KEY}>{SECRET_VALUE}</{SECRET_KEY}></extensions>
</gpx>
'''


def kml() -> str:
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document><name>Synthetic places</name>
  <Placemark><name>Pin</name><description>{SECRET_PARAM}={SECRET_VALUE}</description>
    <Point><coordinates>12.4964,41.9028,21</coordinates></Point></Placemark>
  <Folder><name>Walks</name><Placemark><name>Walk</name>
    <LineString><coordinates>12.49,41.89,0 12.50,41.90,0 12.51,41.91,0</coordinates></LineString></Placemark></Folder>
</Document></kml>
'''


# --- Companion appearance samples ---------------------------------------------------------------------------

def appearance_samples() -> list[tuple[str, str, bytes]]:
    """(format id, file name, bytes) for the Theme page: small, neutral and free of credential-like values."""
    global SECRET_KEY, SECRET_ARRAY, SECRET_PARAM, SECRET_COLUMN, SECRET_VALUE, URL_USER
    saved = (SECRET_KEY, SECRET_ARRAY, SECRET_PARAM, SECRET_COLUMN, SECRET_VALUE, URL_USER)
    SECRET_KEY, SECRET_ARRAY, SECRET_PARAM, SECRET_COLUMN, SECRET_VALUE, URL_USER = 'comment', 'bias', 'ref', 'remark', 'A short remark.', ''
    try:
        return [
            ('data.parquet', 'example.parquet', parquet_rows()),
            ('data.avro', 'example.avro', avro('deflate')),
            ('data.arrow', 'example.arrow', arrow_file()),
            ('data.numpy', 'example.npy', npy_matrix()),
            ('data.numpy-archive', 'example.npz', npz()),
            ('data.har', 'example.har', har().encode()),
            ('data.geojson', 'example.geojson', geojson().encode()),
            ('data.gpx', 'example.gpx', gpx().encode()),
            ('data.kml', 'example.kml', kml().encode()),
        ]
    finally:
        SECRET_KEY, SECRET_ARRAY, SECRET_PARAM, SECRET_COLUMN, SECRET_VALUE, URL_USER = saved


def kmz() -> bytes:
    """A KMZ package: `doc.kml` plus an icon that must never be read."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w') as archive:
        info = zipfile.ZipInfo('doc.kml', date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, kml())
        icon = zipfile.ZipInfo('files/icon.png', date_time=(2026, 1, 1, 0, 0, 0))
        archive.writestr(icon, b'\x89PNG synthetic icon bytes')
    return buffer.getvalue()


# --- Registry and Swift export ------------------------------------------------------------------------------

def binary_fixtures() -> dict[str, bytes]:
    return {
        'parquet': parquet(), 'parquetRows': parquet_rows(), 'avro': avro('null'), 'avroDeflate': avro('deflate'),
        'arrowFile': arrow_file(), 'arrowStream': arrow_stream(), 'arrowSharing': arrow_sharing_bomb(), 'arrowDeep': arrow_sharing_bomb(levels=20, fan=1),
        'arrowManyBatches': arrow_file(batches=[1] * 70), 'numpy': npy_matrix(), 'numpyArchive': npz(), 'kmz': kmz(),
    }


def text_fixtures() -> dict[str, str]:
    return {'har': har(), 'geoJSON': geojson(), 'gpx': gpx(), 'kml': kml()}


def swift_source() -> str:
    lines = ['// Generated by script/data_fixtures.py; do not edit. Run `python3 script/data_fixtures.py --swift`.',
             '// Synthetic bytes assembled from the public specifications; the secret-looking values are fake.',
             'import Foundation', '', 'public enum DataFixtures {',
             f'    public static let secret = "{SECRET}"', '']
    for name, data in binary_fixtures().items():
        lines.append(f'    public static let {name} = Data(base64Encoded: "{base64.b64encode(data).decode()}")!')
    for name, text in text_fixtures().items():
        lines.append(f'    public static let {name} = Data(base64Encoded: "{base64.b64encode(text.encode()).decode()}")!')
    lines.append('}')
    return '\n'.join(lines) + '\n'


def main() -> int:
    arguments = sys.argv[1:]
    if arguments == ['--swift']:
        for path in SWIFT_FIXTURES:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(swift_source())
            print(f'Wrote {path.relative_to(ROOT)}')
        return 0
    if arguments == ['--check']:
        if any(not path.is_file() or path.read_text() != swift_source() for path in SWIFT_FIXTURES):
            print('Swift data fixtures are stale; run script/data_fixtures.py --swift', file=sys.stderr)
            return 1
        print('Swift data fixtures are current.')
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main())
