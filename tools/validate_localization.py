#!/usr/bin/env python3
"""Check owned localization references, plural resources, copy lints and generated resources.

This catches missing resources, stale copies and copy that breaks the documented rules. It is not
a translation-quality or complete UI-text audit; those remain human/runtime validation requirements.
Errors make the exit status 1. Warnings and the identical-to-English report never do.

    python3 tools/validate_localization.py            # errors, then a summary of the warnings
    python3 tools/validate_localization.py --verbose  # also list every warning item

This module also owns the shape knowledge the other localization tools share: the plural catalog
shape, the CLDR category table, placeholder parsing and the generated resource format.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import unicodedata
from xml.parsers.expat import ExpatError

ROOT = Path(__file__).resolve().parents[1]
RENDERERS = ROOT / "Packages/PreviewCore/Sources/PreviewRenderers"
RESOURCES = RENDERERS / "Resources"
CATALOG = RESOURCES / "Localizable.xcstrings"
FORMAT_CATALOG = ROOT / "Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json"
METADATA_CATALOG = ROOT / "Configuration/Metadata.xcstrings"
LOCALIZATION = ROOT / "tools/localization"
UNREFERENCED_ALLOWLIST = LOCALIZATION / "unreferenced-allowlist.json"
TECHNICAL_NAMES = LOCALIZATION / "technical-names.json"

PLACEHOLDER = re.compile(
    r"%(?:(?P<position>[1-9][0-9]*)\$)?"
    r"(?P<format>#@[A-Za-z_][A-Za-z0-9_]*@"
    r"|(?!#@)[-+#0 ]*[0-9]*(?:\.[0-9]+)?(?:(?:ll|l|z)?[diu]|l?[feg]|[s@]))"
)

# Generated resource format. generate_localization.py writes it; this module reads and checks it.
STRINGS_HEADER = "/* Generated from Localizable.xcstrings; do not edit directly. */"
STRINGS_ENTRY = re.compile(r'("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");')
PLURAL_VARIABLE = "count"
PLURAL_FORMAT = "%#@count@"
# A plural key is also written to Localizable.strings as PLURAL_FORMAT, so a plain lookup of the key
# finds a value. If a Mac run shows that Foundation prefers that entry over the stringsdict, set this
# to False: plural keys then live only in the stringsdict, as Xcode itself generates them.
PLURAL_FORMAT_IN_STRINGS = True
PLURAL_RULE_TYPE = "NSStringPluralRuleType"
PLURAL_VALUE_TYPE = "lld"
PLURAL_CATEGORY_ORDER = ("zero", "one", "two", "few", "many", "other")

# CLDR plural categories for integer values, as (required, optional) per selected language. Source:
# https://www.unicode.org/cldr/charts/latest/supplemental/language_plural_rules.html. French, Spanish
# and Portuguese also define `many` (multiples of a million, "1 million de lignes"). A count never
# reaches that, so it stays optional unless the development language supplies it. Every language in
# tools/localization/languages.json needs a row before it can carry a plural string.
_ONE_OTHER = (("one", "other"), ())
_ROMANCE = (("one", "other"), ("many",))
_OTHER_ONLY = (("other",), ())
PLURAL_CATEGORIES = {
    "en": _ONE_OTHER, "tr": _ONE_OTHER, "de": _ONE_OTHER, "hi": _ONE_OTHER,
    "ku-Latn": _ONE_OTHER, "bn": _ONE_OTHER, "ha": _ONE_OTHER,
    "ru": (("one", "few", "many", "other"), ()),
    "fr": _ROMANCE, "es": _ROMANCE, "pt": _ROMANCE,
    "zh-Hans": _OTHER_ONLY, "ja": _OTHER_ONLY, "id": _OTHER_ONLY,
}

# Copy lints (warnings): (languages, pattern, message). A straight apostrophe between two letters
# is an apostrophe that should be U+2019; quotation marks and primes are not matched.
#
# French sets `: ; ? ! »` off from the word before them, and « from the word after it, with a no-break space
# (U+00A0, or the narrow U+202F), so a line never starts with a lone mark. An ordinary space there breaks the
# line, and no space at all is the English habit.
#
# Hausa writes its glottal stop (hamza: "nau'in", "na'ura", "'yan") with one character. U+02BC MODIFIER LETTER
# APOSTROPHE is the choice. Unicode encodes it as a letter, for this use in orthographies, so selection, search,
# sorting and case mapping keep a word whole; it is never a quotation mark, so quote substitution and the
# English and French apostrophe rules above leave it alone, which U+2019 (a closing quotation mark, and the
# apostrophe those rules require) does not. The catalog used to mix U+0027 and U+2019 in 126 places. The native
# reviewer may prefer the other character: change HAUSA_GLOTTAL_STOP and run normalize_localization_typography.py.
FRENCH_NO_BREAK = "\u00a0\u202f"
HAUSA_GLOTTAL_STOP = "\u02bc"
HAUSA_APOSTROPHES = "'\u2019\u2018`\u00b4"
FRENCH_BREAKING_SPACE = re.compile(r"(?<= )[:;?!\u00bb]|\u00ab(?= )")
FRENCH_MISSING_SPACE = re.compile(r"(?<=[^\W\d_])[;?!\u00bb]|(?<=[^\W\d_]):(?=\s|\Z)|\u00ab(?=[^\s" + FRENCH_NO_BREAK + r"])")
HAUSA_APOSTROPHE = re.compile("(?<=[^\\W\\d_])[" + re.escape(HAUSA_APOSTROPHES) + "](?=[^\\W\\d_])")
TYPOGRAPHY_RULES = (
    (("en", "fr"), re.compile(r"(?<=[^\W\d_])'(?=[^\W\d_])"),
     "straight apostrophe between letters; use U+2019"),
    (("fr",), FRENCH_BREAKING_SPACE,
     "breaking space beside : ; ? ! \u00bb or \u00ab; use a no-break space (U+00A0 or U+202F)"),
    (("fr",), FRENCH_MISSING_SPACE,
     "no space beside ; ? ! \u00bb \u00ab or a colon; French sets them off with a no-break space (U+00A0 or U+202F)"),
    (("ha",), HAUSA_APOSTROPHE,
     "glottal stop written with an apostrophe or quotation mark; use U+02BC (" + HAUSA_GLOTTAL_STOP + ")"),
)

# German quotation marks open with U+201E and close with U+201C: „Dateitypen“. Straight quotes, the English closing
# mark U+201D and guillemets mean another convention.
GERMAN_OPENING, GERMAN_CLOSING = "\u201e", "\u201c"
GERMAN_FOREIGN_QUOTES = '"\u201d\u00ab\u00bb\u2039\u203a'

# Length budgets (warnings): the most characters a translation may have, as a multiple of the English characters, for
# chrome that has to fit (labels, buttons, chips, headers, status lines). One-word labels would exceed any ratio,
# so a budget is never under LENGTH_FLOOR characters, and English text of more than LENGTH_MAX_ENGLISH characters
# wraps, so it is not measured. The ratios are the program's (decision 027): the Latin-script languages run about
# 1.2 times the English, so 1.5 flags roughly the longest tenth; Bengali, Hindi, Kurmanji and Hausa get 2.0 because
# their drafts are longer and their reviews pending; Chinese and Japanese count full-width characters, about twice the
# width of a Latin letter, so 0.8 of the English count is about 1.6 times its width, the same room. A flagged value
# is not wrong, only worth a reviewer's look: reviewed exceptions go in LENGTH_ALLOWLIST.
LENGTH_BUDGETS = {
    "de": 1.5, "fr": 1.5, "ru": 1.5, "es": 1.5, "pt": 1.5, "id": 1.5, "tr": 1.5,
    "bn": 2.0, "hi": 2.0, "ku-Latn": 2.0, "ha": 2.0,
    "zh-Hans": 0.8, "ja": 0.8,
}
LENGTH_FLOOR = 16
LENGTH_MAX_ENGLISH = 60
LENGTH_ALLOWLIST = LOCALIZATION / "length-allowlist.json"
CHROME_COMMENT = re.compile(r"\b(?:header|notice)\b", re.IGNORECASE)
MAX_CHROME_WORDS = 12
LETTER = re.compile(r"[^\W\d_]")
CALL_SITE = re.compile(r"\bPreviewStrings\.(format|count|text)\b")
CALL_LABELS = {"format": "formatted", "count": "counted"}


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def placeholders(value, *, tolerate_literal_percent=False):
    """Count each format argument by position and directive.

    Strict by default: any percent sign must start a supported directive or be `%%`. A text-only
    resource never reaches String(format:), so with tolerate_literal_percent a percent sign that
    does not start a supported directive, or is followed by whitespace ("100% done"), is literal.
    `%#@name@` is a plural variable reference and consumes an argument like any directive."""
    # Preserve each argument's identity as well as its format. Positional
    # reordering is valid; repeating one index must not conceal a missing one.
    arguments = Counter()
    offset = 0
    next_position = 1
    positional = None
    while (offset := value.find("%", offset)) != -1:
        if value.startswith("%%", offset):
            offset += 2
            continue
        match = PLACEHOLDER.match(value, offset)
        if tolerate_literal_percent and (match is None or value[offset + 1:offset + 2].isspace()):
            offset += 1
            continue
        if match is None:
            raise ValueError(f"Unsupported or incomplete format directive at character {offset}")
        uses_position = match.group("position") is not None
        if positional is not None and positional != uses_position:
            raise ValueError("Cannot mix positional and sequential format arguments")
        positional = uses_position
        position = int(match.group("position")) if uses_position else next_position
        arguments[(position, match.group("format"))] += 1
        next_position += 1
        offset = match.end()
    return arguments


def placeholders_match(source, translation, *, formatted):
    """Placeholder parity for any key. Formatted keys (a PreviewStrings.format call site, or bundle
    metadata) are checked strictly; every other key still compares its supported directives but
    may contain literal percent signs."""
    tolerant = not formatted
    return (placeholders(source, tolerate_literal_percent=tolerant)
            == placeholders(translation, tolerate_literal_percent=tolerant))


# MARK: catalog shape and plural rules

def _text_unit(container):
    if (not isinstance(container, dict) or set(container) != {"stringUnit"}
            or not isinstance(container["stringUnit"], dict)
            or not isinstance(container["stringUnit"].get("value"), str)):
        raise ValueError("expected exactly a stringUnit with a text value")
    return container["stringUnit"]["value"]


def localization_value(localization):
    """The text of a plain localization, or {category: text} for `variations.plural`.

    Anything else (device variations, substitutions, siblings of either shape) is rejected rather than
    silently dropped."""
    if not isinstance(localization, dict):
        raise ValueError("expected an object")
    if "variations" not in localization:
        return _text_unit(localization)
    variations = localization["variations"]
    if set(localization) != {"variations"} or not isinstance(variations, dict) or set(variations) != {"plural"}:
        raise ValueError("only variations.plural is supported")
    plural = variations["plural"]
    if not isinstance(plural, dict) or not plural:
        raise ValueError("variations.plural has no categories")
    variants = {}
    for category, variant in plural.items():
        if category not in PLURAL_CATEGORY_ORDER:
            raise ValueError(f"unknown plural category {category!r}")
        variants[category] = _text_unit(variant)
    return variants


def ordered_variants(variants):
    """Plural variants in CLDR order, for deterministic output."""
    return [(category, variants[category]) for category in PLURAL_CATEGORY_ORDER if category in variants]


def catalog_localization(value):
    """The String Catalog localization for a text or a {category: text} plural value; the inverse of
    localization_value."""
    def unit(text):
        return {"stringUnit": {"state": "translated", "value": text}}
    if isinstance(value, dict):
        return {"variations": {"plural": {category: unit(text) for category, text in ordered_variants(value)}}}
    return unit(value)


def canonical_json(document):
    """Text for a catalog or translation input with its `strings` and `metadata` dictionaries sorted
    by key, so additions from parallel workstreams land in different places."""
    document = dict(document)
    for field in ("strings", "metadata"):
        if isinstance(document.get(field), dict):
            document[field] = dict(sorted(document[field].items()))
    return json.dumps(document, ensure_ascii=False, indent=2) + "\n"


def plural_categories(language, english_categories=()):
    """(required, allowed) plural categories for integers. `many` is required for French, Spanish and
    Portuguese only when the development language supplies it."""
    try:
        required, optional = PLURAL_CATEGORIES[language]
    except KeyError:
        raise ValueError(f"No CLDR plural categories are encoded for {language}; add a row to PLURAL_CATEGORIES")
    required = set(required) | (set(optional) & set(english_categories))
    return required, required | set(optional)


def without_directives(text):
    return PLACEHOLDER.sub("", text.replace("%%", ""))


def plural_problems(language, variants, english=None):
    """Problems in one language's plural variants. `english` holds the development language's
    variants; leave it None when checking the development language itself.

    Every variant prints the count as `%2$@` (the caller formats it for the locale), so each carries
    the placeholders of the English `other` variant, never the raw first argument that selects the
    category, and no digits of its own."""
    problems = []
    reference_variants = variants if english is None else english
    try:
        required, allowed = plural_categories(language, () if english is None else english)
    except ValueError as error:
        return [str(error)]
    if missing := sorted(required - set(variants)):
        problems.append(f"missing plural categories {missing}")
    if extra := sorted(set(variants) - allowed):
        problems.append(f"plural categories {extra} are not defined for {language} (CLDR allows {sorted(allowed)})")
    reference = None
    if isinstance(reference_variants.get("other"), str):
        try:
            reference = placeholders(reference_variants["other"])
        except ValueError as error:
            problems.append(f"invalid format directive in the development language: {error}")
    for category, text in ordered_variants(variants):
        if not isinstance(text, str) or not text.strip():
            problems.append(f"{category}: empty or non-string text")
            continue
        try:
            found = placeholders(text)
        except ValueError as error:
            problems.append(f"{category}: invalid format directive ({error})")
            continue
        if any(position == 1 for position, _ in found):
            problems.append(f"{category}: prints the selector argument; print the count with %2$@, which is formatted for the locale")
        if reference is not None and found != reference:
            problems.append(f"{category}: placeholders differ from the development language's other variant")
        if any(unicodedata.category(character) == "Nd" for character in without_directives(text)):
            problems.append(f"{category}: contains a literal digit; print the count with %2$@")
    return problems


def value_problems(language, value, english, *, formatted, is_development=False):
    """Problems with one language's value for a key, given the development language's value.

    A plain key holds text in every language; a plural key holds {category: text} in every language."""
    if isinstance(english, dict):
        if not isinstance(value, dict):
            return ["expected an object of plural categories, not a plain string"]
        return plural_problems(language, value, None if is_development else english)
    if isinstance(value, dict):
        return ["expected a plain string, not an object of plural categories"]
    if not isinstance(value, str) or not value.strip():
        return ["empty or non-string text"]
    try:
        if not placeholders_match(english, value, formatted=formatted):
            return ["placeholders differ from the development language"]
    except ValueError as error:
        return [f"invalid format directive ({error})"]
    return []


def stringsdict_entry(variants):
    """The Localizable.stringsdict entry for one plural key: the format selects the category from the
    first argument and every variant prints the second as `%2$@`."""
    rule = {"NSStringFormatSpecTypeKey": PLURAL_RULE_TYPE, "NSStringFormatValueTypeKey": PLURAL_VALUE_TYPE}
    rule.update(variants)
    return {"NSStringLocalizedFormatKey": PLURAL_FORMAT, PLURAL_VARIABLE: rule}


# MARK: Swift call sites and catalog references

def swift_sources():
    for directory in [RENDERERS, ROOT / "Apps", ROOT / "Extensions"]:
        yield from sorted(directory.rglob("*.swift"))


def case_identifiers():
    return dict(re.findall(r'\bcase\s+(\w+)\s*=\s*"([^"\n]+)"',
                           (RENDERERS / "PreviewStrings.swift").read_text(encoding="utf-8")))


def scan_call_sites():
    """Return ({"format": keys, "count": keys, "text": keys}, unrecognized).

    The keys are those passed as a literal `.case` first argument to PreviewStrings.format, .count and
    .text. `unrecognized` lists every format or count call whose first argument is not a literal case
    that PreviewStrings.swift declares, with its file and line: validation cannot check placeholders or
    plural categories for a key it cannot see."""
    identifiers = case_identifiers()
    sites = {"format": set(), "count": set(), "text": set()}
    unrecognized = []
    for source in swift_sources():
        text = source.read_text(encoding="utf-8")
        for reference in CALL_SITE.finditer(text):
            function = reference[1]
            call = re.match(r"\s*\(\s*\.(\w+)\s*" + (r"[,)]" if function == "text" else ","), text[reference.end():])
            if call is not None and call[1] in identifiers:
                sites[function].add(identifiers[call[1]])
            elif function != "text":
                detail = f".{call[1]} is not a PreviewStrings.Key case" if call else "the first argument is not a literal .case"
                unrecognized.append(f"Unrecognized {CALL_LABELS[function]}-resource key use: "
                                    f"{source.relative_to(ROOT)}:{text.count(chr(10), 0, reference.start()) + 1} ({detail})")
    return sites, unrecognized


def call_site_keys(function, strict):
    """Keys of one function's literal call sites. Unrecognized calls raise unless strict is False, which
    lets a merge go ahead before the lead has added the cases that in-flight work refers to; the
    validator reports them as errors instead."""
    sites, unrecognized = scan_call_sites()
    if strict and unrecognized:
        raise ValueError("\n".join(unrecognized))
    return sites[function]


def formatted_string_keys(strict=True):
    """Discover typed format calls; plain text resources may contain literal %."""
    return call_site_keys("format", strict)


def counted_string_keys(strict=True):
    """Discover typed count calls; each must name a plural catalog entry."""
    return call_site_keys("count", strict)


def format_catalog_keys(node):
    """Localization keys the format catalog names: every nameKey and descriptionKey at any depth."""
    if isinstance(node, dict):
        for field, value in node.items():
            if field in ("nameKey", "descriptionKey") and isinstance(value, str):
                yield value
            else:
                yield from format_catalog_keys(value)
    elif isinstance(node, list):
        for item in node:
            yield from format_catalog_keys(item)


# MARK: generated resources

def parse_strings(text):
    """Strict reader for the generator's own .strings output: the header comment, then one
    `"key" = "value";` line per entry, both JSON-quoted, with a terminating newline. Anything else is
    an error, so a hand edit or a different generator cannot pass as the generated file."""
    lines = text.split("\n")
    if lines.pop() != "":
        raise ValueError("missing the terminating newline")
    if not lines or lines[0] != STRINGS_HEADER:
        raise ValueError("missing the generated-file header comment on the first line")
    entries = {}
    for number, line in enumerate(lines[1:], start=2):
        match = STRINGS_ENTRY.fullmatch(line)
        if match is None:
            raise ValueError(f"line {number} is not a generated entry")
        key, value = json.loads(match[1]), json.loads(match[2])
        if key in entries:
            raise ValueError(f"line {number} repeats the key {key!r}")
        entries[key] = value
    return entries


def read_strings(path, use_plutil=None):
    """The entries of a generated .strings file: plutil when it is installed, else parse_strings."""
    if use_plutil is None:
        use_plutil = shutil.which("plutil") is not None
    if not use_plutil:
        return parse_strings(Path(path).read_bytes().decode("utf-8"))
    result = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)], capture_output=True, text=True)
    if result.returncode:
        raise ValueError("plutil could not read the file")
    return json.loads(result.stdout)


def read_stringsdict(path):
    try:
        return plistlib.loads(Path(path).read_bytes())
    except (ValueError, ExpatError) as error:
        raise ValueError(str(error))


def expected_strings(values):
    """The Localizable.strings entries for one language's values."""
    return {key: PLURAL_FORMAT if isinstance(value, dict) else value
            for key, value in values.items() if PLURAL_FORMAT_IN_STRINGS or not isinstance(value, dict)}


def expected_stringsdict(values):
    return {key: stringsdict_entry(value) for key, value in values.items() if isinstance(value, dict)}


# MARK: lints

def load_allowlists(errors):
    """(unreferenced keys with their reasons, technical names). A missing file is an empty list."""
    reasons, names = {}, set()
    if UNREFERENCED_ALLOWLIST.is_file():
        document = read_json(UNREFERENCED_ALLOWLIST)
        reasons = document.get("keys") if isinstance(document, dict) else None
        if (not isinstance(reasons, dict)
                or any(not isinstance(reason, str) or not reason.strip() for reason in reasons.values())):
            errors.append(f"{UNREFERENCED_ALLOWLIST.name}: expected {{\"keys\": {{key: reason}}}} with a reason for every key")
            reasons = {}
    if TECHNICAL_NAMES.is_file():
        document = read_json(TECHNICAL_NAMES)
        listed = document.get("names") if isinstance(document, dict) else None
        if not isinstance(listed, list) or not all(isinstance(name, str) for name in listed):
            errors.append(f"{TECHNICAL_NAMES.name}: expected {{\"names\": [text, ...]}}")
            listed = []
        names = set(listed)
    return reasons, names


def comparable(value):
    return value.get("other") if isinstance(value, dict) else value


def identical_to_english(values, development, technical):
    """Map each key to the languages whose text equals the development language's, leaving out
    technical names, and text with no letters outside placeholders (nothing to translate)."""
    report = {}
    for key, english in sorted(values.get(development, {}).items()):
        text = comparable(english)
        if not isinstance(text, str) or text in technical or not LETTER.search(without_directives(text)):
            continue
        languages = [language for language in sorted(values) if language != development
                     and comparable(values[language].get(key)) == text]
        if languages:
            report[key] = languages
    return report


def german_quote_problems(text):
    """What is wrong with the quotation marks of a German text, as short messages: marks of another convention,
    and an opening mark without its closing mark or the reverse."""
    problems = []
    foreign = sorted({character for character in text if character in GERMAN_FOREIGN_QUOTES})
    if foreign:
        problems.append("quotation mark " + " ".join(f"U+{ord(character):04X}" for character in foreign)
                        + f"; German quotes are {GERMAN_OPENING}...{GERMAN_CLOSING} (U+201E, U+201C)")
    open_quote = False
    for character in text:
        if character == GERMAN_OPENING:
            if open_quote:
                problems.append(f"{GERMAN_OPENING} opened twice without {GERMAN_CLOSING}")
            open_quote = True
        elif character == GERMAN_CLOSING:
            if not open_quote:
                problems.append(f"{GERMAN_CLOSING} without an opening {GERMAN_OPENING}")
            open_quote = False
    if open_quote:
        problems.append(f"{GERMAN_OPENING} without a closing {GERMAN_CLOSING}")
    return list(dict.fromkeys(problems))


# Typography checks written as functions: (languages, text -> messages).
TYPOGRAPHY_CHECKS = (
    (("de",), german_quote_problems),
)


def typography_warnings(values):
    warnings = []
    for languages, pattern, message in TYPOGRAPHY_RULES:
        for language in languages:
            for key, value in sorted(values.get(language, {}).items()):
                texts = value.values() if isinstance(value, dict) else [value]
                if any(pattern.search(text) for text in texts):
                    warnings.append(f"{language}/{key}: {message}")
    for languages, check in TYPOGRAPHY_CHECKS:
        for language in languages:
            for key, value in sorted(values.get(language, {}).items()):
                texts = value.values() if isinstance(value, dict) else [value]
                messages = list(dict.fromkeys(message for text in texts for message in check(text)))
                warnings.extend(f"{language}/{key}: {message}" for message in messages)
    return warnings


def display_length(text):
    """The characters a reader counts: code points without combining marks and format characters, so Indic vowel
    signs, the virama and joiners do not inflate Bengali and Hindi. Placeholders count as written."""
    return sum(1 for character in text if unicodedata.category(character) not in ("Mn", "Me", "Cf"))


def length_allowlist(errors):
    """{key: set of languages, or None for every language} from LENGTH_ALLOWLIST. Each entry is a reason text, or
    {"languages": [...], "reason": text}; a missing file is an empty list."""
    if not LENGTH_ALLOWLIST.is_file():
        return {}
    document = read_json(LENGTH_ALLOWLIST)
    listed = document.get("keys") if isinstance(document, dict) else None
    allowed = {}
    if not isinstance(listed, dict):
        errors.append(f"{LENGTH_ALLOWLIST.name}: expected {{\"keys\": {{key: reason}}}}")
        return allowed
    for key, entry in listed.items():
        languages = None
        reason = entry
        if isinstance(entry, dict):
            reason = entry.get("reason")
            languages = entry.get("languages")
            if languages is not None and (not isinstance(languages, list) or not languages
                                          or not all(language in LENGTH_BUDGETS for language in languages)):
                errors.append(f"{LENGTH_ALLOWLIST.name}: {key}: languages must be a non-empty list of budgeted languages")
                continue
        if not isinstance(reason, str) or not reason.strip():
            errors.append(f"{LENGTH_ALLOWLIST.name}: {key}: a reason is required")
            continue
        allowed[key] = None if languages is None else set(languages)
    return allowed


def length_overruns(values, development):
    """Every value over its language's budget: [(key, language, translated length, english length, budget)], the
    longest overshoot first, because the characters over the budget are what truncate. Plural keys compare their
    `other` variants."""
    overruns = []
    for key, english in sorted(values.get(development, {}).items()):
        source = comparable(english)
        if not isinstance(source, str) or not 0 < display_length(source) <= LENGTH_MAX_ENGLISH:
            continue
        for language, ratio in LENGTH_BUDGETS.items():
            text = comparable(values.get(language, {}).get(key))
            if not isinstance(text, str):
                continue
            budget = max(ratio * display_length(source), LENGTH_FLOOR)
            if display_length(text) > budget:
                overruns.append((key, language, display_length(text), display_length(source), budget))
    return sorted(overruns, key=lambda item: (-(item[2] - item[4]), item[0], item[1]))


def length_warnings(values, development, allowed):
    """(warnings, stale allow-list entries): the overruns the allow-list does not accept, and the entries that
    accept nothing any more (the key is gone or the value fits)."""
    overruns = length_overruns(values, development)
    warnings = []
    used = set()
    for key, language, length, english, budget in overruns:
        accepted = allowed.get(key, False)
        if accepted is None or (accepted is not False and language in accepted):
            used.add(key)
            continue
        warnings.append(f"{key}: {language} has {length} characters for {english} in English (at most {budget:g})")
    stale = [f"{key}: " + ("no longer in the catalog" if key not in values.get(development, {}) else "nothing exceeds its budget")
             for key in sorted(allowed) if key not in used]
    return warnings, stale


def chrome_length_warnings(entries, values, development):
    warnings = []
    for key, entry in sorted(entries.items()):
        if key.startswith("format."):
            # A format's description is a File Types row, not a header or notice, and its comment may use the word
            # in another sense ("header" of an archive); the row has its own three-line rule.
            continue
        comment = entry.get("comment", "")
        text = comparable(values.get(development, {}).get(key))
        if (isinstance(comment, str) and CHROME_COMMENT.search(comment) and isinstance(text, str)
                and len(text.split()) > MAX_CHROME_WORDS):
            warnings.append(f"{key}: {len(text.split())} words (header and notice strings stay within {MAX_CHROME_WORDS})")
    return warnings


# MARK: validation

def check_catalog(entries, development, sites, errors):
    """Check every key in every language; return {language: {key: text or {category: text}}}."""
    values = {}
    for key, entry in sorted(entries.items()):
        parsed = {}
        for language, localization in entry.get("localizations", {}).items():
            try:
                parsed[language] = localization_value(localization)
            except ValueError as error:
                errors.append(f"Unsupported resource variant: {language}/{key}: {error}")
        english = parsed.get(development)
        if english is None:
            errors.append(f"Missing development-language text: {key}")
        for language, value in parsed.items():
            values.setdefault(language, {})[key] = value
            if english is not None:
                for problem in value_problems(language, value, english, formatted=key in sites["format"],
                                              is_development=language == development):
                    errors.append(f"{language}/{key}: {problem}")
    return values


def check_call_sites(values, development, sites, errors):
    plural_keys = {key for key, value in values.get(development, {}).items() if isinstance(value, dict)}
    for key in sorted(sites["count"] - plural_keys):
        errors.append(f"PreviewStrings.count needs a plural catalog entry: {key}")
    for function in ("format", "text"):
        for key in sorted(sites[function] & plural_keys):
            errors.append(f"Plural key read with PreviewStrings.{function}: {key}; use PreviewStrings.count")
    return plural_keys


def check_generated(values, entries, required, errors):
    for language, expected in sorted(values.items()):
        for key in sorted(entries.keys() - expected.keys()):
            errors.append(f"Incomplete catalog locale: {language}/{key}")
        for key in sorted(required - expected.keys()):
            errors.append(f"Incomplete declared locale: {language}/{key}")
        strings_path = RESOURCES / f"{language}.lproj/Localizable.strings"
        if not strings_path.is_file():
            errors.append(f"Missing generated fallback: {strings_path.relative_to(ROOT)}")
        else:
            try:
                if read_strings(strings_path) != expected_strings(expected):
                    errors.append(f"Generated fallback differs from catalog: {language}")
            except ValueError as error:
                errors.append(f"Invalid strings resource: {strings_path.relative_to(ROOT)} ({error})")
        plural_path = RESOURCES / f"{language}.lproj/Localizable.stringsdict"
        plurals = expected_stringsdict(expected)
        if not plurals:
            if plural_path.exists():
                errors.append(f"Stale plural resource: {plural_path.relative_to(ROOT)}; run generate_localization.py")
        elif not plural_path.is_file():
            errors.append(f"Missing generated plural resource: {plural_path.relative_to(ROOT)}")
        else:
            try:
                if read_stringsdict(plural_path) != plurals:
                    errors.append(f"Generated plural resource differs from catalog: {language}")
            except ValueError as error:
                errors.append(f"Invalid plural resource: {plural_path.relative_to(ROOT)} ({error})")


def print_warnings(warnings, verbose):
    warnings = {label: items for label, items in warnings.items() if items}
    if not warnings:
        return
    print("Warnings (they never fail the check):")
    for label, items in warnings.items():
        print(f"  {label}: {len(items)}")
        shown = items if verbose else items[:5]
        for item in shown:
            print(f"    {item}")
        if len(shown) < len(items):
            print(f"    ... {len(items) - len(shown)} more; run with --verbose to list every item")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--verbose", action="store_true", help="list every warning item, not the first five")
    arguments = parser.parse_args(argv)

    errors = []
    warnings = {}
    catalog = read_json(CATALOG)
    entries = catalog["strings"]
    development = catalog["sourceLanguage"]
    sites, unrecognized = scan_call_sites()
    errors.extend(unrecognized)
    selected = set(read_json(LOCALIZATION / "languages.json")["languages"])
    for language in sorted(selected - PLURAL_CATEGORIES.keys()):
        errors.append(f"No CLDR plural categories are encoded for {language}; add a row to PLURAL_CATEGORIES")

    required = set()
    accessor_files = list(RENDERERS.rglob("PreviewStrings.swift"))
    if len(accessor_files) != 1:
        errors.append("Expected one PreviewStrings.swift typed resource accessor")
    else:
        required.update(case_identifiers().values())
        if not required:
            errors.append("No typed localization keys found")
    referenced = set(required)
    named_by_formats = set(format_catalog_keys(read_json(FORMAT_CATALOG)))
    required.update(named_by_formats)
    referenced.update(named_by_formats)
    for key in sorted(required - entries.keys()):
        errors.append(f"Missing catalog key: {key}")

    values = check_catalog(entries, development, sites, errors)
    plural_keys = check_call_sites(values, development, sites, errors)
    if set(values) != selected:
        errors.append(f"Declared locale set differs from selected languages: {sorted(set(values) ^ selected)}")

    metadata = read_json(METADATA_CATALOG)["strings"]
    for key, entry in metadata.items():
        localizations = entry.get("localizations", {})
        if set(localizations) != selected:
            errors.append(f"Incomplete bundle metadata locales: {key}")
        source = localizations.get(development, {}).get("stringUnit", {}).get("value", "")
        for language, localization in localizations.items():
            value = localization.get("stringUnit", {}).get("value")
            try:
                valid = isinstance(value, str) and value and placeholders_match(source, value, formatted=True)
            except ValueError:
                valid = False
            if not valid:
                errors.append(f"Invalid metadata translation: {language}/{key}")

    for language in sorted(selected - {development}):
        inputs = read_json(LOCALIZATION / "translations" / f"{language}.json")
        if inputs.get("strings") != values.get(language):
            errors.append(f"Translation input differs from runtime catalog: {language}; run merge_localizations.py")
        metadata_values = {key: entry.get("localizations", {}).get(language, {}).get("stringUnit", {}).get("value")
                           for key, entry in metadata.items()}
        if inputs.get("metadata") != metadata_values:
            errors.append(f"Metadata input differs from runtime catalog: {language}; run merge_localizations.py")

    check_generated(values, entries, required, errors)

    allowed, technical = load_allowlists(errors)
    for key in sorted(entries.keys() - referenced - allowed.keys()):
        errors.append(f"Unreferenced catalog key: {key} (add a case or retire it; or list it in {UNREFERENCED_ALLOWLIST.name} with a reason)")
    warnings["allowlist entries that are referenced or missing"] = [
        f"{key}: " + ("no longer in the catalog" if key not in entries else "now referenced")
        for key in sorted(allowed) if key not in entries or key in referenced]
    warnings["values identical to English outside the technical names"] = [
        f"{key}: {', '.join(languages)}" for key, languages in identical_to_english(values, development, technical).items()]
    warnings["typography"] = typography_warnings(values)
    warnings["long header and notice strings"] = chrome_length_warnings(entries, values, development)
    over_budget, stale_length_entries = length_warnings(values, development, length_allowlist(errors))
    warnings["translations over their length budget"] = over_budget
    warnings["length allowlist entries that are not needed"] = stale_length_entries

    if errors:
        print("\n".join(errors), file=sys.stderr)
        print_warnings(warnings, arguments.verbose)
        return 1
    print(f"Localization references verified: {len(entries)} keys ({len(plural_keys)} plural), {len(values)} locale(s). "
          "Translation quality and installed-host behavior remain separate checks.")
    print_warnings(warnings, arguments.verbose)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError) as error:
        print(f"Localization validation failed: {error}", file=sys.stderr)
        sys.exit(1)
