#!/usr/bin/env python3
"""Prepare the pinned Sparkle 2 distribution and stripped runtime framework under .build/sparkle."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

VERSION = "2.10.1"
ARCHIVE_SHA256 = "1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
ARCHIVE_URL = f"https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/Sparkle-{VERSION}.tar.xz"
ROOT = Path(__file__).resolve().parents[1]
EXTRACTION_MARKER = ".prev-sparkle-extracted"

MACH_O_RELATIVE_PATHS = (
    "Versions/B/Sparkle",
    "Versions/B/Autoupdate",
    "Versions/B/Updater.app/Contents/MacOS/Updater",
    "Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader",
    "Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer",
)


def extraction_marker() -> str:
    return f"Sparkle {VERSION} sha256 {ARCHIVE_SHA256}\n"


def remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def extracted_tree_is_current(dist: Path) -> bool:
    marker = dist / EXTRACTION_MARKER
    framework = dist / "Sparkle.framework" / "Versions" / "B" / "Sparkle"
    try:
        return (
            dist.is_dir()
            and not dist.is_symlink()
            and framework.is_file()
            and marker.is_file()
            and not marker.is_symlink()
            and marker.read_text() == extraction_marker()
        )
    except OSError:
        return False


def check_archive_members(members, destination: Path) -> None:
    root = destination.resolve()
    for member in members:
        if member.name.startswith("/") or ".." in Path(member.name).parts:
            raise SystemExit(f"Unsafe Sparkle archive member path: {member.name}")
        if not (member.isreg() or member.isdir() or member.issym()):
            raise SystemExit(f"Unsupported Sparkle archive member kind: {member.name}")
        if member.issym():
            link_parent = (destination / member.name).parent
            link_target = Path(os.path.normpath(os.path.join(str(link_parent), member.linkname)))
            if not str(link_target).startswith(str(destination)):
                raise SystemExit(f"Unsafe Sparkle archive symlink target: {member.name} -> {member.linkname}")


def extract_pinned_distribution(archive: Path, workspace: Path, dist: Path) -> None:
    for leftover in workspace.glob("sparkle-extract-*"):
        remove_path(leftover)
    scratch = Path(tempfile.mkdtemp(prefix="sparkle-extract-", dir=workspace))
    try:
        with tarfile.open(archive, mode="r:xz") as bundle:
            members = bundle.getmembers()
            check_archive_members(members, scratch)
            if hasattr(tarfile, "data_filter"):
                bundle.extractall(scratch, members=members, filter="data")
            else:
                bundle.extractall(scratch, members=members)
        if not (scratch / "Sparkle.framework").is_dir():
            raise SystemExit("Sparkle archive did not contain Sparkle.framework.")
        (scratch / EXTRACTION_MARKER).write_text(extraction_marker())
        remove_path(dist)
        os.replace(scratch, dist)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def shipped_lproj_names() -> set[str]:
    policy = json.loads((ROOT / "tools" / "localization" / "languages.json").read_text())
    shipped = {f"{language}.lproj" for language in policy["shipped"]}
    shipped.add("Base.lproj")
    return shipped


def sign_component(path: Path, identity: str, entitlements: Path | None = None) -> None:
    arguments = ["/usr/bin/codesign", "--force", "--sign", identity, "--timestamp=none"]
    if identity != "-":
        arguments += ["--options", "runtime"]
    if entitlements is not None:
        arguments += ["--entitlements", str(entitlements)]
    arguments.append(str(path))
    subprocess.run(arguments, check=True)


def stage_runtime_framework(dist: Path, workspace: Path, architecture: str, sign_identity: str = "-") -> Path:
    runtime_dir = workspace / f"runtime-{architecture}"
    remove_path(runtime_dir)
    runtime_dir.mkdir(parents=True, exist_ok=True)
    source_fw = dist / "Sparkle.framework"
    target_fw = runtime_dir / "Sparkle.framework"
    shutil.copytree(source_fw, target_fw, symlinks=True)

    # Remove build-only headers and clang module maps from the runtime framework.
    for unused in (
        target_fw / "Headers",
        target_fw / "PrivateHeaders",
        target_fw / "Modules",
        target_fw / "Versions" / "B" / "Headers",
        target_fw / "Versions" / "B" / "PrivateHeaders",
        target_fw / "Versions" / "B" / "Modules",
    ):
        remove_path(unused)

    # Prune non-shipped localizations so the embedded framework matches the app's language policy.
    allowed_lproj = shipped_lproj_names()
    resources = target_fw / "Versions" / "B" / "Resources"
    for item in list(resources.iterdir()):
        if item.suffix == ".lproj" and item.name not in allowed_lproj:
            remove_path(item)

    # Embed the upstream Sparkle license inside the framework resources.
    notice = ROOT / "ThirdPartyNotices" / "Sparkle" / "LICENSE"
    if not notice.is_file():
        raise SystemExit(f"Missing {notice}")
    shutil.copy2(notice, resources / "LICENSE")

    # Thin universal Mach-O binaries to the requested architecture.
    for rel in MACH_O_RELATIVE_PATHS:
        binary = target_fw / rel
        thinned = binary.with_suffix(".thin")
        subprocess.run(
            ["/usr/bin/lipo", str(binary), "-thin", architecture, "-output", str(thinned)],
            check=True,
        )
        os.replace(thinned, binary)
        binary.chmod(0o755)

    # Sign inside-out outside Xcode's user-script sandbox so embed_sparkle.py only copies sealed files.
    versions_b = target_fw / "Versions" / "B"
    downloader_entitlements = ROOT / "Configuration" / "SparkleDownloader.entitlements"
    sign_component(versions_b / "XPCServices" / "Downloader.xpc", sign_identity, entitlements=downloader_entitlements)
    sign_component(versions_b / "XPCServices" / "Installer.xpc", sign_identity)
    sign_component(versions_b / "Autoupdate", sign_identity)
    sign_component(versions_b / "Updater.app", sign_identity)
    sign_component(target_fw, sign_identity)

    return target_fw


def refresh_bundle_filelists(workspace: Path) -> None:
    inputs = [ROOT / "Configuration" / "SparkleDownloader.entitlements"]
    outputs = [
        "$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)",
        "$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/Sparkle.framework",
    ]
    seen_outputs = set(outputs)

    for architecture in ("arm64", "x86_64"):
        fw = workspace / f"runtime-{architecture}" / "Sparkle.framework"
        if not fw.is_dir():
            continue
        for root_dir, dirnames, filenames in os.walk(fw, followlinks=False):
            rel_root = Path(root_dir).relative_to(fw)
            out_prefix = "$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/Sparkle.framework"
            if str(rel_root) != ".":
                out_dir = f"{out_prefix}/{rel_root.as_posix()}"
                if out_dir not in seen_outputs:
                    outputs.append(out_dir)
                    seen_outputs.add(out_dir)
            for name in sorted(dirnames) + sorted(filenames):
                full_path = Path(root_dir) / name
                rel_path = full_path.relative_to(fw).as_posix()
                out_path = f"{out_prefix}/{rel_path}"
                if out_path not in seen_outputs:
                    outputs.append(out_path)
                    seen_outputs.add(out_path)
                if full_path.is_file() and not full_path.is_symlink():
                    inputs.append(full_path)

    (workspace / "bundle-inputs.xcfilelist").write_text(
        "\n".join(str(path) for path in inputs if path.exists()) + "\n"
    )
    (workspace / "bundle-outputs.xcfilelist").write_text("\n".join(outputs) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--architecture",
        choices=("arm64", "x86_64"),
        default="arm64" if platform.machine() == "arm64" else "x86_64",
    )
    parser.add_argument(
        "--sign-identity",
        default="-",
        help="Code-signing identity for inside-out signing of the staged Sparkle.framework (default: ad hoc '-')",
    )
    parser.add_argument(
        "--refresh-bundle-filelists",
        action="store_true",
        help="Refresh Xcode input/output file lists without downloading or extracting Sparkle",
    )
    args = parser.parse_args()
    workspace = ROOT / ".build" / "sparkle"
    workspace.mkdir(parents=True, exist_ok=True)
    if args.refresh_bundle_filelists:
        refresh_bundle_filelists(workspace)
        return

    archive = workspace / f"Sparkle-{VERSION}.tar.xz"
    if not archive.exists():
        temporary = archive.with_suffix(".download")
        urllib.request.urlretrieve(ARCHIVE_URL, temporary)
        temporary.rename(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA256:
        raise SystemExit("Sparkle archive checksum mismatch; refusing to stage.")

    dist = workspace / "dist"
    if not extracted_tree_is_current(dist):
        extract_pinned_distribution(archive, workspace, dist)

    target_fw = stage_runtime_framework(dist, workspace, args.architecture, sign_identity=args.sign_identity)
    refresh_bundle_filelists(workspace)
    print(target_fw)


if __name__ == "__main__":
    main()
