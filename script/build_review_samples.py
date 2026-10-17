#!/usr/bin/env python3
"""Build the App Review sample archive: a small, curated set of synthetic files and a README.

    python3 script/build_review_samples.py                       # dist/review-samples/
    python3 script/build_review_samples.py --output DIRECTORY    # folder and zip into DIRECTORY
    python3 script/build_review_samples.py --check               # build in a temporary directory and cross-check

The output directory receives `SpacePane-Review-Samples/` (the files and a `README.txt`) and
`SpacePane-Review-Samples.zip`. The zip is attached in App Store Connect under App Review Information. `dist/` is
ignored by git, so the archive is never tracked.

Nothing here invents file content. The bytes come from the repository's generators, imported rather than copied:
`script/generate_host_fixtures.py` (the Finder test set), `script/generate_store_demo_files.py` (the files the store
screenshots show) and, for one Swift file, `script/generate_appearance_samples.py`. Two small plain-text files, a
Python source file and a `Makefile`, are written here because no generator makes either; they are text, not binary.
Every secret-looking value in the set is a made-up string. The set is one clear sample for each format family that
docs/release/app-store-listing.md names, so a reviewer does not have to hunt.

The result is deterministic: entries are sorted, the zip stores them uncompressed with fixed timestamps, permissions
and creator, and two runs give the same bytes.

`--check` builds into a temporary directory and fails, with one line per problem, when
  * a file named in the "Notes for App Review" or "If App Review objects" section of
    docs/release/app-store-submission.md, or in the README, is missing from the archive, or a sample is missing
    from the README;
  * the Notes are over Apple's 4,000-byte limit or still contain a bracketed placeholder;
  * a file or the zip is larger than its limit, or the README is not plain ASCII under 80 columns and 60 lines.
A file name here means a token that starts with two digits and a dash, `Makefile`, or `README.txt`.

Plain Python 3.9 or newer and the standard library only. Exit status 0 on success, 1 when a check fails.
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Dict, List, NamedTuple, Optional, Sequence, Tuple, Union

SCRIPT_DIRECTORY = Path(__file__).resolve().parent
ROOT = SCRIPT_DIRECTORY.parent
sys.path.insert(0, str(SCRIPT_DIRECTORY))

FOLDER_NAME = "SpacePane-Review-Samples"
ZIP_NAME = FOLDER_NAME + ".zip"
README_NAME = "README.txt"
DEFAULT_OUTPUT = ROOT / "dist/review-samples"
SUBMISSION = ROOT / "docs/release/app-store-submission.md"
NOTES_HEADING = "## Notes for App Review"
REPLIES_HEADING = "## If App Review objects"

# A fixed instant (the date this set was designed) so the zip never depends on the clock.
ZIP_DATE_TIME = (2026, 10, 12, 0, 0, 0)
ZIP_UNIX = 3

MAXIMUM_FILE_BYTES = 128 * 1024
MAXIMUM_ZIP_BYTES = 1024 * 1024
MAXIMUM_NOTES_BYTES = 4000  # Apple's limit for the Notes field.
README_MAXIMUM_LINES = 59
README_MAXIMUM_COLUMNS = 79

FILE_NAME_TOKEN = re.compile(r"^\d{2}-[A-Za-z][A-Za-z0-9._-]*/?$")
OTHER_FILE_NAMES = frozenset({"Makefile", README_NAME})
PLACEHOLDER = re.compile(r"\[[^\]\n]+\]|\b(?:TODO|TBD|FIXME)\b")

# Text that nothing in the archive may contain, whatever generator it came from.
UNSAFE_PATTERNS = (
    ("email address", re.compile(rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")),
    ("private key block", re.compile(rb"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("AWS access key", re.compile(rb"AKIA[0-9A-Z]{16}")),
    ("GitHub token", re.compile(rb"gh[pousr]_[A-Za-z0-9]{20,}")),
    ("telephone number", re.compile(rb"\+\d{1,3}[ -]?\(?\d{2,4}\)?[ -]?\d{3,4}[ -]?\d{3,4}")),
)

PYTHON_SAMPLE = '''"""A synthetic sample for the SpacePane review archive."""
from dataclasses import dataclass


@dataclass
class Point:
    x: float
    y: float


def distance(a: Point, b: Point) -> float:
    """Straight-line distance between two points."""
    return ((b.x - a.x) ** 2 + (b.y - a.y) ** 2) ** 0.5


if __name__ == "__main__":
    print(distance(Point(0, 0), Point(3, 4)))  # 5.0
'''

# A file named exactly Makefile has no extension; recipe lines start with a tab.
MAKEFILE_SAMPLE = (
    "# A synthetic sample: a file with no extension.\n"
    "CC ?= cc\n"
    ".PHONY: all test clean\n"
    "\n"
    "all:\n"
    "\t@echo building\n"
    "\n"
    "test: all\n"
    "\t@echo testing\n"
    "\n"
    "clean:\n"
    "\t@echo cleaning\n"
)

Content = Union[bytes, Dict[str, bytes]]


class Sample(NamedTuple):
    """One entry of the archive. `kind` says which generator `source` names a file (or constant) of."""
    name: str
    kind: str  # host, host-folder, demo, appearance or authored
    source: str
    expect: str  # at most 58 characters, ASCII; the README row


SAMPLES: Tuple[Sample, ...] = (
    Sample("01-settings.json", "demo", "settings.json", "JSON outline; fake token and password concealed"),
    Sample("02-records.jsonl", "host", "04-records.jsonl", "One row per JSON record; secret concealed"),
    Sample("03-config.yaml", "host", "05-config.yaml", "YAML as outline or source; password concealed"),
    Sample("04-config.toml", "host", "06-config.toml", "TOML as outline or source; password concealed"),
    Sample("05-document.xml", "host", "11-document.xml", "XML structure and source; password concealed"),
    Sample("06-properties.plist", "host", "12-properties.plist", "Binary property list as a readable tree"),
    Sample("07-stations.sqlite", "demo", "stations.sqlite", "Tables, columns and row counts, read-only"),
    Sample("08-release.zip", "demo", "release-1.4.zip", "Entry tree; nothing is extracted"),
    Sample("09-listing.tar", "host", "18-listing.tar", "TAR entry list"),
    Sample("10-content.gz", "host", "19-content.gz", "GZIP: the text inside, secret concealed"),
    Sample("11-listing.xip", "host", "20-listing.xip", "XIP entry list"),
    Sample("12-listing.rar", "host", "31-listing.rar", "RAR entry list"),
    Sample("13-listing.7z", "host", "32-listing.7z", "7z entry list"),
    Sample("14-folder/", "host-folder", "21-folder", "Select the folder itself: its contents"),
    Sample("15-analysis.ipynb", "demo", "tide-analysis.ipynb", "Notebook cells and saved outputs; never run"),
    Sample("16-document.md", "demo", "README.md", "Markdown with headings, a table and a Contents view"),
    Sample("17-change.patch", "host", "10-change.patch", "Diff with additions and deletions colored"),
    Sample("18-table.csv", "host", "24-table.csv", "Table; secret column concealed"),
    Sample("19-diagram.mmd", "host", "51-diagram.mmd", "Mermaid flowchart drawn, source one click away"),
    Sample("20-diagram.drawio", "host", "52-diagram.drawio", "draw.io page drawn natively"),
    Sample("21-data.parquet", "host", "71-data.parquet", "Parquet schema and row groups"),
    Sample("22-book.epub", "host", "92-book.epub", "Cover, details and chapter text"),
    Sample("23-comic.cbz", "host", "91-comic.cbz", "Comic pages and details; nothing is extracted"),
    Sample("24-captions.srt", "host", "26-captions.srt", "Subtitle cues with their times"),
    Sample("25-silent.mid", "host", "22-silent.mid", "MIDI with play and scrub controls (no sound)"),
    Sample("26-example.swift", "appearance", "SWIFT", "Source with syntax color (macOS may differ)"),
    Sample("27-example.py", "authored", "PYTHON_SAMPLE", "Source with syntax color"),
    Sample("28-binary.stl", "host", "101-binary.stl", "3D model; macOS may show its own preview"),
    Sample("29-model.obj", "host", "103-model.obj", "3D model; macOS may show its own preview"),
    Sample("30-model.ply", "host", "105-ascii.ply", "3D model; macOS may show its own preview"),
    Sample("31-model.3mf", "host", "108-model.3mf", "3D model you can turn; print size and volume"),
    Sample("32-model.gguf", "host", "111-example.gguf", "AI model summary from the header; never loaded"),
    Sample("33-extension.vsix", "host", "115-example-secret.vsix", "Editor extension card: activation, permissions"),
    Sample("34-package.whl", "host", "117-example-1.0-py3-none-any.whl", "Python package summary; nothing installed"),
    Sample("Makefile", "authored", "MAKEFILE_SAMPLE", "No extension: shown as text, highlighted"),
)

README_HEAD = """\
SpacePane review samples
Every file here is synthetic. No secret in it is real.

HOW TO TRY
1. Open SpacePane. The banner at the top of the General page has an
   "Open System Settings" button; click it and switch on SpacePane
   Preview and SpacePane Thumbnails. (macOS 15: System Settings >
   General > Login Items & Extensions > Quick Look.)
2. Unzip this folder, select a file in Finder and press Space.

macOS decides which app previews a type; if another app already does,
Quick Look may use it. An info symbol shows when SpacePane made the
preview. The fake secret is in 01-settings.json (an invented token
and password): SpacePane conceals it and leaves the file unchanged.
Other files carry the invented value synthetic-host-matrix-secret.

FILE                 WHAT TO LOOK FOR
"""


class ArchiveError(Exception):
    """A rule of this script was broken; the message says which."""


# --- Sources ------------------------------------------------------------------------------------------------------


class Sources:
    """The generators' output, made once: host fixtures, the store demo files and the shared Swift sample."""

    def __init__(self, workspace: Path):
        import generate_appearance_samples
        import generate_host_fixtures
        import generate_store_demo_files

        self.appearance = generate_appearance_samples
        # The host generator writes a fresh directory under .build/ (ignored by git) and never overwrites.
        self.host_directory = generate_host_fixtures.generate()
        self.demo_directory = workspace / "demo"
        self.demo_directory.mkdir()
        # Not main(): it also binds demo files to Xcode with an extended attribute, which a sample archive must not.
        for write in (generate_store_demo_files.write_settings, generate_store_demo_files.write_readme,
                      generate_store_demo_files.write_notebook, generate_store_demo_files.write_database,
                      generate_store_demo_files.write_archive):
            write(self.demo_directory)

    def close(self) -> None:
        shutil.rmtree(self.host_directory, ignore_errors=True)

    def content(self, sample: Sample) -> Content:
        if sample.kind == "host":
            return (self.host_directory / sample.source).read_bytes()
        if sample.kind == "demo":
            return (self.demo_directory / sample.source).read_bytes()
        if sample.kind == "host-folder":
            folder = self.host_directory / sample.source
            return {str(path.relative_to(folder)): path.read_bytes() for path in sorted(folder.rglob("*")) if path.is_file()}
        if sample.kind == "appearance":
            return getattr(self.appearance, sample.source).encode("utf-8")
        if sample.kind == "authored":
            return globals()[sample.source].encode("utf-8")
        raise ArchiveError(f"{sample.name}: unknown kind {sample.kind!r}")


# --- README -------------------------------------------------------------------------------------------------------


def readme_text() -> str:
    rows = "".join(f"{sample.name:<21}{sample.expect}\n" for sample in SAMPLES)
    return README_HEAD + rows


def readme_problems(text: str) -> List[str]:
    problems = []
    if not text.isascii():
        problems.append(f"{README_NAME} is not plain ASCII")
    lines = text.splitlines()
    if len(lines) > README_MAXIMUM_LINES:
        problems.append(f"{README_NAME} has {len(lines)} lines; the limit is {README_MAXIMUM_LINES}")
    for number, line in enumerate(lines, start=1):
        if len(line) > README_MAXIMUM_COLUMNS:
            problems.append(f"{README_NAME} line {number} is {len(line)} columns; the limit is {README_MAXIMUM_COLUMNS}")
    return problems


# --- Build --------------------------------------------------------------------------------------------------------


def collect_files() -> Dict[str, bytes]:
    """Every file of the archive, by path relative to the folder, from the generators. Nothing is written."""
    with tempfile.TemporaryDirectory(prefix="review-samples-") as workspace:
        sources = Sources(Path(workspace))
        try:
            files: Dict[str, bytes] = {}
            for sample in SAMPLES:
                content = sources.content(sample)
                if isinstance(content, dict):
                    for relative, data in content.items():
                        files[sample.name + relative] = data
                else:
                    files[sample.name] = content
        finally:
            sources.close()
    files[README_NAME] = readme_text().encode("ascii")
    return files


def content_problems(files: Dict[str, bytes]) -> List[str]:
    problems = []
    for name, data in sorted(files.items()):
        if len(data) > MAXIMUM_FILE_BYTES:
            problems.append(f"{name} is {len(data)} bytes; the limit is {MAXIMUM_FILE_BYTES}")
        for label, pattern in UNSAFE_PATTERNS:
            if pattern.search(data):
                problems.append(f"{name} contains what looks like a {label}")
    problems.extend(readme_problems(files[README_NAME].decode("ascii")))
    return problems


def directory_names(files: Dict[str, bytes]) -> List[str]:
    names = {""}
    for name in files:
        parts = name.split("/")[:-1]
        for count in range(1, len(parts) + 1):
            names.add("/".join(parts[:count]))
    return sorted(names)


def zip_bytes(files: Dict[str, bytes]) -> bytes:
    """A zip of the folder: sorted entries, stored (not compressed), fixed time, mode and creator."""
    import io

    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_STORED) as archive:
        entries = [(FOLDER_NAME + "/" + directory).rstrip("/") + "/" for directory in directory_names(files)]
        entries += [FOLDER_NAME + "/" + name for name in files]
        for entry in sorted(entries):
            info = zipfile.ZipInfo(entry, date_time=ZIP_DATE_TIME)
            info.create_system = ZIP_UNIX
            info.compress_type = zipfile.ZIP_STORED
            if entry.endswith("/"):
                info.external_attr = (0o40755 << 16) | 0x10
                archive.writestr(info, b"")
            else:
                info.external_attr = 0o100644 << 16
                archive.writestr(info, files[entry[len(FOLDER_NAME) + 1:]])
    return buffer.getvalue()


def write_folder(folder: Path, files: Dict[str, bytes]) -> None:
    for directory in directory_names(files):
        (folder / directory).mkdir(parents=True, exist_ok=True)
        (folder / directory).chmod(0o755)
    for name, data in files.items():
        path = folder / name
        path.write_bytes(data)
        path.chmod(0o644)


def build(output: Path) -> Tuple[Path, Path]:
    """Write the folder and the zip into `output`, replacing a folder and zip that an earlier run made."""
    files = collect_files()
    problems = content_problems(files)
    archive = zip_bytes(files)
    if len(archive) > MAXIMUM_ZIP_BYTES:
        problems.append(f"{ZIP_NAME} is {len(archive)} bytes; the limit is {MAXIMUM_ZIP_BYTES}")
    if problems:
        raise ArchiveError("\n".join(problems))
    folder, zip_path = output / FOLDER_NAME, output / ZIP_NAME
    if folder.exists():
        if not (folder / README_NAME).is_file():
            raise ArchiveError(f"{folder} exists and is not an earlier output of this script; move it away first")
        shutil.rmtree(folder)
    output.mkdir(parents=True, exist_ok=True)
    folder.mkdir()
    write_folder(folder, files)
    zip_path.write_bytes(archive)
    return folder, zip_path


# --- Check --------------------------------------------------------------------------------------------------------


def section(markdown: str, heading: str) -> str:
    """A second-level section: from its heading to the next second-level heading."""
    start = markdown.find(heading)
    if start < 0:
        raise ArchiveError(f'docs/release/app-store-submission.md has no "{heading}" section')
    end = markdown.find("\n## ", start + len(heading))
    return markdown[start:end if end >= 0 else len(markdown)]


def notes_section(markdown: str) -> str:
    return section(markdown, NOTES_HEADING)


def pasted_notes(section: str) -> str:
    """The text that is pasted into App Store Connect: the section's block-quote lines, without the quote marks."""
    lines = [line[2:] if line.startswith("> ") else "" for line in section.splitlines() if line.startswith(">")]
    return "\n".join(lines).strip()


def referenced_names(text: str) -> List[str]:
    """File names a text mentions, without a trailing slash or full stop, in order and without repeats."""
    found: List[str] = []
    for token in re.findall(r"[A-Za-z0-9][A-Za-z0-9._/-]*", text):
        token = token.rstrip(".")
        if FILE_NAME_TOKEN.match(token) or token in OTHER_FILE_NAMES:
            token = token.rstrip("/")
            if token not in found:
                found.append(token)
    return found


def archive_names(files: Dict[str, bytes]) -> List[str]:
    """What a person can select: the top-level entries, plus every file and folder below them."""
    return sorted(set(files) | (set(directory_names(files)) - {""}))


def cross_check(files: Dict[str, bytes], submission: str, zip_size: int) -> List[str]:
    problems = content_problems(files)
    if zip_size > MAXIMUM_ZIP_BYTES:
        problems.append(f"{ZIP_NAME} is {zip_size} bytes; the limit is {MAXIMUM_ZIP_BYTES}")
    available = set(archive_names(files))
    notes_text = notes_section(submission)
    notes = pasted_notes(notes_text)
    if not notes:
        problems.append("the Notes for App Review section has no block-quote text to paste")
    if len(notes.encode("utf-8")) > MAXIMUM_NOTES_BYTES:
        problems.append(f"the notes are {len(notes.encode('utf-8'))} bytes; Apple's limit is {MAXIMUM_NOTES_BYTES}")
    for match in PLACEHOLDER.finditer(notes):
        problems.append(f"the notes still contain a placeholder: {match.group(0)!r}")
    mentioned = referenced_names(notes_text)
    if not any(name in available for name in mentioned):
        problems.append("the notes name no file of the archive")
    for name in mentioned:
        if name not in available:
            problems.append(f"the notes name {name}, which is not in {ZIP_NAME}")
    if REPLIES_HEADING in submission:
        for name in referenced_names(section(submission, REPLIES_HEADING)):
            if name not in available:
                problems.append(f"the prepared replies name {name}, which is not in {ZIP_NAME}")
    readme = files[README_NAME].decode("ascii")
    for name in referenced_names(readme):
        if name not in available:
            problems.append(f"{README_NAME} names {name}, which is not in {ZIP_NAME}")
    described = set(referenced_names(readme))
    for sample in SAMPLES:
        if sample.name.rstrip("/") not in described:
            problems.append(f"{README_NAME} does not describe {sample.name}")
    return problems


def check() -> int:
    submission = SUBMISSION.read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory(prefix="review-samples-check-") as directory:
        try:
            folder, zip_path = build(Path(directory))
        except ArchiveError as error:
            print(f"review samples: FAILED\n{error}", file=sys.stderr)
            return 1
        files = {str(path.relative_to(folder)): path.read_bytes() for path in sorted(folder.rglob("*")) if path.is_file()}
        with zipfile.ZipFile(zip_path) as archive:
            inside = {info.filename[len(FOLDER_NAME) + 1:] for info in archive.infolist() if not info.is_dir()}
        if inside != set(files):
            print("review samples: FAILED\nthe zip and the folder hold different files", file=sys.stderr)
            return 1
        problems = cross_check(files, submission, zip_path.stat().st_size)
    if problems:
        print("review samples: FAILED", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    print(f"review samples: ok ({len(files)} files)")
    return 0


# --- Command line -------------------------------------------------------------------------------------------------


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Build the App Review sample archive.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT,
                        help=f"directory for {FOLDER_NAME}/ and {ZIP_NAME} (default: dist/review-samples)")
    parser.add_argument("--check", action="store_true",
                        help="build in a temporary directory and cross-check the notes and the README against it")
    arguments = parser.parse_args(argv)
    if arguments.check:
        return check()
    try:
        folder, zip_path = build(arguments.output)
    except ArchiveError as error:
        print(f"review samples: FAILED\n{error}", file=sys.stderr)
        return 1
    files = sorted(path for path in folder.rglob("*") if path.is_file())
    print(f"{folder} ({len(files)} files)")
    print(f"{zip_path} ({zip_path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
