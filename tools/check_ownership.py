#!/usr/bin/env python3
"""Check that a workstream's changes stay inside the files it owns.

Decision 027, backlog Q-20: decision 026's ownership table, as amended by decision 027, turned into a
check. Parallel agents own disjoint files (AGENTS.md, "Working without a compiler"); the table is
tools/ownership.json, a map from workstream name to path globs, plus "lead" for everything shared.

    python3 tools/check_ownership.py --workstream ux-chrome --base <commit>
    python3 tools/check_ownership.py --workstream ux-chrome --base <commit> --allow-shared
    python3 tools/check_ownership.py --list [--workstream ux-chrome]    # print the globs
    python3 tools/check_ownership.py --audit [--verbose]                # find gaps in the table

The check lists the files that differ from <commit> in the working tree (staged, unstaged and untracked
files; a rename counts as a deletion plus an addition) and puts each into one category:

    owned     matches one of the workstream's own globs.
    new test  a NEW test file (under Packages/PreviewCore/Tests, Tests, script/test_*.py or tools/test_*.py)
              whose name contains the workstream's slug: its name, or its name without the "ux-" or "q-"
              prefix, compared case-insensitively and ignoring everything but letters and digits.
              Existing test files stay with the lead.
    shared    matches a "lead" glob (contracts, catalogs, plan, changelog, existing tests ...). Fails unless
              --allow-shared is given, which the lead does after approving the edit.
    other     belongs to another workstream. Always fails.
    unowned   matches no entry in the table. Always fails: the lead assigns the file in tools/ownership.json
              before anyone edits it.

A workstream's own globs win over the lead's, so a file listed for both is the workstream's. Globs are
relative to the repository root: `*` and `?` stay inside one path component and a `**` component matches
any number of directories (`dir/**` is everything below dir). With --workstream lead the lead's globs are
the owned set. Decision 027 amendment 2 lets every workstream that adds strings commit its
PreviewStrings.swift cases below its own marker; this check cannot see markers, so review that block by eye.

Exit status: 0 allowed, 1 violations, 2 usage, table or git error.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, NamedTuple, Optional, Pattern, Sequence

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "tools" / "ownership.json"
LEAD = "lead"
# Where a workstream may add NEW test files, provided the file name carries its slug.
NEW_TEST_FILE_GLOBS = ("Packages/PreviewCore/Tests/**", "Tests/**", "script/test_*.py", "tools/test_*.py")
WORKSTREAM_NAME = re.compile(r"^[a-z0-9][a-z0-9-]*$")
SLUG_PREFIXES = ("ux-", "q-")


class ConfigError(ValueError):
    pass


class GitError(RuntimeError):
    pass


class Change(NamedTuple):
    path: str
    status: str  # "A" added or untracked, "M" modified, "D" deleted


class Verdict(NamedTuple):
    path: str
    status: str
    category: str  # owned, new test, shared, other or unowned
    note: str = ""


# ---------------------------------------------------------------------------------------------------
# Globs
# ---------------------------------------------------------------------------------------------------

def glob_problem(pattern: str) -> Optional[str]:
    """Why a glob is not accepted, or None. Rejecting what the matcher cannot honour avoids silent surprises."""
    if not pattern:
        return "is empty"
    if pattern.startswith("/") or "\\" in pattern:
        return "must be a repository-relative path with forward slashes"
    if any(character in pattern for character in "[]{}"):
        return "uses a character class or brace group, which is not supported"
    segments = pattern.split("/")
    if any(not segment for segment in segments):
        return "has an empty path component (write `dir/**`, not `dir/`)"
    if ".." in segments or "." in segments:
        return "must not contain `.` or `..` components"
    return None


def glob_to_regex(pattern: str) -> Pattern[str]:
    """Translate a path glob: `*` and `?` stay in one path component, a whole `**` component spans directories."""
    segments = pattern.split("/")
    parts: List[str] = []
    for index, segment in enumerate(segments):
        last = index == len(segments) - 1
        if segment == "**":
            parts.append(".+" if last else "(?:[^/]+/)*")
            continue
        parts.append("".join("[^/]*" if c == "*" else "[^/]" if c == "?" else re.escape(c) for c in segment))
        if not last:
            parts.append("/")
    return re.compile("\\A" + "".join(parts) + "\\Z")


def any_match(patterns: Sequence[Pattern[str]], path: str) -> bool:
    return any(pattern.match(path) for pattern in patterns)


NEW_TEST_FILE_PATTERNS = [glob_to_regex(glob) for glob in NEW_TEST_FILE_GLOBS]


# ---------------------------------------------------------------------------------------------------
# The table
# ---------------------------------------------------------------------------------------------------

class Table:
    def __init__(self, globs: Dict[str, List[str]]) -> None:
        self.globs = globs
        self._patterns = {name: [glob_to_regex(glob) for glob in values] for name, values in globs.items()}

    def names(self) -> List[str]:
        """The lead first, then the workstreams in file order."""
        return [LEAD] + [name for name in self.globs if name != LEAD]

    def matches(self, name: str, path: str) -> bool:
        return any_match(self._patterns[name], path)

    def workstreams_matching(self, path: str, excluding: Sequence[str] = ()) -> List[str]:
        return [name for name in self.globs if name != LEAD and name not in excluding and self.matches(name, path)]


def load_table(path: Path) -> Table:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ConfigError(f"cannot read the ownership table {path}: {error}") from error
    if not isinstance(document, dict):
        raise ConfigError(f"{path}: expected a JSON object of workstream name to glob list")
    globs: Dict[str, List[str]] = {}
    for name, values in document.items():
        if name.startswith("_"):  # annotations such as "_comment"
            continue
        if not WORKSTREAM_NAME.match(name):
            raise ConfigError(f"{path}: workstream name {name!r} must be lower-case letters, digits and hyphens")
        if not isinstance(values, list) or not values or not all(isinstance(value, str) for value in values):
            raise ConfigError(f"{path}: {name!r} must be a non-empty list of glob strings")
        for glob in values:
            problem = glob_problem(glob)
            if problem:
                raise ConfigError(f"{path}: {name!r}: glob {glob!r} {problem}")
        globs[name] = values
    if LEAD not in globs:
        raise ConfigError(f"{path}: the table needs a {LEAD!r} entry for the shared files")
    return Table(globs)


# ---------------------------------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------------------------------

def normalize(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", text.lower())


def slug_aliases(workstream: str) -> List[str]:
    """The names a new test file may carry: the workstream name, and the name without its ux- or q- prefix."""
    names = [workstream]
    for prefix in SLUG_PREFIXES:
        if workstream.startswith(prefix) and len(workstream) > len(prefix):
            names.append(workstream[len(prefix):])
    return names


def carries_slug(workstream: str, path: str) -> bool:
    name = normalize(Path(path).name)
    return any(normalize(alias) in name for alias in slug_aliases(workstream))


def classify(change: Change, workstream: str, table: Table) -> Verdict:
    path = change.path
    if table.matches(workstream, path):
        return Verdict(path, change.status, "owned")
    is_new_test = change.status == "A" and any_match(NEW_TEST_FILE_PATTERNS, path)
    if is_new_test and carries_slug(workstream, path):
        return Verdict(path, change.status, "new test")
    if table.matches(LEAD, path):
        note = ""
        if is_new_test:
            note = ("a new test file's name must contain " + " or ".join(f'"{alias}"' for alias in slug_aliases(workstream))
                    + " (case and punctuation ignored)")
        return Verdict(path, change.status, "shared", note)
    others = table.workstreams_matching(path, excluding=[workstream])
    if others:
        return Verdict(path, change.status, "other", "owned by " + ", ".join(others))
    return Verdict(path, change.status, "unowned", "matches no entry in the ownership table")


def is_violation(verdict: Verdict, allow_shared: bool) -> bool:
    return verdict.category in ("other", "unowned") or (verdict.category == "shared" and not allow_shared)


# ---------------------------------------------------------------------------------------------------
# Git
# ---------------------------------------------------------------------------------------------------

def git_output(*arguments: str) -> List[str]:
    """NUL-separated output of a git command run at the repository root."""
    try:
        result = subprocess.run(["git", *arguments], cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as error:
        raise GitError(f"git is not available: {error}") from error
    if result.returncode != 0:
        raise GitError(result.stderr.decode("utf-8", "replace").strip() or f"git {arguments[0]} failed")
    return [item.decode("utf-8", "surrogateescape") for item in result.stdout.split(b"\0")]


def changed_files(base: str) -> List[Change]:
    """Files that differ from `base` in the working tree, plus untracked files. Renames are not detected."""
    if base.startswith("-"):
        raise GitError(f"invalid base {base!r}")
    tokens = git_output("diff", "--name-status", "-z", "--no-renames", base, "--")
    changes: Dict[str, str] = {}
    for index in range(0, len(tokens) - 1, 2):
        status, path = tokens[index], tokens[index + 1]
        if status:
            changes[path] = "A" if status[0] == "A" else "D" if status[0] == "D" else "M"
    for path in git_output("ls-files", "-z", "--others", "--exclude-standard"):
        if path:
            changes.setdefault(path, "A")
    return [Change(path, changes[path]) for path in sorted(changes)]


def working_tree_files() -> List[str]:
    names = git_output("ls-files", "-z", "--cached", "--others", "--exclude-standard")
    return sorted({name for name in names if name and (ROOT / name).is_file()})


# ---------------------------------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------------------------------

def summary_line(table: Table, path: Path) -> str:
    count = sum(len(values) for values in table.globs.values())
    workstreams = len(table.globs) - 1
    try:
        shown = path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        shown = str(path)
    return f"{shown}: {len(table.globs)} owners (the lead and {workstreams} workstreams), {count} globs"


def print_listing(table: Table, config: Path, only: Optional[str]) -> None:
    print(summary_line(table, config))
    for name in [only] if only else table.names():
        if name == LEAD:
            print(f"{LEAD}  (shared files; any other workstream needs --allow-shared to change them)")
        else:
            print(f"{name}  (new test files may carry: {', '.join(slug_aliases(name))})")
        for glob in table.globs[name]:
            print(f"  {glob}")
    print("new test files are allowed in " + ", ".join(NEW_TEST_FILE_GLOBS) + " when the file name carries the workstream slug")


CATEGORY_ORDER = {"unowned": 0, "other": 1, "shared": 2, "new test": 3, "owned": 4}


def print_check(workstream: str, verdicts: Sequence[Verdict], allow_shared: bool, verbose: bool) -> int:
    violations = [verdict for verdict in verdicts if is_violation(verdict, allow_shared)]
    for verdict in sorted(verdicts, key=lambda item: (CATEGORY_ORDER[item.category], item.path)):
        if verdict in violations:
            label = {"shared": "SHARED", "other": "OTHER", "unowned": "UNOWNED"}[verdict.category]
        elif verbose or verdict.category == "shared":
            label = "ok" if verdict.category != "shared" else "ok (shared, --allow-shared)"
        else:
            continue
        note = f"  [{verdict.note}]" if verdict.note else ""
        print(f"  {label:<8} {verdict.status} {verdict.path}{note}")
    counts = {category: sum(1 for verdict in verdicts if verdict.category == category)
              for category in ("owned", "new test", "shared", "other", "unowned")}
    detail = ", ".join(f"{count} {category}" for category, count in counts.items() if count) or "nothing changed"
    if violations:
        hints = []
        if any(verdict.category == "shared" for verdict in violations):
            hints.append("shared files need the lead's approval: rerun with --allow-shared once approved")
        if any(verdict.category in ("other", "unowned") for verdict in violations):
            hints.append("ask the lead to assign or reassign these files in tools/ownership.json")
        print(f"FAILED {workstream}: {len(violations)} of {len(verdicts)} changed file(s) outside its ownership ({detail}). "
              + "; ".join(hints) + ".")
        return 1
    print(f"OK {workstream}: {len(verdicts)} changed file(s) allowed ({detail}).")
    return 0


def parent_directory(path: str) -> str:
    return path.rsplit("/", 1)[0] if "/" in path else "."


def print_audit(table: Table, files: Sequence[str], config: Path, verbose: bool) -> None:
    print(summary_line(table, config) + f"; {len(files)} files in the working tree")
    unowned = [path for path in files if not table.matches(LEAD, path) and not table.workstreams_matching(path)]
    claimed = [(path, names) for path in files for names in [table.workstreams_matching(path)] if len(names) > 1]
    dead = [(name, glob) for name in table.names() for glob in table.globs[name]
            if not any(glob_to_regex(glob).match(path) for path in files)]
    print(f"unowned files: {len(unowned)} (matched by no entry; assign them before anyone edits them)")
    if verbose:
        for path in unowned:
            print(f"  {path}")
    else:
        directories: Dict[str, int] = {}
        for path in unowned:
            directories[parent_directory(path)] = directories.get(parent_directory(path), 0) + 1
        for directory in sorted(directories):
            print(f"  {directory}/  ({directories[directory]})")
    print(f"files claimed by more than one workstream: {len(claimed)} (intended where the table says so)")
    for path, names in claimed:
        print(f"  {path}: {', '.join(names)}")
    print(f"globs that match no file: {len(dead)} (expected for files not created yet)")
    for name, glob in dead:
        print(f"  {name}: {glob}")


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Check that a workstream's changes stay inside the files it owns.",
                                     epilog="Table: tools/ownership.json. Decision 027, Q-20.")
    parser.add_argument("--workstream", help="workstream name from the table (or lead)")
    parser.add_argument("--base", metavar="COMMIT", help="compare the working tree with this commit")
    parser.add_argument("--allow-shared", action="store_true", help="accept changes to the lead's shared files (the lead's approval)")
    parser.add_argument("--list", action="store_true", help="print the globs (of --workstream, or of everyone)")
    parser.add_argument("--audit", action="store_true", help="report unowned files, shared claims and globs that match nothing")
    parser.add_argument("--verbose", action="store_true", help="also list allowed files (check) or every unowned file (audit)")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG, help="ownership table (default: %(default)s)")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_argument_parser()
    args = parser.parse_args(argv)
    if args.list and args.audit:
        parser.error("--list and --audit are separate modes")
    if not (args.list or args.audit) and not (args.workstream and args.base):
        parser.error("give --workstream and --base (or --list, or --audit)")
    try:
        table = load_table(args.config)
        if args.workstream and args.workstream not in table.globs:
            raise ConfigError(f"unknown workstream {args.workstream!r}; the table has: {', '.join(table.names())}")
        if args.list:
            print_listing(table, args.config, args.workstream)
            return 0
        if args.audit:
            print_audit(table, working_tree_files(), args.config, args.verbose)
            return 0
        changes = changed_files(args.base)
    except (ConfigError, GitError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    verdicts = [classify(change, args.workstream, table) for change in changes]
    return print_check(args.workstream, verdicts, args.allow_shared, args.verbose)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:  # output piped into head or less and closed early
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(0)
