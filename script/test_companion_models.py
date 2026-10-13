#!/usr/bin/env python3
"""Exercise actual companion models using isolated temporary preferences and files."""
import os
from pathlib import Path
import subprocess
import sys

from package_link import ROOT, package_objects, package_module_flags

bin_dir = Path(sys.argv[1])
sdk = subprocess.check_output([
    "/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path",
], text=True).strip()
sources = [
    ROOT / "Apps/PrevApp/Models/PreviewSession.swift",
    ROOT / "Apps/PrevApp/Models/FileTypeSettingsGroup.swift",
    ROOT / "Apps/PrevApp/Models/AppearanceSampleLibrary.swift",
    ROOT / "Apps/PrevApp/Models/AppearanceSampleSession.swift",
    ROOT / "Apps/PrevApp/Models/FormatFilenameSummary.swift",
    ROOT / "Apps/PrevApp/Models/BundledNotices.swift",
    ROOT / "Apps/PrevApp/Models/AboutAcknowledgements.swift",
    ROOT / "Apps/PrevApp/Models/FileTypeEnablementSummary.swift",
    ROOT / "Apps/PrevApp/Models/CompanionRoute.swift",
    ROOT / "Apps/PrevApp/Views/Components/CompanionSymbol.swift",
    ROOT / "Apps/PrevApp/Stores/CompanionPreferences.swift",
    ROOT / "Apps/PrevApp/Stores/CompanionSettings.swift",
    ROOT / "Apps/PrevApp/Models/QuickLookProviderScanner.swift",
    ROOT / "Apps/PrevApp/Models/QuickLookProviderDiagnostics.swift",
    ROOT / "Apps/PrevApp/Models/AppearanceThemeTransfer.swift",
    ROOT / "Apps/PrevApp/Models/SettingsStatus.swift",
    ROOT / "Apps/PrevApp/Models/TypographyPointFormat.swift",
    ROOT / "Apps/PrevApp/Models/FontFamilyList.swift",
    ROOT / "Apps/PrevApp/Models/ProfileNameCheck.swift",
    ROOT / "Apps/PrevApp/Models/AppearancePinnedLayout.swift",
    ROOT / "Apps/PrevApp/Models/AppearanceTileFlow.swift",
    ROOT / "Tests/Integration/SettingsModelChecks.swift",
    ROOT / "Tests/Integration/CompanionUndoChecks.swift",
    ROOT / "Tests/Integration/CompanionPresentationChecks.swift",
    ROOT / "Tests/Integration/CompanionLayoutChecks.swift",
    ROOT / "Tests/Integration/CompanionErrorStateChecks.swift",
    ROOT / "Tests/Integration/CompanionModelChecks.swift",
]
command = [
    "/usr/bin/xcrun", "swiftc", "-parse-as-library",
    "-sdk", sdk, "-target", f"{os.uname().machine}-apple-macosx15.0",
    "-swift-version", "6", "-strict-concurrency=complete", "-default-isolation", "nonisolated",
    "-I", str(bin_dir), "-I", str(bin_dir / "Modules"),
]


def compile_and_run(name: str, check_sources: list[Path]) -> None:
    executable = bin_dir / name
    subprocess.run(command + package_module_flags(bin_dir) + ["-module-name", name, "-o", str(executable)]
                   + [str(path) for path in check_sources], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)


compile_and_run("CompanionModelChecks", sources + package_objects(bin_dir))
compile_and_run("DirectPreviewDropChecks", [
    ROOT / "Apps/PrevApp/Support/DirectPreviewFileDrop.swift",
    ROOT / "Tests/Integration/DirectPreviewDropChecks.swift",
])
compile_and_run("PreviewLiveReloadChecks", [
    ROOT / "Apps/PrevApp/Models/PreviewSession.swift",
    ROOT / "Tests/Integration/PreviewLiveReloadChecks.swift",
] + package_objects(bin_dir))

compile_and_run("PreviewMonitorRearmChecks", [
    ROOT / "Apps/PrevApp/Models/PreviewSession.swift",
    ROOT / "Tests/Integration/PreviewMonitorRearmChecks.swift",
] + package_objects(bin_dir))

compile_and_run("PreviewExtensionRearmChecks", [
    ROOT / "Extensions/PrevPreviewExtension/PreviewViewController.swift",
    ROOT / "Tests/Integration/PreviewExtensionRearmChecks.swift",
] + package_objects(bin_dir))

# Process policy changes belong in a disposable executable, never the shared test runner.
compile_and_run("DatalessProcessChecks", [
    ROOT / "Tests/Integration/DatalessProcessChecks.swift",
] + package_objects(bin_dir))

# An independent process holds a SQLite-range write lock. Same-process POSIX
# locking tests cannot demonstrate this guard because a process owns its locks.
import fcntl
import tempfile
probe = bin_dir / 'SQLiteSnapshotProbe'
subprocess.run(command + package_module_flags(bin_dir) + ['-module-name', 'SQLiteSnapshotProbe', '-o', str(probe),
               str(ROOT / 'Tests/Integration/SQLiteSnapshotProbe.swift')]
               + [str(path) for path in package_objects(bin_dir)], check=True)
with tempfile.TemporaryDirectory(prefix='prev-sqlite-lock-') as temporary:
    source = Path(temporary) / 'synthetic.sqlite'
    original = bytes([7]) * 100
    source.write_bytes(original)
    subprocess.run([str(probe), str(source), 'readable'], check=True, timeout=10)
    with source.open('r+b') as writer:
        fcntl.lockf(writer, fcntl.LOCK_EX | fcntl.LOCK_NB, 512, 1_073_741_824, os.SEEK_SET)
        subprocess.run([str(probe), str(source), 'unavailable'], check=True, timeout=10)
        fcntl.lockf(writer, fcntl.LOCK_UN, 512, 1_073_741_824, os.SEEK_SET)
    subprocess.run([str(probe), str(source), 'readable'], check=True, timeout=10)
    assert source.read_bytes() == original
    assert list(Path(temporary).iterdir()) == [source]
print('SQLite snapshot cross-process lock and no-source/sidecar-write checks passed.')

# The inks the companion draws small text with, measured in four appearances. Last, so that a failure here (it
# resolves system colors in each appearance) never hides the model checks above.
compile_and_run("CompanionContrastChecks", [
    ROOT / "Apps/PrevApp/Views/Components/CompanionStyle.swift",
    ROOT / "Tests/Integration/CompanionContrastChecks.swift",
])

# The scheme gallery reads the renderers' own swatches, so it is compiled on its own: a change to that accessor
# fails this step and leaves every check above standing.
compile_and_run("CompanionGalleryChecks", [
    ROOT / "Apps/PrevApp/Models/AppearanceSchemeGallery.swift",
    ROOT / "Tests/Integration/CompanionGalleryChecks.swift",
] + package_objects(bin_dir))
