#!/usr/bin/env python3
"""Write the synthetic files that the App Store screenshots show.

Everything here is invented for a fictional project named Harbor. The few secret-looking values are fake and
exist so that a capture shows concealment; none is a real credential. The output is deterministic, so a
screenshot can be retaken later from identical files.

usage: generate_store_demo_files.py [output directory]   (default: .build/store-screenshots/Harbor)
"""
import json
import math
import pathlib
import plistlib
import sqlite3
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FAKE_TOKEN = "harbor-demo-token-not-a-real-credential"
FAKE_PASSWORD = "harbor-demo-password-not-real"
STATIONS = [
    ("HBR-01", "North Pier", 41.0214, 28.9731, "2024-03-12", 1),
    ("HBR-02", "Lighthouse", 41.0166, 28.9853, "2024-03-12", 1),
    ("HBR-03", "Ferry Terminal", 41.0092, 28.9760, "2024-05-02", 1),
    ("HBR-04", "Breakwater East", 41.0257, 28.9912, "2024-07-19", 0),
    ("HBR-05", "Customs Quay", 41.0131, 28.9689, "2025-01-08", 1),
    ("HBR-06", "Dry Dock", 41.0305, 28.9644, "2025-02-21", 1),
]


def write_settings(directory):
    settings = {
        "service": {"name": "harbor-api", "version": "1.4.0", "region": "eu-central", "port": 8443},
        "database": {"host": "db.harbor.example", "port": 5432, "name": "harbor", "user": "harbor_app",
                     "password": FAKE_PASSWORD, "poolSize": 12, "ssl": True},
        "auth": {"issuer": "https://login.harbor.example", "apiToken": FAKE_TOKEN, "sessionMinutes": 45},
        "stations": [{"id": code, "name": name, "active": bool(active)} for code, name, _, _, _, active in STATIONS[:4]],
        "features": {"tideForecast": True, "stormAlerts": True, "publicMap": False},
        "logging": {"level": "info", "retainDays": 30, "redactFields": ["password", "apiToken"]},
    }
    (directory / "settings.json").write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")


def write_config(directory):
    (directory / "deploy.yaml").write_text(f"""# Harbor deployment (synthetic sample)
service: harbor-api
replicas: 3
image: registry.harbor.example/harbor-api:1.4.0

database:
  host: db.harbor.example
  port: 5432
  user: harbor_app
  password: {FAKE_PASSWORD}

auth:
  issuer: https://login.harbor.example
  api_token: {FAKE_TOKEN}
  client_secret: harbor-demo-client-secret-not-real

alerts:
  storm_wind_knots: 34
  notify:
    - harbor-master@harbor.example
    - duty-officer@harbor.example

resources:
  cpu: 500m
  memory: 512Mi
""", encoding="utf-8")


def write_readme(directory):
    (directory / "README.md").write_text("""# Harbor

Harbor collects wind, tide and pressure readings from six weather stations around the port and
serves them to the harbor master's dashboard.

## Files

- `settings.json`: service configuration
- `deploy.yaml`: deployment values
- `stations.sqlite`: stations and their readings
- `tide-analysis.ipynb`: the weekly tide notebook
- `release-1.4.zip`: the packaged release
- `winch-gear.step`: the winch gear model

## Quick start

```sh
harbor serve --config settings.json
harbor stations list
```

## Stations

| Code | Name | Since |
|---|---|---|
| HBR-01 | North Pier | 2024 |
| HBR-02 | Lighthouse | 2024 |
| HBR-03 | Ferry Terminal | 2024 |

> Storm alerts are sent when sustained wind passes 34 knots.

## Roadmap

1. Tide forecast for the next 72 hours
2. Public map of live readings
3. Offline mode for the pilot boats
""", encoding="utf-8")


def write_notebook(directory):
    def markdown(text):
        return {"cell_type": "markdown", "metadata": {}, "source": text.splitlines(keepends=True)}

    def code(count, text, output=None):
        outputs = [] if output is None else [
            {"output_type": "stream", "name": "stdout", "text": output.splitlines(keepends=True)}]
        return {"cell_type": "code", "execution_count": count, "metadata": {}, "outputs": outputs,
                "source": text.splitlines(keepends=True)}

    notebook = {
        "cells": [
            markdown("# Weekly tide analysis\n\nReadings from the six Harbor stations, 6 to 12 October."),
            code(1, "import statistics\n\nreadings = load_readings('stations.sqlite', week=41)\nlen(readings)", "1008\n"),
            markdown("## Highest tides"),
            code(2, "for station, values in by_station(readings).items():\n"
                    "    print(f'{station}: {max(values):.2f} m')",
                 "HBR-01: 2.41 m\nHBR-02: 2.38 m\nHBR-03: 2.52 m\nHBR-04: 2.47 m\nHBR-05: 2.36 m\nHBR-06: 2.44 m\n"),
            markdown("## Storm check\n\nSustained wind above **34 knots** raises an alert."),
            code(3, f"api_token = '{FAKE_TOKEN}'\nalerts = storm_alerts(readings, threshold=34)\nprint(len(alerts), 'alerts')",
                 "2 alerts\n"),
        ],
        "metadata": {"kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
                     "language_info": {"name": "python"}},
        "nbformat": 4,
        "nbformat_minor": 5,
    }
    (directory / "tide-analysis.ipynb").write_text(json.dumps(notebook, indent=1) + "\n", encoding="utf-8")


def write_database(directory):
    path = directory / "stations.sqlite"
    path.unlink(missing_ok=True)
    connection = sqlite3.connect(path)
    connection.executescript("""
        CREATE TABLE stations (id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
                               latitude REAL, longitude REAL, installed_on TEXT, active INTEGER NOT NULL DEFAULT 1);
        CREATE TABLE readings (id INTEGER PRIMARY KEY, station_id INTEGER NOT NULL REFERENCES stations(id),
                               taken_at TEXT NOT NULL, wind_knots REAL, tide_m REAL, pressure_hpa REAL);
        CREATE TABLE alerts (id INTEGER PRIMARY KEY, station_id INTEGER NOT NULL REFERENCES stations(id),
                             raised_at TEXT NOT NULL, kind TEXT NOT NULL, detail TEXT);
        CREATE TABLE operators (id INTEGER PRIMARY KEY, name TEXT NOT NULL, role TEXT NOT NULL);
        CREATE INDEX readings_by_station ON readings(station_id, taken_at);
    """)
    connection.executemany("INSERT INTO stations (code, name, latitude, longitude, installed_on, active) VALUES (?,?,?,?,?,?)", STATIONS)
    readings = []
    for station in range(1, 7):
        for step in range(168):
            day, hour = 6 + step // 24, step % 24
            readings.append((station, f"2026-10-{day:02d}T{hour:02d}:00:00Z",
                             round(8 + (step * 7 + station * 3) % 23 + station * 0.4, 1),
                             round(1.2 + ((step * 5 + station) % 13) / 10, 2),
                             round(1009 + (step * 3 + station * 2) % 17 + 0.3, 1)))
    connection.executemany("INSERT INTO readings (station_id, taken_at, wind_knots, tide_m, pressure_hpa) VALUES (?,?,?,?,?)", readings)
    connection.executemany("INSERT INTO alerts (station_id, raised_at, kind, detail) VALUES (?,?,?,?)", [
        (3, "2026-10-08T03:00:00Z", "storm", "Sustained wind 36 knots"),
        (4, "2026-10-08T04:00:00Z", "storm", "Sustained wind 35 knots"),
        (1, "2026-10-10T17:00:00Z", "tide", "High tide 2.41 m"),
    ])
    connection.executemany("INSERT INTO operators (name, role) VALUES (?,?)", [
        ("Duty Officer", "operations"), ("Harbor Master", "admin"), ("Pilot Desk", "viewer")])
    connection.commit()
    connection.execute("VACUUM")
    connection.close()


def write_archive(directory):
    entries = {
        "harbor-1.4/README.md": "# Harbor 1.4\n",
        "harbor-1.4/LICENSE": "Synthetic sample.\n",
        "harbor-1.4/bin/harbor": "#!/bin/sh\necho harbor\n",
        "harbor-1.4/config/settings.example.json": "{}\n",
        "harbor-1.4/config/deploy.example.yaml": "service: harbor-api\n",
        "harbor-1.4/docs/stations.md": "# Stations\n" + "North Pier\n" * 40,
        "harbor-1.4/docs/alerts.md": "# Alerts\n" + "Storm above 34 knots\n" * 30,
        "harbor-1.4/docs/changelog.md": "# Changelog\n" + "- Tide forecast\n" * 60,
        "harbor-1.4/lib/readings.py": "def load_readings():\n    return []\n" * 25,
        "harbor-1.4/lib/alerts.py": "def storm_alerts():\n    return []\n" * 18,
        "harbor-1.4/lib/tides.py": "def forecast():\n    return []\n" * 32,
        "harbor-1.4/migrations/001_stations.sql": "CREATE TABLE stations (id INTEGER PRIMARY KEY);\n",
        "harbor-1.4/migrations/002_readings.sql": "CREATE TABLE readings (id INTEGER PRIMARY KEY);\n",
        "harbor-1.4/migrations/003_alerts.sql": "CREATE TABLE alerts (id INTEGER PRIMARY KEY);\n",
    }
    folders = sorted({str(pathlib.PurePosixPath(name).parent) + "/" for name in entries}
                     | {"harbor-1.4/"})
    with zipfile.ZipFile(directory / "release-1.4.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for name in folders:
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 9, 12, 0, 0))
            info.external_attr = (0o40755 << 16) | 0x10
            archive.writestr(info, "")
        for name, text in entries.items():
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 9, 12, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, text)


def gear_profile(teeth=14, root=30.0, tip=38.0):
    """A gear outline, counter-clockwise: four corners per tooth."""
    points = []
    pitch = 2 * math.pi / teeth
    for tooth in range(teeth):
        start = tooth * pitch
        for radius, fraction in ((root, 0.00), (tip, 0.16), (tip, 0.44), (root, 0.60)):
            angle = start + fraction * pitch
            points.append((radius * math.cos(angle), radius * math.sin(angle)))
    return points


def hexagon(radius=11.0):
    return [(radius * math.cos(math.pi / 3 * corner), radius * math.sin(math.pi / 3 * corner)) for corner in range(6)]


def write_step(directory, height=14.0):
    """A faceted solid as AP214 text: a gear outline with a hexagonal bore, extruded along Z.

    Every face is a plane and every edge a line, so the file needs no curve fitting. Each edge is used once in
    each direction, which is what makes the shell closed.
    """
    lines = []

    def add(text):
        lines.append(text)
        return len(lines)

    def number(value):
        text = f"{value:.6f}".rstrip("0")
        return text + "0" if text.endswith(".") else text

    def point(x, y, z):
        return add(f"CARTESIAN_POINT('',({number(x)},{number(y)},{number(z)}))")

    def direction(x, y, z):
        return add(f"DIRECTION('',({number(x)},{number(y)},{number(z)}))")

    application = add("APPLICATION_CONTEXT('core data for automotive mechanical design processes')")
    add(f"APPLICATION_PROTOCOL_DEFINITION('international standard','automotive_design',2000,#{application})")
    product_context = add(f"PRODUCT_CONTEXT('',#{application},'mechanical')")
    product = add(f"PRODUCT('Harbor winch gear','Harbor winch gear','',(#{product_context}))")
    formation = add(f"PRODUCT_DEFINITION_FORMATION('','',#{product})")
    definition_context = add(f"PRODUCT_DEFINITION_CONTEXT('part definition',#{application},'design')")
    definition = add(f"PRODUCT_DEFINITION('design','',#{formation},#{definition_context})")
    shape = add(f"PRODUCT_DEFINITION_SHAPE('','',#{definition})")
    length = add("( LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.) )")
    angle = add("( NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.) )")
    solid_angle = add("( NAMED_UNIT(*) SI_UNIT($,.STERADIAN.) SOLID_ANGLE_UNIT() )")
    uncertainty = add(f"UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(1.E-07),#{length},'distance_accuracy_value','confusion accuracy')")
    context = add(f"( GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNCERTAINTY_ASSIGNED_CONTEXT((#{uncertainty})) "
                  f"GLOBAL_UNIT_ASSIGNED_CONTEXT((#{length},#{angle},#{solid_angle})) REPRESENTATION_CONTEXT('Context #1','3D Context with UNIT and UNCERTAINTY') )")

    def edge(start, end, start_vertex, end_vertex):
        delta = [b - a for a, b in zip(start, end)]
        size = math.sqrt(sum(part * part for part in delta))
        vector = add(f"VECTOR('',#{direction(*[part / size for part in delta])},{number(size)})")
        line = add(f"LINE('',#{point(*start)},#{vector})")
        return add(f"EDGE_CURVE('',#{start_vertex},#{end_vertex},#{line},.T.)")

    def loop(uses):
        oriented = [add(f"ORIENTED_EDGE('',*,*,#{curve},{'.T.' if forward else '.F.'})") for curve, forward in uses]
        return add("EDGE_LOOP('',(" + ",".join(f"#{item}" for item in oriented) + "))")

    def face(origin, normal, reference, outer, inner=()):
        placement = add(f"AXIS2_PLACEMENT_3D('',#{point(*origin)},#{direction(*normal)},#{direction(*reference)})")
        plane = add(f"PLANE('',#{placement})")
        bounds = [add(f"FACE_OUTER_BOUND('',#{outer},.T.)")] + [add(f"FACE_BOUND('',#{item},.T.)") for item in inner]
        return add("ADVANCED_FACE('',(" + ",".join(f"#{item}" for item in bounds) + f"),#{plane},.T.)")

    faces, top_loops, bottom_loops = [], [], []
    # The outline runs counter-clockwise and the bore clockwise, so the material is always on the left.
    for ring in (gear_profile(), list(reversed(hexagon()))):
        count = len(ring)
        bottom = [add(f"VERTEX_POINT('',#{point(x, y, 0.0)})") for x, y in ring]
        top = [add(f"VERTEX_POINT('',#{point(x, y, height)})") for x, y in ring]
        bottom_edges, top_edges, risers = [], [], []
        for index, (x, y) in enumerate(ring):
            following = (index + 1) % count
            next_x, next_y = ring[following]
            bottom_edges.append(edge((x, y, 0.0), (next_x, next_y, 0.0), bottom[index], bottom[following]))
            top_edges.append(edge((x, y, height), (next_x, next_y, height), top[index], top[following]))
            risers.append(edge((x, y, 0.0), (x, y, height), bottom[index], top[index]))
        for index, (x, y) in enumerate(ring):
            following = (index + 1) % count
            next_x, next_y = ring[following]
            span = math.hypot(next_x - x, next_y - y)
            side = loop([(bottom_edges[index], True), (risers[following], True), (top_edges[index], False), (risers[index], False)])
            faces.append(face((x, y, 0.0), ((next_y - y) / span, -(next_x - x) / span, 0.0), (0.0, 0.0, 1.0), side))
        top_loops.append(loop([(curve, True) for curve in top_edges]))
        bottom_loops.append(loop([(curve, False) for curve in reversed(bottom_edges)]))
    faces.append(face((0.0, 0.0, height), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), top_loops[0], top_loops[1:]))
    faces.append(face((0.0, 0.0, 0.0), (0.0, 0.0, -1.0), (1.0, 0.0, 0.0), bottom_loops[0], bottom_loops[1:]))

    shell = add("CLOSED_SHELL('',(" + ",".join(f"#{item}" for item in faces) + "))")
    solid = add(f"MANIFOLD_SOLID_BREP('',#{shell})")
    axis = add(f"AXIS2_PLACEMENT_3D('',#{point(0.0, 0.0, 0.0)},#{direction(0.0, 0.0, 1.0)},#{direction(1.0, 0.0, 0.0)})")
    representation = add(f"ADVANCED_BREP_SHAPE_REPRESENTATION('',(#{axis},#{solid}),#{context})")
    add(f"SHAPE_DEFINITION_REPRESENTATION(#{shape},#{representation})")
    add(f"PRODUCT_RELATED_PRODUCT_CATEGORY('part',$,(#{product}))")

    header = ("ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION(('Synthetic sample'),'2;1');\n"
              "FILE_NAME('winch-gear','2026-10-11T00:00:00',('synthetic'),('synthetic'),'generate_store_demo_files.py','SpacePane demo files','');\n"
              "FILE_SCHEMA(('AUTOMOTIVE_DESIGN { 1 0 10303 214 1 1 1 1 }'));\nENDSEC;\nDATA;\n")
    body = "".join(f"#{index} = {text};\n" for index, text in enumerate(lines, start=1))
    (directory / "winch-gear.step").write_text(header + body + "ENDSEC;\nEND-ISO-10303-21;\n", encoding="ascii")


def open_with(path, bundle_identifier="com.apple.dt.Xcode", application="/Applications/Xcode.app"):
    """Bind one file to an app, the same per-file choice Finder's Get Info "Open with" writes.

    Quick Look's panel names the app a file opens with. On the capturing Mac the default apps for notebooks and
    SQLite files are other vendors' products, and their names do not belong in a store image. The binding is an
    extended attribute on this demo file only; no default app of the system changes.
    """
    if not pathlib.Path(application).is_dir():
        return
    value = plistlib.dumps({"bundleidentifier": bundle_identifier, "path": application, "version": 0}, fmt=plistlib.FMT_BINARY)
    subprocess.run(["/usr/bin/xattr", "-wx", "com.apple.LaunchServices.OpenWith", value.hex(), str(path)], check=True)


def main():
    directory = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / ".build/store-screenshots/Harbor"
    directory.mkdir(parents=True, exist_ok=True)
    write_settings(directory)
    write_config(directory)
    write_readme(directory)
    write_notebook(directory)
    write_database(directory)
    write_archive(directory)
    write_step(directory)
    for name in ("tide-analysis.ipynb", "stations.sqlite"):
        open_with(directory / name)
    for stale in ("mooring-block.step",):
        (directory / stale).unlink(missing_ok=True)
    print(directory)


if __name__ == "__main__":
    main()
