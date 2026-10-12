#!/usr/bin/env python3
"""Exercise customization lifecycle and persistence with actual isolated companion models."""
import os
from pathlib import Path
import subprocess
import sys

from package_link import ROOT, package_objects, package_module_flags

bin_dir = Path(sys.argv[1])
sdk = subprocess.check_output(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
sources = [
    ROOT / "Apps/PrevApp/Models/PreviewSession.swift",
    ROOT / "Apps/PrevApp/Models/AppearanceThemeTransfer.swift",
    ROOT / "Apps/PrevApp/Stores/CompanionSettings.swift",
    ROOT / "Tests/Integration/AppearanceInteractionChecks.swift",
]
executable = bin_dir / "AppearanceInteractionChecks"
command = [
    "/usr/bin/xcrun", "swiftc", "-parse-as-library", "-sdk", sdk,
    "-target", f"{os.uname().machine}-apple-macosx15.0", "-swift-version", "6",
    "-strict-concurrency=complete", "-default-isolation", "nonisolated",
    "-I", str(bin_dir), "-I", str(bin_dir / "Modules"),
] + package_module_flags(bin_dir) + ["-module-name", "AppearanceInteractionChecks", "-o", str(executable)]
subprocess.run(command + [str(path) for path in sources + package_objects(bin_dir)], check=True)
subprocess.run([str(executable)], check=True, timeout=30)
