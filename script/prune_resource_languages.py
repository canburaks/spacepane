#!/usr/bin/env python3
"""Remove the draft languages from the resource bundles nested in a built app or extension.

usage: prune_resource_languages.py RESOURCES_FOLDER [--policy tools/localization/languages.json]

RESOURCES_FOLDER is a host's `Contents/Resources`. Every `*.bundle` directly inside it (today only
`PreviewCore_PreviewRenderers.bundle`, which SwiftPM builds from every chosen language) loses each `.lproj`
folder whose language is not in the policy file's `shipped` list. The folders at the top of the host are not
touched: they come from `script/build_metadata.py`, and `script/check_release_archive.py` compares them with the
ship list. The drafts stay in the repository and in the package; only the shipped product omits them.

Xcode runs this after the host's resources are copied and before code signing, so the seal covers the pruned
bundle (review of 2026-10-17, finding 16). Plain Python 3.9 and the standard library only.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import sys
from typing import List, Sequence, Tuple

DEFAULT_POLICY = Path(__file__).resolve().parents[1] / "tools/localization/languages.json"
LPROJ = ".lproj"


def load_policy(path: Path) -> Tuple[List[str], str]:
    """The ship list and the development language of the policy file, which must be consistent."""
    policy = json.loads(Path(path).read_text())
    shipped, development = list(policy["shipped"]), policy["developmentLanguage"]
    if not shipped:
        raise ValueError("The ship list is empty")
    if development not in shipped:
        raise ValueError(f"The ship list {shipped} lacks the development language {development}")
    return shipped, development


def language_folders(bundle: Path) -> List[Path]:
    """Every `.lproj` folder or link in the bundle, whatever its layout (`Contents/Resources` or flat)."""
    return sorted(path for path in bundle.rglob(f"*{LPROJ}") if path.is_dir() or path.is_symlink())


def prune(resources: Path, shipped: Sequence[str], development: str) -> List[Path]:
    """Delete the non-shipped `.lproj` folders of each nested bundle; return the paths removed.

    A bundle that carries languages must keep the development language: it is the fallback of the typed
    string API, and a bundle that would lose it is reported before anything is deleted.
    """
    if not resources.is_dir():
        raise ValueError(f"Resources folder not found: {resources}")
    doomed: List[Path] = []
    for bundle in sorted(item for item in resources.iterdir() if item.suffix == ".bundle" and item.is_dir()):
        present = language_folders(bundle)
        if not present:
            continue
        kept = {path.name[:-len(LPROJ)] for path in present} & set(shipped)
        if development not in kept:
            raise ValueError(f"{bundle.name} would lose its development language {development}; "
                             f"it carries {sorted(path.name for path in present)}")
        doomed += [path for path in present if path.name[:-len(LPROJ)] not in shipped]
    for path in doomed:
        if path.is_symlink():
            path.unlink()
        else:
            shutil.rmtree(path)
    return doomed


def main(argv: Sequence[str] = ()) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("resources", type=Path, help="a host's Contents/Resources folder")
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY, help="the language policy file")
    arguments = parser.parse_args(argv or sys.argv[1:])
    try:
        shipped, development = load_policy(arguments.policy)
        removed = prune(arguments.resources, shipped, development)
    except (OSError, ValueError, KeyError) as error:
        print(f"prune_resource_languages: {error}", file=sys.stderr)
        return 1
    for path in removed:
        print(f"Pruned {path.relative_to(arguments.resources)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
