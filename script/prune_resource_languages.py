#!/usr/bin/env python3
"""Remove the draft languages from the resource bundles nested in a built app or extension.

usage: prune_resource_languages.py RESOURCES_FOLDER [--bundle NAME ...] [--policy tools/localization/languages.json]

RESOURCES_FOLDER is a host's `Contents/Resources`. Each named nested bundle (every `*.bundle` directly inside the
folder when none is named) loses each `.lproj` folder whose language is not in the policy file's `shipped` list.
The Xcode phases name `PreviewCore_PreviewRenderers.bundle`, which SwiftPM builds from every chosen language. The
folders at the top of the host are not touched: they come from `script/build_metadata.py`, and
`script/check_release_archive.py` compares them with the ship list and refuses a draft in any nested bundle. The
drafts stay in the repository and in the package; only the shipped product omits them.

Xcode runs this after the host's resources are copied and before code signing, so the seal covers the pruned
bundle (review of 2026-10-17, finding 16). The phase runs in the user-script sandbox, which allows writes only to
declared outputs: script/prune-outputs.xcfilelist names every file the script may delete, and the script never
reads a folder it does not delete or keep by name. Plain Python 3.9 and the standard library only.
"""
from __future__ import annotations

import argparse
import json
import os
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
    """Every `.lproj` folder or link in the bundle, whatever its layout (`Contents/Resources` or flat).

    Language folders are listed, never entered, so the walk needs no access to the ones a build keeps.
    """
    found: List[Path] = []
    for directory, names, _ in os.walk(bundle):
        found += [Path(directory, name) for name in names if name.endswith(LPROJ)]
        names[:] = [name for name in names if not name.endswith(LPROJ)]
    return sorted(found)


def prune(resources: Path, shipped: Sequence[str], development: str, bundles: Sequence[str] = ()) -> List[Path]:
    """Delete the non-shipped `.lproj` folders of the named nested bundles; return the paths removed.

    `bundles` names directories of `resources`; none means every `*.bundle` there. A bundle that carries
    languages must keep the development language: it is the fallback of the typed string API, and a bundle
    that would lose it is reported before anything is deleted.
    """
    if not resources.is_dir():
        raise ValueError(f"Resources folder not found: {resources}")
    if bundles:
        missing = [name for name in bundles if not (resources / name).is_dir()]
        if missing:
            raise ValueError(f"Nested bundle not found in {resources}: {', '.join(missing)}")
        chosen = sorted(resources / name for name in bundles)
    else:
        chosen = sorted(item for item in resources.iterdir() if item.suffix == ".bundle" and item.is_dir())
    doomed: List[Path] = []
    for bundle in chosen:
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
    parser.add_argument("--bundle", action="append", default=[], metavar="NAME",
                        help="a nested bundle to prune (repeatable); every nested bundle when omitted")
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY, help="the language policy file")
    arguments = parser.parse_args(argv or sys.argv[1:])
    try:
        shipped, development = load_policy(arguments.policy)
        removed = prune(arguments.resources, shipped, development, arguments.bundle)
    except (OSError, ValueError, KeyError) as error:
        print(f"prune_resource_languages: {error}", file=sys.stderr)
        return 1
    for path in removed:
        print(f"Pruned {path.relative_to(arguments.resources)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
