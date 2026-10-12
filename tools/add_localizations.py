#!/usr/bin/env python3
"""Add new localized keys to an owned String Catalog and every translation input in one step.

    python3 tools/add_localizations.py ADDITIONS.json [--catalog strings|metadata]

ADDITIONS.json maps each new key to its translator comment and one value per language in
tools/localization/languages.json, for example:

    {"preview.mode.example": {"comment": "Preview mode title.", "en": "Example", "tr": "Örnek", ...}}

A count sentence is a plural key: give every language an object of its CLDR plural categories
instead of a string. Each variant prints the count as %2$@ (PreviewStrings.count passes the
locale-formatted number as the second argument) and carries no digits of its own:

    {"preview.count.lines": {"comment": "...", "en": {"one": "%2$@ line", "other": "%2$@ lines"},
                              "ru": {"one": "...", "few": "...", "many": "...", "other": "..."}, ...}}

The development language decides the kind: a plain string for a plural key, or an object for a
plain key, is rejected. An optional "case" field per key (the PreviewStrings.Key case the lead adds
for it) is ignored here.

Every language is required. Existing keys are rejected so a batch never silently replaces reviewed
text, and nothing is written unless every entry is valid. The catalog and the inputs are written
with their keys sorted. Afterwards run tools/merge_localizations.py, tools/generate_localization.py
and tools/validate_localization.py. Values remain drafts pending native-speaker review.
"""
import argparse
import json
from pathlib import Path
import sys

from validate_localization import canonical_json, catalog_localization, ordered_variants, value_problems

ROOT = Path(__file__).resolve().parents[1]
INPUTS = ROOT / 'tools/localization'
CATALOGS = {
    'strings': ROOT / 'Packages/PreviewCore/Sources/PreviewRenderers/Resources/Localizable.xcstrings',
    'metadata': ROOT / 'Configuration/Metadata.xcstrings',
}


def entry_errors(key, entry, languages, development, kind):
    if not isinstance(entry, dict):
        return [f'{key}: expected an object']
    errors = []
    if not isinstance(entry.get('comment'), str) or not entry['comment'].strip():
        errors.append(f'{key}: missing translator comment')
    missing = [language for language in languages if language not in entry]
    if missing:
        errors.append(f'{key}: missing {missing}')
    extra = set(entry) - set(languages) - {'comment', 'case'}
    if extra:
        errors.append(f'{key}: unknown fields {sorted(extra)}')
    english = entry.get(development)
    if kind == 'metadata' and isinstance(english, dict):
        errors.append(f'{key}: plural variants are not supported in the metadata catalog')
    elif isinstance(english, (str, dict)):
        for language in languages:
            if language in entry:
                errors += [f'{key}/{language}: {problem}' for problem in value_problems(
                    language, entry[language], english, formatted=kind == 'metadata', is_development=language == development)]
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('additions', type=Path)
    parser.add_argument('--catalog', choices=sorted(CATALOGS), default='strings')
    args = parser.parse_args(argv)
    policy = json.loads((INPUTS / 'languages.json').read_text(encoding='utf-8'))
    development = policy['developmentLanguage']
    languages = policy['languages']
    additions = json.loads(args.additions.read_text(encoding='utf-8'))
    if not isinstance(additions, dict):
        print('ADDITIONS.json must map each new key to its entry', file=sys.stderr)
        return 1
    catalog_path = CATALOGS[args.catalog]
    catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
    translations = {language: json.loads((INPUTS / 'translations' / f'{language}.json').read_text(encoding='utf-8'))
                    for language in languages if language != development}
    errors = []
    for key, entry in additions.items():
        if key in catalog['strings'] or any(key in document.get(args.catalog, {}) for document in translations.values()):
            errors.append(f'{key}: already exists')
        errors += entry_errors(key, entry, languages, development, args.catalog)
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    for key, entry in additions.items():
        catalog['strings'][key] = {
            'comment': entry['comment'],
            'extractionState': 'manual',
            'localizations': {development: catalog_localization(entry[development])},
        }
        for language, document in translations.items():
            value = entry[language]
            document[args.catalog][key] = dict(ordered_variants(value)) if isinstance(value, dict) else value
    catalog_path.write_text(canonical_json(catalog), encoding='utf-8')
    for language, document in translations.items():
        (INPUTS / 'translations' / f'{language}.json').write_text(canonical_json(document), encoding='utf-8')
    print(f'Added {len(additions)} key(s) to {args.catalog}; now run merge_localizations.py, generate_localization.py and validate_localization.py.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
