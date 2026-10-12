#!/usr/bin/env python3
"""Validate complete translation inputs before publishing both owned catalogs.

Each input, tools/localization/translations/<language>.json, holds `strings` and `metadata`
dictionaries. A plain key holds text; a plural key holds an object of CLDR categories
(`{"one": "...", "other": "..."}`). Every key is checked against the development language:
placeholders must match for every key (strictly for formatted keys and bundle metadata, with literal
percent signs tolerated elsewhere), a plural key needs exactly the categories its language's CLDR
rules define, and a plain string for a plural key, or an object for a plain key, is rejected.
Nothing is written unless every input is valid; the catalogs and the inputs are then written with
their keys sorted.
"""
import json
from pathlib import Path
import sys

from validate_localization import (
    canonical_json, catalog_localization, formatted_string_keys, localization_value, ordered_variants, value_problems,
)

ROOT = Path(__file__).resolve().parents[1]
INPUTS = ROOT / 'tools/localization'
CATALOGS = {
    'strings': ROOT / 'Packages/PreviewCore/Sources/PreviewRenderers/Resources/Localizable.xcstrings',
    'metadata': ROOT / 'Configuration/Metadata.xcstrings',
}
MAX_REPORTED = 20


def main():
    policy = json.loads((INPUTS / 'languages.json').read_text(encoding='utf-8'))
    development = policy['developmentLanguage']
    languages = policy['languages']
    if len(languages) != len(set(languages)) or development not in languages:
        raise ValueError('Invalid language policy')
    catalogs = {kind: json.loads(path.read_text(encoding='utf-8')) for kind, path in CATALOGS.items()}
    formatted = formatted_string_keys(strict=False)
    problems = []
    english = {}
    for kind, catalog in catalogs.items():
        for key, entry in catalog['strings'].items():
            try:
                english[kind, key] = localization_value(entry['localizations'][development])
            except (KeyError, ValueError) as error:
                problems.append(f'{development}/{kind}/{key}: unusable development-language entry ({error})')
                continue
            if kind == 'metadata' and isinstance(english[kind, key], dict):
                problems.append(f'{development}/{kind}/{key}: plural variants are not supported in the metadata catalog')
                continue
            problems += [f'{development}/{kind}/{key}: {problem}' for problem in value_problems(
                development, english[kind, key], english[kind, key],
                formatted=kind == 'metadata' or key in formatted, is_development=True)]

    inputs = {}
    for language in languages:
        if language == development:
            continue
        path = INPUTS / 'translations' / f'{language}.json'
        original = path.read_text(encoding='utf-8')
        translation = json.loads(original)
        inputs[language] = (path, original, translation)
        if set(translation) != set(catalogs):
            raise ValueError(f'{language}: expected strings and metadata dictionaries')
        for kind, catalog in catalogs.items():
            source = catalog['strings']
            values = translation[kind]
            if set(values) != set(source):
                raise ValueError(f'{language}/{kind}: missing {sorted(set(source)-set(values))}; extra {sorted(set(values)-set(source))}')
            for key, value in values.items():
                if (kind, key) in english:
                    problems += [f'{language}/{kind}/{key}: {problem}' for problem in value_problems(
                        language, value, english[kind, key], formatted=kind == 'metadata' or key in formatted)]
    if problems:
        shown = problems[:MAX_REPORTED]
        if len(problems) > len(shown):
            shown.append(f'... {len(problems) - len(shown)} more')
        raise ValueError('Invalid translation inputs:\n' + '\n'.join(shown))

    for language, (path, original, translation) in inputs.items():
        for kind, catalog in catalogs.items():
            for key, value in translation[kind].items():
                catalog['strings'][key]['localizations'][language] = catalog_localization(value)
    for kind, catalog in catalogs.items():
        CATALOGS[kind].write_text(canonical_json(catalog), encoding='utf-8')
    for language, (path, original, translation) in inputs.items():
        normalized = {kind: {key: dict(ordered_variants(value)) if isinstance(value, dict) else value
                             for key, value in values.items()} for kind, values in translation.items()}
        text = canonical_json(normalized)
        if text == original:
            continue
        # Another editor may have changed the input since it was read; never overwrite their edit.
        if path.read_text(encoding='utf-8') == original:
            path.write_text(text, encoding='utf-8')
        else:
            print(f'{path.name} changed during the merge; left unsorted. Run merge_localizations.py again.', file=sys.stderr)
    print(f'Merged {len(languages)} locales; linguistic and host review remain separate.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print(f'Localization merge failed: {error}', file=sys.stderr)
        sys.exit(1)
