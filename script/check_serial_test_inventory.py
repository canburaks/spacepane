#!/usr/bin/env python3
"""Validate the built Swift Testing inventory before excluding serial liveness suites.

Suite selection keeps renamed/new member tests serial. The exact count guard
requires a deliberate review if tests disappear, move or are added. Input is
`swift test list`, not a source-code approximation or successful empty test run.
"""
import argparse
from pathlib import Path
import re

PLAIN_SUITE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def validate_inventory(text, suites, expected_count):
    if not suites or any(not PLAIN_SUITE.fullmatch(name) for name in suites):
        raise ValueError("serial selection requires plain nonempty suite names")
    if len(set(suites)) != len(suites):
        raise ValueError("serial suite names must be unique")
    if type(expected_count) is not int or expected_count <= 0:
        raise ValueError("expected serial test count must be positive")
    pattern = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\.(" + "|".join(suites) + r")/[^\s]+$")
    selected = []
    represented = set()
    for line in text.splitlines():
        match = pattern.fullmatch(line.strip())
        if match:
            selected.append(line.strip())
            represented.add(match.group(1))
    if len(selected) != len(set(selected)):
        raise ValueError("built serial test inventory contains duplicate identifiers")
    missing = set(suites) - represented
    if missing:
        raise ValueError("built inventory has no tests in: " + ", ".join(sorted(missing)))
    if len(selected) != expected_count:
        raise ValueError(f"expected {expected_count} serial liveness tests, discovered {len(selected)}; review the suite change and count together")
    return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory", type=Path)
    parser.add_argument("--suites", required=True)
    parser.add_argument("--expected", required=True, type=int)
    args = parser.parse_args()
    try:
        selected = validate_inventory(args.inventory.read_text(), args.suites.split("|"), args.expected)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Serial test inventory rejected: {error}\n")
    print(f"Serial inventory verified: {len(selected)} tests in {len(args.suites.split('|'))} named suites")


if __name__ == "__main__":
    main()
