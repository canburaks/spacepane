#!/usr/bin/env python3
"""Compile localized bundle names and imported type descriptions from owned catalogs."""
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def shipped_languages():
    """Languages a build may carry: the development language plus each language with a recorded review.

    `languages` in the policy file stays the chosen set whose drafts live in the repository. The
    store lists every language found at the top of the app bundle, and a nested resource bundle
    follows the host bundle's languages, so the generated top-level `.lproj` set is the ship list.
    """
    policy = json.loads((ROOT / "tools/localization/languages.json").read_text())
    development, chosen, shipped = policy["developmentLanguage"], policy["languages"], policy["shipped"]
    reviews = policy["reviews"]
    if len(set(shipped)) != len(shipped) or development not in shipped or not set(shipped) <= set(chosen):
        raise ValueError("Shipped languages must be distinct, chosen languages that include the development language")
    if not set(reviews) <= set(chosen):
        raise ValueError("A review record names a language outside the chosen set")
    for language in shipped:
        record = reviews.get(language, {})
        if language != development and not (record.get("reviewer") and record.get("date")):
            raise ValueError(f"{language} cannot ship without a review record naming its reviewer and date")
    return shipped


def compile_metadata(output, role, brand):
    shipped = set(shipped_languages())
    catalog = json.loads((ROOT / "Configuration/Metadata.xcstrings").read_text())
    item = catalog["strings"][f"metadata.{role}.name"]
    formats = json.loads((ROOT / "Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json").read_text())
    descriptions = json.loads((ROOT / "Packages/PreviewCore/Sources/PreviewRenderers/Resources/Localizable.xcstrings").read_text())["strings"]
    description_keys = sorted({imported["descriptionKey"] for descriptor in formats["formats"]
                               for imported in descriptor.get("importedContentTypes", [])})
    if not brand.strip() or "$(" in brand:
        raise ValueError("PREV_DISPLAY_NAME must resolve to a nonempty brand")
    localized_values = {}
    for language, localization in item["localizations"].items():
        if not language or "/" in language or ".." in language:
            raise ValueError("Invalid catalog language identifier")
        template = localization["stringUnit"]["value"]
        if template.count("%@") != 1:
            raise ValueError("Bundle-name template must contain one brand placeholder")
        title = template.replace("%@", brand)
        values = {"CFBundleDisplayName": title, "CFBundleName": title}
        for key in description_keys:
            if key in values:
                raise ValueError("Imported type description collides with bundle metadata")
            # Type names remain owned by the format localization catalog. The
            # declaration uses its resource key, which InfoPlist.strings resolves.
            value = descriptions[key]["localizations"].get(language, {}).get("stringUnit", {}).get("value")
            if not isinstance(value, str) or not value:
                raise ValueError(f"Missing imported type description: {language}/{key}")
            values[key] = value
        localized_values[language] = values
    if not shipped <= set(localized_values):
        raise ValueError("A shipped language has no bundle metadata")
    # Validate every localization, drafts included, before publishing any generated resource.
    output.mkdir(parents=True, exist_ok=True)
    for language, values in localized_values.items():
        if language not in shipped:
            continue
        destination = output / f"{language}.lproj"
        destination.mkdir(exist_ok=True)
        # JSON string escaping is compatible with .strings for these values.
        content = "\n".join(f"{json.dumps(key, ensure_ascii=False)} = {json.dumps(value, ensure_ascii=False)};"
                            for key, value in values.items()) + "\n"
        (destination / "InfoPlist.strings").write_text(content)


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[2] not in {"app", "preview", "thumbnail"}:
        raise SystemExit("usage: build_metadata.py OUTPUT_DIRECTORY app|preview|thumbnail")
    compile_metadata(Path(sys.argv[1]), sys.argv[2], os.environ["PREV_DISPLAY_NAME"])
