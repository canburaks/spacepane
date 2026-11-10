#!/usr/bin/env python3
"""Embed the pre-staged, inside-out signed Sparkle.framework in the companion app when PREV_INCLUDE_SPARKLE is YES."""
from __future__ import annotations

import os
from pathlib import Path
import shutil


def remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def main() -> int:
    project_dir = Path(os.environ["PROJECT_DIR"])
    destination_root = (
        Path(os.environ["TARGET_BUILD_DIR"]) / os.environ["FRAMEWORKS_FOLDER_PATH"]
    )
    destination = destination_root / "Sparkle.framework"

    if os.environ.get("PREV_INCLUDE_SPARKLE", "NO") != "YES":
        remove_path(destination)
        return 0

    architectures = os.environ.get("ARCHS", "").split()
    if not architectures:
        raise SystemExit("ARCHS is empty; cannot select Sparkle runtime slice.")
    primary_arch = architectures[0]
    source = project_dir / ".build" / "sparkle" / f"runtime-{primary_arch}" / "Sparkle.framework"
    if not source.is_dir():
        raise SystemExit(
            f"Missing {source}. Run `python3 script/build_sparkle.py --architecture {primary_arch}` before building."
        )

    destination_root.mkdir(parents=True, exist_ok=True)
    remove_path(destination)
    shutil.copytree(source, destination, symlinks=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
