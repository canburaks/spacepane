#!/usr/bin/env python3
"""The portable static gate: every repository check that needs no Apple toolchain (decision 027, Q-18).

    python3 script/check_static.py                    # run every step, one line each
    python3 script/check_static.py --verbose          # also print the output of passing steps
    python3 script/check_static.py --require-syntax   # fail, instead of skipping, without the tree-sitter packages
    python3 script/check_static.py --list             # name the steps and what each runs
    ./script/build_and_run.sh --check-static          # the same, through the repository entry point

Plain Python 3.9 or newer and the standard library only, so it behaves the same on Linux (cloud sessions,
continuous integration) and on a Mac. Steps run in this order and report one line each; the exit status
is 1 when any required step fails:

    manifests           script/sync_manifests.py --check
    appearance samples  script/generate_appearance_samples.py --check
    localization tests  tools/test_localization.py
    benchmark tests     script/test_compare_benchmarks.py
    benchmark runners   script/test_benchmark_release_summaries.py
    image benchmark tests script/test_benchmark_release_images.py
    package link inventory script/test_package_link.py
    cad build tests     script/test_build_cad_worker.py
    review samples      script/build_review_samples.py --check
    review sample tests script/test_build_review_samples.py
    localization        tools/validate_localization.py (its exit status is the result)
    shell syntax        bash -n script/build_and_run.sh
    decision numbers    every file in docs/decisions starts with three digits; numbers are unique
    wall-clock tests    every name in WALL_CLOCK_SUITES (script/build_and_run.sh) exists in Packages/PreviewCore/Tests
    ownership tool      tools/check_ownership.py compiles and its table loads
    chrome inks         PreviewRenderers draw muted text and rules from palette tiers, never system secondary ink
    dataless guard      file-opening APIs appear only in the allowlisted checked owners (Q-153, MATERIALIZATION_ALLOWLIST)
    swift syntax        tools/check_swift_syntax.py --all, when the tree-sitter packages can be imported

The Swift syntax step is skipped, with a clear line, when neither this interpreter nor .venv-tools (which
the tool finds by itself) can import tree-sitter; setup is in tools/check_swift_syntax.py. Skipping never
fails the gate unless --require-syntax is given. A passing gate says nothing about whether Swift compiles;
that stays with the macOS job and Mac sessions (decision 027, "Two environments, one rule").
"""
from __future__ import annotations

import argparse
import os
import py_compile
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Callable, Dict, FrozenSet, List, NamedTuple, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[1]
DECISIONS_DIRECTORY = ROOT / "docs" / "decisions"
BUILD_SCRIPT = ROOT / "script" / "build_and_run.sh"
PACKAGE_TESTS = ROOT / "Packages" / "PreviewCore" / "Tests"
STEP_TIMEOUT_SECONDS = 300
FAILURE_OUTPUT_LINES = 40

PASS, FAIL, SKIP = "ok", "FAIL", "skip"

DECISION_FILE = re.compile(r"^(\d{3})-.+\.md$")
# Files in docs/decisions that are not decision records: the index.
NON_DECISION_FILES = frozenset({"README.md"})
# Two records share 006 for historical reasons (docs/decisions/README.md). No other number may repeat.
ALLOWED_DUPLICATE_NUMBERS: Dict[str, FrozenSet[str]] = {
    "006": frozenset({"006-direct-file-drop.md", "006-opt-in-cad-previews.md"}),
}

WALL_CLOCK_ASSIGNMENT = re.compile(r"""^[ \t]*WALL_CLOCK_SUITES=(?:'([^'\n]*)'|"([^"\n]*)")""", re.MULTILINE)
PLAIN_TEST_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SWIFT_SUITE = re.compile(r"\b(?:struct|class|enum)\s+([A-Za-z_][A-Za-z0-9_]*)")
SWIFT_LINE_COMMENT = re.compile(r"^[ \t]*//.*$", re.MULTILINE)
PLUTIL_MISSING = re.compile(r"No such file or directory: 'plutil'")

SYNTAX_TOOL = "tools/check_swift_syntax.py"
OWNERSHIP_TOOL = "tools/check_ownership.py"
SYNTAX_SETUP = "python3 -m venv .venv-tools && .venv-tools/bin/pip install tree-sitter tree-sitter-swift (Python 3.10 or newer)"


class Result(NamedTuple):
    status: str
    detail: str
    output: str = ""


class Step(NamedTuple):
    name: str
    runs: str
    run: Callable[[], Result]


# ---------------------------------------------------------------------------------------------------
# Running commands
# ---------------------------------------------------------------------------------------------------

def run_command(command: Sequence[str], timeout: int = STEP_TIMEOUT_SECONDS) -> Tuple[int, str]:
    """Run a command at the repository root; return its exit status and merged output."""
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    try:
        completed = subprocess.run(list(command), cwd=str(ROOT), env=environment, timeout=timeout,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except FileNotFoundError:
        return 127, f"command not found: {command[0]}"
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {timeout} s: {' '.join(command)}"
    return completed.returncode, completed.stdout.decode("utf-8", "replace")


def last_line(output: str) -> str:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    return lines[-1] if lines else ""


def unittest_summary(output: str) -> str:
    match = re.search(r"^Ran (\d+) tests?", output, re.MULTILINE)
    return f"{match.group(1)} tests passed" if match else last_line(output)


def script_step(arguments: Sequence[str], summarize: Callable[[str], str] = last_line) -> Callable[[], Result]:
    """A step that passes when `python3 <arguments>` exits 0."""
    def step() -> Result:
        code, output = run_command([sys.executable, *arguments])
        if code != 0:
            return Result(FAIL, f"exit {code}: python3 {' '.join(arguments)}", output)
        return Result(PASS, summarize(output) or "passed", output)
    return step


def compile_problem(path: Path) -> Optional[str]:
    """Why a Python file does not compile, or None. The bytecode goes to a scratch folder, never next to the source."""
    with tempfile.TemporaryDirectory() as scratch:
        try:
            py_compile.compile(str(path), cfile=os.path.join(scratch, "compiled.pyc"), doraise=True)
        except (py_compile.PyCompileError, OSError) as error:
            return str(error)
    return None


def shown(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


# ---------------------------------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------------------------------

def localization_step() -> Result:
    code, output = run_command([sys.executable, "tools/validate_localization.py"])
    if code == 0:
        return Result(PASS, last_line(output) or "passed", output)
    if PLUTIL_MISSING.search(output):  # transitional: only a validator without its Python fallback fails this way
        return Result(FAIL, "plutil (a macOS tool) is missing on this host and tools/validate_localization.py has no "
                            "Python fallback yet; this is not a localization defect", output)
    return Result(FAIL, f"exit {code}: python3 tools/validate_localization.py", output)


def shell_syntax_step() -> Result:
    shell = shutil.which("bash") or "/bin/bash"
    code, output = run_command([shell, "-n", shown(BUILD_SCRIPT)])
    if code != 0:
        return Result(FAIL, f"bash -n {shown(BUILD_SCRIPT)} exit {code}", output)
    return Result(PASS, f"bash -n {shown(BUILD_SCRIPT)}")


def check_decision_numbers(directory: Path = DECISIONS_DIRECTORY,
                           allowed: Dict[str, FrozenSet[str]] = ALLOWED_DUPLICATE_NUMBERS) -> Result:
    """Every file in the decisions folder starts with three digits and each number is used once, bar the allowed pairs."""
    if not directory.is_dir():
        return Result(FAIL, f"{shown(directory)} is not a folder")
    by_number: Dict[str, List[str]] = {}
    problems: List[str] = []
    for entry in sorted(directory.iterdir(), key=lambda item: item.name):
        name = entry.name
        if name.startswith(".") or name in NON_DECISION_FILES or not entry.is_file():
            continue
        match = DECISION_FILE.match(name)
        if match is None:
            problems.append(f"{name}: a decision file name starts with three digits and a hyphen and ends in .md")
            continue
        by_number.setdefault(match.group(1), []).append(name)
    allowed_shared = []
    for number, names in sorted(by_number.items()):
        if len(names) == 1:
            continue
        if set(names) <= allowed.get(number, frozenset()):
            allowed_shared.append(number)
        else:
            problems.append(f"number {number} is used by {len(names)} records: {', '.join(names)}")
    if problems:
        detail = problems[0] if len(problems) == 1 else f"{len(problems)} problems"
        return Result(FAIL, detail, "\n".join(problems))
    total = sum(len(names) for names in by_number.values())
    detail = f"{total} records with unique numbers"
    if allowed_shared:
        detail += f" (shared by design: {', '.join(allowed_shared)})"
    return Result(PASS, detail)


def wall_clock_suite_names(script_text: str) -> Optional[List[str]]:
    """The alternatives of WALL_CLOCK_SUITES in script/build_and_run.sh, or None when the assignment is absent."""
    match = WALL_CLOCK_ASSIGNMENT.search(script_text)
    if match is None:
        return None
    value = match.group(1) if match.group(1) is not None else match.group(2)
    return value.split("|")


def swift_suite_names(tests: Path) -> Dict[str, List[str]]:
    """Suite type name to the test files that declare it; runtime discovery checks membership and count."""
    declared: Dict[str, List[str]] = {}
    for path in sorted(tests.rglob("*.swift")):
        text = SWIFT_LINE_COMMENT.sub("", path.read_text(encoding="utf-8", errors="replace"))
        for name in set(SWIFT_SUITE.findall(text)):
            declared.setdefault(name, []).append(shown(path))
    return declared


def check_wall_clock_tests(build_script: Path = BUILD_SCRIPT, tests: Path = PACKAGE_TESTS) -> Result:
    """Every selected suite must exist; compiled inventory validates its exact nonzero test count."""
    try:
        names = wall_clock_suite_names(build_script.read_text(encoding="utf-8"))
    except OSError as error:
        return Result(FAIL, f"cannot read {shown(build_script)}: {error}")
    if names is None:
        return Result(FAIL, f"no WALL_CLOCK_SUITES assignment in {shown(build_script)}; "
                            f"update script/check_static.py if the serial pass is selected another way")
    if not tests.is_dir():
        return Result(FAIL, f"{shown(tests)} is not a folder")
    problems = []
    script_text = build_script.read_text(encoding="utf-8")
    if not re.search(r"^[ \t]*EXPECTED_SERIAL_TESTS=[1-9][0-9]*[ \t]*$", script_text, re.MULTILINE):
        problems.append("EXPECTED_SERIAL_TESTS must be a positive literal count")
    if len(set(names)) != len(names):
        problems.append("WALL_CLOCK_SUITES contains duplicate suite names")
    for name in names:
        if not name:
            problems.append("WALL_CLOCK_SUITES has an empty alternative, which would match every test")
        elif not PLAIN_TEST_NAME.match(name):
            problems.append(f"{name!r} is not a plain test suite name; this check cannot verify it")
    declared = swift_suite_names(tests)
    for name in names:
        if PLAIN_TEST_NAME.match(name) and name not in declared:
            problems.append(f"{name}: no suite type with this name in {shown(tests)}")
    if problems:
        detail = problems[0] if len(problems) == 1 else f"{len(problems)} problems"
        return Result(FAIL, detail, "\n".join(problems))
    files = sorted({path for name in names for path in declared[name]})
    return Result(PASS, f"{len(names)} suite names found in {len(files)} files under {shown(tests)}")


def ownership_tool_step() -> Result:
    problem = compile_problem(ROOT / OWNERSHIP_TOOL)
    if problem:
        return Result(FAIL, f"{OWNERSHIP_TOOL} does not compile", problem)
    code, output = run_command([sys.executable, OWNERSHIP_TOOL, "--list"])
    if code != 0:
        return Result(FAIL, f"{OWNERSHIP_TOOL} --list exit {code}", output)
    first = output.strip().splitlines()[0] if output.strip() else "table loaded"
    return Result(PASS, f"compiles; {first}", output)


def skipped_reason(output: str) -> Optional[str]:
    """The cause printed by `check_swift_syntax.py` on its one "skipped:" line, or None when it did not skip."""
    for line in output.splitlines():
        if line.startswith("skipped:"):
            return line[len("skipped:"):].strip().split(". Create", 1)[0]
    return None


def swift_syntax_step(require: bool) -> Callable[[], Result]:
    def step() -> Result:
        problem = compile_problem(ROOT / SYNTAX_TOOL)
        if problem:
            return Result(FAIL, f"{SYNTAX_TOOL} does not compile", problem)
        code, output = run_command([sys.executable, SYNTAX_TOOL, "--all"])
        if code != 0:
            return Result(FAIL, f"exit {code}: python3 {SYNTAX_TOOL} --all", output)
        reason = skipped_reason(output)
        if reason is not None:
            return Result(FAIL if require else SKIP, f"{reason}; setup: {SYNTAX_SETUP}")
        return Result(PASS, last_line(output).split(". ", 1)[0], output)
    return step


CHROME_INK_PATTERN = re.compile(r"secondaryLabelColor|withAlphaComponent\(0\.75\)")
# Files whose inks a later round migrates to the palette's muted and hairline tiers (decision 027, Q-34).
CHROME_INK_PENDING = set()


def check_chrome_inks() -> Result:
    """Chrome draws muted text and rules from the scheme palette, never from system secondary ink or alpha."""
    renderers = ROOT / "Packages/PreviewCore/Sources/PreviewRenderers"
    offenders = []
    for path in sorted(renderers.rglob("*.swift")):
        relative = path.relative_to(ROOT).as_posix()
        if relative in CHROME_INK_PENDING:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if CHROME_INK_PATTERN.search(line):
                offenders.append(f"{relative}:{number}")
    if offenders:
        return Result(FAIL, "system secondary ink or alpha in chrome", "\n".join(offenders))
    pending = len(CHROME_INK_PENDING)
    return Result(PASS, f"no system secondary ink or alpha outside the {pending} file(s) still pending migration")


# ---------------------------------------------------------------------------------------------------
# Dataless guard (decision 027, Q-153; immediate-workstreams plan section 5, task A2)
# ---------------------------------------------------------------------------------------------------
# No SpacePane code path may make a cloud provider download a file implicitly. Every API that opens a
# path, lists a directory or hands a path to a framework therefore lives in a small set of owner files
# that run it inside `DatalessFiles.withoutMaterializing` (or in code that never touches a user file).
# This step fails on any other file, so a new open path needs a reviewed allowlist entry with a reason.
# Matching is textual: it flags a call even when a particular call is harmless, and it cannot see an
# open reached through a framework call that is not in MATERIALIZATION_APIS. The guard supports the
# Q-153 audit; it does not replace the provider observation on a signed host.

GUARDED, RESOURCE, NON_SOURCE, PENDING = "guarded", "resource", "non-source", "pending"
GUARD_KINDS = (GUARDED, RESOURCE, NON_SOURCE, PENDING)

MATERIALIZATION_ROOTS = ("Packages/PreviewCore/Sources", "Extensions", "Apps", "Native")
MATERIALIZATION_SUFFIXES = frozenset({".swift", ".c", ".cc", ".cpp", ".m", ".mm", ".h", ".hpp"})
# A folder with this name is test code (helper fixtures read files by design); it is never production.
MATERIALIZATION_SKIPPED_FOLDER = "Tests"

_C_CALL_PREFIX = r"(?:\b(?:Darwin|Glibc)\.|::|(?<![\w.:]))"  # a C function: bare, Darwin./Glibc. or :: qualified, never `value.name(`
_C_FLAG_ARGUMENTS = r"(?:[^()]|\([^()]*\))*?\bO_[A-Z]"        # an `open` call is recognised by its O_ flag, so a method named open is not


def _c_call(name: str) -> "re.Pattern[str]":
    return re.compile(_C_CALL_PREFIX + name + r"\(")


MATERIALIZATION_APIS: Dict[str, "re.Pattern[str]"] = {
    "open": re.compile(r"\b(?:Darwin|Glibc)\.open\(|(?:::|(?<![\w.:]))open\(" + _C_FLAG_ARGUMENTS),
    "openat": _c_call("openat"),
    "opendir": _c_call("(?:fd)?opendir"),
    "readdir": _c_call("readdir(?:_r)?"),
    "fopen": _c_call("f(?:re)?open"),
    "contentsOf": re.compile(r"\b(?:Data|String|NSString|NSData|NSMutableData|NSDictionary|NSArray|NSImage|NSAttributedString|CIImage)"
                             r"\(\s*(?:contentsOf|contentsOfFile|contentsOfURL|byReferencing(?:File|URL)?)\s*:"),
    "FileHandle": re.compile(r"\bFileHandle\("),
    "CGImageSourceCreateWithURL": re.compile(r"\bCGImageSourceCreateWithURL\b"),
    "sqlite3_open": re.compile(r"\bsqlite3_open(?:_v2|16)?\("),
    "AVURLAsset": re.compile(r"\bAVURLAsset\b|\bAVAsset\(\s*url\b|\bAVAudioFile\(\s*forReading\b"
                             r"|\bAVAudioPlayer\(\s*contentsOf\b|\bAVPlayerItem\(\s*url\b"),
    "MDLAsset": re.compile(r"\bMDLAsset\(\s*url\b"),
    "contentsOfDirectory": re.compile(r"\b(?:contentsOfDirectory|subpathsOfDirectory|directoryContents)\b"
                                      r"|\benumerator\(\s*at(?:Path)?\s*:"),
    "SecStaticCodeCreateWithPath": re.compile(r"\bSecStaticCodeCreateWithPath(?:AndAttributes)?\b"),
    "NSFileCoordinator": re.compile(r"\bNSFileCoordinator\b"),
    "startDownloadingUbiquitousItem": re.compile(r"\bstartDownloadingUbiquitousItem\b"),
    "PDFDocument": re.compile(r"\bPDFDocument\(\s*url\s*:"),
    "contentsAtPath": re.compile(r"\.contents\(\s*atPath\s*:"),
    "InputStream": re.compile(r"\bInputStream\(\s*(?:url|fileAtPath)\s*:"),
    "resourceBytes": re.compile(r"\.resourceBytes\b|\b(?:url|\w+URL)\.lines\b"),
}


class GuardEntry(NamedTuple):
    """One allowlisted file: the APIs it may use, why that is safe, and whether it is a fix still pending."""
    apis: FrozenSet[str]
    kind: str
    reason: str


class Hit(NamedTuple):
    line: int
    api: str


_CORE = "Packages/PreviewCore/Sources"

# Keys are repository-relative paths; every reason is one line. `guarded` runs inside the checked
# no-materialization scope (PreviewFileAccess/DatalessFiles.swift) or reads only bytes a guarded reader
# returned; `resource` reads this app's own bundled files; `non-source` never names a user file;
# `pending` is a known unguarded path whose fix is requested and not yet applied (the gate prints it).
MATERIALIZATION_ALLOWLIST: Dict[str, GuardEntry] = {
    f"{_CORE}/PreviewCore/BoundedReadAccess.swift": GuardEntry(
        frozenset({"open"}), GUARDED,
        "Owner of complete, leading and range reads: Darwin.open runs inside the checked scope with fstat dataless-flag checks."),
    f"{_CORE}/PreviewCore/PreviewMonitorDescriptor.swift": GuardEntry(
        frozenset({"open"}), GUARDED,
        "Monitor owner: the O_EVTONLY open runs inside the checked scope after a raw no-follow lstat and dataless-flag check."),
    f"{_CORE}/PreviewFormats/Containers/DirectoryReadAccess.swift": GuardEntry(
        frozenset({"open", "openat", "opendir", "readdir"}), GUARDED,
        "Folder and bundle owner: the root open, descriptor-relative openat, fdopendir and readdir run inside the checked scope."),
    f"{_CORE}/PreviewFormats/Packages/CodeSigningSummary.swift": GuardEntry(
        frozenset({"SecStaticCodeCreateWithPath"}), GUARDED,
        "Reached only from ApplicationBundleAdapter.parse inside the checked scope; Security opens the bundle path on that thread."),
    f"{_CORE}/PreviewFormats/Containers/SQLiteInspectionAdapter.swift": GuardEntry(
        frozenset({"sqlite3_open"}), GUARDED,
        "Opens :memory: only; sqlite3_deserialize copies bytes a guarded reader already returned, and no source path reaches SQLite."),
    f"{_CORE}/PreviewContracts/FormatCatalog.swift": GuardEntry(
        frozenset({"contentsOf"}), RESOURCE,
        "Reads FormatCatalog.json from this module's own resource bundle, never a user file."),
    "Apps/PrevApp/Models/AppearanceSampleLibrary.swift": GuardEntry(
        frozenset({"FileHandle"}), RESOURCE,
        "Reads the app's bundled appearance-sample manifest; samples are then previewed through the normal guarded pipeline."),
    f"{_CORE}/PreviewCADFormats/CADWorkerProcess.swift": GuardEntry(
        frozenset({"open"}), NON_SOURCE,
        "Opens /dev/null as the helper's discarded stream; the source bytes reach the helper from a guarded reader through a pipe."),
    "Native/CADWorker/main.cpp": GuardEntry(
        frozenset({"open"}), NON_SOURCE,
        "Opens /dev/null as its output sink; the helper takes bytes from standard input and accepts no source path."),
    f"{_CORE}/PreviewPreferences/BoundedPreferencesData.swift": GuardEntry(
        frozenset({"open"}), PENDING,
        "PENDING (request R1): the app-group snapshot is app-owned, but AppearanceThemeReader also opens a user-chosen theme file here."),
    "Apps/PrevApp/Models/QuickLookProviderScanner.swift": GuardEntry(
        frozenset({"open", "opendir", "readdir"}), PENDING,
        "PENDING (request R2): inventory of installed apps under /Applications, not a preview source, opened outside the checked scope."),
}


def blank_comment_lines(text: str) -> str:
    """The text with whole-line comments emptied, so line numbers are unchanged.

    A line that starts with `//`, or a block comment that starts a line, is blanked. A comment after code
    is kept on purpose: telling it from `//` inside a string needs a tokenizer, and hiding code is worse
    than flagging a comment."""
    lines = text.split("\n")
    inside_block = False
    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if inside_block:
            end = line.find("*/")
            inside_block = end < 0
            lines[index] = "" if end < 0 else line[end + 2:]
        elif stripped.startswith("//"):
            lines[index] = ""
        elif stripped.startswith("/*"):
            end = stripped.find("*/", 2)
            inside_block = end < 0
            lines[index] = "" if end < 0 else stripped[end + 2:]
    return "\n".join(lines)


def materialization_hits(text: str) -> List[Hit]:
    """Every use of an API in MATERIALIZATION_APIS outside whole-line comments, by line and identifier."""
    code = blank_comment_lines(text)
    found = {Hit(code.count("\n", 0, match.start()) + 1, api)
             for api, pattern in MATERIALIZATION_APIS.items() for match in pattern.finditer(code)}
    return sorted(found)


def entry_problem(entry: GuardEntry) -> Optional[str]:
    if entry.kind not in GUARD_KINDS:
        return f"unknown kind {entry.kind!r}"
    if not entry.reason.strip():
        return "empty reason"
    if "\n" in entry.reason:
        return "the reason must be one line"
    if not entry.apis:
        return "declares no API"
    unknown = sorted(entry.apis - set(MATERIALIZATION_APIS))
    return f"unknown API {unknown[0]!r}" if unknown else None


def materialization_sources(base: Path, root: str) -> List[Path]:
    folder = base / root
    return sorted(path for path in folder.rglob("*")
                  if path.is_file() and path.suffix in MATERIALIZATION_SUFFIXES
                  and MATERIALIZATION_SKIPPED_FOLDER not in path.relative_to(folder).parts[:-1])


def check_dataless_guard(base: Path = ROOT, roots: Sequence[str] = MATERIALIZATION_ROOTS,
                         allowlist: Optional[Dict[str, GuardEntry]] = None) -> Result:
    """Fail on a file-opening API outside the allowlist, an undeclared API in an allowlisted file or a stale entry."""
    table = MATERIALIZATION_ALLOWLIST if allowlist is None else allowlist
    for root in roots:
        if not (base / root).is_dir():
            return Result(FAIL, f"{root} is not a folder", f"{root} is not a folder under {shown(base)}")
    files = [path for root in roots for path in materialization_sources(base, root)]
    if not files:
        return Result(FAIL, f"no source files under {', '.join(roots)}", "the scan found nothing to check")
    problems: List[str] = []
    valid: Dict[str, GuardEntry] = {}
    for path, entry in sorted(table.items()):
        reason = entry_problem(entry)
        if reason is None:
            valid[path] = entry
        else:
            problems.append(f"allowlist entry {path}: {reason}")
    used: Dict[str, set] = {}
    for path in files:
        relative = path.relative_to(base).as_posix()
        entry = valid.get(relative)
        for hit in materialization_hits(path.read_text(encoding="utf-8", errors="replace")):
            if entry is not None and hit.api in entry.apis:
                used.setdefault(relative, set()).add(hit.api)
            elif entry is not None:
                problems.append(f"{relative}:{hit.line}: {hit.api} is not declared in this file's allowlist entry")
            else:
                problems.append(f"{relative}:{hit.line}: {hit.api} outside the checked owners; route the open through "
                                f"DatalessFiles.withoutMaterializing or add a reviewed MATERIALIZATION_ALLOWLIST entry")
    scanned = {path.relative_to(base).as_posix() for path in files}
    for path, entry in sorted(valid.items()):
        if path not in scanned:
            problems.append(f"stale allowlist entry {path}: no such file under the scanned folders")
            continue
        for api in sorted(entry.apis - used.get(path, set())):
            problems.append(f"stale allowlist entry {path}: no {api} call remains; delete it from the entry")
    if problems:
        detail = problems[0] if len(problems) == 1 else f"{len(problems)} problems"
        return Result(FAIL, detail, "\n".join(problems))
    kinds = [entry.kind for entry in valid.values()]
    pending = sorted(path for path, entry in valid.items() if entry.kind == PENDING)
    detail = (f"{len(files)} files scanned; {len(valid)} files allowlisted ({kinds.count(GUARDED)} guarded, "
              f"{kinds.count(RESOURCE)} resource, {kinds.count(NON_SOURCE)} non-source); {len(pending)} pending")
    listing = "\n".join(f"pending fix: {path}: {valid[path].reason}" for path in pending)
    return Result(PASS, detail, listing)


def dataless_guard_step() -> Result:
    return check_dataless_guard()


def build_steps(require_syntax: bool = False) -> List[Step]:
    return [
        Step("manifests", "script/sync_manifests.py --check",
             script_step(["script/sync_manifests.py", "--check"])),
        Step("appearance samples", "script/generate_appearance_samples.py --check",
             script_step(["script/generate_appearance_samples.py", "--check"])),
        Step("localization tests", "tools/test_localization.py",
             script_step(["tools/test_localization.py"], unittest_summary)),
        Step("benchmark tests", "script/test_compare_benchmarks.py",
             script_step(["script/test_compare_benchmarks.py"], unittest_summary)),
        Step("benchmark runners", "script/test_benchmark_release_summaries.py",
             script_step(["script/test_benchmark_release_summaries.py"], unittest_summary)),
        Step("image benchmark tests", "script/test_benchmark_release_images.py",
             script_step(["script/test_benchmark_release_images.py"], unittest_summary)),
        Step("package link inventory", "script/test_package_link.py",
             script_step(["script/test_package_link.py"], unittest_summary)),
        Step("release archive tests", "script/test_check_release_archive.py",
             script_step(["script/test_check_release_archive.py"], unittest_summary)),
        Step("host matrix", "script/check_host_matrix.py", script_step(["script/check_host_matrix.py"])),
        Step("host matrix tests", "script/test_check_host_matrix.py",
             script_step(["script/test_check_host_matrix.py"], unittest_summary)),
        Step("cad source offer", "script/package_cad_source_offer.py --check",
             script_step(["script/package_cad_source_offer.py", "--check"])),
        Step("cad source offer tests", "script/test_package_cad_source_offer.py",
             script_step(["script/test_package_cad_source_offer.py"], unittest_summary)),
        Step("cad worker protocol tests", "Native/CADWorker/Tests/test_protocol.py",
             script_step(["Native/CADWorker/Tests/test_protocol.py"], unittest_summary)),
        Step("cad build tests", "script/test_build_cad_worker.py",
             script_step(["script/test_build_cad_worker.py"], unittest_summary)),
        Step("review samples", "script/build_review_samples.py --check",
             script_step(["script/build_review_samples.py", "--check"])),
        Step("review sample tests", "script/test_build_review_samples.py",
             script_step(["script/test_build_review_samples.py"], unittest_summary)),
        Step("localization", "tools/validate_localization.py", localization_step),
        Step("shell syntax", "bash -n script/build_and_run.sh", shell_syntax_step),
        Step("decision numbers", "docs/decisions file names", check_decision_numbers),
        Step("wall-clock tests", "WALL_CLOCK_SUITES names in Packages/PreviewCore/Tests", check_wall_clock_tests),
        Step("ownership tool", f"py_compile and --list of {OWNERSHIP_TOOL}", ownership_tool_step),
        Step("chrome inks", "palette tiers instead of system secondary ink in PreviewRenderers", check_chrome_inks),
        Step("dataless guard", "file-opening APIs only in the allowlisted checked owners (Q-153)", dataless_guard_step),
        Step("swift syntax", f"{SYNTAX_TOOL} --all (needs tree-sitter)", swift_syntax_step(require_syntax)),
    ]


# ---------------------------------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------------------------------

def format_line(status: str, name: str, detail: str, seconds: float) -> str:
    timing = f" ({seconds:.1f} s)" if seconds >= 0.05 else ""
    return f"[{status:^4}] {name:<19} {detail}{timing}"


def indented(text: str, limit: Optional[int]) -> str:
    lines = text.rstrip().splitlines()
    omitted = 0
    if limit is not None and len(lines) > limit:
        omitted = len(lines) - limit
        lines = lines[-limit:]
    prefix = [f"         ... {omitted} earlier line(s) not shown; rerun with --verbose"] if omitted else []
    return "\n".join(prefix + ["         " + line for line in lines])


def run_steps(steps: Sequence[Step], verbose: bool = False) -> int:
    counts = {PASS: 0, FAIL: 0, SKIP: 0}
    for step in steps:
        started = time.monotonic()
        try:
            result = step.run()
        except Exception as error:  # a defect in the gate itself must never read as a pass
            result = Result(FAIL, f"internal error: {type(error).__name__}: {error}")
        counts[result.status] += 1
        print(format_line(result.status, step.name, result.detail, time.monotonic() - started), flush=True)
        if result.output.strip() and (verbose or result.status == FAIL):
            print(indented(result.output, None if verbose else FAILURE_OUTPUT_LINES), flush=True)
    summary = f"{counts[PASS]} passed, {counts[SKIP]} skipped, {counts[FAIL]} failed"
    if counts[FAIL]:
        print(f"check_static: FAILED ({summary})")
        return 1
    print(f"check_static: OK ({summary}). This gate does not show that Swift compiles; the macOS job and Mac sessions do.")
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Run the portable static gate (no Apple toolchain needed).")
    parser.add_argument("--verbose", action="store_true", help="print the output of every step")
    parser.add_argument("--require-syntax", action="store_true",
                        help="fail instead of skipping the Swift syntax step when tree-sitter is unavailable")
    parser.add_argument("--list", action="store_true", help="list the steps and what each runs")
    args = parser.parse_args(argv)
    steps = build_steps(args.require_syntax)
    if args.list:
        for step in steps:
            print(f"{step.name:<19} {step.runs}")
        return 0
    print(f"check_static: {len(steps)} steps (Python {sys.version.split()[0]})", flush=True)
    return run_steps(steps, args.verbose)


if __name__ == "__main__":
    sys.exit(main())
