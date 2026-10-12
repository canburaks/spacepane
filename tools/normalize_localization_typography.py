#!/usr/bin/env python3
"""Rewrite the mechanical typography of translation inputs and additions files (decision 027, Q-23 and Q-111).

The validator warns about the same patterns (`tools/validate_localization.py`, TYPOGRAPHY_RULES); this tool fixes the
ones that have exactly one right answer, so a batch of new strings does not need a hand edit per value:

- French: an ordinary space before `: ; ? ! »` and after `«` becomes a no-break space (U+00A0). A narrow no-break
  space (U+202F) already there is kept. A missing space is only reported by the validator, never inserted, because
  a `?` or `!` may belong to a token.
- Hausa: an apostrophe-like mark between two letters (U+0027, U+2019, U+2018, a backtick or an acute accent) becomes
  the glottal stop, HAUSA_GLOTTAL_STOP (U+02BC).

German quotation marks are not mechanical (a straight quote may open or close) and stay a warning.

    python3 tools/normalize_localization_typography.py                    # report what would change
    python3 tools/normalize_localization_typography.py --write            # rewrite tools/localization/translations
    python3 tools/normalize_localization_typography.py --write --additions tools/localization/additions/ux-chrome.json

Rewriting translation inputs is followed by `merge_localizations.py` and `generate_localization.py`; an additions
file is rewritten in its own order, with its `case`, `comment` and every other field untouched. Exit status: 0 when
nothing needs a change or every change was written, 1 when --write was not given and something would change.
"""
import argparse
import json
from pathlib import Path
import re
import sys

from validate_localization import (
    HAUSA_APOSTROPHE, HAUSA_GLOTTAL_STOP, LOCALIZATION, canonical_json,
)

NO_BREAK_SPACE = " "
SPACE_BEFORE_FRENCH_MARK = re.compile(r" (?=[:;?!»])")
SPACE_AFTER_FRENCH_OPENING = re.compile(r"(?<=«) ")


def normalize_text(language, text):
    """`text` with the mechanical typography of `language` applied; other languages come back unchanged."""
    if language == "fr":
        text = SPACE_BEFORE_FRENCH_MARK.sub(NO_BREAK_SPACE, text)
        return SPACE_AFTER_FRENCH_OPENING.sub(NO_BREAK_SPACE, text)
    if language == "ha":
        return HAUSA_APOSTROPHE.sub(HAUSA_GLOTTAL_STOP, text)
    return text


def normalize_value(language, value):
    """A plain text or a {category: text} plural value, normalized."""
    if isinstance(value, dict):
        return {category: normalize_text(language, text) for category, text in value.items()}
    return normalize_text(language, value) if isinstance(value, str) else value


def normalize_strings(language, strings):
    """(normalized dictionary, keys that changed) for one language's {key: value} dictionary."""
    result = {key: normalize_value(language, value) for key, value in strings.items()}
    return result, [key for key in strings if result[key] != strings[key]]


def normalize_translation_input(path, language):
    """(text to write, changed keys) for one translation input; the metadata dictionary is left alone."""
    document = json.loads(path.read_text(encoding="utf-8"))
    document["strings"], changed = normalize_strings(language, document["strings"])
    return canonical_json(document), changed


def normalize_additions(path):
    """(text to write, [(key, language)] changed) for one additions file."""
    document = json.loads(path.read_text(encoding="utf-8"))
    changed = []
    for key, entry in document.items():
        for language in ("fr", "ha"):
            if language in entry:
                updated = normalize_value(language, entry[language])
                if updated != entry[language]:
                    entry[language] = updated
                    changed.append((key, language))
    return json.dumps(document, ensure_ascii=False, indent=2) + "\n", changed


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--write", action="store_true", help="rewrite the files; without it only report")
    parser.add_argument("--additions", nargs="*", default=[], metavar="FILE",
                        help="additions files to normalize as well as the translation inputs")
    parser.add_argument("--additions-only", action="store_true", help="leave the translation inputs alone")
    arguments = parser.parse_args(argv)

    pending = 0
    targets = []
    if not arguments.additions_only:
        for language in ("fr", "ha"):
            path = LOCALIZATION / "translations" / f"{language}.json"
            text, keys = normalize_translation_input(path, language)
            targets.append((path, text, [f"{language}/{key}" for key in keys]))
    for name in arguments.additions:
        path = Path(name)
        text, pairs = normalize_additions(path)
        targets.append((path, text, [f"{language}/{key}" for key, language in pairs]))
    for path, text, changed in targets:
        if not changed:
            continue
        pending += len(changed)
        print(f"{path}: {len(changed)} value(s) {'rewritten' if arguments.write else 'would change'}")
        if arguments.write:
            path.write_text(text, encoding="utf-8")
    if not pending:
        print("Typography is already normalized.")
    return 0 if arguments.write or not pending else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError) as error:
        print(f"Typography normalization failed: {error}", file=sys.stderr)
        sys.exit(1)
