#!/usr/bin/env python3
"""Assemble the LGPL source-offer bundle for the CAD helper from the repository alone (decision 027, Q-171, D20 (a)).

    python3 script/package_cad_source_offer.py --check                     # inputs consistent and a bundle assembles complete
    python3 script/package_cad_source_offer.py --check BUNDLE_DIRECTORY    # verify a bundle that was built earlier
    python3 script/package_cad_source_offer.py --output DIRECTORY          # assemble into a new or empty directory
    python3 script/package_cad_source_offer.py --output DIRECTORY --tarball BUNDLE.tar.gz
    python3 script/package_cad_source_offer.py --output DIRECTORY --include-archive .build/cad/occt-<revision>.tar.gz

The CAD helper (`Native/CADWorker`) statically links Open CASCADE Technology under the LGPL 2.1 with the Open CASCADE
exception. D20 (a) meets the source and relinking obligation by publishing the helper's sources, the pinned OCCT
archive, the build-manifest edits and the build scripts, with a written offer (`Native/CADWorker/SOURCE-OFFER.md`,
pending legal review; whether to ship 1.0 without CAD is the owner's decision and is not made here).

This script never touches the network. It reads the pinned revision, archive checksum and URL from
`script/build_cad_worker.py` (parsed, never run), checks that `ThirdPartyNotices/OCCT/NOTICE.txt`,
`docs/dependencies/occt.md` and the offer text say the same, and copies these files into a bundle that mirrors the
repository's layout, so the bundle's own `script/build_cad_worker.py` runs from its root:

    README.md, LICENSE, SOURCE-OFFER.md, PINNED-SOURCE.txt, MANIFEST.sha256
    excerpts/narrow_manifests.py.txt, excerpts/build_cad_worker_main.py.txt   the manifest edits and the configure step
    script/build_cad_worker.py, script/embed_cad_worker.py, Configuration/CADWorker.entitlements
    Native/CADWorker/**                                                       every source, test and fixture
    ThirdPartyNotices/OCCT/**, docs/dependencies/occt.md
    .build/cad/occt-<revision>.tar.gz                                         only with --include-archive

The archive is not in the repository, and this script cannot download it; `--include-archive` accepts a local copy
and refuses it unless its SHA-256 equals the pinned one. `--check` verifies completeness: the required files, every
source named in the helper's CMake file, the offer text naming the pinned values and the pending legal review, the helper
license, no unfilled placeholder in the offer, and a manifest whose hashes match every file with no file unlisted. A
`.git` directory in a bundle directory is ignored, so a repository that mirrors a bundle can be checked in place. The
bundle is deterministic: the same repository gives
the same bytes, including the optional tarball.

Plain Python 3.9 or newer and the standard library only. Exit status 0 on success, 1 when a check fails, 2 on usage errors.
"""
from __future__ import annotations

import argparse
import ast
import gzip
import hashlib
import io
import re
import shutil
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import Dict, List, NamedTuple, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[1]

BUILD_SCRIPT = "script/build_cad_worker.py"
EMBED_SCRIPT = "script/embed_cad_worker.py"
ENTITLEMENTS = "Configuration/CADWorker.entitlements"
WORKER_DIRECTORY = "Native/CADWorker"
WORKER_CMAKE = "Native/CADWorker/CMakeLists.txt"
OFFER = "Native/CADWorker/SOURCE-OFFER.md"
LICENSE_SOURCE = "Native/CADWorker/LICENSE"
NOTICE_DIRECTORY = "ThirdPartyNotices/OCCT"
NOTICE_SUMMARY = "ThirdPartyNotices/OCCT/NOTICE.txt"
DEPENDENCY_RECORD = "docs/dependencies/occt.md"

REQUIRED_NOTICES = ("BISON_NOTICE.txt", "FLEX_NOTICE.txt", "LICENSE_GPL_3.txt", "LICENSE_LGPL_21.txt",
                    "NOTICE.txt", "OCCT_LGPL_EXCEPTION.txt")
# The generated and copied files at the bundle root and under excerpts.
BUNDLE_OFFER = "SOURCE-OFFER.md"
BUNDLE_LICENSE = "LICENSE"
BUNDLE_README = "README.md"
BUNDLE_PINNED = "PINNED-SOURCE.txt"
BUNDLE_MANIFEST = "MANIFEST.sha256"
EXCERPT_MANIFESTS = "excerpts/narrow_manifests.py.txt"
EXCERPT_BUILD = "excerpts/build_cad_worker_main.py.txt"
ARCHIVE_URL_PREFIX = "https://codeload.github.com/Open-Cascade-SAS/OCCT/tar.gz/"
LEGAL_MARKER = "pending legal review"
# A bracketed gap left in the offer, such as "[support address, to be supplied before release]".
PLACEHOLDER = re.compile(r"\[[^\]\n]*\bto be (?:supplied|published)\b[^\]\n]*\]", re.IGNORECASE)
# Version-control metadata is not part of a bundle, so a repository that mirrors one can be checked in place.
VCS_NAMES = frozenset({".git"})

# Files that never belong in a source bundle even when a build left them next to the sources.
EXCLUDED_NAMES = frozenset({"__pycache__", ".DS_Store"})
EXCLUDED_SUFFIXES = (".pyc", ".o", ".a", ".dylib")

REVISION = re.compile(r"^[0-9a-f]{40}$")
CHECKSUM = re.compile(r"^[0-9a-f]{64}$")
MANIFEST_LINE = re.compile(r"^([0-9a-f]{64})  (\S.*)$")


class Pinned(NamedTuple):
    revision: str
    sha256: str
    url: str
    version: str

    @property
    def archive_path(self) -> str:
        """Where the build script looks for the archive before it would download one."""
        return f".build/cad/occt-{self.revision}.tar.gz"


class OfferError(Exception):
    """A problem that stops assembly; the message says what and where."""


# ---------------------------------------------------------------------------------------------------
# The pinned reference
# ---------------------------------------------------------------------------------------------------

def evaluate(node: ast.AST, names: Dict[str, str]) -> str:
    """The value of a string constant, a known name or a concatenation of those; anything else is an error."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name) and node.id in names:
        return names[node.id]
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return evaluate(node.left, names) + evaluate(node.right, names)
    raise OfferError("a pinned value in the build script is not a plain string")


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise OfferError(f"cannot read {path.name}: {error}") from error


def parse_build_script(root: Path) -> Tuple[Dict[str, str], str, ast.Module]:
    source = read_text(root / BUILD_SCRIPT)
    try:
        tree = ast.parse(source)
    except SyntaxError as error:
        raise OfferError(f"{BUILD_SCRIPT} does not parse: {error.msg}") from error
    values: Dict[str, str] = {}
    for node in tree.body:
        if (isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name)
                and node.targets[0].id in ("REVISION", "ARCHIVE_SHA256", "ARCHIVE_URL")):
            values[node.targets[0].id] = evaluate(node.value, values)
    return values, source, tree


def pinned_reference(root: Path) -> Pinned:
    values, _, _ = parse_build_script(root)
    missing = [name for name in ("REVISION", "ARCHIVE_SHA256", "ARCHIVE_URL") if name not in values]
    if missing:
        raise OfferError(f"{BUILD_SCRIPT} does not define {', '.join(missing)}")
    revision, checksum, url = values["REVISION"], values["ARCHIVE_SHA256"], values["ARCHIVE_URL"]
    if not REVISION.match(revision):
        raise OfferError(f"REVISION in {BUILD_SCRIPT} is not a 40-digit commit")
    if not CHECKSUM.match(checksum):
        raise OfferError(f"ARCHIVE_SHA256 in {BUILD_SCRIPT} is not a SHA-256")
    if url != ARCHIVE_URL_PREFIX + revision:
        raise OfferError(f"ARCHIVE_URL in {BUILD_SCRIPT} is not the immutable-commit URL of REVISION")
    version = re.search(r"\bOCCT (\d+\.\d+\.\d+)\b", read_text(root / NOTICE_SUMMARY))
    if not version:
        raise OfferError(f"{NOTICE_SUMMARY} names no OCCT version")
    return Pinned(revision, checksum, url, version.group(1))


def function_source(source: str, tree: ast.Module, name: str) -> str:
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == name:
            segment = ast.get_source_segment(source, node)
            if segment:
                return segment
    raise OfferError(f"{BUILD_SCRIPT} has no function {name}")


# ---------------------------------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------------------------------

def is_excluded(path: Path) -> bool:
    return any(part in EXCLUDED_NAMES for part in path.parts) or path.name.endswith(EXCLUDED_SUFFIXES)


def tree_files(root: Path, directory: str) -> List[str]:
    """Every regular file below `directory`, as sorted paths relative to `root`; links and special files are errors."""
    base = root / directory
    if not base.is_dir() or base.is_symlink():
        raise OfferError(f"{directory} is not a directory")
    found: List[str] = []
    for path in sorted(base.rglob("*")):
        if is_excluded(path.relative_to(base)):
            continue
        if path.is_symlink():
            raise OfferError(f"{path.relative_to(root).as_posix()} is a symbolic link; a bundle holds regular files only")
        if path.is_dir():
            continue
        if not path.is_file():
            raise OfferError(f"{path.relative_to(root).as_posix()} is not a regular file")
        found.append(path.relative_to(root).as_posix())
    return found


def cmake_sources(root: Path) -> List[str]:
    """The source files the helper's `add_executable(CADWorker ...)` names."""
    text = read_text(root / WORKER_CMAKE)
    match = re.search(r"add_executable\(\s*CADWorker\s+([^)]*)\)", text)
    if not match:
        raise OfferError(f"{WORKER_CMAKE} has no add_executable(CADWorker ...)")
    return match.group(1).split()


def input_problems(root: Path) -> List[str]:
    """Why the repository cannot yield a complete bundle: missing files and disagreeing statements. Empty when fine."""
    problems: List[str] = []
    try:
        pinned = pinned_reference(root)
    except OfferError as error:
        return [str(error)]
    required = [BUILD_SCRIPT, EMBED_SCRIPT, ENTITLEMENTS, OFFER, LICENSE_SOURCE, NOTICE_SUMMARY, DEPENDENCY_RECORD,
                WORKER_CMAKE]
    required += [f"{NOTICE_DIRECTORY}/{name}" for name in REQUIRED_NOTICES]
    for path in required:
        if not (root / path).is_file():
            problems.append(f"missing {path}")
    if problems:
        return problems
    statements = {
        NOTICE_SUMMARY: (pinned.revision, pinned.sha256, pinned.url),
        DEPENDENCY_RECORD: (pinned.revision, pinned.sha256),
        OFFER: (pinned.revision, pinned.sha256, pinned.url, pinned.version),
    }
    for path, expected in statements.items():
        text = read_text(root / path)
        problems += [f"{path} does not state the pinned value {value}" for value in expected if value not in text]
    offer = read_text(root / OFFER)
    if LEGAL_MARKER not in offer.lower():
        problems.append(f"{OFFER} is not marked '{LEGAL_MARKER}'")
    for needed in (BUILD_SCRIPT.rsplit("/", 1)[-1], NOTICE_DIRECTORY, "MANIFEST.sha256"):
        if needed not in offer:
            problems.append(f"{OFFER} never mentions {needed}")
    problems += [f"{OFFER} still has the placeholder {gap}" for gap in PLACEHOLDER.findall(offer)]
    if not read_text(root / LICENSE_SOURCE).strip():
        problems.append(f"{LICENSE_SOURCE} is empty")
    try:
        sources = cmake_sources(root)
    except OfferError as error:
        return problems + [str(error)]
    try:
        present = set(tree_files(root, WORKER_DIRECTORY))
    except OfferError as error:
        return problems + [str(error)]
    problems += [f"{WORKER_CMAKE} names {name}, which is not a file of {WORKER_DIRECTORY}"
                 for name in sources if f"{WORKER_DIRECTORY}/{name}" not in present]
    return problems


# ---------------------------------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------------------------------

def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def pinned_text(pinned: Pinned, includes_archive: bool) -> str:
    archive = (f"Included in this bundle at {pinned.archive_path}; the build script uses it instead of downloading one."
               if includes_archive else
               f"Not included in this bundle. Fetch it from the URL above to {pinned.archive_path}; the build script "
               "verifies the checksum before use and refuses a mismatch.")
    return "\n".join([
        f"SpacePane CAD helper: the pinned Open CASCADE source ({LEGAL_MARKER})",
        "",
        f"Library:         Open CASCADE Technology (OCCT) {pinned.version}, commit {pinned.revision}",
        f"Source archive:  {pinned.url}",
        f"SHA-256:         {pinned.sha256}",
        f"Archive:         {archive}",
        "",
        f"Verify:          shasum -a 256 {pinned.archive_path}",
        "Rebuild:         python3 script/build_cad_worker.py --architecture arm64 --test",
        "Manifest edits:  excerpts/narrow_manifests.py.txt (the only changes to the unpacked archive)",
        "Configure step:  excerpts/build_cad_worker_main.py.txt",
        "Written offer:   SOURCE-OFFER.md",
        "",
        "This file is generated by script/package_cad_source_offer.py from script/build_cad_worker.py.",
        "",
    ])


def readme_text(pinned: Pinned) -> str:
    return "\n".join([
        "# SpacePane CAD helper: source",
        "",
        "SpacePane's optional STEP and IGES previews run in `CADWorker`, a small separate executable. It statically links",
        f"parts of Open CASCADE Technology (OCCT) {pinned.version}, which is licensed under the GNU Lesser General Public",
        "License version 2.1 with the Open CASCADE exception. This repository is the corresponding source for that helper:",
        "it lets you modify the library and relink the helper for your own use. The SpacePane app and its Quick Look",
        "extensions are not part of it and never link OCCT.",
        "",
        "## What is here",
        "",
        "- `SOURCE-OFFER.md`: the written offer, with the contact address and the download location.",
        "- `PINNED-SOURCE.txt`: the exact OCCT revision, its archive URL and SHA-256.",
        "- `Native/CADWorker`: the helper's source, tests and synthetic fixtures.",
        "- `script/build_cad_worker.py`, `script/embed_cad_worker.py`, `Configuration/CADWorker.entitlements`: the build,",
        "  the embedding step and the sandbox entitlements. `excerpts/` shows the two parts that matter for the library.",
        "- `ThirdPartyNotices/OCCT`: the OCCT license, the Open CASCADE exception and the notices for the generated parser.",
        "- `docs/dependencies/occt.md`: the dependency audit.",
        "- `MANIFEST.sha256`: the SHA-256 of every other file. Check it with `shasum -a 256 -c MANIFEST.sha256`.",
        "",
        "## Rebuild and relink",
        "",
        "You need CMake, Xcode's command-line tools and Python 3.9 or newer.",
        "",
        "```sh",
        "python3 script/build_cad_worker.py --architecture arm64 --test",
        "```",
        "",
        "The script does this, in order:",
        "",
        f"1. It takes the archive from `{pinned.archive_path}` when that file exists, otherwise it downloads",
        f"   {pinned.url}.",
        f"2. It refuses an archive whose SHA-256 is not `{pinned.sha256}`.",
        "3. It unpacks the archive under `.build/cad` and applies the build-manifest edits in",
        "   `excerpts/narrow_manifests.py.txt`.",
        "4. It builds the static kernel, then links `CADWorker` from `Native/CADWorker`.",
        "",
        "To link a helper with a modified library, edit the unpacked tree under",
        f"`.build/cad/OCCT-{pinned.revision}` and run the same command again.",
        "",
        "## Licenses",
        "",
        "Everything written for SpacePane in this repository is under the MIT License (`LICENSE`). OCCT and the",
        "third-party notices keep their own terms (`ThirdPartyNotices/OCCT`).",
        "",
        "## Where this comes from",
        "",
        "This repository is generated from SpacePane's private repository by `script/package_cad_source_offer.py`, one",
        "release at a time, and tagged with the release. Do not send changes here. Questions and requests: see",
        "`SOURCE-OFFER.md`.",
        "",
    ])


def excerpt_text(title: str, code: str) -> str:
    return f"# {title}\n# Excerpt of {BUILD_SCRIPT}; the complete script is script/build_cad_worker.py.\n\n{code}\n"


def copy_file(root: Path, bundle: Path, relative: str) -> None:
    destination = bundle / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root / relative, destination)
    destination.chmod(0o644)


def write_file(bundle: Path, relative: str, text: str) -> None:
    destination = bundle / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding="utf-8")
    destination.chmod(0o644)


def bundle_files(bundle: Path) -> List[str]:
    return sorted(relative.as_posix() for relative in (path.relative_to(bundle) for path in bundle.rglob("*"))
                  if not any(part in VCS_NAMES for part in relative.parts)
                  and ((bundle / relative).is_file() or (bundle / relative).is_symlink()))


def manifest_text(bundle: Path) -> str:
    lines = [f"{sha256_of(bundle / name)}  {name}" for name in bundle_files(bundle) if name != BUNDLE_MANIFEST]
    return "\n".join(lines) + "\n"


def assemble(root: Path, bundle: Path, archive: Optional[Path] = None) -> List[str]:
    """Write the bundle into `bundle` (absent or empty) and return its file names. Raises OfferError on any problem."""
    problems = input_problems(root)
    if problems:
        raise OfferError("; ".join(problems))
    pinned = pinned_reference(root)
    if archive is not None:
        if not archive.is_file() or archive.is_symlink():
            raise OfferError(f"the archive {archive} is not a regular file")
        if sha256_of(archive) != pinned.sha256:
            raise OfferError(f"the archive {archive.name} does not have the pinned SHA-256; refusing to include it")
    if bundle.exists() and (not bundle.is_dir() or any(bundle.iterdir())):
        raise OfferError(f"{bundle} exists and is not an empty directory")
    _, source, tree = parse_build_script(root)
    bundle.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root / OFFER, bundle / BUNDLE_OFFER)
    (bundle / BUNDLE_OFFER).chmod(0o644)
    shutil.copyfile(root / LICENSE_SOURCE, bundle / BUNDLE_LICENSE)
    (bundle / BUNDLE_LICENSE).chmod(0o644)
    write_file(bundle, BUNDLE_README, readme_text(pinned))
    write_file(bundle, BUNDLE_PINNED, pinned_text(pinned, archive is not None))
    write_file(bundle, EXCERPT_MANIFESTS, excerpt_text("The build-manifest changes applied to the unpacked archive",
                                                       function_source(source, tree, "narrow_manifests")))
    write_file(bundle, EXCERPT_BUILD, excerpt_text("The configure and build steps",
                                                   function_source(source, tree, "main")))
    for relative in (BUILD_SCRIPT, EMBED_SCRIPT, ENTITLEMENTS, DEPENDENCY_RECORD):
        copy_file(root, bundle, relative)
    for relative in tree_files(root, WORKER_DIRECTORY) + tree_files(root, NOTICE_DIRECTORY):
        copy_file(root, bundle, relative)
    if archive is not None:
        destination = bundle / pinned.archive_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(archive, destination)
        destination.chmod(0o644)
    (bundle / BUNDLE_MANIFEST).write_text(manifest_text(bundle), encoding="utf-8")
    return bundle_files(bundle)


def write_tarball(bundle: Path, destination: Path) -> None:
    """A deterministic gzip tarball: sorted members, fixed owner, mode and time, one top-level folder."""
    top = bundle.name
    raw = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0, compresslevel=9) as compressed:
        with tarfile.open(fileobj=compressed, mode="w", format=tarfile.GNU_FORMAT) as archive:
            for name in bundle_files(bundle):
                path = bundle / name
                member = tarfile.TarInfo(f"{top}/{name}")
                member.size = path.stat().st_size
                member.mode, member.uid, member.gid, member.uname, member.gname, member.mtime = 0o644, 0, 0, "", "", 0
                with path.open("rb") as stream:
                    archive.addfile(member, stream)
    destination.write_bytes(raw.getvalue())


# ---------------------------------------------------------------------------------------------------
# Verification of a bundle
# ---------------------------------------------------------------------------------------------------

def bundle_problems(bundle: Path, pinned: Pinned) -> List[str]:
    """Everything wrong with a bundle directory; empty when it is complete and untampered."""
    if not bundle.is_dir():
        return [f"{bundle} is not a directory"]
    problems: List[str] = []
    links = [path.relative_to(bundle).as_posix() for path in bundle.rglob("*") if path.is_symlink()]
    problems += [f"{name} is a symbolic link" for name in links]
    present = [name for name in bundle_files(bundle) if name not in links]
    required = [BUNDLE_OFFER, BUNDLE_LICENSE, BUNDLE_README, BUNDLE_PINNED, BUNDLE_MANIFEST, EXCERPT_MANIFESTS,
                EXCERPT_BUILD, BUILD_SCRIPT, EMBED_SCRIPT, ENTITLEMENTS, DEPENDENCY_RECORD, WORKER_CMAKE, OFFER,
                LICENSE_SOURCE]
    required += [f"{NOTICE_DIRECTORY}/{name}" for name in REQUIRED_NOTICES]
    problems += [f"the bundle lacks {name}" for name in required if name not in present]
    manifest_path = bundle / BUNDLE_MANIFEST
    listed: Dict[str, str] = {}
    if manifest_path.is_file():
        for number, line in enumerate(read_text(manifest_path).splitlines(), start=1):
            match = MANIFEST_LINE.match(line)
            if not match:
                problems.append(f"{BUNDLE_MANIFEST} line {number} is not '<sha256>  <path>'")
                continue
            if match.group(2) in listed:
                problems.append(f"{BUNDLE_MANIFEST} lists {match.group(2)} twice")
            listed[match.group(2)] = match.group(1)
        for name, expected in sorted(listed.items()):
            path = bundle / name
            if name == BUNDLE_MANIFEST or ".." in name.split("/") or name.startswith("/"):
                problems.append(f"{BUNDLE_MANIFEST} lists an invalid path {name}")
            elif not path.is_file() or path.is_symlink():
                problems.append(f"{BUNDLE_MANIFEST} lists {name}, which is missing")
            elif sha256_of(path) != expected:
                problems.append(f"{name} does not match its hash in {BUNDLE_MANIFEST}")
        problems += [f"{name} is in the bundle but not in {BUNDLE_MANIFEST}" for name in present
                     if name != BUNDLE_MANIFEST and name not in listed]
    for name in (BUNDLE_OFFER, BUNDLE_PINNED):
        path = bundle / name
        if not path.is_file():
            continue
        text = read_text(path)
        problems += [f"{name} does not state the pinned value {value}"
                     for value in (pinned.revision, pinned.sha256, pinned.url) if value not in text]
        if LEGAL_MARKER not in text.lower():
            problems.append(f"{name} is not marked '{LEGAL_MARKER}'")
    if (bundle / BUNDLE_OFFER).is_file() and (bundle / OFFER).is_file() and \
            (bundle / BUNDLE_OFFER).read_bytes() != (bundle / OFFER).read_bytes():
        problems.append(f"{BUNDLE_OFFER} differs from {OFFER}")
    if (bundle / BUNDLE_LICENSE).is_file() and (bundle / LICENSE_SOURCE).is_file() and \
            (bundle / BUNDLE_LICENSE).read_bytes() != (bundle / LICENSE_SOURCE).read_bytes():
        problems.append(f"{BUNDLE_LICENSE} differs from {LICENSE_SOURCE}")
    if (bundle / BUNDLE_OFFER).is_file():
        problems += [f"{BUNDLE_OFFER} still has the placeholder {gap}"
                     for gap in PLACEHOLDER.findall(read_text(bundle / BUNDLE_OFFER))]
    archive = bundle / pinned.archive_path
    if archive.exists() and (not archive.is_file() or sha256_of(archive) != pinned.sha256):
        problems.append(f"{pinned.archive_path} does not have the pinned SHA-256")
    elif not archive.exists() and f"Included in this bundle at {pinned.archive_path}" in (
            read_text(bundle / BUNDLE_PINNED) if (bundle / BUNDLE_PINNED).is_file() else ""):
        problems.append(f"{BUNDLE_PINNED} says the archive is included, but {pinned.archive_path} is missing")
    if (bundle / WORKER_CMAKE).is_file():
        try:
            sources = cmake_sources(bundle)
        except OfferError as error:
            problems.append(str(error))
        else:
            problems += [f"the bundle lacks {WORKER_DIRECTORY}/{name}, which the helper's CMake file names"
                         for name in sources if f"{WORKER_DIRECTORY}/{name}" not in present]
    return problems


def check_repository(root: Path) -> Tuple[List[str], str]:
    """The input check, then assemble into a scratch directory and verify that bundle."""
    problems = input_problems(root)
    if problems:
        return problems, ""
    pinned = pinned_reference(root)
    with tempfile.TemporaryDirectory(prefix="cad-source-offer-") as scratch:
        bundle = Path(scratch) / "bundle"
        try:
            names = assemble(root, bundle)
        except OfferError as error:
            return [str(error)], ""
        problems = bundle_problems(bundle, pinned)
    return problems, f"CAD source offer ok: {len(names)} files, OCCT {pinned.version} {pinned.revision[:12]}, {LEGAL_MARKER}"


# ---------------------------------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------------------------------

def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Assemble or check the CAD helper's LGPL source-offer bundle.")
    parser.add_argument("--root", type=Path, default=ROOT, help="repository root (default: this repository)")
    parser.add_argument("--check", nargs="?", const="", metavar="BUNDLE",
                        help="verify the repository's inputs, or the given bundle directory")
    parser.add_argument("--output", type=Path, help="assemble the bundle into this new or empty directory")
    parser.add_argument("--tarball", type=Path, help="with --output: also write a deterministic .tar.gz")
    parser.add_argument("--include-archive", type=Path, metavar="FILE",
                        help="with --output: add a local copy of the pinned OCCT archive after checking its SHA-256")
    arguments = parser.parse_args(argv)
    if (arguments.check is None) == (arguments.output is None):
        parser.error("give exactly one of --check and --output")
    if arguments.output is None and (arguments.tarball or arguments.include_archive):
        parser.error("--tarball and --include-archive need --output")
    root = arguments.root.resolve()
    try:
        if arguments.check is not None:
            if arguments.check:
                problems = bundle_problems(Path(arguments.check), pinned_reference(root))
                message = f"CAD source offer bundle ok: {arguments.check}"
            else:
                problems, message = check_repository(root)
            if problems:
                print("\n".join(problems), file=sys.stderr)
                print(f"CAD source offer: {len(problems)} problem(s)", file=sys.stderr)
                return 1
            print(message)
            return 0
        names = assemble(root, arguments.output.resolve(), arguments.include_archive)
        problems = bundle_problems(arguments.output.resolve(), pinned_reference(root))
        if problems:
            print("\n".join(problems), file=sys.stderr)
            return 1
        if arguments.tarball:
            write_tarball(arguments.output.resolve(), arguments.tarball)
        print(f"wrote {len(names)} files to {arguments.output}" + (f" and {arguments.tarball}" if arguments.tarball else ""))
        return 0
    except OfferError as error:
        print(f"CAD source offer: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
