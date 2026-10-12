#!/usr/bin/env python3
"""Read resolved Xcode settings; reject compile placeholders before launch."""
import json
from pathlib import Path
import re
import sys

data = json.loads(Path(sys.argv[1]).read_text())
targets = {item["target"]: item["buildSettings"] for item in data}
required_targets = {"Prev", "PrevPreviewExtension", "PrevThumbnailExtension", "CADImportService"}
if not required_targets.issubset(targets):
    missing = ", ".join(sorted(required_targets - targets.keys()))
    raise SystemExit(f"Xcode did not resolve settings for these scheme targets: {missing}. Repair the checked-in Prev.xcodeproj/xcshareddata/xcschemes/Prev.xcscheme and recheck with full Xcode before running.")
host = targets["Prev"]
if len(sys.argv) == 3:
    field = sys.argv[2]
    values = {"bundle": str(Path(host["TARGET_BUILD_DIR"]) / host["FULL_PRODUCT_NAME"]), "executable": host["EXECUTABLE_NAME"], "identifier": host["PRODUCT_BUNDLE_IDENTIFIER"], "team": host.get("DEVELOPMENT_TEAM", "")}
    print(values[field])
    raise SystemExit()
for name in sorted(required_targets):
    settings = targets[name]
    team = settings.get("DEVELOPMENT_TEAM", "")
    bundle = settings.get("PRODUCT_BUNDLE_IDENTIFIER", "")
    group = settings.get("APP_GROUP_IDENTIFIER", "") if name != "CADImportService" else "not-required"
    if not re.fullmatch(r"[A-Z0-9]{10}", team) or not bundle or not group or "invalid.example" in bundle or "invalid.example" in group or "$(" in bundle + group:
        raise SystemExit("Signed run needs a real team, owned bundle identifiers and App Group in Configuration/Local.xcconfig. Prototype identifiers support compile checks only.")
print("Resolved signing identities supplied; Xcode still validates certificate/provisioning availability.")
