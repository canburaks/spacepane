"""Synthetic triangle-mesh files for the mesh formats (STL, OBJ, PLY, 3MF).

Shared by generate_appearance_samples.py and generate_host_fixtures.py so both build the same
authored torus. Nothing here is copied from a real model, and no value resembles a credential.
Every writer is deterministic: no timestamps, random values or machine-specific data.
"""
from __future__ import annotations

from io import BytesIO
import math
import struct
import zipfile

Vertex = tuple[float, float, float]


def torus(segments: int = 20, sides: int = 12, major: float = 10.0, minor: float = 4.0) -> tuple[list[Vertex], list[tuple[int, int, int, int]]]:
    """A torus in millimetres: vertices and outward-facing quads (counter-clockwise)."""
    vertices: list[Vertex] = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        for j in range(sides):
            b = 2 * math.pi * j / sides
            radius = major + minor * math.cos(b)
            vertices.append((radius * math.cos(a), radius * math.sin(a), minor * math.sin(b)))
    quads = []
    for i in range(segments):
        for j in range(sides):
            a = i * sides + j
            b = ((i + 1) % segments) * sides + j
            c = ((i + 1) % segments) * sides + (j + 1) % sides
            d = i * sides + (j + 1) % sides
            quads.append((a, b, c, d))
    return vertices, quads


def triangles(quads: list[tuple[int, int, int, int]]) -> list[tuple[int, int, int]]:
    return [triangle for a, b, c, d in quads for triangle in ((a, b, c), (a, c, d))]


def _normal(a: Vertex, b: Vertex, c: Vertex) -> Vertex:
    u = tuple(b[k] - a[k] for k in range(3))
    v = tuple(c[k] - a[k] for k in range(3))
    n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    length = math.sqrt(sum(x * x for x in n)) or 1.0
    return (n[0] / length, n[1] / length, n[2] / length)


def stl_binary(vertices: list[Vertex], tris: list[tuple[int, int, int]], header: bytes = b'Synthetic binary STL mesh sample') -> bytes:
    data = header[:80].ljust(80, b' ') + struct.pack('<I', len(tris))
    for a, b, c in tris:
        corners = (vertices[a], vertices[b], vertices[c])
        data += struct.pack('<12fH', *_normal(*corners), *[x for corner in corners for x in corner], 0)
    return data


def stl_ascii(vertices: list[Vertex], tris: list[tuple[int, int, int]], name: str = 'synthetic') -> bytes:
    lines = [f'solid {name}']
    for a, b, c in tris:
        corners = (vertices[a], vertices[b], vertices[c])
        n = _normal(*corners)
        lines.append(f'  facet normal {n[0]:.6f} {n[1]:.6f} {n[2]:.6f}')
        lines.append('    outer loop')
        lines.extend(f'      vertex {x:.6f} {y:.6f} {z:.6f}' for x, y, z in corners)
        lines.append('    endloop')
        lines.append('  endfacet')
    lines.append(f'endsolid {name}')
    return ('\n'.join(lines) + '\n').encode('ascii')


def obj_text(vertices: list[Vertex], quads: list[tuple[int, int, int, int]], comment: str = 'Synthetic OBJ mesh sample') -> bytes:
    lines = [f'# {comment}', 'mtllib synthetic.mtl', 'o torus']
    lines.extend(f'v {x:.6f} {y:.6f} {z:.6f}' for x, y, z in vertices)
    lines.append('usemtl synthetic')
    lines.extend('f ' + ' '.join(str(i + 1) for i in quad) for quad in quads)
    return ('\n'.join(lines) + '\n').encode('ascii')


def obj_relative(vertices: list[Vertex], quads: list[tuple[int, int, int, int]], comment: str) -> bytes:
    """OBJ whose faces use v/vt/vn references with negative (relative) indices, after all vertices."""
    count = len(vertices)
    lines = [f'# {comment}', 'g synthetic']
    lines.extend(f'v {x:.6f} {y:.6f} {z:.6f}' for x, y, z in vertices)
    lines.append('vt 0 0')
    lines.append('vn 0 0 1')
    for quad in quads:
        lines.append('f ' + ' '.join(f'{i - count}/-1/-1' for i in quad))
    return ('\n'.join(lines) + '\n').encode('ascii')


def _ply_header(kind: str, vertex_count: int, face_count: int, comment: str) -> bytes:
    return ('ply\n' f'format {kind} 1.0\n' f'comment {comment}\n' f'element vertex {vertex_count}\n'
            'property float x\nproperty float y\nproperty float z\n'
            f'element face {face_count}\nproperty list uchar int vertex_indices\nend_header\n').encode('ascii')


def ply_ascii(vertices: list[Vertex], quads: list[tuple[int, int, int, int]], comment: str = 'Synthetic PLY mesh sample') -> bytes:
    lines = [f'{x:.6f} {y:.6f} {z:.6f}' for x, y, z in vertices]
    lines.extend('4 ' + ' '.join(str(i) for i in quad) for quad in quads)
    return _ply_header('ascii', len(vertices), len(quads), comment) + ('\n'.join(lines) + '\n').encode('ascii')


def ply_binary(vertices: list[Vertex], quads: list[tuple[int, int, int, int]], big_endian: bool = False,
               comment: str = 'Synthetic binary PLY mesh sample') -> bytes:
    order = '>' if big_endian else '<'
    kind = 'binary_big_endian' if big_endian else 'binary_little_endian'
    body = b''.join(struct.pack(order + '3f', *vertex) for vertex in vertices)
    body += b''.join(struct.pack(order + 'B4i', 4, *quad) for quad in quads)
    return _ply_header(kind, len(vertices), len(quads), comment) + body


_CONTENT_TYPES = ('<?xml version="1.0" encoding="UTF-8"?>'
                  '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                  '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                  '<Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/></Types>')
_RELATIONSHIPS = ('<?xml version="1.0" encoding="UTF-8"?>'
                  '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                  '<Relationship Target="/3D/3dmodel.model" Id="rel0" '
                  'Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/></Relationships>')


def threemf(vertices: list[Vertex], tris: list[tuple[int, int, int]], unit: str = 'millimeter',
            composed: bool = False, title: str = 'Synthetic 3MF mesh sample') -> bytes:
    """A 3MF package. `composed` builds two instances of the mesh through a component list, with
    transforms on the components and on the build item, to exercise the transform composition."""
    vertex_xml = ''.join(f'<vertex x="{x:.6f}" y="{y:.6f}" z="{z:.6f}"/>' for x, y, z in vertices)
    triangle_xml = ''.join(f'<triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in tris)
    resources = f'<object id="1" type="model"><mesh><vertices>{vertex_xml}</vertices><triangles>{triangle_xml}</triangles></mesh></object>'
    if composed:
        resources += ('<object id="2" type="model"><components>'
                      '<component objectid="1"/>'
                      '<component objectid="1" transform="1 0 0 0 1 0 0 0 1 30 0 0"/>'
                      '</components></object>')
        build = '<item objectid="2" transform="1 0 0 0 1 0 0 0 1 0 0 5"/>'
    else:
        build = '<item objectid="1"/>'
    model = ('<?xml version="1.0" encoding="UTF-8"?>'
             f'<model unit="{unit}" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">'
             f'<metadata name="Title">{title}</metadata><resources>{resources}</resources><build>{build}</build></model>')
    output = BytesIO()
    with zipfile.ZipFile(output, 'w') as archive:
        for name, text in (('[Content_Types].xml', _CONTENT_TYPES), ('_rels/.rels', _RELATIONSHIPS), ('3D/3dmodel.model', model)):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, text.encode('utf-8'))
    return output.getvalue()
