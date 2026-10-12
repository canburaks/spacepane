#!/usr/bin/env python3
"""Check the machine-readable host matrix (decision 027, Q-170): what was observed in Finder, per format and surface.

    python3 script/check_host_matrix.py                  # check docs/validation/host-matrix.json against the catalog
    python3 script/check_host_matrix.py --matrix PATH --catalog PATH --root DIR

The matrix is a claim register, not a test result. Every cell says what a person saw on a named Mac or says that
nothing was seen. This check cannot observe Finder; it keeps the register honest and complete:

    schema      schemaVersion 1; the top-level keys, host keys, format keys and surface keys are exactly the
                documented ones, so a misspelled key cannot silently turn a claim into "not observed".
    catalog     every format id of Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json
                appears exactly once, and no other id does. A new catalog format fails here until its row exists.
    surfaces    every format has `finderPreview`, `finderThumbnail` and `quickLookPanel`, each with one outcome:
                  provider       this app's own content was seen on that surface
                  otherProvider  another provider's content was seen
                  generic        only a generic icon and metadata were seen
                  declined       the type was switched off or unsupported on that host and said so
                  notObserved    nothing was seen (the default; carries no host and no record)
    citations   every outcome other than `notObserved` names a host that is listed, and a record: the cell's own
                `record` or else the host's. A record is a file under docs/validation (an `#anchor` must match a
                heading of that file). A host's date is not later than `generated`.
    catalog     a format the catalog gives no thumbnail (`thumbnail: none`) cannot have a `provider` thumbnail.
    resolved    a `resolvedType` is allowed only for a format with at least one observed surface.

Surfaces: `quickLookPanel` is the Space-bar panel; `finderPreview` is the preview pane or column preview;
`finderThumbnail` is a Finder icon or thumbnail. Gallery, Spotlight, full screen and multi-selection have no cell
yet; adding one raises `schemaVersion`.

Optional keys beyond the minimal schema (the website's data sync may ignore them): `hosts[].identity` (the bundle
identity that was installed on that Mac), `formats[].resolvedType` (the type macOS resolved for the fixture) and
`surfaces.*.record` (the record for that cell when it differs from the host's).

Plain Python 3.9 or newer and the standard library only. Exit status 0 when the matrix is complete and consistent,
1 when it has problems (one per line), 2 for usage errors. `script/test_check_host_matrix.py` covers the rules.
"""
from __future__ import annotations

import argparse
import datetime
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[1]
MATRIX_PATH = "docs/validation/host-matrix.json"
CATALOG_PATH = "Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json"
RECORD_DIRECTORY = "docs/validation/"

SCHEMA_VERSION = 1
SURFACES = ("finderPreview", "finderThumbnail", "quickLookPanel")
OUTCOMES = ("provider", "otherProvider", "generic", "declined", "notObserved")
SIGNINGS = ("development", "distribution", "testflight", "unsigned")

TOP_KEYS = ("schemaVersion", "generated", "hosts", "formats")
HOST_REQUIRED = ("id", "os", "hardware", "signing", "date", "record")
HOST_OPTIONAL = ("identity",)
FORMAT_REQUIRED = ("id", "surfaces")
FORMAT_OPTIONAL = ("resolvedType",)
CELL_KEYS = ("outcome", "host", "record", "note")

HOST_ID = re.compile(r"^[a-z0-9][a-z0-9.-]{0,63}$")
FORMAT_ID = re.compile(r"^[a-z0-9][a-z0-9.-]*$")
TYPE_IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]*$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
HEADING = re.compile(r"^#{1,6}[ \t]+(.+?)[ \t]*#*[ \t]*$")
MAXIMUM_NOTE = 240
MAXIMUM_TEXT = 200


# ---------------------------------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------------------------------

def read_json(path: Path) -> Tuple[Any, Optional[str]]:
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except OSError as error:
        return None, f"cannot read {path}: {error.strerror or error}"
    except ValueError as error:
        return None, f"{path} is not valid JSON: {error}"


def catalog_thumbnails(catalog: Any) -> Tuple[Dict[str, str], Optional[str]]:
    """Format id -> thumbnail policy for every catalog format, or an error."""
    entries = catalog.get("formats") if isinstance(catalog, dict) else None
    if not isinstance(entries, list) or not entries:
        return {}, "the catalog has no `formats` list"
    result: Dict[str, str] = {}
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
            return {}, "a catalog format has no string `id`"
        if entry["id"] in result:
            return {}, f"the catalog lists `{entry['id']}` twice"
        policy = entry.get("thumbnail")
        result[entry["id"]] = policy if isinstance(policy, str) else ""
    return result, None


def heading_slug(text: str) -> str:
    """GitHub's anchor for a heading: lower case, punctuation dropped, spaces to hyphens."""
    lowered = text.strip().lower()
    kept = "".join(character for character in lowered if character.isalnum() or character in "_- ")
    return kept.replace(" ", "-")


def heading_slugs(markdown: str) -> Set[str]:
    slugs: Set[str] = set()
    fenced = False
    for line in markdown.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            fenced = not fenced
            continue
        if fenced:
            continue
        match = HEADING.match(line)
        if match:
            slugs.add(heading_slug(match.group(1)))
    return slugs


# ---------------------------------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------------------------------

def is_text(value: Any, limit: int = MAXIMUM_TEXT) -> bool:
    return (isinstance(value, str) and value != "" and value == value.strip() and "\n" not in value
            and "\r" not in value and len(value) <= limit)


def valid_date(value: Any) -> Optional[datetime.date]:
    if not isinstance(value, str) or not DATE.match(value):
        return None
    try:
        return datetime.date.fromisoformat(value)
    except ValueError:
        return None


def key_problems(where: str, value: Dict[str, Any], required: Sequence[str], optional: Sequence[str]) -> List[str]:
    problems = [f"{where}: missing key `{key}`" for key in required if key not in value]
    allowed = set(required) | set(optional)
    problems += [f"{where}: unknown key `{key}` (allowed: {', '.join(sorted(allowed))})"
                 for key in value if key not in allowed]
    return problems


def record_problem(root: Path, value: Any) -> Optional[str]:
    """Why a record citation is not acceptable, or None."""
    if not isinstance(value, str) or not value:
        return "the record is not a non-empty string"
    path_text, _, fragment = value.partition("#")
    if value.count("#") > 1 or (value.endswith("#")):
        return f"the record `{value}` has a malformed anchor"
    if (path_text.startswith("/") or "\\" in path_text or ".." in path_text.split("/")
            or not path_text.startswith(RECORD_DIRECTORY) or not path_text.endswith(".md")):
        return f"the record `{value}` is not a Markdown file under {RECORD_DIRECTORY}"
    path = root / path_text
    if not path.is_file():
        return f"the record `{path_text}` does not exist"
    if fragment:
        try:
            slugs = heading_slugs(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError) as error:
            return f"the record `{path_text}` cannot be read: {error}"
        if fragment not in slugs:
            return f"the record `{path_text}` has no heading for the anchor `#{fragment}`"
    return None


def validate_hosts(matrix: Dict[str, Any], root: Path, generated: Optional[datetime.date]) -> Tuple[List[str], Dict[str, Dict[str, Any]]]:
    problems: List[str] = []
    hosts = matrix.get("hosts")
    known: Dict[str, Dict[str, Any]] = {}
    if not isinstance(hosts, list):
        return ["hosts: not a list"], known
    for index, host in enumerate(hosts):
        label = f"hosts[{index}]"
        if not isinstance(host, dict):
            problems.append(f"{label}: not an object")
            continue
        problems += key_problems(label, host, HOST_REQUIRED, HOST_OPTIONAL)
        identifier = host.get("id")
        if isinstance(identifier, str) and HOST_ID.match(identifier):
            label = f"hosts[{identifier}]"
            if identifier in known:
                problems.append(f"{label}: the host id is used twice")
            known.setdefault(identifier, host)
        elif "id" in host:
            problems.append(f"{label}: `id` must match {HOST_ID.pattern}")
        for key in ("os", "hardware") + HOST_OPTIONAL:
            if key in host and not is_text(host[key]):
                problems.append(f"{label}: `{key}` must be one line of text of at most {MAXIMUM_TEXT} characters")
        if "signing" in host and host["signing"] not in SIGNINGS:
            problems.append(f"{label}: `signing` must be one of {', '.join(SIGNINGS)}")
        if "date" in host:
            date = valid_date(host["date"])
            if date is None:
                problems.append(f"{label}: `date` must be a calendar date written YYYY-MM-DD")
            elif generated is not None and date > generated:
                problems.append(f"{label}: the date {host['date']} is later than `generated`")
        if "record" in host:
            problem = record_problem(root, host["record"])
            if problem:
                problems.append(f"{label}: {problem}")
    return problems, known


def validate_cell(where: str, cell: Any, hosts: Dict[str, Dict[str, Any]], root: Path,
                  surface: str, thumbnail_policy: str) -> Tuple[List[str], bool]:
    """Problems of one surface cell, and whether it claims an observation."""
    if not isinstance(cell, dict):
        return [f"{where}: not an object"], False
    problems = [f"{where}: unknown key `{key}` (allowed: {', '.join(CELL_KEYS)})" for key in cell if key not in CELL_KEYS]
    outcome = cell.get("outcome")
    if outcome not in OUTCOMES:
        return problems + [f"{where}: `outcome` must be one of {', '.join(OUTCOMES)}"], False
    if "note" in cell and not is_text(cell["note"], MAXIMUM_NOTE) and cell["note"] != "":
        problems.append(f"{where}: `note` must be one line of at most {MAXIMUM_NOTE} characters, without edge spaces")
    if outcome == "notObserved":
        for key in ("host", "record"):
            if key in cell:
                problems.append(f"{where}: a notObserved cell cannot carry `{key}`")
        return problems, False
    host = cell.get("host")
    if not isinstance(host, str) or host not in hosts:
        problems.append(f"{where}: `{outcome}` must cite a host that is listed in `hosts`")
        record: Any = cell.get("record")
    else:
        record = cell.get("record", hosts[host].get("record"))
    if "record" in cell:
        problem = record_problem(root, cell["record"])
        if problem:
            problems.append(f"{where}: {problem}")
    elif record is None:
        problems.append(f"{where}: `{outcome}` must cite a record")
    if surface == "finderThumbnail" and outcome == "provider" and thumbnail_policy == "none":
        problems.append(f"{where}: the catalog gives this format no thumbnail, so a `provider` thumbnail contradicts it")
    return problems, True


def validate_formats(matrix: Dict[str, Any], thumbnails: Dict[str, str], hosts: Dict[str, Dict[str, Any]],
                     root: Path) -> List[str]:
    problems: List[str] = []
    formats = matrix.get("formats")
    if not isinstance(formats, list):
        return ["formats: not a list"]
    seen: Dict[str, int] = {}
    for index, entry in enumerate(formats):
        label = f"formats[{index}]"
        if not isinstance(entry, dict):
            problems.append(f"{label}: not an object")
            continue
        problems += key_problems(label, entry, FORMAT_REQUIRED, FORMAT_OPTIONAL)
        identifier = entry.get("id")
        if not isinstance(identifier, str) or not FORMAT_ID.match(identifier):
            problems.append(f"{label}: `id` must be a catalog format id")
            continue
        label = f"formats[{identifier}]"
        seen[identifier] = seen.get(identifier, 0) + 1
        if seen[identifier] == 2:
            problems.append(f"{label}: the format appears more than once")
        if identifier not in thumbnails:
            problems.append(f"{label}: the id is not in the catalog")
        surfaces = entry.get("surfaces")
        observed = False
        if not isinstance(surfaces, dict):
            problems.append(f"{label}.surfaces: not an object")
        else:
            problems += [f"{label}.surfaces: missing `{name}`" for name in SURFACES if name not in surfaces]
            problems += [f"{label}.surfaces: unknown surface `{name}` (allowed: {', '.join(SURFACES)})"
                         for name in surfaces if name not in SURFACES]
            for name in SURFACES:
                if name in surfaces:
                    cell_problems, claims = validate_cell(f"{label}.surfaces.{name}", surfaces[name], hosts, root,
                                                          name, thumbnails.get(identifier, ""))
                    problems += cell_problems
                    observed = observed or claims
        if "resolvedType" in entry:
            if not (isinstance(entry["resolvedType"], str) and TYPE_IDENTIFIER.match(entry["resolvedType"])):
                problems.append(f"{label}: `resolvedType` must be a type identifier")
            elif not observed:
                problems.append(f"{label}: a `resolvedType` needs at least one observed surface")
    missing = sorted(set(thumbnails) - set(seen))
    if missing:
        problems.append("formats: the catalog formats without a row: " + ", ".join(missing))
    return problems


def validate(matrix: Any, thumbnails: Dict[str, str], root: Path) -> List[str]:
    """Every problem of a loaded matrix; an empty list means the matrix is complete and consistent."""
    if not isinstance(matrix, dict):
        return ["the matrix is not a JSON object"]
    problems = key_problems("matrix", matrix, TOP_KEYS, ())
    version = matrix.get("schemaVersion")
    if isinstance(version, bool) or version != SCHEMA_VERSION:
        problems.append(f"schemaVersion must be {SCHEMA_VERSION}")
    generated = valid_date(matrix.get("generated"))
    if generated is None:
        problems.append("generated must be a calendar date written YYYY-MM-DD")
    host_problems, hosts = validate_hosts(matrix, root, generated)
    return problems + host_problems + validate_formats(matrix, thumbnails, hosts, root)


def summary(matrix: Dict[str, Any]) -> str:
    """One line: the size of the matrix and how many cells claim each outcome."""
    counts: Dict[str, int] = {}
    for entry in matrix.get("formats", []):
        for cell in entry.get("surfaces", {}).values():
            outcome = cell.get("outcome", "?")
            counts[outcome] = counts.get(outcome, 0) + 1
    observed = [f"{counts[name]} {name}" for name in OUTCOMES if name != "notObserved" and counts.get(name)]
    detail = ", ".join(observed) if observed else "no observation"
    return (f"host matrix ok: {len(matrix.get('formats', []))} formats, {len(matrix.get('hosts', []))} host(s), "
            f"{counts.get('notObserved', 0)} cells notObserved; claimed: {detail}")


# ---------------------------------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------------------------------

def run(root: Path, matrix_path: Path, catalog_path: Path) -> Tuple[int, List[str]]:
    matrix, error = read_json(matrix_path)
    if error:
        return 1, [error]
    catalog, error = read_json(catalog_path)
    if error:
        return 1, [error]
    thumbnails, error = catalog_thumbnails(catalog)
    if error:
        return 1, [error]
    problems = validate(matrix, thumbnails, root)
    if problems:
        return 1, problems + [f"host matrix: {len(problems)} problem(s) in {matrix_path}"]
    return 0, [summary(matrix)]


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Check docs/validation/host-matrix.json against the format catalog.")
    parser.add_argument("--root", type=Path, default=ROOT, help="repository root that record paths are relative to")
    parser.add_argument("--matrix", type=Path, help=f"default: <root>/{MATRIX_PATH}")
    parser.add_argument("--catalog", type=Path, help=f"default: <root>/{CATALOG_PATH}")
    arguments = parser.parse_args(argv)
    root = arguments.root.resolve()
    code, lines = run(root, arguments.matrix or root / MATRIX_PATH, arguments.catalog or root / CATALOG_PATH)
    print("\n".join(lines), file=sys.stdout if code == 0 else sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
