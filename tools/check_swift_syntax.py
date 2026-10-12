#!/usr/bin/env python3
"""Fail when a Swift source file has more syntax errors than its recorded baseline.

Decision 027, backlog Q-19. Swift written in a session without a compiler needs some check before it
reaches a Mac session. This gate parses files with tree-sitter and reports the commonest blind
mistakes: unbalanced braces and brackets, broken string interpolation, stray or missing tokens. It is
a SYNTAX gate only. It cannot see a missing import, a wrong type, an unavailable API or an isolation
error, so a clean result is never evidence that the code compiles.

One-time setup. The environment is ignored by git (.venv-tools/ is in .gitignore), is never committed
and never ships; both packages are development-only dependencies (decision 027, D25b):

    python3 -m venv .venv-tools && .venv-tools/bin/pip install tree-sitter tree-sitter-swift

The packages need Python 3.10 or newer (tree-sitter 0.25 and later; the grammar will not load into older
bindings). macOS's /usr/bin/python3 is 3.9, so create the environment with a newer interpreter, for
example `python3.12 -m venv .venv-tools`. When the interpreter that runs this script cannot parse but
.venv-tools exists, the script re-runs itself with that environment's interpreter, so a bare
`tools/check_swift_syntax.py` works without activating anything (PREV_SYNTAX_NO_REEXEC=1 turns that off).

Usage (any Python 3.9 or newer starts it; the packages come from the interpreter that ends up running it):

    .venv-tools/bin/python tools/check_swift_syntax.py --base <commit>      # Swift files changed since a commit
    .venv-tools/bin/python tools/check_swift_syntax.py --all                # every Swift file in the working tree (the default)
    .venv-tools/bin/python tools/check_swift_syntax.py Path/File.swift Dir  # explicit files or folders
    ... --print-baseline                                                    # baseline entries for files with errors (all files by default)
    ... --require                                                           # fail, instead of skipping, without the packages

`--base` compares the working tree with the commit, so staged, unstaged and untracked Swift files count
as well as commits; deleted files are ignored. Without usable packages (missing, or too old to
load the grammar) the script prints one line starting "skipped:" and exits 0, so portable gates may call
it unconditionally; CI passes --require.

The baseline, tools/swift-syntax-baseline.json, lists files on which tree-sitter-swift reports errors
for valid Swift (parser gaps) with the number of ERROR plus MISSING nodes tolerated in each. A file
fails when it has MORE such nodes than its entry (a file without an entry tolerates none). A real
mistake inside a file that already has known gaps is therefore caught only if it adds nodes. Counts
depend on the grammar version: the baseline records the versions it was made with, and a failure
prints a note when the installed versions differ. Regenerate entries with --print-baseline and keep a
comment on each saying which construct the parser cannot read.

Exit status: 0 clean (or skipped), 1 syntax errors above the baseline, 2 usage or environment error.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, NamedTuple, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASELINE = ROOT / "tools" / "swift-syntax-baseline.json"
SETUP_COMMAND = "python3 -m venv .venv-tools && .venv-tools/bin/pip install tree-sitter tree-sitter-swift"
SETUP_HINT = (f"Create the ignored environment once with `{SETUP_COMMAND}` using Python 3.10 or newer (for example "
              "`python3.12 -m venv .venv-tools`), then run .venv-tools/bin/python tools/check_swift_syntax.py")
PACKAGES = ("tree-sitter", "tree-sitter-swift")
TOOLS_ENVIRONMENT_PYTHON = ROOT / ".venv-tools" / "bin" / "python"
NO_REEXEC_VARIABLE = "PREV_SYNTAX_NO_REEXEC"  # also set before re-running, so the child never re-runs again
# Folders that never hold repository Swift sources; used when walking a folder or when git is unavailable.
SKIPPED_DIRECTORIES = frozenset({".git", ".build", ".swiftpm", ".venv-tools", "node_modules", "dist",
                                 "DerivedData", "__pycache__"})
DEFAULT_REPORT_LIMIT = 5

Problem = Tuple[int, int, str]  # line, column (both 1-based), "ERROR" or "MISSING <node type>"


class GitError(RuntimeError):
    pass


class BaselineError(ValueError):
    pass


class Baseline(NamedTuple):
    allowed: Dict[str, int]
    recorded_with: Dict[str, str]


class Evaluation(NamedTuple):
    failures: List[Tuple[str, int, int]]  # path, nodes found, nodes allowed
    known: List[Tuple[str, int]]  # files with errors, all within their baseline
    improved: List[Tuple[str, int, int]]  # baseline files that now have fewer nodes than recorded


def package_versions() -> Dict[str, str]:
    from importlib import metadata

    versions = {}
    for name in PACKAGES:
        try:
            versions[name] = metadata.version(name)
        except metadata.PackageNotFoundError:
            versions[name] = "unknown"
    return versions


def load_parser():
    """Return a tree-sitter parser for Swift. Raises ImportError when the packages are missing."""
    import tree_sitter
    import tree_sitter_swift

    language = tree_sitter.Language(tree_sitter_swift.language())
    try:
        return tree_sitter.Parser(language)
    except TypeError:  # tree-sitter before 0.22 builds an empty parser first
        parser = tree_sitter.Parser()
        parser.set_language(language)
        return parser


def environment_interpreter() -> Optional[str]:
    """The tools environment's interpreter, when it exists, is not the running one and re-running is allowed."""
    if os.environ.get(NO_REEXEC_VARIABLE):
        return None
    candidate = str(TOOLS_ENVIRONMENT_PYTHON)
    if TOOLS_ENVIRONMENT_PYTHON.exists() and os.path.abspath(candidate) != os.path.abspath(sys.executable):
        return candidate
    return None


def rerun_with(interpreter: str, argv: Optional[Sequence[str]]) -> None:
    """Replace this process with the same command under `interpreter`. Returns only if that fails."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    os.environ[NO_REEXEC_VARIABLE] = "1"
    try:
        os.execv(interpreter, [interpreter, str(Path(__file__).resolve()), *arguments])
    except OSError:
        pass


def syntax_problems(parser, data: bytes) -> List[Problem]:
    """Every ERROR and MISSING node of the parse, in source order. A full walk keeps the count exact."""
    found: List[Problem] = []
    stack = [parser.parse(data).root_node]
    while stack:
        node = stack.pop()
        if node.type == "ERROR":
            found.append((node.start_point[0] + 1, node.start_point[1] + 1, "ERROR"))
        elif node.is_missing:
            found.append((node.start_point[0] + 1, node.start_point[1] + 1, "MISSING " + node.type))
        stack.extend(node.children)
    found.sort()
    return found


def load_baseline(path: Path) -> Baseline:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise BaselineError(f"cannot read baseline {path}: {error}") from error
    files = document.get("files") if isinstance(document, dict) else None
    if not isinstance(files, dict):
        raise BaselineError(f"{path}: expected an object with a \"files\" object")
    allowed: Dict[str, int] = {}
    for name, entry in files.items():
        count = entry.get("errorNodes") if isinstance(entry, dict) else None
        if not isinstance(count, int) or isinstance(count, bool) or count < 0:
            raise BaselineError(f"{path}: \"{name}\" needs an integer \"errorNodes\" of at least 0")
        allowed[name] = count
    recorded = document.get("recordedWith", {})
    if not isinstance(recorded, dict):
        raise BaselineError(f"{path}: \"recordedWith\" must be an object")
    return Baseline(allowed, {str(key): str(value) for key, value in recorded.items()})


def evaluate(found: Dict[str, List[Problem]], allowed: Dict[str, int]) -> Evaluation:
    """Compare node counts per file with the baseline; a file without an entry tolerates none."""
    failures, known, improved = [], [], []
    for path in sorted(found):
        count = len(found[path])
        limit = allowed.get(path, 0)
        if count > limit:
            failures.append((path, count, limit))
        elif count > 0:
            known.append((path, count))
        if path in allowed and count < limit:
            improved.append((path, count, limit))
    return Evaluation(failures, known, improved)


def git_names(*arguments: str) -> List[str]:
    try:
        result = subprocess.run(["git", *arguments], cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as error:
        raise GitError(f"git is not available: {error}") from error
    if result.returncode != 0:
        raise GitError(result.stderr.decode("utf-8", "replace").strip() or f"git {arguments[0]} failed")
    return [item.decode("utf-8", "surrogateescape") for item in result.stdout.split(b"\0") if item]


def existing_swift(names: Sequence[str]) -> List[str]:
    return sorted({name for name in names if name.endswith(".swift") and (ROOT / name).is_file()})


def changed_swift_files(base: str) -> List[str]:
    """Swift files that differ from `base` in the working tree, plus untracked ones; deletions are dropped."""
    changed = git_names("diff", "--name-only", "-z", "--diff-filter=ACMRT", base, "--")
    untracked = git_names("ls-files", "-z", "--others", "--exclude-standard")
    return existing_swift(changed + untracked)


def walk_swift(directory: Path) -> List[str]:
    found = []
    for path in sorted(directory.rglob("*.swift")):
        relative = path.relative_to(directory)
        if path.is_file() and not any(part in SKIPPED_DIRECTORIES for part in relative.parts):
            found.append(display_path(path))
    return found


def all_swift_files() -> List[str]:
    """Every Swift file git tracks or could track (untracked, not ignored); a plain walk without git."""
    try:
        return existing_swift(git_names("ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.swift"))
    except GitError:
        return walk_swift(ROOT)


def display_path(path: Path) -> str:
    """Repository-relative path with forward slashes when the file is inside the repository."""
    resolved = path.resolve()
    try:
        return resolved.relative_to(ROOT).as_posix()
    except ValueError:
        return resolved.as_posix()


def explicit_swift_files(paths: Sequence[str]) -> List[str]:
    found: List[str] = []
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            found.extend(walk_swift(path))
        elif path.is_file():
            if path.suffix == ".swift":
                found.append(display_path(path))
            else:
                print(f"ignored (not a .swift file): {raw}", file=sys.stderr)
        else:
            raise FileNotFoundError(f"no such file or folder: {raw}")
    return sorted(set(found))


def absolute(name: str) -> Path:
    path = Path(name)
    return path if path.is_absolute() else ROOT / path


def describe(name: str, problem: Problem, lines: Sequence[str]) -> str:
    line, column, kind = problem
    text = lines[line - 1].strip() if 0 < line <= len(lines) else ""
    if len(text) > 100:
        text = text[:97] + "..."
    return f"    {name}:{line}:{column}: {kind}" + (f"  | {text}" if text else "")


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Fail when a Swift file has more tree-sitter syntax errors than its baseline "
                    "(a syntax check only; it does not prove the code compiles).",
        epilog=f"Setup: {SETUP_COMMAND}")
    parser.add_argument("paths", nargs="*", help="Swift files or folders to check")
    parser.add_argument("--base", metavar="COMMIT", help="check Swift files changed since COMMIT (working tree included)")
    parser.add_argument("--all", action="store_true", help="check every Swift file in the working tree")
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE, help="baseline JSON (default: %(default)s)")
    parser.add_argument("--require", action="store_true", help="fail instead of skipping when the packages are not importable")
    parser.add_argument("--print-baseline", action="store_true",
                        help="print baseline entries for every checked file with errors instead of checking")
    parser.add_argument("--max-report", type=int, default=DEFAULT_REPORT_LIMIT, metavar="N",
                        help="error locations printed per failing file (default: %(default)s)")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    argument_parser = build_argument_parser()
    args = argument_parser.parse_args(argv)
    if not (args.base or args.all or args.paths):
        args.all = True  # a bare run checks everything; AGENTS.md asks for it before each push
    if sum([bool(args.base), bool(args.all), bool(args.paths)]) != 1:
        argument_parser.error("give only one of --base COMMIT, --all or explicit paths")

    try:
        parser = load_parser()
    except ImportError as error:
        problem = f"the tree-sitter packages are not importable ({error})"
    except Exception as error:  # packages present, but the grammar and the bindings are incompatible
        problem = f"cannot build a Swift parser ({error})"
    else:
        problem = None
    if problem:
        interpreter = environment_interpreter()
        if interpreter:
            rerun_with(interpreter, argv)
        if args.require:
            print(f"error: {problem}. {SETUP_HINT}", file=sys.stderr)
            return 2
        print(f"skipped: {problem}. {SETUP_HINT}")
        return 0

    try:
        # Creating the baseline must not require one to exist already.
        baseline = Baseline({}, {}) if args.print_baseline else load_baseline(args.baseline)
        if args.base:
            files = changed_swift_files(args.base)
        elif args.all:
            files = all_swift_files()
        else:
            files = explicit_swift_files(args.paths)
    except (BaselineError, GitError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    found: Dict[str, List[Problem]] = {}
    contents: Dict[str, bytes] = {}
    for name in files:
        try:
            data = absolute(name).read_bytes()
        except OSError as error:
            print(f"error: cannot read {name}: {error}", file=sys.stderr)
            return 2
        problems = syntax_problems(parser, data)
        found[name] = problems
        if problems:
            contents[name] = data

    versions = package_versions()
    if args.print_baseline:
        entries = {name: {"errorNodes": len(problems), "comment": ""} for name, problems in sorted(found.items()) if problems}
        print(json.dumps({"recordedWith": versions, "files": entries}, indent=2, ensure_ascii=False))
        return 0

    result = evaluate(found, baseline.allowed)
    for name, count, limit in result.improved:
        print(f"note: {name} has {count} error node(s), below its baseline of {limit}; "
              f"{'remove' if count == 0 else 'lower'} its entry in {display_path(args.baseline)}.")
    if args.all:
        for name in sorted(baseline.allowed):
            if not absolute(name).is_file():
                print(f"note: baseline entry {name} names a file that no longer exists; remove it.")

    label = ", ".join(f"{package} {versions[package]}" for package in PACKAGES)
    if result.failures:
        print("Swift syntax errors above the baseline:")
        for name, count, limit in result.failures:
            print(f"  {name}: {count} error node(s), baseline allows {limit}")
            lines = contents[name].decode("utf-8", "replace").split("\n")
            shown = found[name][:max(args.max_report, 0)]
            for problem in shown:
                print(describe(name, problem, lines))
            if len(found[name]) > len(shown):
                print(f"    ... and {len(found[name]) - len(shown)} more")
            if limit:
                print(f"    (the locations include the {limit} node(s) the baseline already tolerates)")
        mismatched = {key: value for key, value in baseline.recorded_with.items() if versions.get(key) != value}
        if mismatched:
            recorded = ", ".join(f"{key} {value}" for key, value in sorted(mismatched.items()))
            print(f"note: the baseline was recorded with {recorded}; this run uses {label}. If a known file now fails, "
                  f"regenerate its entry with --print-baseline.")
        print(f"FAILED: {len(result.failures)} file(s) have more syntax errors than their baseline. These are syntax errors only; "
              f"for valid Swift that tree-sitter cannot read, add a commented entry to {display_path(args.baseline)}.")
        return 1

    known = f"; {len(result.known)} known parser gap(s) within the baseline" if result.known else ""
    print(f"Swift syntax OK: {len(files)} file(s) checked with {label}{known}. "
          f"This is a syntax check only; it does not show that the code compiles.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
