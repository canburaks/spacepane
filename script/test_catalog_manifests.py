#!/usr/bin/env python3
"""Tests for the catalog rules that script/sync_manifests.py derives and script/validate_project.py enforces.

The rules: an imported declaration may list several parents and every one of its types must reach public.data
(review finding 0); the thumbnail extension registers only formats whose policy is `content` (finding 9); no
identifier of another developer's product appears in the catalog or the manifests (finding 11); the preview
extension names the CAD service only when the product carries CAD (finding 22). Plain Python 3.9.
"""
import copy
import json
from pathlib import Path
import plistlib
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import sync_manifests  # noqa: E402
import validate_project  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json"
FOREIGN = "com.quicklookpro."


def declaration(identifier, conforms_to, extensions=("xyz",)):
    return {"identifier": identifier, "conformsTo": conforms_to, "descriptionKey": "type." + identifier,
            "referenceURL": "https://example.com", "extensions": list(extensions)}


def entry(format_id, content_types, thumbnail="content", extensions=("xyz",), imported=None, optional=None):
    item = {"id": format_id, "contentTypes": list(content_types), "extensions": list(extensions),
            "presentation": "text", "thumbnail": thumbnail}
    if imported is not None:
        item["importedContentTypes"] = imported
    if optional is not None:
        item["optionalContentTypes"] = optional
    return item


def real_formats():
    return json.loads(CATALOG.read_text())["formats"]


def plist(name):
    return plistlib.loads((ROOT / "Configuration" / name).read_bytes())


class DerivedManifestTests(unittest.TestCase):
    def test_a_single_parent_string_becomes_a_one_element_list(self):
        formats = [entry("a.one", ["org.example.one"], imported=[declaration("org.example.one", "public.text")])]
        _, _, imported = sync_manifests.derived(formats)
        self.assertEqual(imported[0]["UTTypeConformsTo"], ["public.text"])

    def test_a_parent_list_is_written_in_order(self):
        formats = [entry("a.one", ["org.example.one"],
                         imported=[declaration("org.example.one", ["public.database", "public.data"])])]
        _, _, imported = sync_manifests.derived(formats)
        self.assertEqual(imported[0]["UTTypeConformsTo"], ["public.database", "public.data"])

    def test_the_thumbnail_list_takes_only_the_content_policy(self):
        formats = [entry("a.content", ["org.example.content"], thumbnail="content"),
                   entry("a.generic", ["public.folder"], thumbnail="generic"),
                   entry("a.none", ["org.example.none"], thumbnail="none")]
        preview, thumbnail, _ = sync_manifests.derived(formats)
        self.assertEqual(thumbnail, ["org.example.content"])
        self.assertEqual(preview, ["org.example.content", "public.folder", "org.example.none"])


class CatalogRuleTests(unittest.TestCase):
    def validated(self, *formats):
        return validate_project.validate_catalog(list(formats))

    def test_a_parent_list_is_accepted(self):
        _, _, imported = self.validated(entry("a.one", ["org.example.one"],
                                              imported=[declaration("org.example.one", ["public.archive", "public.data"])]))
        self.assertEqual(imported[0]["UTTypeConformsTo"], ["public.archive", "public.data"])

    def test_a_single_parent_string_still_works(self):
        _, _, imported = self.validated(entry("a.one", ["org.example.one"],
                                              imported=[declaration("org.example.one", "public.plain-text")]))
        self.assertEqual(imported[0]["UTTypeConformsTo"], ["public.plain-text"])

    def test_parents_that_macos_declares_without_a_parent_need_public_data(self):
        for parent in ("public.database", "public.archive"):
            for conforms_to in (parent, [parent]):
                with self.subTest(parent=parent, conforms_to=conforms_to):
                    with self.assertRaisesRegex(ValueError, "public.data"):
                        self.validated(entry("a.one", ["org.example.one"],
                                             imported=[declaration("org.example.one", conforms_to)]))

    def test_a_malformed_parent_list_is_refused(self):
        for conforms_to in ([], ["public.text", "public.text"], [3], None, ""):
            with self.subTest(conforms_to=conforms_to):
                with self.assertRaises(ValueError):
                    self.validated(entry("a.one", ["org.example.one"],
                                         imported=[declaration("org.example.one", conforms_to)]))

    def test_the_thumbnail_types_exclude_the_generic_policy(self):
        _, thumbnail, _ = self.validated(entry("a.content", ["org.example.content"]),
                                         entry("a.generic", ["public.folder"], thumbnail="generic", extensions=()),
                                         entry("a.none", ["org.example.none"], thumbnail="none"))
        self.assertEqual(thumbnail, ["org.example.content"])

    def test_another_products_identifier_is_refused_even_as_an_optional_alias(self):
        with self.assertRaisesRegex(ValueError, FOREIGN):
            self.validated(entry("a.one", ["org.example.one", FOREIGN + "thing"], optional=[FOREIGN + "thing"]))

    def test_another_products_identifier_is_refused_as_a_canonical_type(self):
        with self.assertRaisesRegex(ValueError, FOREIGN):
            self.validated(entry("a.one", [FOREIGN + "thing"]))

    def test_the_extension_free_format_keeps_its_exact_claim(self):
        root = entry("text.plain", ["public.data"], thumbnail="none", extensions=())
        root["presentation"] = "text"
        types, thumbnail, _ = self.validated(root)
        self.assertEqual(types, ["public.data"])
        self.assertEqual(thumbnail, [])

    def test_the_real_catalog_passes(self):
        types, thumbnail, imported = validate_project.validate_catalog(real_formats())
        self.assertNotIn("public.data", thumbnail)
        self.assertTrue(imported)
        self.assertFalse([t for t in types if t.startswith(FOREIGN)])


class RealCatalogTests(unittest.TestCase):
    def test_the_catalog_and_manifests_carry_no_identifier_of_another_product(self):
        for path in [CATALOG, *(ROOT / "Configuration" / name for name in
                                ("App-Info.plist", "Preview-Info.plist", "Thumbnail-Info.plist"))]:
            with self.subTest(path=path.name):
                self.assertNotIn("quicklookpro", path.read_text())

    def test_every_imported_declaration_reaches_public_data(self):
        reaching = {"public.data", "public.text", "public.plain-text", "public.json", "public.xml", "public.source-code",
                    "public.zip-archive", "com.apple.xml-property-list"}
        for item in real_formats():
            for found in item.get("importedContentTypes", []):
                parents = found["conformsTo"]
                parents = [parents] if isinstance(parents, str) else parents
                with self.subTest(identifier=found["identifier"]):
                    self.assertTrue(set(parents) & reaching, parents)

    def test_sqlite_parquet_and_rar_list_public_data_in_every_manifest(self):
        expected = {"org.sqlite.sqlite": ["public.database", "public.data"],
                    "org.apache.parquet": ["public.database", "public.data"],
                    "org.webmeister.spacepane.type.rar": ["public.archive", "public.data"]}
        for name in ("App-Info.plist", "Preview-Info.plist", "Thumbnail-Info.plist"):
            found = {item["UTTypeIdentifier"]: item["UTTypeConformsTo"]
                     for item in plist(name)["UTImportedTypeDeclarations"]}
            for identifier, parents in expected.items():
                with self.subTest(manifest=name, identifier=identifier):
                    self.assertEqual(found[identifier], parents)

    def test_the_thumbnail_extension_registers_only_content_formats(self):
        formats = real_formats()
        wanted = {t for item in formats if item["thumbnail"] == "content" for t in item["contentTypes"]}
        declared = plist("Thumbnail-Info.plist")["NSExtension"]["NSExtensionAttributes"]["QLSupportedContentTypes"]
        self.assertEqual(set(declared), wanted)
        generic = {t for item in formats if item["thumbnail"] == "generic" for t in item["contentTypes"]}
        self.assertFalse(generic & set(declared) - wanted)
        for system_type in ("public.folder", "com.apple.application-bundle", "com.apple.disk-image-udif",
                            "com.apple.installer-package-archive", "public.zip-archive"):
            self.assertNotIn(system_type, declared)

    def test_app_bundles_keep_their_own_icon(self):
        policy = {item["id"]: item["thumbnail"] for item in real_formats()}
        self.assertEqual(policy["package.application"], "generic")


class CADServiceKeyTests(unittest.TestCase):
    SERVICE = "$(PREVIEW_BASE_BUNDLE_IDENTIFIER).cad-import"

    def settings(self, **overrides):
        values = {"PREV_CAD_SERVICE_IDENTIFIER_YES": self.SERVICE, "PREV_CAD_SERVICE_IDENTIFIER_NO": "",
                  "PREV_CAD_SERVICE_IDENTIFIER": "$(PREV_CAD_SERVICE_IDENTIFIER_$(PREV_INCLUDE_CAD))"}
        values.update(overrides)
        return values

    def problems(self, info, include_cad, settings=None):
        return validate_project.cad_service_key_problems(info, self.settings() if settings is None else settings,
                                                         include_cad, self.SERVICE)

    def test_the_key_resolves_to_the_service_only_when_cad_is_included(self):
        info = {"CADImportServiceIdentifier": "$(PREV_CAD_SERVICE_IDENTIFIER)"}
        self.assertEqual(self.problems(info, True), [])
        self.assertEqual(self.problems(info, False), [])

    def test_a_literal_identifier_is_refused_when_cad_is_left_out(self):
        info = {"CADImportServiceIdentifier": self.SERVICE}
        self.assertTrue(self.problems(info, False))

    def test_a_setting_that_names_the_service_when_cad_is_left_out_is_refused(self):
        info = {"CADImportServiceIdentifier": "$(PREV_CAD_SERVICE_IDENTIFIER)"}
        self.assertTrue(self.problems(info, False, self.settings(PREV_CAD_SERVICE_IDENTIFIER_NO=self.SERVICE)))

    def test_a_setting_that_is_empty_when_cad_is_included_is_refused(self):
        info = {"CADImportServiceIdentifier": "$(PREV_CAD_SERVICE_IDENTIFIER)"}
        self.assertTrue(self.problems(info, True, self.settings(PREV_CAD_SERVICE_IDENTIFIER_YES="")))

    def test_the_real_configuration_follows_the_mode(self):
        info = plist("Preview-Info.plist")
        settings = validate_project.xcconfig(ROOT / "Configuration/Base.xcconfig")
        for include_cad in (True, False):
            with self.subTest(include_cad=include_cad):
                self.assertEqual(self.problems(info, include_cad, settings), [])


if __name__ == "__main__":
    unittest.main()
