"""Synthetic PyTorch checkpoint for the appearance sample and the Finder host fixtures (decision 030).

The checkpoint is a ZIP in the layout PyTorch 1.6 and later write: `archive/data.pkl`, `archive/version`,
`archive/byteorder` and one 16-byte storage under `archive/data/`. `data.pkl` is a protocol 2 pickle of an
`OrderedDict` holding one 2 by 2 tensor, assembled here opcode by opcode: the dictionary and the tensor are
rebuilt by `collections.OrderedDict` and `torch._utils._rebuild_tensor_v2`, and the tensor's storage is a
tuple given to BINPERSID. These are exactly the imports an ordinary checkpoint names and no others.

Nothing here imports the pickle module, unpickles anything or pickles a live object: the stream is written
byte by byte from the opcode table in Python's documentation of `pickletools`, and it is never loaded.
Standard library only; every function is pure and deterministic.
"""
from __future__ import annotations

from io import BytesIO
import struct
import zipfile

# Opcodes used below (see the table in the pickletools documentation).
PROTO, GLOBAL, BINPUT, EMPTY_TUPLE, REDUCE, MARK = b'\x80', b'c', b'q', b')', b'R', b'('
BINUNICODE, BININT1, TUPLE, TUPLE2, BINPERSID, NEWFALSE = b'X', b'K', b't', b'\x86', b'Q', b'\x89'
SETITEMS, STOP = b'u', b'.'


def _put(index: int) -> bytes:
    return BINPUT + bytes([index])


def _text(value: str) -> bytes:
    data = value.encode('utf-8')
    return BINUNICODE + struct.pack('<I', len(data)) + data


def _global(module: str, name: str) -> bytes:
    return GLOBAL + module.encode('ascii') + b'\n' + name.encode('ascii') + b'\n'


def _small(value: int) -> bytes:
    return BININT1 + bytes([value])


def checkpoint_pickle(extra_entry: tuple[str, str] | None = None) -> bytes:
    """`OrderedDict([(extra key, extra string)?, ('weight', tensor)])` as protocol 2 opcodes.

    `extra_entry` adds one plain string value before the tensor; it is data in the stream and imports nothing.
    """
    dictionary = _global('collections', 'OrderedDict') + _put(0) + EMPTY_TUPLE + REDUCE + _put(1)
    extra = b''
    if extra_entry is not None:
        extra = _text(extra_entry[0]) + _put(2) + _text(extra_entry[1]) + _put(3)
    # The storage: ('storage', torch.FloatStorage, '0', 'cpu', 4) given to BINPERSID.
    storage = (MARK + _text('storage') + _put(4) + _global('torch', 'FloatStorage') + _put(5) + _text('0') + _put(6)
               + _text('cpu') + _put(7) + _small(4) + TUPLE + _put(8) + BINPERSID)
    # _rebuild_tensor_v2(storage, offset 0, size (2, 2), stride (2, 1), requires_grad False, hooks OrderedDict()).
    tensor = (_global('torch._utils', '_rebuild_tensor_v2') + _put(9) + MARK + storage + _small(0)
              + _small(2) + _small(2) + TUPLE2 + _put(10) + _small(2) + _small(1) + TUPLE2 + _put(11) + NEWFALSE
              + _global('collections', 'OrderedDict') + _put(12) + EMPTY_TUPLE + REDUCE + _put(13) + TUPLE + _put(14)
              + REDUCE + _put(15))
    return PROTO + b'\x02' + dictionary + MARK + extra + _text('weight') + _put(16) + tensor + SETITEMS + STOP


def checkpoint_archive(extra_entry: tuple[str, str] | None = None) -> bytes:
    """The checkpoint as a ZIP with stored members and fixed timestamps."""
    members = [
        ('archive/data.pkl', checkpoint_pickle(extra_entry)),
        ('archive/byteorder', b'little'),
        ('archive/data/0', struct.pack('<4f', 0.5, -1.0, 2.0, 0.25)),
        ('archive/version', b'3\n'),
    ]
    output = BytesIO()
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_STORED) as archive:
        for name, data in members:
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED
            archive.writestr(info, data)
    return output.getvalue()


def appearance_samples() -> list[tuple[str, str, bytes]]:
    """(format ID, file name, bytes) for the Theme page: an ordinary checkpoint with only expected imports."""
    return [('ml.pickle', 'example.pt', checkpoint_archive())]


def host_fixtures(secret: str) -> list[tuple[str, str, bytes]]:
    """The same checkpoint with `secret` as a plain string under the key `api_key` in the dictionary.

    The scan never reads string values, so the secret must appear nowhere in the preview.
    """
    return [('ml.pickle', 'example.pt', checkpoint_archive(('api_key', secret)))]
