#!/usr/bin/env python3
"""Inspect signed app/extension resources without launching hosts or changing preferences.

This verifies explicit Foundation lookup from the supplied artifacts, including
regional aliases, fallback and interpolation. Finder's effective
language, UTType display, layout and VoiceOver still need separate host observations.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REGIONAL_PREFERENCES = {
    "en": "en-GB", "tr": "tr-TR", "de": "de-AT", "fr": "fr-CA",
    "zh-Hans": "zh-Hans-CN", "ja": "ja-JP", "hi": "hi-IN", "ku-Latn": "ku-Latn-TR",
    "ru": "ru-RU", "id": "id-ID", "bn": "bn-BD", "ha": "ha-Latn-NG",
    "pt": "pt-BR", "es": "es-MX",
}


def resource_hashes(app: Path) -> dict[str, str]:
    return {str(path.relative_to(app)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in app.rglob("*") if path.is_file() and path.suffix in {".strings", ".plist"}}


def hosts_in(app: Path) -> dict[str, Path]:
    hosts = {"app": app}
    points = {"com.apple.quicklook.preview": "preview", "com.apple.quicklook.thumbnail": "thumbnail"}
    for extension in sorted((app / "Contents/PlugIns").glob("*.appex")):
        info = plistlib.loads((extension / "Contents/Info.plist").read_bytes())
        point = info.get("NSExtension", {}).get("NSExtensionPointIdentifier")
        if point in points:
            role = points[point]
            if role in hosts:
                raise ValueError(f"Duplicate {role} extension in supplied app")
            hosts[role] = extension
    if set(hosts) != {"app", "preview", "thumbnail"}:
        raise ValueError("Supply an app containing its actual preview and thumbnail extensions")
    return hosts


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, help="Path to the signed app artifact containing both Quick Look extensions")
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    hosts = hosts_in(app)
    before = resource_hashes(app)
    for host in hosts.values():
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(host)], check=True, capture_output=True, text=True)

    languages = json.loads((ROOT / "tools/localization/languages.json").read_text())["languages"]
    if set(languages) != set(REGIONAL_PREFERENCES):
        raise ValueError("Update regional lookup checks for the selected language set")
    strings = json.loads((ROOT / "Packages/PreviewCore/Sources/PreviewRenderers/Resources/Localizable.xcstrings").read_text())["strings"]
    metadata = json.loads((ROOT / "Configuration/Metadata.xcstrings").read_text())["strings"]
    formats = json.loads((ROOT / "Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json").read_text())["formats"]
    type_keys = {item["descriptionKey"] for descriptor in formats for item in descriptor.get("importedContentTypes", [])}
    app_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    brand = app_info["CFBundleDisplayName"]
    cases = [([language], language) for language in languages]
    cases += [([REGIONAL_PREFERENCES[language]], language) for language in languages]
    cases += [(["pt-PT"], "pt"), (["es-ES"], "es"), (["zz-ZZ"], "en"),
              (["zz-ZZ", "tr-TR"], "tr"), (["ar-SA"], "en")]

    with tempfile.TemporaryDirectory(prefix="prev-resource-checks-") as temporary:
        directory = Path(temporary)
        executable = directory / "LocalizedBundleChecks"
        sdk = subprocess.check_output(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
        subprocess.run(["/usr/bin/xcrun", "swiftc", "-parse-as-library", "-sdk", sdk,
                        "-target", f"{os.uname().machine}-apple-macosx15.0", "-swift-version", "6",
                        "-strict-concurrency=complete", "-default-isolation", "nonisolated",
                        "-o", str(executable), str(ROOT / "Tests/Integration/LocalizedBundleChecks.swift")], check=True)
        manifest_path = directory / "manifest.json"
        for preferences, language in cases:
            translated = {key: item["localizations"][language].get("stringUnit", {"value": "%#@count@"})["value"] for key, item in strings.items()}
            expected_hosts = []
            for role, host in hosts.items():
                title = metadata[f"metadata.{role}.name"]["localizations"][language]["stringUnit"]["value"].replace("%@", brand)
                expected_hosts.append({"role": role, "path": str(host), "metadata": {
                    "CFBundleDisplayName": title, "CFBundleName": title,
                    **{key: translated[key] for key in type_keys},
                }})
            manifest_path.write_text(json.dumps({"preferences": preferences, "expectedLanguage": language, "formattingLocale": preferences[0],
                                                  "bundles": expected_hosts, "strings": translated}))
            # Explicit lookup avoids altering any preference domain or assuming
            # that the standalone helper chooses languages like a Finder host.
            result = subprocess.run([str(executable), str(manifest_path)],
                                    check=False, capture_output=True, text=True, timeout=20)
            if result.returncode:
                raise RuntimeError(f"Resource lookup failed for {preferences}: {result.stderr.strip()}")
            print(f"Passed explicit preferences {preferences}: {language}; all 3 bundle contexts")
    if resource_hashes(app) != before:
        raise RuntimeError("Supplied app resources changed during read-only inspection")
    print(f"Passed {len(cases)} explicit language cases, {len(hosts)} signed bundles, {len(strings)} keys each; resources unchanged.")
    print("This is resource lookup evidence; actual companion/Finder effective language, layout and VoiceOver remain separate.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Bundle localization check failed: {error}", file=sys.stderr)
        sys.exit(1)
