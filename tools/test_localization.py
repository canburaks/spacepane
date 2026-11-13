#!/usr/bin/env python3
"""Focused translation-format, plural, merge, add and lint checks; no runtime resources or user files change."""
from collections import Counter
from contextlib import ExitStack, redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import plistlib
import re
import shutil
import tempfile
import unittest
from unittest.mock import Mock, patch

import add_localizations
import generate_localization
import merge_localizations
import normalize_localization_typography
import validate_localization
from validate_localization import (
    canonical_json, catalog_localization, counted_string_keys, formatted_string_keys, localization_value,
    parse_strings, placeholders, placeholders_match, plural_categories, plural_problems, read_strings, value_problems,
)


class PlaceholderTests(unittest.TestCase):
    def test_positional_reordering_retains_each_argument(self):
        self.assertEqual(placeholders("%@, %lld"), placeholders("%2$lld, %1$@"))

    def test_repeating_a_position_cannot_drop_another_argument(self):
        self.assertNotEqual(placeholders("%1$@ / %2$@"), placeholders("%1$@ / %1$@"))

    def test_argument_type_remains_attached_to_its_position(self):
        self.assertNotEqual(placeholders("%@, %lld"), placeholders("%1$lld, %2$@"))

    def test_unknown_argument_position_does_not_match(self):
        self.assertNotEqual(placeholders("%@"), placeholders("%9$@"))

    def test_escaped_percent_does_not_consume_an_argument(self):
        self.assertEqual(placeholders("100%%: %@"), placeholders("%1$@: 100%%"))
        self.assertEqual(placeholders("%%"), placeholders(""))
        self.assertEqual(placeholders("%%%lld"), placeholders("%1$lld"))

    def test_unsupported_or_incomplete_directives_are_rejected(self):
        for value in ["%@ %n", "%0$@", "%*d", "%", "%1$", "%Q"]:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    placeholders(value)

    def test_mixed_argument_positioning_is_rejected(self):
        with self.assertRaises(ValueError):
            placeholders("%1$@ %@")

    def test_numeric_format_specifications_are_preserved(self):
        self.assertEqual(placeholders("%.2f"), placeholders("%1$.2f"))
        self.assertNotEqual(placeholders("%.2f"), placeholders("%.1f"))

    def test_literal_percentages_remain_plain_text(self):
        self.assertTrue(placeholders_match("100% complete", "100% done", formatted=False))

    def test_format_calls_discover_owned_resource_keys(self):
        # A call whose case is not declared yet (work in flight before the lead adds it) is the validator's
        # concern, so this pin does not depend on it.
        formatted = formatted_string_keys(strict=False)
        # Discovery of these established keys is pinned. Feature work adds further formatted keys,
        # so the set may grow; every discovered key must still name a real formatted resource.
        self.assertTrue({
            "action.aboutApp", "about.version", "about.privacy.body",
            "fileTypes.enabledCount", "fileTypes.group.disclosure",
            "appearance.unavailableFontFamily", 
            "appearance.syntax.control", "appearance.profile.deleteNamed",
            "appearance.profile.count", "appearance.sample.status",
            "preview.records.invalid", "preview.records.record", "midi.positionValue", "geometry.summary.dimensions",
            "preview.table.column", "preview.table.accessibilityLabel",
            "notebook.language", "notebook.cell.codeNumbered", "notebook.output.numbered", "notebook.output.notShown",
            "notebook.output.moreLines", "notebook.truncated",
            "settings.behavior.folderDepthValue", "settings.providers.checked", "settings.providers.found",
            "settings.providers.limit", "settings.providers.unreadable", "settings.providers.skipped",
            "settings.providers.formats", "settings.providers.formatsMore"
        } <= formatted)
        catalog = json.loads((validate_localization.RENDERERS / "Resources/Localizable.xcstrings").read_text())["strings"]
        for key in formatted:
            self.assertIn(key, catalog, key)
            english = catalog[key]["localizations"]["en"]["stringUnit"]["value"]
            self.assertTrue(placeholders(english), f"{key} is formatted but has no placeholder")

    def test_dynamic_format_call_cannot_silently_escape_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            renderers = root / "renderers"
            renderers.mkdir()
            (renderers / "PreviewStrings.swift").write_text('case example = "example.key"')
            (renderers / "Dynamic.swift").write_text('PreviewStrings.format(key, arguments: [value])')
            with patch.object(validate_localization, "ROOT", root), \
                    patch.object(validate_localization, "RENDERERS", renderers):
                with self.assertRaisesRegex(ValueError, "Unrecognized formatted-resource key use"):
                    formatted_string_keys()

    def test_merge_keeps_literal_percentages_in_text_only_resources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inputs = root / "inputs"
            translations = inputs / "translations"
            translations.mkdir(parents=True)
            (inputs / "languages.json").write_text(json.dumps({
                "developmentLanguage": "en", "languages": ["en", "tr"]
            }))
            sources = {
                "strings": {"preview.summary.partial": "100% complete"},
                "metadata": {"metadata.app.name": "%@"}
            }
            catalogs = {kind: root / f"{kind}.xcstrings" for kind in sources}
            for kind, values in sources.items():
                catalogs[kind].write_text(json.dumps({"strings": {
                    key: {"localizations": {"en": {"stringUnit": {"value": value}}}}
                    for key, value in values.items()
                }}))
            (translations / "tr.json").write_text(json.dumps({
                "strings": {"preview.summary.partial": "100% done"},
                "metadata": {"metadata.app.name": "%@"}
            }))
            with patch.object(merge_localizations, "INPUTS", inputs), \
                    patch.object(merge_localizations, "CATALOGS", catalogs), \
                    redirect_stdout(io.StringIO()):
                merge_localizations.main()
            merged = json.loads(catalogs["strings"].read_text())
            self.assertEqual(merged["strings"]["preview.summary.partial"]
                             ["localizations"]["tr"]["stringUnit"]["value"], "100% done")

    def test_bad_translation_does_not_publish_either_catalog(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inputs = root / "inputs"
            translations = inputs / "translations"
            translations.mkdir(parents=True)
            (inputs / "languages.json").write_text(json.dumps({
                "developmentLanguage": "en", "languages": ["en", "tr"]
            }))
            catalogs = {kind: root / f"{kind}.xcstrings" for kind in ["strings", "metadata"]}
            source = json.dumps({"strings": {"midi.positionValue": {"localizations": {
                "en": {"stringUnit": {"value": "%1$@ / %2$@"}}
            }}}})
            for catalog in catalogs.values():
                catalog.write_text(source)
            for invalid_kind in catalogs:
                with self.subTest(kind=invalid_kind):
                    values = {kind: {"midi.positionValue": "%2$@ / %1$@"} for kind in catalogs}
                    values[invalid_kind]["midi.positionValue"] = "%1$@ / %1$@"
                    (translations / "tr.json").write_text(json.dumps(values))
                    with patch.object(merge_localizations, "INPUTS", inputs), \
                            patch.object(merge_localizations, "CATALOGS", catalogs):
                        with self.assertRaises(ValueError):
                            merge_localizations.main()
                    for catalog in catalogs.values():
                        self.assertEqual(catalog.read_text(), source)


# MARK: fixtures

PLURAL_LINES = {
    "comment": "Count of displayed lines; the first argument selects the plural rule, the second is the locale-formatted number.",
    "en": {"one": "%2$@ line", "other": "%2$@ lines"},
    "ru": {"one": "%2$@ строка", "few": "%2$@ строки", "many": "%2$@ строк", "other": "%2$@ строки"},
    "ja": {"other": "%2$@ 行"},
}
PLAIN_EXAMPLE = {"comment": "Example action title.", "en": "Example", "ru": "Пример", "ja": "例"}
ENTRIES = {"preview.count.lines": PLURAL_LINES, "action.example": PLAIN_EXAMPLE}


class Repository:
    """A throwaway repository root holding only what the localization tools read, with every
    tool's module-level paths pointed at it. Nothing here touches the real catalogs."""

    def __init__(self, languages=("en", "ru", "ja")):
        self.languages = list(languages)
        self._directory = tempfile.TemporaryDirectory()
        self.root = Path(self._directory.name)
        self.renderers = self.root / "Packages/PreviewCore/Sources/PreviewRenderers"
        self.resources = self.renderers / "Resources"
        self.catalog = self.resources / "Localizable.xcstrings"
        self.formats = self.root / "Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json"
        self.metadata = self.root / "Configuration/Metadata.xcstrings"
        self.localization = self.root / "tools/localization"
        self.translations = self.localization / "translations"
        self.catalogs = {"strings": self.catalog, "metadata": self.metadata}
        self._patches = ExitStack()

    def __enter__(self):
        self._patches.enter_context(patch.multiple(
            validate_localization, ROOT=self.root, RENDERERS=self.renderers, RESOURCES=self.resources,
            CATALOG=self.catalog, FORMAT_CATALOG=self.formats, METADATA_CATALOG=self.metadata,
            LOCALIZATION=self.localization, UNREFERENCED_ALLOWLIST=self.localization / "unreferenced-allowlist.json",
            TECHNICAL_NAMES=self.localization / "technical-names.json",
            LENGTH_ALLOWLIST=self.localization / "length-allowlist.json"))
        self._patches.enter_context(patch.object(normalize_localization_typography, "LOCALIZATION", self.localization))
        self._patches.enter_context(patch.object(generate_localization, "RESOURCES", self.resources))
        for module in (merge_localizations, add_localizations):
            self._patches.enter_context(patch.multiple(module, INPUTS=self.localization, CATALOGS=self.catalogs))
        return self

    def __exit__(self, *exception):
        self._patches.close()
        self._directory.cleanup()

    def write(self, entries, *, merged=True, cases=None, swift=None, formats=None):
        """Write catalogs, inputs, a PreviewStrings.swift naming `cases` (default: every key) and any
        extra Swift sources. With merged=False the catalog holds the development language only."""
        for directory in (self.resources, self.formats.parent, self.metadata.parent, self.translations):
            directory.mkdir(parents=True, exist_ok=True)
        development, others = self.languages[0], self.languages[1:]
        shown = self.languages if merged else [development]
        strings = {key: {"comment": entry["comment"], "extractionState": "manual",
                         "localizations": {language: catalog_localization(entry[language]) for language in shown}}
                   for key, entry in entries.items()}
        self.catalog.write_text(canonical_json({"sourceLanguage": development, "strings": strings, "version": "1.0"}), encoding="utf-8")
        self.metadata.write_text(canonical_json({"sourceLanguage": development, "version": "1.0", "strings": {
            "metadata.app.name": {"localizations": {language: catalog_localization("%@") for language in shown}}}}), encoding="utf-8")
        (self.localization / "languages.json").write_text(json.dumps({
            "developmentLanguage": development, "languages": self.languages}), encoding="utf-8")
        for language in others:
            (self.translations / f"{language}.json").write_text(canonical_json({
                "strings": {key: entry[language] for key, entry in entries.items()},
                "metadata": {"metadata.app.name": "%@"}}), encoding="utf-8")
        names = list(entries) if cases is None else cases
        (self.renderers / "PreviewStrings.swift").write_text(
            "\n".join(f'case c{index} = "{key}"' for index, key in enumerate(names)), encoding="utf-8")
        self.formats.write_text(json.dumps(formats or {"formats": []}), encoding="utf-8")
        for relative, text in (swift or {}).items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")

    def generate(self):
        with redirect_stdout(io.StringIO()):
            generate_localization.main()

    def validate(self, *arguments, plutil=False):
        """Run the validator; without plutil (the default, on every platform) its strict reader checks the
        generated .strings files."""
        out, err = io.StringIO(), io.StringIO()
        with ExitStack() as stack:
            if not plutil:
                stack.enter_context(patch.object(validate_localization.shutil, "which", return_value=None))
            stack.enter_context(redirect_stdout(out))
            stack.enter_context(redirect_stderr(err))
            code = validate_localization.main(list(arguments))
        return code, out.getvalue(), err.getvalue()

    def merge(self):
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(err):
            merge_localizations.main()
        return err.getvalue()

    def add(self, additions, catalog="strings"):
        path = self.root / "additions.json"
        path.write_text(json.dumps(additions, ensure_ascii=False), encoding="utf-8")
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = add_localizations.main([str(path), "--catalog", catalog])
        return code, err.getvalue()

    def read_catalog(self):
        return json.loads(self.catalog.read_text(encoding="utf-8"))["strings"]

    def read_input(self, language):
        return json.loads((self.translations / f"{language}.json").read_text(encoding="utf-8"))


def entry(en, ru=None, ja=None, comment="Test string."):
    return {"comment": comment, "en": en, "ru": en if ru is None else ru, "ja": en if ja is None else ja}


# MARK: placeholders and plural rules

class PluralPlaceholderTests(unittest.TestCase):
    def test_plural_variable_reference_is_a_placeholder(self):
        self.assertEqual(placeholders("%#@count@"), Counter({(1, "#@count@"): 1}))
        self.assertEqual(placeholders("%1$#@count@"), Counter({(1, "#@count@"): 1}))
        self.assertNotEqual(placeholders("%#@count@"), placeholders("%@"))

    def test_incomplete_plural_variable_is_rejected(self):
        for value in ["%#@", "%#@count", "%#@@", "%1$#@"]:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    placeholders(value)

    def test_variants_print_the_second_argument(self):
        self.assertEqual(placeholders("%2$@ lines"), Counter({(2, "@"): 1}))
        self.assertEqual(placeholders("%2$@ строки"), placeholders("строки %2$@"))

    def test_every_key_is_compared_even_without_a_call_site(self):
        self.assertFalse(placeholders_match("Rows: %lld", "Satırlar", formatted=False))
        self.assertFalse(placeholders_match("Copy", "Kopya %@", formatted=False))
        self.assertTrue(placeholders_match("Rows: %lld", "Satırlar: %lld", formatted=False))

    def test_literal_percent_is_tolerated_only_outside_formatted_keys(self):
        self.assertTrue(placeholders_match("Sampled 25% of rows", "25 % des lignes", formatted=False))
        self.assertTrue(placeholders_match("100% complete", "100% done", formatted=False))
        for value in ["Sampled 25% of rows", "50%"]:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    placeholders_match(value, value, formatted=True)

    def test_tolerance_still_counts_real_directives_and_escapes(self):
        self.assertEqual(placeholders("%lld%% of %@", tolerate_literal_percent=True),
                         placeholders("%1$lld%% of %2$@", tolerate_literal_percent=True))
        self.assertNotEqual(placeholders("25% of %@", tolerate_literal_percent=True), placeholders("25% of", tolerate_literal_percent=True))


class PluralRuleTests(unittest.TestCase):
    def test_each_selected_language_has_its_cldr_categories(self):
        # Independent expectations, so a wrong row in PLURAL_CATEGORIES cannot agree with itself.
        one_other = ({"one", "other"}, {"one", "other"})
        expected = {
            "en": one_other, "tr": one_other, "de": one_other, "hi": one_other, "ku-Latn": one_other,
            "bn": one_other, "ha": one_other,
            "ru": ({"one", "few", "many", "other"}, {"one", "few", "many", "other"}),
            "fr": ({"one", "other"}, {"one", "many", "other"}),
            "es": ({"one", "other"}, {"one", "many", "other"}),
            "pt": ({"one", "other"}, {"one", "many", "other"}),
            "zh-Hans": ({"other"}, {"other"}), "ja": ({"other"}, {"other"}), "id": ({"other"}, {"other"}),
        }
        selected = json.loads((validate_localization.LOCALIZATION / "languages.json").read_text(encoding="utf-8"))["languages"]
        self.assertEqual(set(selected), set(expected))
        for language, categories in expected.items():
            with self.subTest(language=language):
                self.assertEqual(plural_categories(language), categories)

    def test_many_is_required_for_romance_languages_only_when_english_has_it(self):
        for language in ["fr", "es", "pt"]:
            with self.subTest(language=language):
                self.assertEqual(plural_categories(language, ["one", "other"])[0], {"one", "other"})
                self.assertEqual(plural_categories(language, ["one", "many", "other"])[0], {"one", "many", "other"})
        self.assertEqual(plural_categories("ru", ["one", "other"])[0], {"one", "few", "many", "other"})

    def test_a_language_without_encoded_rules_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "No CLDR plural categories are encoded for xx"):
            plural_categories("xx")

    def test_missing_extra_and_unknown_categories_are_reported(self):
        english = {"one": "%2$@ line", "other": "%2$@ lines"}
        self.assertEqual(plural_problems("en", english), [])
        self.assertTrue(any("missing plural categories ['other']" in p for p in plural_problems("en", {"one": "%2$@ line"})))
        self.assertTrue(any("['few', 'many']" in p for p in plural_problems("en", {**english, "few": "x %2$@", "many": "y %2$@"})))
        ru = {"one": "%2$@ строка", "few": "%2$@ строки", "other": "%2$@ строки"}
        self.assertTrue(any("missing plural categories ['many']" in p for p in plural_problems("ru", ru, english)))
        self.assertTrue(any("not defined for ja" in p for p in plural_problems("ja", {"one": "%2$@ 行", "other": "%2$@ 行"}, english)))
        self.assertEqual(plural_problems("ja", {"other": "%2$@ 行"}, english), [])
        self.assertEqual(plural_problems("fr", {"one": "%2$@ ligne", "many": "%2$@ de lignes", "other": "%2$@ lignes"}, english), [])

    def test_every_variant_must_carry_the_english_placeholders(self):
        english = {"one": "%2$@ line", "other": "%2$@ lines"}
        for variants in [{"one": "une ligne", "other": "%2$@ lignes"},
                         {"one": "%2$@ ligne", "other": "%1$lld lignes"},
                         {"one": "%2$@ ligne %2$@", "other": "%2$@ lignes"},
                         {"one": "%2$@ ligne", "other": "%#@count@ lignes"}]:
            with self.subTest(variants=variants):
                self.assertTrue(any("placeholders differ" in p for p in plural_problems("fr", variants, english)))

    def test_variants_never_print_the_selector_argument(self):
        english = {"one": "%2$@ line", "other": "%2$@ lines"}
        for variants in [{"one": "%1$lld ligne", "other": "%1$lld lignes"},
                         {"one": "%2$@ ligne", "other": "%2$@ lignes (%1$lld)"},
                         {"one": "%2$@ ligne", "other": "%#@count@ lignes"}]:
            with self.subTest(variants=variants):
                self.assertTrue(any("prints the selector argument" in p for p in plural_problems("fr", variants, english)))
        self.assertTrue(any("prints the selector argument" in p for p in plural_problems("en", {"one": "%1$lld line", "other": "%1$lld lines"})))

    def test_variants_reject_literal_digits_and_empty_text(self):
        english = {"one": "%2$@ line", "other": "%2$@ lines"}
        self.assertTrue(any("literal digit" in p for p in plural_problems("fr", {"one": "1 ligne %2$@", "other": "%2$@ lignes"}, english)))
        self.assertTrue(any("literal digit" in p for p in plural_problems("bn", {"one": "১ %2$@", "other": "%2$@ লাইন"}, english)))
        self.assertTrue(any("empty" in p for p in plural_problems("fr", {"one": " ", "other": "%2$@ lignes"}, english)))
        self.assertTrue(any("invalid format directive" in p for p in plural_problems("fr", {"one": "%2$@ 100%", "other": "%2$@ lignes"}, english)))

    def test_plain_and_plural_values_are_never_interchangeable(self):
        plural = {"one": "%2$@ line", "other": "%2$@ lines"}
        self.assertEqual(value_problems("tr", "%2$@ satır", plural, formatted=False),
                         ["expected an object of plural categories, not a plain string"])
        self.assertEqual(value_problems("tr", plural, "Example", formatted=False),
                         ["expected a plain string, not an object of plural categories"])
        self.assertEqual(value_problems("tr", " ", "Example", formatted=False), ["empty or non-string text"])


class CatalogShapeTests(unittest.TestCase):
    def test_plain_and_plural_localizations_are_read(self):
        self.assertEqual(localization_value({"stringUnit": {"state": "translated", "value": "Example"}}), "Example")
        plural = {"variations": {"plural": {
            "one": {"stringUnit": {"state": "translated", "value": "%2$@ line"}},
            "other": {"stringUnit": {"state": "translated", "value": "%2$@ lines"}}}}}
        self.assertEqual(localization_value(plural), {"one": "%2$@ line", "other": "%2$@ lines"})

    def test_catalog_localization_is_the_inverse_in_cldr_order(self):
        variants = {"other": "c", "few": "b", "one": "a", "many": "d"}
        built = catalog_localization(variants)
        self.assertEqual(list(built["variations"]["plural"]), ["one", "few", "many", "other"])
        self.assertEqual(built["variations"]["plural"]["few"], {"stringUnit": {"state": "translated", "value": "b"}})
        self.assertEqual(localization_value(built), variants)
        self.assertEqual(catalog_localization("x"), {"stringUnit": {"state": "translated", "value": "x"}})

    def test_unsupported_shapes_are_rejected_not_dropped(self):
        unit = {"stringUnit": {"state": "translated", "value": "x"}}
        for localization in [
            {"variations": {"device": {"mac": unit}}},
            {"variations": {"plural": {"one": unit}}, "stringUnit": unit["stringUnit"]},
            {"variations": {"plural": {"several": unit}}},
            {"variations": {"plural": {}}},
            {"variations": {"plural": {"one": {"stringUnit": {"state": "translated"}}}}},
            {"stringUnit": unit["stringUnit"], "substitutions": {}},
            {"substitutions": {}},
            "x",
        ]:
            with self.subTest(localization=localization):
                with self.assertRaises(ValueError):
                    localization_value(localization)

    def test_canonical_json_sorts_both_dictionaries_and_keeps_the_rest(self):
        text = canonical_json({"sourceLanguage": "en", "strings": {"b": 1, "a": 2}, "metadata": {"z": 1, "y": 2}, "version": "1.0"})
        document = json.loads(text)
        self.assertEqual(list(document), ["sourceLanguage", "strings", "metadata", "version"])
        self.assertEqual(list(document["strings"]), ["a", "b"])
        self.assertEqual(list(document["metadata"]), ["y", "z"])
        self.assertTrue(text.endswith("}\n"))


# MARK: generation and the .strings reader

class GeneratorTests(unittest.TestCase):
    def test_plural_keys_generate_a_stringsdict_beside_strings(self):
        with Repository() as repo:
            repo.write(ENTRIES)
            repo.generate()
            for language in repo.languages:
                directory = repo.resources / f"{language}.lproj"
                with self.subTest(language=language):
                    document = plistlib.loads((directory / "Localizable.stringsdict").read_bytes())
                    self.assertEqual(document, {"preview.count.lines": {
                        "NSStringLocalizedFormatKey": "%#@count@",
                        "count": {"NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                                  "NSStringFormatValueTypeKey": "lld", **PLURAL_LINES[language]}}})
                    strings = (directory / "Localizable.strings").read_text(encoding="utf-8")
                    self.assertTrue(strings.startswith("/* Generated from Localizable.xcstrings; do not edit directly. */\n"))
                    self.assertIn('"preview.count.lines" = "%#@count@";\n', strings)
                    self.assertIn(f'"action.example" = "{PLAIN_EXAMPLE[language]}";\n', strings)

    def test_a_plural_key_can_live_only_in_the_stringsdict(self):
        with Repository() as repo, patch.object(validate_localization, "PLURAL_FORMAT_IN_STRINGS", False):
            repo.write(ENTRIES)
            repo.generate()
            for language in repo.languages:
                directory = repo.resources / f"{language}.lproj"
                self.assertEqual(parse_strings((directory / "Localizable.strings").read_text(encoding="utf-8")),
                                 {"action.example": PLAIN_EXAMPLE[language]})
                self.assertIn("preview.count.lines", plistlib.loads((directory / "Localizable.stringsdict").read_bytes()))
            code, out, err = repo.validate()
            self.assertEqual((code, err), (0, ""))

    def test_the_stringsdict_is_an_apple_xml_property_list(self):
        with Repository() as repo:
            repo.write(ENTRIES)
            repo.generate()
            data = (repo.resources / "ru.lproj/Localizable.stringsdict").read_bytes()
            self.assertTrue(data.startswith(b'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"'))
            self.assertIn(b'<plist version="1.0">', data)
            self.assertIn("<string>%2$@ строк</string>".encode("utf-8"), data)

    def test_languages_without_plural_keys_get_no_stringsdict_and_stale_ones_are_removed(self):
        with Repository() as repo:
            repo.write({"action.example": PLAIN_EXAMPLE})
            stale = repo.resources / "ru.lproj/Localizable.stringsdict"
            stale.parent.mkdir(parents=True)
            stale.write_bytes(b"stale")
            repo.generate()
            for language in repo.languages:
                self.assertTrue((repo.resources / f"{language}.lproj/Localizable.strings").is_file())
                self.assertFalse((repo.resources / f"{language}.lproj/Localizable.stringsdict").exists())

    def test_generation_is_deterministic(self):
        with Repository() as repo:
            repo.write(ENTRIES)
            repo.generate()
            first = {str(path.relative_to(repo.resources)): path.read_bytes() for path in repo.resources.rglob("Localizable.str*")}
            repo.generate()
            second = {str(path.relative_to(repo.resources)): path.read_bytes() for path in repo.resources.rglob("Localizable.str*")}
            self.assertEqual(first, second)
            self.assertEqual(len(first), 6)

    def test_mixed_plain_and_plural_localizations_are_refused_before_anything_is_written(self):
        with Repository() as repo:
            repo.write(ENTRIES)
            catalog = repo.read_catalog()
            catalog["preview.count.lines"]["localizations"]["ru"] = catalog_localization("%2$@ строк")
            repo.catalog.write_text(canonical_json({"sourceLanguage": "en", "strings": catalog, "version": "1.0"}), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "plural in some languages"):
                repo.generate()
            self.assertEqual(list(repo.resources.rglob("*.lproj")), [])

    def test_other_variations_and_a_missing_other_variant_are_refused(self):
        unit = {"stringUnit": {"state": "translated", "value": "x"}}
        for localization, message in [({"variations": {"device": {"mac": unit}}}, "only variations.plural"),
                                      ({"variations": {"plural": {"one": unit}}}, "needs an `other` variant")]:
            with self.subTest(message=message):
                with Repository() as repo:
                    repo.write({"action.example": PLAIN_EXAMPLE})
                    catalog = repo.read_catalog()
                    for language in repo.languages:
                        catalog["action.example"]["localizations"][language] = localization
                    repo.catalog.write_text(canonical_json({"sourceLanguage": "en", "strings": catalog, "version": "1.0"}), encoding="utf-8")
                    with self.assertRaisesRegex(ValueError, message):
                        repo.generate()
                    self.assertEqual(list(repo.resources.rglob("*.lproj")), [])


class StringsReaderTests(unittest.TestCase):
    TRICKY = {
        "quote": 'He said "no"', "slash": "a\\b", "newline": "one\ntwo", "tab": "a\tb",
        "unicode": "e\u0301 İ ı مثال 日本語 \U0001F600", "percent": "100%% %@",
        "structure": '} = "x";', "line separator": "a\u2028b", 'odd "key" = ;': "value",
    }

    def test_the_reader_round_trips_the_generators_quoting(self):
        text = generate_localization.render_strings(self.TRICKY)
        self.assertEqual(parse_strings(text), self.TRICKY)
        self.assertEqual(len(text.split("\n")), len(self.TRICKY) + 2)

    def test_the_reader_agrees_with_a_generated_file(self):
        with Repository() as repo:
            repo.write(ENTRIES)
            repo.generate()
            for language in repo.languages:
                with self.subTest(language=language):
                    path = repo.resources / f"{language}.lproj/Localizable.strings"
                    self.assertEqual(read_strings(path, use_plutil=False),
                                     {"action.example": PLAIN_EXAMPLE[language], "preview.count.lines": "%#@count@"})

    def test_the_reader_rejects_anything_the_generator_would_not_write(self):
        header = validate_localization.STRINGS_HEADER
        self.assertEqual(parse_strings(f'{header}\n"a" = "b";\n'), {"a": "b"})
        for name, text in {
            "empty file": "",
            "no header": '"a" = "b";\n',
            "no final newline": f'{header}\n"a" = "b";',
            "blank line": f'{header}\n\n"a" = "b";\n',
            "single quotes": f"{header}\n'a' = 'b';\n",
            "missing semicolon": f'{header}\n"a" = "b"\n',
            "extra spaces": f'{header}\n"a"  =  "b";\n',
            "comment between entries": f'{header}\n"a" = "b";\n/* note */\n',
            "duplicate key": f'{header}\n"a" = "b";\n"a" = "c";\n',
            "bad escape": f'{header}\n"a" = "\\q";\n',
            "carriage returns": f'{header}\r\n"a" = "b";\r\n',
            "unquoted key": f'{header}\na = "b";\n',
        }.items():
            with self.subTest(name):
                with self.assertRaises(ValueError):
                    parse_strings(text)

    def test_plutil_is_used_when_installed_and_the_reader_otherwise(self):
        path = Path("unused.strings")
        with patch.object(validate_localization.shutil, "which", return_value="/usr/bin/plutil"), \
                patch.object(validate_localization.subprocess, "run", return_value=Mock(returncode=0, stdout='{"a": "b"}')) as run:
            self.assertEqual(read_strings(path), {"a": "b"})
        self.assertEqual(run.call_args.args[0][:3], ["plutil", "-convert", "json"])
        with patch.object(validate_localization.shutil, "which", return_value="/usr/bin/plutil"), \
                patch.object(validate_localization.subprocess, "run", return_value=Mock(returncode=1, stdout="")):
            with self.assertRaises(ValueError):
                read_strings(path)
        with tempfile.TemporaryDirectory() as directory:
            generated = Path(directory) / "Localizable.strings"
            generated.write_text(f'{validate_localization.STRINGS_HEADER}\n"a" = "b";\n', encoding="utf-8")
            with patch.object(validate_localization.shutil, "which", return_value=None), \
                    patch.object(validate_localization.subprocess, "run", side_effect=AssertionError("plutil must not run")):
                self.assertEqual(read_strings(generated), {"a": "b"})


# MARK: validation

class ValidatorTests(unittest.TestCase):
    def test_a_consistent_repository_with_a_plural_key_passes(self):
        with Repository() as repo:
            repo.write(ENTRIES, swift={"Apps/Example.swift": "PreviewStrings.count(.c0, 3, locale: locale)"})
            repo.generate()
            code, out, err = repo.validate()
            self.assertEqual((code, err), (0, ""))
            self.assertIn("2 keys (1 plural), 3 locale(s)", out)
            self.assertEqual(counted_string_keys(), {"preview.count.lines"})
            self.assertEqual(formatted_string_keys(), set())

    def test_wrong_plural_categories_and_variants_are_errors(self):
        english = PLURAL_LINES["en"]
        for language, variants, message in [
            ("ru", {"one": "%2$@ строка", "few": "%2$@ строки", "other": "%2$@ строки"},
             "ru/preview.count.lines: missing plural categories ['many']"),
            ("ja", {"one": "%2$@ 行", "other": "%2$@ 行"}, "plural categories ['one'] are not defined for ja"),
            ("en", {**english, "many": "%2$@ x"}, "plural categories ['many'] are not defined for en"),
            ("ru", {**PLURAL_LINES["ru"], "few": "строки"}, "few: placeholders differ"),
            ("ja", {"other": "1 行 %2$@"}, "other: contains a literal digit"),
        ]:
            with self.subTest(language=language, message=message):
                with Repository() as repo:
                    repo.write({"preview.count.lines": {**PLURAL_LINES, language: variants}})
                    repo.generate()
                    code, out, err = repo.validate()
                    self.assertEqual(code, 1)
                    self.assertIn(message, err)

    def test_plain_and_plural_values_cannot_swap_places_in_the_catalog(self):
        for key, language, replacement, message in [
            ("preview.count.lines", "ja", "%2$@ 行", "ja/preview.count.lines: expected an object of plural categories"),
            ("action.example", "ru", {"other": "Пример"}, "ru/action.example: expected a plain string"),
        ]:
            with self.subTest(key=key):
                with Repository() as repo:
                    repo.write(ENTRIES)
                    repo.generate()
                    catalog = repo.read_catalog()
                    catalog[key]["localizations"][language] = catalog_localization(replacement)
                    repo.catalog.write_text(canonical_json({"sourceLanguage": "en", "strings": catalog, "version": "1.0"}), encoding="utf-8")
                    code, out, err = repo.validate()
                    self.assertEqual(code, 1)
                    self.assertIn(message, err)

    def test_call_sites_must_use_count_for_plural_keys_only(self):
        for source, message in {
            "PreviewStrings.count(.c1, 3, locale: locale)": "PreviewStrings.count needs a plural catalog entry: action.example",
            "PreviewStrings.format(.c0, arguments: [3])": "Plural key read with PreviewStrings.format: preview.count.lines",
            "Text(PreviewStrings.text(.c0))": "Plural key read with PreviewStrings.text: preview.count.lines",
        }.items():
            with self.subTest(source=source):
                with Repository() as repo:
                    repo.write(ENTRIES, swift={"Apps/Example.swift": source})
                    repo.generate()
                    code, out, err = repo.validate()
                    self.assertEqual(code, 1)
                    self.assertIn(message, err)

    def test_a_dynamic_count_call_cannot_escape_validation(self):
        with Repository() as repo:
            repo.write(ENTRIES, swift={"Apps/Dynamic.swift": "PreviewStrings.count(key, 3)"})
            repo.generate()
            code, out, err = repo.validate()
            self.assertEqual(code, 1)
            self.assertIn("Unrecognized counted-resource key use: Apps/Dynamic.swift:1 (the first argument is not a literal .case)", err)
            with self.assertRaisesRegex(ValueError, "Unrecognized counted-resource key use"):
                counted_string_keys()

    def test_unrecognized_call_sites_do_not_hide_the_other_findings(self):
        with Repository() as repo:
            repo.write(ENTRIES, cases=["preview.count.lines"], swift={"Apps/New.swift": "PreviewStrings.format(.notYetAdded, arguments: [1])"})
            repo.generate()
            code, out, err = repo.validate()
            self.assertEqual(code, 1)
            self.assertIn("Apps/New.swift:1 (.notYetAdded is not a PreviewStrings.Key case)", err)
            self.assertIn("Unreferenced catalog key: action.example", err)

    def test_every_unrecognized_call_site_is_reported_with_its_line_and_merge_may_skip_them(self):
        swift = {
            "Apps/One.swift": "let a = 1\nlet b = PreviewStrings.format(.missingCase, arguments: [1])\n",
            "Apps/Two.swift": "PreviewStrings.count(key, 2)\nPreviewStrings.format(.c1, arguments: [1])\n",
        }
        with Repository() as repo:
            repo.write(ENTRIES, swift=swift)
            with self.assertRaises(ValueError) as caught:
                formatted_string_keys()
            message = str(caught.exception)
            self.assertIn("Apps/One.swift:2 (.missingCase is not a PreviewStrings.Key case)", message)
            self.assertIn("Apps/Two.swift:1 (the first argument is not a literal .case)", message)
            self.assertEqual(formatted_string_keys(strict=False), {"action.example"})
            self.assertEqual(counted_string_keys(strict=False), set())

    def test_placeholder_parity_covers_keys_without_call_sites(self):
        with Repository() as repo:
            repo.write({"stat.rows": entry("Rows: %lld", ru="Строки", ja="行: %lld")})
            repo.generate()
            code, out, err = repo.validate()
            self.assertEqual(code, 1)
            self.assertIn("ru/stat.rows: placeholders differ from the development language", err)

    def test_literal_percent_signs_stay_valid_in_text_only_keys_but_not_formatted_ones(self):
        entries = {"stat.sampled": entry("Sampled 25% of rows", ru="Выборка 25% строк", ja="行の25%を抽出")}
        with Repository() as repo:
            repo.write(entries)
            repo.generate()
            self.assertEqual(repo.validate()[0], 0)
        with Repository() as repo:
            repo.write(entries, swift={"Apps/Example.swift": "PreviewStrings.format(.c0, arguments: [25])"})
            repo.generate()
            code, out, err = repo.validate()
            self.assertEqual(code, 1)
            self.assertIn("en/stat.sampled: invalid format directive", err)

    def test_unreferenced_keys_fail_unless_allowlisted_and_stale_allowlist_entries_warn(self):
        with Repository() as repo:
            repo.write(ENTRIES, cases=["preview.count.lines"])
            repo.generate()
            code, out, err = repo.validate()
            self.assertEqual(code, 1)
            self.assertIn("Unreferenced catalog key: action.example", err)
            allowlist = repo.localization / "unreferenced-allowlist.json"
            allowlist.write_text(json.dumps({"keys": {"action.example": "kept for translators"}}), encoding="utf-8")
            code, out, err = repo.validate()
            self.assertEqual((code, err), (0, ""))
            allowlist.write_text(json.dumps({"keys": {"preview.count.lines": "now has a case", "gone.key": "removed"}}), encoding="utf-8")
            code, out, err = repo.validate()
            self.assertEqual(code, 1)
            self.assertIn("preview.count.lines: now referenced", out)
            self.assertIn("gone.key: no longer in the catalog", out)

    def test_a_malformed_allowlist_is_an_error(self):
        with Repository() as repo:
            repo.write(ENTRIES)
            repo.generate()
            (repo.localization / "unreferenced-allowlist.json").write_text(json.dumps({"keys": {"action.example": ""}}), encoding="utf-8")
            code, out, err = repo.validate()
            self.assertEqual(code, 1)
            self.assertIn("unreferenced-allowlist.json: expected", err)

    def test_keys_named_by_the_format_catalog_count_as_referenced_and_must_exist(self):
        formats = {"formats": [{"nameKey": "format.x.name", "descriptionKey": "format.x.description",
                                "importedContentTypes": [{"descriptionKey": "type.x.description"}]}]}
        entries = {**ENTRIES, "format.x.name": entry("X"), "format.x.description": entry("About X"), "type.x.description": entry("X file")}
        with Repository() as repo:
            repo.write(entries, cases=list(ENTRIES), formats=formats)
            repo.generate()
            self.assertEqual(repo.validate()[0], 0)
        del entries["type.x.description"]
        with Repository() as repo:
            repo.write(entries, cases=list(ENTRIES), formats=formats)
            repo.generate()
            code, out, err = repo.validate()
            self.assertEqual(code, 1)
            self.assertIn("Missing catalog key: type.x.description", err)

    def test_a_language_without_encoded_plural_rules_fails(self):
        with Repository(languages=("en", "xx")) as repo:
            repo.write({"action.example": {"comment": "c", "en": "Example", "xx": "Exemplo"}})
            repo.generate()
            code, out, err = repo.validate()
            self.assertEqual(code, 1)
            self.assertIn("No CLDR plural categories are encoded for xx", err)

    def test_stale_missing_and_edited_generated_resources_are_errors(self):
        with Repository() as repo:
            repo.write(ENTRIES)
            repo.generate()
            plural = repo.resources / "ru.lproj/Localizable.stringsdict"
            document = plistlib.loads(plural.read_bytes())
            document["preview.count.lines"]["count"]["few"] = "tampered %2$@"
            plural.write_bytes(plistlib.dumps(document))
            self.assertIn("Generated plural resource differs from catalog: ru", repo.validate()[2])
            plural.write_bytes(b"not a property list")
            self.assertIn("Invalid plural resource", repo.validate()[2])
            plural.unlink()
            self.assertIn("Missing generated plural resource", repo.validate()[2])
            strings = repo.resources / "en.lproj/Localizable.strings"
            strings.write_text(strings.read_text(encoding="utf-8").replace("%#@count@", "%2$@ lines"), encoding="utf-8")
            self.assertIn("Generated fallback differs from catalog: en", repo.validate()[2])
            strings.write_text("garbage", encoding="utf-8")
            self.assertIn("Invalid strings resource", repo.validate()[2])
            strings.unlink()
            self.assertIn("Missing generated fallback", repo.validate()[2])
        with Repository() as repo:
            repo.write({"action.example": PLAIN_EXAMPLE})
            repo.generate()
            (repo.resources / "ja.lproj/Localizable.stringsdict").write_bytes(plistlib.dumps({}))
            self.assertIn("Stale plural resource", repo.validate()[2])

    @unittest.skipUnless(shutil.which("plutil"), "plutil exists on macOS only")
    def test_plutil_reads_the_generated_resources_the_same_way(self):
        with Repository() as repo:
            repo.write(ENTRIES)
            repo.generate()
            self.assertEqual(repo.validate(plutil=True)[:1], (0,))
            for path in repo.resources.rglob("Localizable.stringsdict"):
                self.assertEqual(validate_localization.subprocess.run(["plutil", "-lint", str(path)], capture_output=True).returncode, 0)


class LintTests(unittest.TestCase):
    def test_identical_to_english_is_reported_without_failing(self):
        entries = {
            "action.example": entry("Example", ru="Example", ja="例"),
            "format.json.name": entry("JSON"),
            "stat.pair": entry("%1$@ / %2$@"),
        }
        with Repository() as repo:
            repo.write(entries)
            repo.generate()
            (repo.localization / "technical-names.json").write_text(json.dumps({"names": ["JSON"]}), encoding="utf-8")
            code, out, err = repo.validate()
            self.assertEqual((code, err), (0, ""))
            self.assertIn("values identical to English outside the technical names: 1", out)
            self.assertIn("action.example: ru", out)
            self.assertNotIn("format.json.name", out)
            self.assertNotIn("stat.pair", out)
            (repo.localization / "technical-names.json").unlink()
            self.assertIn("format.json.name: ja, ru", repo.validate("--verbose")[1])

    def test_warning_lists_are_abbreviated_unless_verbose(self):
        entries = {f"action.item{n}": entry(f"Item {chr(97 + n)}") for n in range(7)}
        with Repository() as repo:
            repo.write(entries)
            repo.generate()
            code, out, err = repo.validate()
            self.assertEqual(code, 0)
            self.assertIn("... 2 more; run with --verbose", out)
            self.assertNotIn("action.item6", out)
            self.assertIn("action.item6: ja, ru", repo.validate("--verbose")[1])

    def test_straight_apostrophes_are_warned_for_english_and_french_only(self):
        entries = {
            "a.straight": {"comment": "c", "en": "It doesn't work", "fr": "L'ordre"},
            "a.curly": {"comment": "c", "en": "It doesn\u2019t work", "fr": "L\u2019ordre"},
            "a.quote": {"comment": "c", "en": "Use 'quotes' here", "fr": "Un 'mot'"},
        }
        with Repository(languages=("en", "fr")) as repo:
            repo.write(entries)
            repo.generate()
            code, out, err = repo.validate("--verbose")
            self.assertEqual((code, err), (0, ""))
            self.assertIn("typography: 2", out)
            self.assertIn("en/a.straight: straight apostrophe between letters; use U+2019", out)
            self.assertIn("fr/a.straight", out)
            self.assertNotIn("a.curly", out)
            self.assertNotIn("a.quote", out)
        with Repository(languages=("en", "de")) as repo:
            repo.write({"a.straight": {"comment": "c", "en": "Works", "de": "Geht's"}})
            repo.generate()
            self.assertNotIn("typography", repo.validate("--verbose")[1])

    def test_plural_variants_are_scanned_for_apostrophes(self):
        with Repository(languages=("en", "ja")) as repo:
            repo.write({"a.count": {"comment": "c", "en": {"one": "%2$@ file's line", "other": "%2$@ lines"}, "ja": {"other": "%2$@ 行"}}})
            repo.generate()
            self.assertIn("en/a.count: straight apostrophe", repo.validate("--verbose")[1])

    def test_long_header_and_notice_strings_warn(self):
        long, short = " ".join(["word"] * 13), " ".join(["word"] * 12)
        entries = {
            "a.header": entry(long, comment="Column header shown in the table."),
            "a.notice": entry(short, comment="Notice above the table."),
            "a.plain": entry(long, comment="Plain label."),
            "a.bannotice": entry(long, comment="Denoticed text."),
        }
        with Repository() as repo:
            repo.write(entries)
            repo.generate()
            code, out, err = repo.validate("--verbose")
            self.assertEqual((code, err), (0, ""))
            self.assertIn("long header and notice strings: 1", out)
            self.assertIn("a.header: 13 words", out)


# MARK: typography and length lints (decision 027, Q-161 and Q-23)

NBSP, NNBSP = " ", " "
GLOTTAL = validate_localization.HAUSA_GLOTTAL_STOP


def warnings_for(language, *texts):
    """The typography warnings for one language's values, as the validator builds them from the catalog."""
    return validate_localization.typography_warnings({language: {f"k{index}": text for index, text in enumerate(texts)}})


class FrenchTypographyTests(unittest.TestCase):
    def test_a_breaking_space_beside_the_marks_is_flagged_and_a_no_break_space_is_not(self):
        for text in ("Nom : %@", "Qui ? Oui !", "Fin ; suite", "« texte »", "« texte »"):
            with self.subTest(text):
                self.assertTrue(warnings_for("fr", text), text)
        for text in ("Nom" + NBSP + ": %@", "Nom" + NNBSP + ": %@", "Qui" + NBSP + "? Oui" + NNBSP + "!", "Fin" + NNBSP + "; suite",
                     "«" + NBSP + "texte" + NBSP + "»", "«" + NNBSP + "texte" + NNBSP + "»", "Heure 12:30", "Ratio 3:2", "Sans ponctuation"):
            with self.subTest(text):
                self.assertEqual(warnings_for("fr", text), [], text)

    def test_no_space_at_all_is_flagged_too(self):
        for text in ("Nom: %@", "Quoi?", "Super!", "Fin;", "«texte»", "Fichier:"):
            with self.subTest(text):
                self.assertTrue(warnings_for("fr", text), text)

    def test_other_languages_keep_their_own_spacing(self):
        for language in ("en", "de", "ru", "tr", "es"):
            self.assertEqual(warnings_for(language, "Name : %@", "Why ? Yes !"), [], language)

    def test_plural_variants_are_scanned(self):
        warnings = validate_localization.typography_warnings({"fr": {"a.count": {"one": "%2$@ ligne : une", "other": "%2$@ lignes"}}})
        self.assertEqual(len(warnings), 1)
        self.assertIn("fr/a.count", warnings[0])

    def test_the_validator_reports_it_under_typography(self):
        with Repository(languages=("en", "fr")) as repo:
            repo.write({"a.label": {"comment": "c", "en": "Name: %@", "fr": "Nom : %@"},
                        "a.fine": {"comment": "c", "en": "Count: %@", "fr": "Nombre" + NBSP + ": %@"}})
            repo.generate()
            code, out, err = repo.validate("--verbose")
            self.assertEqual((code, err), (0, ""))
            self.assertIn("typography: 1", out)
            self.assertIn("fr/a.label: breaking space beside", out)
            self.assertNotIn("a.fine", out)


class HausaTypographyTests(unittest.TestCase):
    def test_the_glottal_stop_is_u02bc_and_the_choice_is_pinned_here(self):
        self.assertEqual(validate_localization.HAUSA_GLOTTAL_STOP, "ʼ")

    def test_other_apostrophes_between_letters_are_flagged(self):
        for mark in ("'", "’", "‘", "`", "´"):
            with self.subTest(hex(ord(mark))):
                self.assertEqual(len(warnings_for("ha", f"Nau{mark}in fayil")), 1)

    def test_the_glottal_stop_and_other_text_pass(self):
        self.assertEqual(warnings_for("ha", f"Nau{GLOTTAL}in fayil", f"Na{GLOTTAL}ura", "Ƙarin dubawa", "Ɗauki ɓoye"), [])
        # Quotation marks and an apostrophe that is not between two letters are not the glottal stop.
        self.assertEqual(warnings_for("ha", "“fayil”", "Zaɓi 'fayil'"), [])

    def test_only_hausa_is_held_to_it_and_plural_variants_are_scanned(self):
        self.assertEqual([w for w in warnings_for("de", "Geht's nicht") if "glottal" in w], [])
        warnings = validate_localization.typography_warnings({"ha": {"a.count": {"one": "%2$@ na'ura", "other": f"%2$@ na{GLOTTAL}urori"}}})
        self.assertEqual(len(warnings), 1)


class GermanQuoteTests(unittest.TestCase):
    def test_low_nine_and_high_six_pass(self):
        self.assertEqual(warnings_for("de", "Unter „Dateitypen“ wählen", "„A“ und „B“", "Ohne Zitat"), [])

    def test_quotation_marks_of_other_conventions_are_flagged(self):
        for text in ('Unter "Dateitypen" wählen', "Unter “Dateitypen” wählen", "Unter »Dateitypen« wählen",
                     "Unter «Dateitypen» wählen", "Unter ›Dateitypen‹ wählen"):
            with self.subTest(text):
                self.assertTrue(warnings_for("de", text), text)

    def test_unbalanced_marks_are_flagged(self):
        self.assertIn("without a closing", warnings_for("de", "Unter „Dateitypen wählen")[0])
        self.assertIn("without an opening", warnings_for("de", "Unter Dateitypen“ wählen")[0])
        self.assertIn("opened twice", warnings_for("de", "„eins „zwei““")[0])

    def test_every_other_language_keeps_its_quotes(self):
        for language in ("en", "fr", "ru", "ja", "tr"):
            self.assertEqual([w for w in warnings_for(language, 'Use "quotes"', "“quotes”") if "quotation mark" in w], [], language)

    def test_the_messages_are_deduplicated_per_text(self):
        self.assertEqual(len(warnings_for("de", 'A "b" and "c"')), 1)


class GermanAddressTests(unittest.TestCase):
    def test_formal_imperatives_and_mid_sentence_formal_pronouns_are_flagged(self):
        for text in (
            "Öffnen Sie die Datei",
            "Wählen Sie einen Dateityp.",
            "Schreibgeschützter Text; durchsuchen Sie den Inhalt.",
            "Die Wiedergabe startet erst, wenn Sie „Wiedergabe“ drücken.",
            "Möglicherweise fehlt Ihnen die Berechtigung.",
            "Vorschau direkt im Finder – vollständig auf Ihrem Mac.",
            "Zugriff auf Ihren Benutzerordner oder Ihre anderen Geräte.",
        ):
            with self.subTest(text):
                warnings = warnings_for("de", text)
                self.assertEqual(len(warnings), 1, text)
                self.assertIn("formal address", warnings[0])

    def test_sentence_initial_formal_sie_ihr_and_ihnen_are_flagged(self):
        for text in (
            "Sie können bis zu 32 Profile speichern.",
            "Sie sollten die Datei prüfen.",
            "Erster Satz. Sie müssen neu starten.",
            "„Sie verwenden die Standardeinstellungen.“",
            "Ihre Dateien bleiben lokal.",
            "Ihr Gerät verlässt kein Inhalt.",
            "Hinweis: Ihren Ordner prüfen.",
            "Ihnen fehlt der Zugriff.",
        ):
            with self.subTest(text):
                warnings = warnings_for("de", text)
                self.assertEqual(len(warnings), 1, text)
                self.assertIn("formal address", warnings[0])

    def test_mid_sentence_uppercase_informal_pronouns_are_flagged(self):
        for text in (
            "Öffne die Datei, wenn Du möchtest.",
            "Auf Deinem Mac gespeichert.",
            "Das hilft Dir weiter.",
            "Melde Dich erneut an.",
            "Speichere Deine Auswahl.",
        ):
            with self.subTest(text):
                warnings = warnings_for("de", text)
                self.assertEqual(len(warnings), 1, text)
                self.assertIn("mid-sentence uppercase informal address", warnings[0])

    def test_neutral_copy_third_person_sie_and_lowercase_du_pass(self):
        self.assertEqual(warnings_for(
            "de",
            "Die Datei in einem Texteditor öffnen.",
            "Sie enthält Binärdaten.",
            "Signaturen werden angezeigt. Sie werden nicht geprüft.",
            "Hinweis: Sie hat keinen Inhalt.",
            "„Sie wurde möglicherweise verschoben.“",
            "Öffne die Datei, wenn du möchtest.",
            "Auf deinem Mac bleibt alles lokal, was dir gehört.",
            "Du kannst bis zu 32 Profile speichern. Deine Auswahl bleibt erhalten.",
            "Sieben Zeilen im Verzeichnis.",
        ), [])

    def test_plural_variants_are_scanned_and_other_languages_are_unaffected(self):
        warnings = validate_localization.typography_warnings(
            {"de": {"a.count": {"one": "%2$@ Zeile. Öffnen Sie die Datei.", "other": "%2$@ Zeilen."}}})
        self.assertEqual(len(warnings), 1)
        self.assertIn("de/a.count: formal address", warnings[0])
        self.assertEqual(warnings_for("en", "Open Sie Ihre Du"), [])


class ShippedTypographyTests(unittest.TestCase):
    """The shipped catalog holds none of the mechanical typography problems. A new French or Hausa string with an
    ordinary space before a colon, or an apostrophe in a Hausa word, fails here; fix it with
    `python3 tools/normalize_localization_typography.py --write` (and `--additions FILE` for an additions file)."""

    def test_french_hausa_and_german_values_follow_their_typography(self):
        catalog = json.loads(validate_localization.CATALOG.read_text(encoding="utf-8"))["strings"]
        values = {}
        for key, entry in catalog.items():
            for language in ("fr", "ha", "de"):
                values.setdefault(language, {})[key] = localization_value(entry["localizations"][language])
        warnings = validate_localization.typography_warnings(
            {language: values[language] for language in ("fr", "ha", "de")})
        self.assertEqual(warnings, [], "run python3 tools/normalize_localization_typography.py --write, then merge and generate")


class NormalizeTypographyTests(unittest.TestCase):
    def test_french_breaking_spaces_become_no_break_spaces_and_the_rest_is_untouched(self):
        normalize = normalize_localization_typography.normalize_text
        self.assertEqual(normalize("fr", "Nom : %@"), "Nom" + NBSP + ": %@")
        self.assertEqual(normalize("fr", "Qui ? Oui ! Fin ; suite"), "Qui" + NBSP + "? Oui" + NBSP + "! Fin" + NBSP + "; suite")
        self.assertEqual(normalize("fr", "« texte »"), "«" + NBSP + "texte" + NBSP + "»")
        self.assertEqual(normalize("fr", "Nom" + NNBSP + ": x"), "Nom" + NNBSP + ": x")
        self.assertEqual(normalize("fr", "Heure 12:30, Nom: x, Quoi?"), "Heure 12:30, Nom: x, Quoi?")
        self.assertEqual(normalize("fr", "Deux  : espaces"), "Deux " + NBSP + ": espaces")

    def test_hausa_apostrophes_between_letters_become_the_glottal_stop(self):
        normalize = normalize_localization_typography.normalize_text
        for mark in ("'", "’", "‘", "`", "´"):
            self.assertEqual(normalize("ha", f"Nau{mark}o{mark}in"), f"Nau{GLOTTAL}o{GLOTTAL}in")
        self.assertEqual(normalize("ha", "'yan “fayil”"), "'yan “fayil”")

    def test_other_languages_and_non_text_values_come_back_unchanged(self):
        normalize = normalize_localization_typography
        self.assertEqual(normalize.normalize_text("en", "It's : here"), "It's : here")
        self.assertEqual(normalize.normalize_text("de", "Name : x"), "Name : x")
        self.assertEqual(normalize.normalize_value("fr", {"one": "1 ligne :", "other": "%2$@ lignes :"}),
                         {"one": "1 ligne" + NBSP + ":", "other": "%2$@ lignes" + NBSP + ":"})
        self.assertEqual(normalize.normalize_value("fr", 7), 7)

    def test_what_the_normalizer_fixes_the_validator_no_longer_reports(self):
        samples = {"fr": ["Nom : %@", "Qui ? Oui !", "« texte »", "Fin ; suite"], "ha": ["Nau'in", "Na’ura", "Nau`o`in"]}
        for language, texts in samples.items():
            with self.subTest(language):
                self.assertTrue(warnings_for(language, *texts))
                self.assertEqual(warnings_for(language, *[normalize_localization_typography.normalize_text(language, text) for text in texts]), [])

    def test_the_tool_reports_by_default_writes_on_request_and_is_idempotent(self):
        entries = {
            "a.label": {"comment": "c", "en": "Name: %@", "fr": "Nom : %@", "ha": "Nau'in %@"},
            "a.count": {"comment": "c", "en": {"one": "%2$@ line", "other": "%2$@ lines"},
                        "fr": {"one": "%2$@ ligne :", "other": "%2$@ lignes :"}, "ha": {"one": "%2$@ na'ura", "other": "%2$@ na'urori"}},
            "a.fine": {"comment": "c", "en": "Fine", "fr": "Bien", "ha": "Lafiya"},
        }
        with Repository(languages=("en", "fr", "ha")) as repo:
            repo.write(entries)
            before = {language: repo.read_input(language) for language in ("fr", "ha")}
            with redirect_stdout(io.StringIO()) as out:
                self.assertEqual(normalize_localization_typography.main([]), 1)
            self.assertIn("fr.json: 2 value(s) would change", out.getvalue())
            self.assertIn("ha.json: 2 value(s) would change", out.getvalue())
            self.assertEqual({language: repo.read_input(language) for language in ("fr", "ha")}, before)
            with redirect_stdout(io.StringIO()):
                self.assertEqual(normalize_localization_typography.main(["--write"]), 0)
            fr, ha = repo.read_input("fr")["strings"], repo.read_input("ha")["strings"]
            self.assertEqual(fr["a.label"], "Nom" + NBSP + ": %@")
            self.assertEqual(fr["a.count"], {"one": "%2$@ ligne" + NBSP + ":", "other": "%2$@ lignes" + NBSP + ":"})
            self.assertEqual(ha["a.label"], f"Nau{GLOTTAL}in %@")
            self.assertEqual(ha["a.count"]["other"], f"%2$@ na{GLOTTAL}urori")
            self.assertEqual((fr["a.fine"], ha["a.fine"]), ("Bien", "Lafiya"))
            self.assertEqual(repo.read_input("fr")["metadata"], before["fr"]["metadata"])
            with redirect_stdout(io.StringIO()) as again:
                self.assertEqual(normalize_localization_typography.main([]), 0)
            self.assertIn("already normalized", again.getvalue())

    def test_an_additions_file_keeps_every_field_but_the_normalized_ones(self):
        additions = {"a.label": {"case": "aLabel", "comment": "c", "en": "Name: %@", "fr": "Nom : %@", "ha": "Nau'in %@", "de": "Name : %@"}}
        with Repository(languages=("en", "fr", "ha")) as repo:
            repo.write({"a.label": {"comment": "c", "en": "Name: %@", "fr": "Nom" + NBSP + ": %@", "ha": f"Nau{GLOTTAL}in %@"}})
            path = repo.root / "additions.json"
            path.write_text(json.dumps(additions, ensure_ascii=False), encoding="utf-8")
            with redirect_stdout(io.StringIO()) as out:
                code = normalize_localization_typography.main(["--additions-only", "--additions", str(path)])
            self.assertEqual(code, 1)
            self.assertIn("additions.json: 2 value(s) would change", out.getvalue())
            self.assertEqual(json.loads(path.read_text(encoding="utf-8")), additions)
            with redirect_stdout(io.StringIO()):
                self.assertEqual(normalize_localization_typography.main(["--additions-only", "--additions", str(path), "--write"]), 0)
            written = json.loads(path.read_text(encoding="utf-8"))["a.label"]
            self.assertEqual(written, {**additions["a.label"], "fr": "Nom" + NBSP + ": %@", "ha": f"Nau{GLOTTAL}in %@"})


class LengthBudgetTests(unittest.TestCase):
    ENGLISH_30 = "Open the folder containing it."  # 30 characters

    @staticmethod
    def values(**texts):
        """{language: {key: text}} for one key `a.label`, English given as `en`."""
        return {language: {"a.label": text} for language, text in texts.items()}

    def overruns(self, **texts):
        return validate_localization.length_overruns(self.values(**texts), "en")

    def test_each_language_has_the_programs_ratio(self):
        budgets = validate_localization.LENGTH_BUDGETS
        self.assertEqual({language for language, ratio in budgets.items() if ratio == 1.5}, {"de", "fr", "ru", "es", "pt", "id", "tr"})
        self.assertEqual({language for language, ratio in budgets.items() if ratio == 2.0}, {"bn", "hi", "ku-Latn", "ha"})
        self.assertEqual({language for language, ratio in budgets.items() if ratio == 0.8}, {"zh-Hans", "ja"})
        self.assertEqual(set(budgets), set(json.loads((Path(validate_localization.__file__).parent / "localization/languages.json")
                                                      .read_text(encoding="utf-8"))["languages"]) - {"en"})

    def test_a_value_over_its_ratio_is_flagged_and_at_the_ratio_is_not(self):
        self.assertEqual(len(self.ENGLISH_30), 30)
        self.assertEqual(self.overruns(en=self.ENGLISH_30, de="x" * 45), [])
        self.assertEqual(self.overruns(en=self.ENGLISH_30, de="x" * 46), [("a.label", "de", 46, 30, 45.0)])
        self.assertEqual(self.overruns(en=self.ENGLISH_30, ha="x" * 60), [])
        self.assertEqual(self.overruns(en=self.ENGLISH_30, ha="x" * 61), [("a.label", "ha", 61, 30, 60.0)])
        self.assertEqual(self.overruns(en=self.ENGLISH_30, ja="x" * 24), [])
        self.assertEqual(len(self.overruns(en=self.ENGLISH_30, ja="x" * 25, **{"zh-Hans": "x" * 25})), 2)

    def test_a_short_label_has_the_floor_not_a_ratio(self):
        floor = validate_localization.LENGTH_FLOOR
        self.assertEqual(self.overruns(en="Reset", de="x" * floor, ja="x" * floor), [])
        self.assertEqual(self.overruns(en="Reset", de="x" * (floor + 1)), [("a.label", "de", floor + 1, 5, float(floor))])

    def test_long_english_text_wraps_and_is_not_measured(self):
        long = "word " * 13
        self.assertGreater(len(long), validate_localization.LENGTH_MAX_ENGLISH)
        self.assertEqual(self.overruns(en=long, de="x" * 500), [])

    def test_combining_marks_and_format_characters_do_not_count(self):
        self.assertEqual(validate_localization.display_length("é"), 1)
        self.assertEqual(validate_localization.display_length("क्"), 1)  # a Devanagari consonant and the virama
        self.assertEqual(validate_localization.display_length("a‍b"), 2)
        self.assertEqual(validate_localization.display_length("%1$@ ab"), 7)

    def test_plural_keys_compare_their_other_variants_and_the_worst_overshoot_comes_first(self):
        values = {"en": {"a.count": {"one": "%2$@ line", "other": "%2$@ lines"}, "a.label": self.ENGLISH_30},
                  "de": {"a.count": {"one": "x", "other": "x" * 40}, "a.label": "x" * 50}}
        # a.count: 40 characters against a budget of 16 (the floor) overshoots by 24; a.label: 50 against 45 by 5.
        self.assertEqual(validate_localization.length_overruns(values, "en"),
                         [("a.count", "de", 40, 10, 16.0), ("a.label", "de", 50, 30, 45.0)])

    def test_the_validator_lists_overruns_without_failing_and_an_allowlist_accepts_reviewed_ones(self):
        entries = {"a.fits": {"comment": "c", "en": "Open", "de": "Öffnen", "ja": "開く"},
                   "a.long": {"comment": "c", "en": self.ENGLISH_30, "de": "x" * 50, "ja": "x" * 30}}
        with Repository(languages=("en", "de", "ja")) as repo:
            repo.write(entries)
            repo.generate()
            code, out, err = repo.validate("--verbose")
            self.assertEqual((code, err), (0, ""))
            self.assertIn("translations over their length budget: 2", out)
            self.assertIn("a.long: de has 50 characters for 30 in English (at most 45)", out)
            self.assertIn("a.long: ja has 30 characters for 30 in English (at most 24)", out)
            self.assertNotIn("a.fits", out)
            allowlist = repo.localization / "length-allowlist.json"
            allowlist.write_text(json.dumps({"keys": {"a.long": {"languages": ["de"], "reason": "Reviewed: fits the wide button."}}}), encoding="utf-8")
            code, out, err = repo.validate("--verbose")
            self.assertEqual((code, err), (0, ""))
            self.assertIn("translations over their length budget: 1", out)
            self.assertNotIn("a.long: de", out)
            self.assertIn("a.long: ja", out)
            allowlist.write_text(json.dumps({"keys": {"a.long": "Reviewed: every language fits."}}), encoding="utf-8")
            code, out, err = repo.validate("--verbose")
            self.assertEqual((code, err), (0, ""))
            self.assertNotIn("translations over their length budget", out)

    def test_stale_allowlist_entries_warn_and_malformed_ones_are_errors(self):
        entries = {"a.fits": {"comment": "c", "en": "Open", "de": "Öffnen"}}
        with Repository(languages=("en", "de")) as repo:
            repo.write(entries)
            repo.generate()
            allowlist = repo.localization / "length-allowlist.json"
            allowlist.write_text(json.dumps({"keys": {"a.fits": "Reviewed.", "gone.key": "Reviewed."}}), encoding="utf-8")
            code, out, err = repo.validate()
            self.assertEqual((code, err), (0, ""))
            self.assertIn("length allowlist entries that are not needed: 2", out)
            self.assertIn("a.fits: nothing exceeds its budget", repo.validate("--verbose")[1])
            self.assertIn("gone.key: no longer in the catalog", repo.validate("--verbose")[1])
            for name, document, message in [
                ("no reason", {"keys": {"a.fits": {"languages": ["de"]}}}, "a reason is required"),
                ("blank reason", {"keys": {"a.fits": "  "}}, "a reason is required"),
                ("unknown language", {"keys": {"a.fits": {"languages": ["xx"], "reason": "r"}}}, "languages must be a non-empty list"),
                ("empty languages", {"keys": {"a.fits": {"languages": [], "reason": "r"}}}, "languages must be a non-empty list"),
                ("wrong shape", ["a.fits"], "expected"),
            ]:
                with self.subTest(name):
                    allowlist.write_text(json.dumps(document), encoding="utf-8")
                    code, out, err = repo.validate()
                    self.assertEqual(code, 1)
                    self.assertIn(message, err)

    def test_format_keys_stay_out_of_the_header_and_notice_word_lint(self):
        long = " ".join(["word"] * 22)
        entries = {"format.archive.7z.description": entry(long, comment="Archive header and notice handling."),
                   "a.notice": entry(long, comment="Notice above the table.")}
        with Repository() as repo:
            repo.write(entries)
            repo.generate()
            code, out, err = repo.validate("--verbose")
            self.assertEqual((code, err), (0, ""))
            self.assertIn("long header and notice strings: 1", out)
            self.assertIn("a.notice: 22 words", out)
            self.assertNotIn("format.archive.7z.description: 22 words", out)


# MARK: merge and add

class MergeTests(unittest.TestCase):
    def test_merge_publishes_plural_variants_and_writes_catalogs_and_inputs_sorted(self):
        entries = {"zeta.example": PLAIN_EXAMPLE, "preview.count.lines": PLURAL_LINES, "alpha.example": PLAIN_EXAMPLE}
        with Repository() as repo:
            repo.write(entries, merged=False)
            document = json.loads(repo.catalog.read_text(encoding="utf-8"))
            document["strings"] = dict(reversed(list(document["strings"].items())))
            repo.catalog.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            unsorted = json.loads((repo.translations / "ru.json").read_text(encoding="utf-8"))
            unsorted["strings"] = dict(reversed(list(unsorted["strings"].items())))
            (repo.translations / "ru.json").write_text(json.dumps(unsorted, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            self.assertNotEqual(list(unsorted["strings"]), sorted(unsorted["strings"]))
            repo.merge()
            catalog = repo.read_catalog()
            self.assertEqual(list(catalog), sorted(entries))
            localizations = catalog["preview.count.lines"]["localizations"]
            self.assertEqual(list(localizations), ["en", "ru", "ja"])
            self.assertEqual(list(localizations["ru"]["variations"]["plural"]), ["one", "few", "many", "other"])
            for language in repo.languages:
                self.assertEqual(localization_value(localizations[language]), PLURAL_LINES[language])
            for language in ("ru", "ja"):
                self.assertEqual(list(repo.read_input(language)["strings"]), sorted(entries))

    def test_merging_again_changes_nothing(self):
        with Repository() as repo:
            repo.write(ENTRIES, merged=False)
            repo.merge()
            files = [repo.catalog, repo.metadata, *sorted(repo.translations.glob("*.json"))]
            first = [path.read_bytes() for path in files]
            repo.merge()
            self.assertEqual([path.read_bytes() for path in files], first)

    def test_merge_rejects_mismatched_kinds_categories_and_variants_and_writes_nothing(self):
        for key, language, value, message in [
            ("preview.count.lines", "ru", "%2$@ строк", "expected an object of plural categories"),
            ("action.example", "ru", {"other": "Пример"}, "expected a plain string"),
            ("preview.count.lines", "ru", {"one": "%2$@ строка", "other": "%2$@ строки"}, "missing plural categories ['few', 'many']"),
            ("preview.count.lines", "ja", {"one": "%2$@ 行", "other": "%2$@ 行"}, "not defined for ja"),
            ("preview.count.lines", "ru", {**PLURAL_LINES["ru"], "few": "%1$lld строки"}, "few: placeholders differ"),
            ("preview.count.lines", "ja", {"other": "1 行 %2$@"}, "contains a literal digit"),
            ("action.example", "ja", "", "empty or non-string text"),
        ]:
            with self.subTest(key=key, language=language, message=message):
                with Repository() as repo:
                    repo.write(ENTRIES, merged=False)
                    document = repo.read_input(language)
                    document["strings"][key] = value
                    (repo.translations / f"{language}.json").write_text(canonical_json(document), encoding="utf-8")
                    before = repo.catalog.read_text(encoding="utf-8")
                    with self.assertRaisesRegex(ValueError, re.escape(message)):
                        repo.merge()
                    self.assertEqual(repo.catalog.read_text(encoding="utf-8"), before)

    def test_merge_does_not_wait_for_cases_that_are_not_added_yet_but_validation_does(self):
        with Repository() as repo:
            repo.write(ENTRIES, merged=False, swift={"Apps/New.swift": "PreviewStrings.format(.notYetAdded, arguments: [1])"})
            repo.merge()
            repo.generate()
            code, out, err = repo.validate()
            self.assertEqual(code, 1)
            self.assertIn(".notYetAdded is not a PreviewStrings.Key case", err)

    def test_merge_checks_placeholders_of_keys_without_call_sites(self):
        with Repository() as repo:
            repo.write({"stat.rows": entry("Rows: %lld", ru="Строки: %lld", ja="行: %lld")}, merged=False)
            document = repo.read_input("ru")
            document["strings"]["stat.rows"] = "Строки"
            (repo.translations / "ru.json").write_text(canonical_json(document), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "ru/strings/stat.rows: placeholders differ"):
                repo.merge()

    def test_merge_rejects_plural_variants_in_the_metadata_catalog(self):
        with Repository() as repo:
            repo.write(ENTRIES, merged=False)
            document = json.loads(repo.metadata.read_text(encoding="utf-8"))
            document["strings"]["metadata.app.name"]["localizations"]["en"] = catalog_localization({"one": "%@", "other": "%@"})
            repo.metadata.write_text(canonical_json(document), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "plural variants are not supported in the metadata catalog"):
                repo.merge()

    def test_merge_never_overwrites_an_input_edited_while_it_ran(self):
        with Repository() as repo:
            repo.write(ENTRIES, merged=False)
            path = repo.translations / "ru.json"
            document = json.loads(path.read_text(encoding="utf-8"))
            document["strings"] = dict(reversed(list(document["strings"].items())))
            unsorted = json.dumps(document, ensure_ascii=False, indent=2) + "\n"
            path.write_text(unsorted, encoding="utf-8")
            real = merge_localizations.catalog_localization

            def edit_then_convert(value):
                path.write_text(unsorted + "\n", encoding="utf-8")
                return real(value)

            with patch.object(merge_localizations, "catalog_localization", edit_then_convert):
                message = repo.merge()
            self.assertEqual(path.read_text(encoding="utf-8"), unsorted + "\n")
            self.assertIn("ru.json changed during the merge", message)


class AddTests(unittest.TestCase):
    PLURAL = {"comment": "Count of entries; the first argument selects the plural rule, the second is the formatted number.",
              "case": "previewCountEntries",
              "en": {"one": "%2$@ entry", "other": "%2$@ entries"},
              "ru": {"other": "%2$@ записи", "many": "%2$@ записей", "few": "%2$@ записи", "one": "%2$@ запись"},
              "ja": {"other": "%2$@ 件"}}
    PLAIN = {"comment": "A plain label.", "case": "previewPlain", "en": "Plain", "ru": "Простой", "ja": "シンプル"}

    def test_add_writes_plural_and_plain_entries_sorted_and_ignores_case(self):
        with Repository() as repo:
            repo.write(ENTRIES)
            unsorted = repo.read_input("ru")
            unsorted["strings"] = dict(reversed(list(unsorted["strings"].items())))
            (repo.translations / "ru.json").write_text(json.dumps(unsorted, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            code, err = repo.add({"preview.count.entries": self.PLURAL, "aaa.plain": self.PLAIN})
            self.assertEqual((code, err), (0, ""))
            catalog = repo.read_catalog()
            self.assertEqual(list(catalog), sorted(catalog))
            added = catalog["preview.count.entries"]
            self.assertEqual(set(added), {"comment", "extractionState", "localizations"})
            self.assertEqual(added["extractionState"], "manual")
            self.assertEqual(list(added["localizations"]), ["en"])
            self.assertEqual(localization_value(added["localizations"]["en"]), self.PLURAL["en"])
            for language in ("ru", "ja"):
                strings = repo.read_input(language)["strings"]
                self.assertEqual(list(strings), sorted(strings))
                self.assertEqual(strings["preview.count.entries"], self.PLURAL[language])
                self.assertEqual(strings["aaa.plain"], self.PLAIN[language])
            self.assertEqual(list(repo.read_input("ru")["strings"]["preview.count.entries"]), ["one", "few", "many", "other"])
            self.assertNotIn("case", json.dumps(repo.read_input("ru")))

    def test_an_added_plural_key_flows_through_merge_generate_and_validate(self):
        with Repository() as repo:
            repo.write(ENTRIES)
            self.assertEqual(repo.add({"preview.count.entries": self.PLURAL})[0], 0)
            accessor = repo.renderers / "PreviewStrings.swift"
            accessor.write_text(accessor.read_text(encoding="utf-8") + '\ncase c9 = "preview.count.entries"\n', encoding="utf-8")
            repo.merge()
            repo.generate()
            code, out, err = repo.validate()
            self.assertEqual((code, err), (0, ""))
            self.assertIn("3 keys (2 plural)", out)
            document = plistlib.loads((repo.resources / "ru.lproj/Localizable.stringsdict").read_bytes())
            self.assertEqual(document["preview.count.entries"]["count"]["many"], "%2$@ записей")

    def test_add_rejects_bad_entries_and_writes_nothing(self):
        without = lambda entry, field: {name: value for name, value in entry.items() if name != field}
        for name, key, additions, message in [
            ("existing key", "action.example", self.PLAIN, "action.example: already exists"),
            ("plain string for a plural key", "a.b", {**self.PLURAL, "ru": "%2$@ записи"}, "expected an object of plural categories"),
            ("object for a plain key", "a.b", {**self.PLAIN, "ru": {"other": "Простой"}}, "expected a plain string"),
            ("missing language", "a.b", without(self.PLAIN, "ja"), "missing ['ja']"),
            ("unknown field", "a.b", {**self.PLAIN, "note": "x"}, "unknown fields ['note']"),
            ("no comment", "a.b", without(self.PLAIN, "comment"), "missing translator comment"),
            ("categories the language does not define", "a.b", {**self.PLURAL, "ja": {"one": "%2$@ 件", "other": "%2$@ 件"}}, "not defined for ja"),
            ("missing categories", "a.b", {**self.PLURAL, "ru": {"one": "%2$@ запись", "other": "%2$@ записи"}}, "missing plural categories ['few', 'many']"),
            ("placeholder mismatch", "a.b", {**self.PLAIN, "en": "Plain %@"}, "a.b/ru: placeholders differ"),
            ("blank text", "a.b", {**self.PLAIN, "ru": "  "}, "empty or non-string text"),
        ]:
            with self.subTest(name):
                with Repository() as repo:
                    repo.write(ENTRIES)
                    before = (repo.catalog.read_text(encoding="utf-8"), repo.read_input("ru"))
                    code, err = repo.add({key: additions})
                    self.assertEqual(code, 1)
                    self.assertIn(message, err)
                    self.assertEqual((repo.catalog.read_text(encoding="utf-8"), repo.read_input("ru")), before)

    def test_the_metadata_catalog_takes_plain_brand_templates_only(self):
        with Repository() as repo:
            repo.write(ENTRIES)
            plain = {"comment": "Extra bundle name.", "en": "%@ Extra", "ru": "%@ Доп", "ja": "%@ 追加"}
            self.assertEqual(repo.add({"metadata.extra.name": plain}, catalog="metadata"), (0, ""))
            self.assertEqual(repo.read_input("ru")["metadata"]["metadata.extra.name"], "%@ Доп")
            self.assertEqual(list(repo.read_input("ru")["metadata"]), sorted(repo.read_input("ru")["metadata"]))
            code, err = repo.add({"metadata.count.name": self.PLURAL}, catalog="metadata")
            self.assertEqual(code, 1)
            self.assertIn("plural variants are not supported in the metadata catalog", err)


if __name__ == "__main__":
    unittest.main()
