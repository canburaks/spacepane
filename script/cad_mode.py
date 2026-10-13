#!/usr/bin/env python3
"""Say whether this build carries the IGES and STEP previews: prints YES or NO.

usage: cad_mode.py

The single source is PREV_INCLUDE_CAD in Configuration/Base.xcconfig (decision 028); the optional, ignored
Configuration/Local.xcconfig overrides it, as it does every other setting, and a PREV_INCLUDE_CAD environment
variable overrides both so a check can look at the other mode without editing a file. Every script that depends on
the mode (build_and_run.sh, stage_companion.py, validate_project.py, check_release_archive.py) reads it here, and
build_and_run.sh passes the answer to xcodebuild so Xcode and the scripts always agree. Plain Python 3.9.
"""
import os
from pathlib import Path
import re
import sys
from typing import Mapping, Optional

ROOT = Path(__file__).resolve().parents[1]
SETTING = "PREV_INCLUDE_CAD"
CONFIGURATIONS = ("Base.xcconfig", "Local.xcconfig")


def _normalized(value: str, origin: str) -> bool:
    if value not in ("YES", "NO"):
        raise ValueError(f"{SETTING} must be YES or NO, found {value!r} in {origin}")
    return value == "YES"


def include_cad(environ: Optional[Mapping[str, str]] = None, configuration: Optional[Path] = None) -> bool:
    """True when the product carries CAD. `environ` and `configuration` (the folder holding the xcconfig files)
    exist for tests; by default the process environment and this repository's Configuration folder are read."""
    environ = os.environ if environ is None else environ
    if environ.get(SETTING):
        return _normalized(environ[SETTING].strip(), "the environment")
    folder = configuration if configuration is not None else ROOT / "Configuration"
    found: Optional[str] = None
    origin = "Configuration"
    for name in CONFIGURATIONS:
        path = folder / name
        if not path.is_file():
            continue
        for line in path.read_text().splitlines():
            match = re.fullmatch(rf"\s*{SETTING}\s*=\s*([^\s/]*)\s*(?://.*)?", line)
            if match:
                found, origin = match[1], name
    if found is None:
        raise ValueError(f"{SETTING} is not set in Configuration/Base.xcconfig")
    return _normalized(found, origin)


def main() -> int:
    try:
        print("YES" if include_cad() else "NO")
    except (ValueError, OSError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
