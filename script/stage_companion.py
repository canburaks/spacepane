#!/usr/bin/env python3
"""Link a CLT-only companion prototype; this never builds or installs extensions."""
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

from build_cad_worker import NOTICE_FOLDERS
from build_metadata import compile_metadata
from package_link import package_objects, package_module_flags

ROOT = Path(__file__).resolve().parents[1]
bin_dir = Path(sys.argv[1])
app = ROOT / "dist/PrevPrototype.app"
objects = package_objects(bin_dir)

brand = None
for config in [ROOT / "Configuration/Branding.xcconfig", ROOT / "Configuration/Local.xcconfig"]:
    if not config.is_file():
        continue
    for line in config.read_text().splitlines():
        match = re.fullmatch(r"\s*PREV_DISPLAY_NAME\s*=\s*(.+?)\s*", line)
        if match:
            brand = match[1]
if not brand or "$(" in brand:
    raise SystemExit("The companion prototype needs a resolved PREV_DISPLAY_NAME in Branding.xcconfig or Local.xcconfig.")

if app.exists():
    shutil.rmtree(app)
macos = app / "Contents/MacOS"
resources = app / "Contents/Resources"
macos.mkdir(parents=True)
resources.mkdir()
sdk = subprocess.check_output(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
architecture = os.uname().machine
sources = sorted((ROOT / "Apps/PrevApp").rglob("*.swift"))
command = ["/usr/bin/xcrun", "swiftc", "-parse-as-library", "-module-name", "Prev", "-sdk", sdk, "-target", f"{architecture}-apple-macosx15.0", "-swift-version", "6", "-strict-concurrency=complete", "-default-isolation", "nonisolated", "-I", str(bin_dir), "-I", str(bin_dir / "Modules"), "-o", str(macos / "PrevPrototype")]
subprocess.run(command + package_module_flags(bin_dir) + [str(source) for source in sources] + [str(obj) for obj in dict.fromkeys(objects)], check=True)
bundles = list(bin_dir.glob("*.bundle"))
if not bundles:
    raise SystemExit("Package resource bundles are unavailable; refusing to stage a broken prototype.")
for bundle in bundles:
    shutil.copytree(bundle, resources / bundle.name)
info = {
    "CFBundleDevelopmentRegion": "en", "CFBundleDisplayName": brand,
    "CFBundleExecutable": "PrevPrototype", "CFBundleIdentifier": "invalid.example.previewprototype.companion",
    "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": brand, "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1", "LSMinimumSystemVersion": "15.0",
    "NSPrincipalClass": "NSApplication", "NSHighResolutionCapable": True, "PreviewDisplayName": brand,
}
with (ROOT / "Configuration/App-Info.plist").open("rb") as handle:
    source_info = plistlib.load(handle)
info["UTImportedTypeDeclarations"] = source_info.get("UTImportedTypeDeclarations", [])
with (app / "Contents/Info.plist").open("wb") as handle:
    plistlib.dump(info, handle)
compile_metadata(resources, "app", brand)
# The Theme page's built-in samples; the Xcode target copies the same folder.
for resource in sorted((ROOT / 'Apps/PrevApp/Resources').iterdir()):
    shutil.copy2(resource, resources / resource.name)
helper = ROOT / '.build/cad' / ('worker-' + architecture) / 'CADWorker'
if not helper.is_file():
    raise SystemExit('Prepare the native CAD helper with script/build_cad_worker.py before staging.')
helper_target = app / 'Contents/Helpers/CADWorker'
helper_target.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(helper, helper_target)
subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', str(helper_target)], check=True)
# The same notice folders the Xcode phase embeds (script/embed_cad_worker.py), so About shows the same rows.
for notice_source, notice_name in NOTICE_FOLDERS:
    shutil.copytree(ROOT / 'ThirdPartyNotices' / notice_source, resources / notice_name)
subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(app)], check=True)
subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(app)], check=True)
print(f"Built local companion prototype: {app}")
print("Prototype uses private settings and ad hoc signing. It has no sandbox/App Group entitlements or embedded Quick Look extensions.")
