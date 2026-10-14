"""Synthetic GGUF and safetensors model files for the appearance samples and the Finder host matrix.

Shared by script/generate_appearance_samples.py and script/generate_host_fixtures.py. Everything is
authored here from the public file formats (the GGUF specification and the safetensors README); no model,
tokenizer or training data is copied, and the two weight tensors hold a few made-up numbers. Every writer is
deterministic and pure: no timestamps, random values, machine-specific data or file writes, so importing
this module does nothing and the same call returns the same bytes.

    appearance_samples()   benign samples, free of secret-like values
    host_fixtures(secret)  the same two files with `secret` stored under a sensitive metadata key
"""
from __future__ import annotations

import json
import struct

# A GGUF metadata value is (kind, value); the kinds below are the ones these samples need.
GGUFValue = tuple[str, object]

_GGUF_ALIGNMENT = 32
_GGUF_VERSION = 3
_GGUF_TYPE_CODES = {'u32': 4, 'f32': 6, 'bool': 7, 'string': 8, 'array': 9}
_GGML_F32 = 0

CHAT_TEMPLATE = (
    "{% for message in messages %}{{ message['role'] }}: {{ message['content'] }}\n{% endfor %}"
)


def _floats(count: int, step: float) -> list[float]:
    """A short, repeating ramp of small numbers (no randomness)."""
    return [((index % 16) - 8) * step for index in range(count)]


def _gguf_string(text: str) -> bytes:
    raw = text.encode('utf-8')
    return struct.pack('<Q', len(raw)) + raw


def _gguf_body(kind: str, value: object) -> bytes:
    if kind == 'string':
        return _gguf_string(str(value))
    if kind == 'u32':
        return struct.pack('<I', int(value))  # type: ignore[arg-type]
    if kind == 'f32':
        return struct.pack('<f', float(value))  # type: ignore[arg-type]
    if kind == 'bool':
        return struct.pack('<B', 1 if value else 0)
    if kind == 'strings':
        items = list(value)  # type: ignore[call-overload]
        return struct.pack('<IQ', _GGUF_TYPE_CODES['string'], len(items)) + b''.join(_gguf_string(item) for item in items)
    raise ValueError(f'unsupported GGUF value kind: {kind}')


def _gguf_entry(key: str, kind: str, value: object) -> bytes:
    code = _GGUF_TYPE_CODES['array'] if kind == 'strings' else _GGUF_TYPE_CODES[kind]
    return _gguf_string(key) + struct.pack('<I', code) + _gguf_body(kind, value)


def gguf(extra_metadata: list[tuple[str, GGUFValue]] | None = None) -> bytes:
    """A GGUF version 3 file: a handful of metadata keys, a four-token vocabulary, a short ordinary chat
    template and two small F32 tensors with real data. `extra_metadata` entries follow the ordinary keys."""
    metadata: list[tuple[str, GGUFValue]] = [
        ('general.architecture', ('string', 'llama')),
        ('general.name', ('string', 'Example Tiny Model')),
        ('general.size_label', ('string', '1K')),
        ('general.license', ('string', 'apache-2.0')),
        ('general.file_type', ('u32', 0)),
        ('general.quantization_version', ('u32', 2)),
        ('llama.context_length', ('u32', 2048)),
        ('llama.block_count', ('u32', 1)),
        ('llama.embedding_length', ('u32', 8)),
        ('llama.attention.head_count', ('u32', 2)),
        ('tokenizer.ggml.model', ('string', 'llama')),
        ('tokenizer.ggml.tokens', ('strings', ['<unk>', '<s>', '</s>', 'hello'])),
        ('tokenizer.chat_template', ('string', CHAT_TEMPLATE)),
    ] + list(extra_metadata or [])

    tensors = [('token_embd.weight', [8, 4], _floats(32, 0.0625)), ('output.weight', [8, 4], _floats(32, 0.03125))]
    header = b'GGUF' + struct.pack('<IQQ', _GGUF_VERSION, len(tensors), len(metadata))
    header += b''.join(_gguf_entry(key, kind, value) for key, (kind, value) in metadata)
    data = b''
    for name, dimensions, values in tensors:
        header += _gguf_string(name) + struct.pack('<I', len(dimensions))
        header += b''.join(struct.pack('<Q', dimension) for dimension in dimensions)
        header += struct.pack('<IQ', _GGML_F32, len(data))
        data += b''.join(struct.pack('<f', value) for value in values)
        data += b'\0' * (-len(data) % _GGUF_ALIGNMENT)
    return header + b'\0' * (-len(header) % _GGUF_ALIGNMENT) + data


def safetensors(extra_metadata: dict[str, str] | None = None) -> bytes:
    """A safetensors file: a `__metadata__` map, two F32 tensors with real data, and the header padded
    with spaces to a multiple of eight bytes as the reference library writes it."""
    metadata = {'format': 'pt', 'note': 'synthetic example'}
    metadata.update(extra_metadata or {})
    tensors = [('embed.weight', [4, 4], _floats(16, 0.0625)), ('norm.weight', [4], _floats(4, 0.125))]
    table: dict[str, object] = {'__metadata__': metadata}
    data = b''
    for name, shape, values in tensors:
        encoded = b''.join(struct.pack('<f', value) for value in values)
        table[name] = {'dtype': 'F32', 'shape': shape, 'data_offsets': [len(data), len(data) + len(encoded)]}
        data += encoded
    header = json.dumps(table, separators=(',', ':'), ensure_ascii=True).encode('ascii')
    header += b' ' * (-len(header) % 8)
    return struct.pack('<Q', len(header)) + header + data


def appearance_samples() -> list[tuple[str, str, bytes]]:
    """(format ID, file name, bytes) for the Theme page's live preview: benign and synthetic."""
    return [('ml.gguf', 'example.gguf', gguf()), ('ml.safetensors', 'example.safetensors', safetensors())]


def host_fixtures(secret: str) -> list[tuple[str, str, bytes]]:
    """(format ID, file name, bytes) for the Finder host matrix. Each file carries `secret` as the value of a
    sensitive metadata key (`general.api_key` in the GGUF file, `api_key` in the safetensors map); the
    preview must conceal it. Nothing else in either file resembles a credential."""
    return [
        ('ml.gguf', 'example.gguf', gguf([('general.api_key', ('string', secret))])),
        ('ml.safetensors', 'example.safetensors', safetensors({'api_key': secret})),
    ]
