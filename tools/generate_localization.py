#!/usr/bin/env python3
"""Generate SwiftPM-compatible .strings and .stringsdict resources from the owned String Catalog.

Edit Localizable.xcstrings, run this command, then validate_localization.py.

Every language gets Localizable.strings. A key with `variations.plural` is written there as the
`%#@count@` format (unless validate_localization.PLURAL_FORMAT_IN_STRINGS is switched off), and every
language that has at least one such key also gets Localizable.stringsdict, which selects the CLDR
category from the first argument and prints the second (`%2$@`) in each variant; PreviewStrings.count
supplies both. A language without plural keys gets no stringsdict and a stale one is removed. Other
variations are refused, never dropped.
"""
import json
from pathlib import Path
import plistlib
import sys

from validate_localization import STRINGS_HEADER, expected_strings, expected_stringsdict, localization_value

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Packages/PreviewCore/Sources/PreviewRenderers/Resources"


def quoted(value):
    return json.dumps(value, ensure_ascii=False)


def collect(catalog):
    """Return {language: {key: text or {category: text}}}, refusing keys that are plural in only some
    languages and plural entries without an `other` variant."""
    languages = {}
    for key, entry in catalog["strings"].items():
        values = {}
        for language, localization in entry.get("localizations", {}).items():
            try:
                values[language] = localization_value(localization)
            except ValueError as error:
                raise ValueError(f"Cannot generate {language}/{key}: {error}")
        if len({isinstance(value, dict) for value in values.values()}) > 1:
            raise ValueError(f"{key} is plural in some languages and plain text in others")
        for language, value in values.items():
            if isinstance(value, dict) and "other" not in value:
                raise ValueError(f"Plural key {language}/{key} needs an `other` variant")
            languages.setdefault(language, {})[key] = value
    return languages


def render_strings(values):
    return STRINGS_HEADER + "\n" + "\n".join(f"{quoted(key)} = {quoted(value)};" for key, value in sorted(values.items())) + "\n"


def render_stringsdict(document):
    """Apple's XML property list exactly as plistlib writes it, with sorted keys so a rerun is byte-identical."""
    return plistlib.dumps(document, fmt=plistlib.FMT_XML, sort_keys=True)


def main():
    catalog = json.loads((RESOURCES / "Localizable.xcstrings").read_text(encoding="utf-8"))
    languages = collect(catalog)
    # Validate all entries before modifying any file.
    for language in languages:
        if not language or any(char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for char in language):
            raise ValueError(f"Invalid locale identifier: {language}")
    plurals = {language: expected_stringsdict(values) for language, values in languages.items()}
    documents = {language: render_stringsdict(document) for language, document in plurals.items() if document}
    for language, values in languages.items():
        target = RESOURCES / f"{language}.lproj/Localizable.strings"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(render_strings(expected_strings(values)), encoding="utf-8")
        plural_target = target.with_suffix(".stringsdict")
        if language in documents:
            plural_target.write_bytes(documents[language])
        elif plural_target.exists():
            plural_target.unlink()
    print(f"Generated {len(languages)} locale resource(s), {len(documents)} with plural variants. Run tools/validate_localization.py next.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print(f"Localization generation failed: {error}", file=sys.stderr)
        sys.exit(1)
