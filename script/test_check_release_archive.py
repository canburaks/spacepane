#!/usr/bin/env python3
"""Unit tests for the release-archive check and the project validator's privacy-manifest checks.

    python3 script/test_check_release_archive.py

Decision 027: Q-27 (archive hardening), Q-44 (the CAD service's accepted client against the preview extension) and
Q-45 (privacy manifests). Every archive is a synthetic tree in a temporary directory, and the Apple tools (codesign,
lipo, xattr) are replaced by a fake that answers from tables, so the tests run on any host with Python 3.9 or newer
and read no user data. The privacy manifests and the project file of this repository are read as they are, so a
broken manifest or a folder the project does not synchronize fails here without a Mac.
"""
import contextlib
import io
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT_DIRECTORY = Path(__file__).resolve().parent
ROOT = SCRIPT_DIRECTORY.parent
sys.path.insert(0, str(SCRIPT_DIRECTORY))

import check_release_archive as archive_check  # noqa: E402
import validate_project  # noqa: E402
from check_release_archive import Signing  # noqa: E402

TEAM = "ABCDE12345"
BASE = "org.example.spacepane"
GROUP = f"{TEAM}.{BASE}.shared"
RUNTIME = archive_check.HARDENED_RUNTIME

SANDBOX = archive_check.SANDBOX
INHERIT = archive_check.INHERIT
USER_SELECTED = archive_check.USER_SELECTED_READ_WRITE
GROUPS = archive_check.APP_GROUPS


def macho(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\xcf\xfa\xed\xfe" + bytes(60))


def api(category, reasons):
    return {"NSPrivacyAccessedAPIType": category, "NSPrivacyAccessedAPITypeReasons": reasons}


def manifest(*entries):
    return {"NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": [],
            "NSPrivacyAccessedAPITypes": list(entries)}


SHARED_APIS = (api(archive_check.FILE_TIMESTAMP, ["3B52.1", "C617.1", "DDA9.1"]),
               api(archive_check.SYSTEM_BOOT_TIME, ["35F9.1"]))
MANIFESTS = {
    "app": manifest(*SHARED_APIS, api(archive_check.USER_DEFAULTS, ["CA92.1"])),
    "preview": manifest(*SHARED_APIS),
    "thumbnail": manifest(*SHARED_APIS),
    "cad-service": manifest(),
}
BUNDLE_ROLES = ("app", "preview", "thumbnail", "cad-service")
LOCALIZED_ROLES = ("app", "preview", "thumbnail")


class FakeTools:
    """Answers the tool calls from the fixture's tables, keyed by the label of the path asked about."""

    def __init__(self, fixture):
        self.fixture = fixture

    def label(self, path):
        for label, known in self.fixture.paths.items():
            if known == path:
                return label
        return path.name if path.name.endswith("-binary") else None

    def entitlements(self, path):
        return dict(self.fixture.entitlements.get(self.label(path), {}))

    def signing(self, path):
        return self.fixture.signings.get(self.label(path), Signing())

    def architectures(self, path):
        return set(self.fixture.architectures.get(self.label(path), {"arm64"}))

    def quarantine(self, path):
        return self.fixture.quarantine

    def verify(self, path):
        return self.fixture.verify


class Fixture:
    """A complete synthetic archive that passes every check; a test changes one thing and expects one problem."""

    def __init__(self, root):
        self.archive = root / "Release.xcarchive"
        self.app = self.archive / "Products/Applications/SpacePane.app"
        preview = self.app / "Contents/PlugIns/PrevPreviewExtension.appex"
        service = preview / "Contents/XPCServices/CADImportService.xpc"
        self.paths = {
            "app": self.app, "preview": preview, "thumbnail": self.app / "Contents/PlugIns/PrevThumbnailExtension.appex",
            "cad-service": service, "helper-app": self.app / "Contents/Helpers/CADWorker",
            "helper-service": service / "Contents/Helpers/CADWorker",
        }
        versions = {"CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1"}
        self.shipped = ["en"]
        self.languages = {role: ["en"] for role in LOCALIZED_ROLES}
        self.infos = {
            "app": {**versions, "CFBundleIdentifier": BASE, "CFBundlePackageType": "APPL",
                    "LSApplicationCategoryType": "public.app-category.utilities", "ITSAppUsesNonExemptEncryption": False,
                    "NSHumanReadableCopyright": "Copyright 2026 Example", "CFBundleIconName": "AppIcon",
                    "CFBundleIconFile": "AppIcon", "PreviewAppGroupIdentifier": GROUP},
            "preview": {**versions, "CFBundleIdentifier": BASE + ".preview", "PreviewAppGroupIdentifier": GROUP,
                        "CADImportServiceIdentifier": BASE + ".cad-import",
                        "NSExtension": {"NSExtensionPointIdentifier": archive_check.PREVIEW_POINT,
                                        "NSExtensionPrincipalClass": "PrevPreviewExtension.PreviewViewController",
                                        "NSExtensionAttributes": {"QLSupportsSearchableItems": False,
                                                                  "QLSupportedContentTypes": ["public.json", "public.yaml"]}}},
            "thumbnail": {**versions, "CFBundleIdentifier": BASE + ".thumbnail", "PreviewAppGroupIdentifier": GROUP,
                          "NSExtension": {"NSExtensionPointIdentifier": archive_check.THUMBNAIL_POINT,
                                          "NSExtensionPrincipalClass": "PrevThumbnailExtension.ThumbnailProvider",
                                          "NSExtensionAttributes": {"QLThumbnailMinimumDimension": 64,
                                                                    "QLSupportedContentTypes": ["public.json", "public.yaml"]}}},
            "cad-service": {**versions, "CFBundleIdentifier": BASE + ".cad-import",
                            "CADAllowedClientIdentifier": BASE + ".preview", "CADAllowedClientTeamIdentifier": TEAM},
        }
        for role in LOCALIZED_ROLES:
            self.infos[role]["CFBundleLocalizations"] = ["en"]
        self.entitlements = {
            "app": {SANDBOX: True, USER_SELECTED: True, GROUPS: [GROUP]},
            "preview": {SANDBOX: True, GROUPS: [GROUP]},
            "thumbnail": {SANDBOX: True, GROUPS: [GROUP]},
            "cad-service": {SANDBOX: True},
            "helper-app": {SANDBOX: True, INHERIT: True},
            "helper-service": {SANDBOX: True, INHERIT: True},
        }
        self.signings = {role: Signing(identifier=self.infos[role]["CFBundleIdentifier"], team=TEAM, flags=RUNTIME)
                         for role in BUNDLE_ROLES}
        self.signings["helper-app"] = Signing(identifier=BASE + ".CADWorker", team=TEAM, flags=RUNTIME)
        self.signings["helper-service"] = Signing(identifier=BASE + ".cad-import.CADWorker", team=TEAM, flags=RUNTIME)
        self.manifests = dict(MANIFESTS)
        self.architectures = {}
        self.quarantine = ""
        self.verify = (True, "")
        self.tools = FakeTools(self)

    def write(self):
        for role in BUNDLE_ROLES:
            path = self.paths[role]
            (path / "Contents/Resources").mkdir(parents=True, exist_ok=True)
            (path / "Contents/Info.plist").write_bytes(plistlib.dumps(self.infos[role]))
            macho(path / f"Contents/MacOS/{role}-binary")
            if self.manifests.get(role) is not None:
                (path / "Contents/Resources" / archive_check.PRIVACY_MANIFEST).write_bytes(plistlib.dumps(self.manifests[role]))
        for role, languages in self.languages.items():
            for language in languages:
                localized = self.paths[role] / "Contents/Resources" / f"{language}.lproj"
                localized.mkdir(parents=True, exist_ok=True)
                (localized / "InfoPlist.strings").write_text('"CFBundleName" = "Example";\n')
        (self.app / "Contents/Resources/AppIcon.icns").write_bytes(b"icns")
        macho(self.paths["helper-app"])
        macho(self.paths["helper-service"])
        notices = self.app / "Contents/Resources/OCCT-Notices"
        notices.mkdir(parents=True, exist_ok=True)
        (notices / "LICENSE_LGPL_21.txt").write_text("notice")
        palettes = self.app / "Contents/Resources/ColorSchemes-Notices"
        palettes.mkdir(parents=True, exist_ok=True)
        (palettes / "NOTICE.md").write_text("notice")
        (self.archive / "dSYMs/SpacePane.app.dSYM").mkdir(parents=True, exist_ok=True)


class ArchiveCase(unittest.TestCase):
    def run_check(self, edit=None, after=None):
        """Build the fixture, let `edit` change its tables, write the tree, let `after` change the tree, and check it."""
        with tempfile.TemporaryDirectory() as directory:
            fixture = Fixture(Path(directory))
            if edit:
                edit(fixture)
            fixture.write()
            if after:
                after(fixture)
            return archive_check.inspect_archive(fixture.archive, fixture.tools, shipped=fixture.shipped)

    def assertFailure(self, report, *fragments):
        self.assertTrue(any(all(fragment in failure for fragment in fragments) for failure in report.failures),
                        f"no failure contains {fragments}; failures were:\n" + "\n".join(report.failures))

    def assertClean(self, report):
        self.assertEqual(report.failures, [])


class ValidArchiveTests(ArchiveCase):
    def test_a_complete_archive_passes(self):
        report = self.run_check()
        self.assertClean(report)
        self.assertIn("4 sandboxed bundles", report.summary)
        self.assertIn("2 helpers", report.summary)
        self.assertIn("4 privacy manifests", report.summary)

    def test_the_cad_peer_note_names_the_three_certificate_forms_and_the_installed_build_proof(self):
        report = self.run_check()
        note = [item for item in report.notes if "CAD peer requirement" in item]
        self.assertEqual(len(note), 1)
        self.assertIn("team's certificate", note[0])
        self.assertIn("Mac App Store marker", note[0])
        self.assertIn("TestFlight marker", note[0])
        self.assertIn("installed TestFlight or App Store build", note[0])

    def test_development_signing_adds_get_task_allow_which_is_a_note(self):
        def edit(fixture):
            for role in ("app", "preview", "thumbnail", "cad-service"):
                fixture.entitlements[role][archive_check.GET_TASK_ALLOW] = True
        report = self.run_check(edit)
        self.assertClean(report)
        self.assertEqual(len([item for item in report.notes if "get-task-allow" in item]), 4)

    def test_profile_identity_keys_are_tolerated_when_they_match_the_team_and_bundle(self):
        def edit(fixture):
            for role in ("app", "preview", "thumbnail", "cad-service"):
                identifier = fixture.infos[role]["CFBundleIdentifier"]
                fixture.entitlements[role][archive_check.APPLICATION_IDENTIFIER] = f"{TEAM}.{identifier}"
                fixture.entitlements[role][archive_check.DEVELOPER_TEAM_IDENTIFIER] = TEAM
        self.assertClean(self.run_check(edit))

    def test_profile_identity_keys_must_agree_with_the_signature(self):
        def edit(fixture):
            fixture.entitlements["preview"][archive_check.APPLICATION_IDENTIFIER] = f"{TEAM}.org.other.preview"
            fixture.entitlements["thumbnail"][archive_check.DEVELOPER_TEAM_IDENTIFIER] = "ZZZZZ99999"
        report = self.run_check(edit)
        self.assertFailure(report, "PrevPreviewExtension.appex", "com.apple.application-identifier")
        self.assertFailure(report, "PrevThumbnailExtension.appex", "com.apple.developer.team-identifier")


class LanguageTests(ArchiveCase):
    """The store lists every language at the top of the app bundle, so the archive carries the ship list only."""

    def test_a_draft_language_in_the_companion_is_refused(self):
        def edit(fixture):
            fixture.languages["app"] = ["en", "de"]
        self.assertFailure(self.run_check(edit), "SpacePane.app", "de", "ship list")

    def test_a_draft_language_in_an_extension_is_refused(self):
        def edit(fixture):
            fixture.languages["thumbnail"] = ["en", "tr"]
        self.assertFailure(self.run_check(edit), "PrevThumbnailExtension.appex", "tr", "ship list")

    def test_a_shipped_language_must_be_present_in_every_localized_bundle(self):
        def edit(fixture):
            fixture.shipped = ["en", "de"]
            for role in LOCALIZED_ROLES:
                fixture.infos[role]["CFBundleLocalizations"] = ["en", "de"]
            fixture.languages["app"] = fixture.languages["thumbnail"] = ["en", "de"]
        self.assertFailure(self.run_check(edit), "PrevPreviewExtension.appex", "de", "ship list")

    def test_two_shipped_languages_pass_when_every_bundle_carries_both(self):
        def edit(fixture):
            fixture.shipped = ["en", "de"]
            for role in LOCALIZED_ROLES:
                fixture.infos[role]["CFBundleLocalizations"] = ["en", "de"]
                fixture.languages[role] = ["en", "de"]
        self.assertClean(self.run_check(edit))

    def test_the_declared_localizations_must_equal_the_ship_list(self):
        def edit(fixture):
            fixture.infos["preview"]["CFBundleLocalizations"] = ["en", "fr"]
        self.assertFailure(self.run_check(edit), "PrevPreviewExtension.appex", "CFBundleLocalizations")

    def test_a_missing_declaration_is_reported(self):
        def edit(fixture):
            del fixture.infos["app"]["CFBundleLocalizations"]
        self.assertFailure(self.run_check(edit), "SpacePane.app", "CFBundleLocalizations")

    def test_the_private_cad_service_has_no_languages_of_its_own(self):
        def after(fixture):
            (fixture.paths["cad-service"] / "Contents/Resources/de.lproj").mkdir(parents=True)
        self.assertFailure(self.run_check(after=after), "CADImportService.xpc", "de")

    def test_draft_translations_inside_a_nested_resource_bundle_are_a_note_not_a_failure(self):
        def after(fixture):
            nested = fixture.app / "Contents/Resources/PreviewCore_PreviewRenderers.bundle/Contents/Resources"
            for language in ("en", "de", "tr"):
                (nested / f"{language}.lproj").mkdir(parents=True)
        report = self.run_check(after=after)
        self.assertClean(report)
        self.assertTrue(any("PreviewCore_PreviewRenderers.bundle" in note and "de, tr" in note for note in report.notes),
                        report.notes)

    def test_the_repository_ship_list_is_read_when_none_is_supplied(self):
        self.assertEqual(archive_check.shipped_languages(), ["en"])


class LayoutTests(ArchiveCase):
    def test_no_application_is_reported_before_anything_else(self):
        with tempfile.TemporaryDirectory() as directory:
            report = archive_check.inspect_archive(Path(directory) / "Empty.xcarchive", FakeTools(Fixture(Path(directory))))
        self.assertEqual(report.failures, ["Archive must contain exactly one application"])

    def test_two_applications_are_refused(self):
        def after(fixture):
            (fixture.archive / "Products/Applications/Second.app/Contents").mkdir(parents=True)
        self.assertFailure(self.run_check(after=after), "exactly one application")

    def test_products_outside_the_app_are_reported(self):
        def after(fixture):
            (fixture.archive / "Products/usr/local/bin").mkdir(parents=True)
            (fixture.archive / "Products/usr/local/bin/tool").write_bytes(b"x")
        self.assertFailure(self.run_check(after=after), "products outside the app")

    def test_an_extension_of_another_kind_is_refused(self):
        def edit(fixture):
            fixture.infos["thumbnail"]["NSExtension"]["NSExtensionPointIdentifier"] = "com.apple.widgetkit-extension"
        report = self.run_check(edit)
        self.assertFailure(report, "unexpected kind")
        self.assertFailure(report, "exactly one thumbnail extension, found 0")

    def test_a_second_preview_extension_is_refused(self):
        def after(fixture):
            second = fixture.app / "Contents/PlugIns/Extra.appex/Contents"
            second.mkdir(parents=True)
            (second / "Info.plist").write_bytes(plistlib.dumps(fixture.infos["preview"]))
        self.assertFailure(self.run_check(after=after), "exactly one preview extension, found 2")

    def test_the_cad_service_must_live_inside_the_preview_extension_only(self):
        def after(fixture):
            stray = fixture.app / "Contents/XPCServices/Other.xpc/Contents"
            stray.mkdir(parents=True)
            (stray / "Info.plist").write_bytes(plistlib.dumps(fixture.infos["cad-service"]))
        self.assertFailure(self.run_check(after=after), "CAD import service once, inside the preview extension only")

    def test_both_cad_worker_copies_are_required(self):
        def after(fixture):
            fixture.paths["helper-service"].unlink()
        self.assertFailure(self.run_check(after=after), "CAD worker in the companion and the CAD service only, found",
                           "Contents/Helpers/CADWorker")

    def test_the_cad_worker_belongs_to_the_companion_and_the_service_not_an_extension(self):
        def after(fixture):
            fixture.paths["helper-service"].unlink()
            macho(fixture.paths["thumbnail"] / "Contents/Helpers/CADWorker")
        self.assertFailure(self.run_check(after=after), "CAD worker in the companion and the CAD service only",
                           "PrevThumbnailExtension.appex/Contents/Helpers/CADWorker")


class InfoPlistTests(ArchiveCase):
    def test_a_prerelease_version_is_refused(self):
        def edit(fixture):
            for role in BUNDLE_ROLES:
                fixture.infos[role]["CFBundleShortVersionString"] = "0.9.0"
        self.assertFailure(self.run_check(edit), "0.x prerelease")

    def test_a_missing_icon_is_reported(self):
        self.assertFailure(self.run_check(after=lambda fixture: (fixture.app / "Contents/Resources/AppIcon.icns").unlink()),
                           "Compiled app icon")

    def test_unresolved_settings_are_found_in_nested_values_of_every_bundle(self):
        def edit(fixture):
            fixture.infos["cad-service"]["CADAllowedClientTeamIdentifier"] = "$(DEVELOPMENT_TEAM)"
            fixture.infos["thumbnail"]["NSExtension"]["NSExtensionPrincipalClass"] = "$(PRODUCT_MODULE_NAME).ThumbnailProvider"
            fixture.infos["preview"]["NSExtension"]["NSExtensionAttributes"]["QLSupportedContentTypes"][1] = "$(TYPE)"
        report = self.run_check(edit)
        self.assertFailure(report, "CADImportService.xpc", "CADAllowedClientTeamIdentifier")
        self.assertFailure(report, "PrevThumbnailExtension.appex", "NSExtension.NSExtensionPrincipalClass")
        self.assertFailure(report, "PrevPreviewExtension.appex", "QLSupportedContentTypes[1]")

    def test_a_prototype_identity_is_refused(self):
        def edit(fixture):
            fixture.infos["app"]["CFBundleIdentifier"] = "invalid.example.previewprototype"
            fixture.infos["thumbnail"]["PreviewAppGroupIdentifier"] = "group.invalid.example.previewprototype"
        report = self.run_check(edit)
        self.assertFailure(report, "SpacePane.app has no real CFBundleIdentifier")
        self.assertFailure(report, "PrevThumbnailExtension.appex has no real PreviewAppGroupIdentifier")

    def test_nested_bundles_share_the_apps_versions(self):
        def edit(fixture):
            fixture.infos["preview"]["CFBundleShortVersionString"] = "1.0.1"
            fixture.infos["cad-service"]["CFBundleVersion"] = "2"
        report = self.run_check(edit)
        self.assertFailure(report, "PrevPreviewExtension.appex", "CFBundleShortVersionString", "1.0.1")
        self.assertFailure(report, "CADImportService.xpc", "CFBundleVersion", "'2'")

    def test_an_extension_identifier_must_be_prefixed_by_the_apps(self):
        def edit(fixture):
            fixture.infos["thumbnail"]["CFBundleIdentifier"] = "org.example.other.thumbnail"
            fixture.signings["thumbnail"] = fixture.signings["thumbnail"]._replace(identifier="org.example.other.thumbnail")
        self.assertFailure(self.run_check(edit), "PrevThumbnailExtension.appex identifier must be prefixed")

    def test_the_preview_extension_must_not_claim_searchable_items(self):
        def edit(fixture):
            fixture.infos["preview"]["NSExtension"]["NSExtensionAttributes"]["QLSupportsSearchableItems"] = True
        self.assertFailure(self.run_check(edit), "QLSupportsSearchableItems")

    def test_the_thumbnail_extension_needs_a_minimum_dimension(self):
        def edit(fixture):
            del fixture.infos["thumbnail"]["NSExtension"]["NSExtensionAttributes"]["QLThumbnailMinimumDimension"]
        self.assertFailure(self.run_check(edit), "QLThumbnailMinimumDimension")

    def test_content_types_must_be_listed_once(self):
        def edit(fixture):
            fixture.infos["preview"]["NSExtension"]["NSExtensionAttributes"]["QLSupportedContentTypes"] = ["public.json", "public.json"]
        self.assertFailure(self.run_check(edit), "QLSupportedContentTypes")


class EntitlementTests(ArchiveCase):
    def test_each_role_carries_only_its_own_entitlements(self):
        cases = {
            "preview": ({"com.apple.security.network.client": True}, "declares network access"),
            "thumbnail": ({"com.apple.security.temporary-exception.mach-lookup.global-name": ["x"]}, "temporary exceptions"),
            "app": ({"com.apple.security.cs.allow-jit": True}, "weakens the hardened runtime"),
            "cad-service": ({"com.apple.security.files.user-selected.read-only": True}, "outside its cad-service role"),
        }
        for role, (extra, expected) in cases.items():
            with self.subTest(role=role):
                report = self.run_check(lambda fixture: fixture.entitlements[role].update(extra))
                self.assertFailure(report, expected)

    def test_an_extension_may_not_hold_the_companions_file_access(self):
        report = self.run_check(lambda fixture: fixture.entitlements["preview"].update({USER_SELECTED: True}))
        self.assertFailure(report, "PrevPreviewExtension.appex", "outside its preview role")

    def test_a_missing_required_entitlement_is_reported(self):
        def edit(fixture):
            del fixture.entitlements["app"][USER_SELECTED]
            fixture.entitlements["cad-service"] = {}
        report = self.run_check(edit)
        self.assertFailure(report, "SpacePane.app", "must grant com.apple.security.files.user-selected.read-write")
        self.assertFailure(report, "CADImportService.xpc", "must grant com.apple.security.app-sandbox")

    def test_helpers_are_signed_with_exactly_sandbox_and_inherit(self):
        def edit(fixture):
            fixture.entitlements["helper-app"][archive_check.GET_TASK_ALLOW] = True
            del fixture.entitlements["helper-service"][INHERIT]
        report = self.run_check(edit)
        self.assertFailure(report, "Contents/Helpers/CADWorker", "outside its helper role")
        self.assertFailure(report, "must grant com.apple.security.inherit")

    def test_the_app_and_both_extensions_must_name_exactly_one_group(self):
        def edit(fixture):
            fixture.entitlements["app"][GROUPS] = [GROUP, "ZZZZZ99999.other"]
            fixture.entitlements["preview"][GROUPS] = []
        report = self.run_check(edit)
        self.assertFailure(report, "SpacePane.app", "exactly one App Group")
        self.assertFailure(report, "PrevPreviewExtension.appex", "exactly one App Group")

    def test_one_group_must_be_shared_and_match_every_info_plist(self):
        def edit(fixture):
            fixture.entitlements["thumbnail"][GROUPS] = [f"{TEAM}.{BASE}.other"]
        report = self.run_check(edit)
        self.assertFailure(report, "must share one App Group")
        self.assertFailure(report, "PrevThumbnailExtension.appex", "differs from its PreviewAppGroupIdentifier")

    def test_an_unresolved_or_prototype_group_is_refused(self):
        def edit(fixture):
            for role in ("app", "preview", "thumbnail"):
                fixture.entitlements[role][GROUPS] = ["group.invalid.example.previewprototype"]
                fixture.infos[role]["PreviewAppGroupIdentifier"] = "group.invalid.example.previewprototype"
        self.assertFailure(self.run_check(edit), "unresolved or a prototype identity")


class SigningTests(ArchiveCase):
    def test_every_bundle_and_helper_needs_the_hardened_runtime(self):
        def edit(fixture):
            fixture.signings["preview"] = fixture.signings["preview"]._replace(flags=0)
            fixture.signings["helper-app"] = fixture.signings["helper-app"]._replace(flags=0x2)
        report = self.run_check(edit)
        self.assertFailure(report, "PrevPreviewExtension.appex is not signed with the hardened runtime")
        self.assertFailure(report, "Contents/Helpers/CADWorker is not signed with the hardened runtime")

    def test_a_signing_identifier_must_equal_the_bundle_identifier(self):
        def edit(fixture):
            fixture.signings["thumbnail"] = fixture.signings["thumbnail"]._replace(identifier="org.example.other")
        self.assertFailure(self.run_check(edit), "PrevThumbnailExtension.appex signing identifier")

    def test_a_helper_is_named_for_its_owner(self):
        def edit(fixture):
            fixture.signings["helper-service"] = fixture.signings["helper-service"]._replace(identifier="CADWorker")
        self.assertFailure(self.run_check(edit), "must be org.example.spacepane.cad-import.CADWorker")

    def test_everything_comes_from_one_team(self):
        def edit(fixture):
            fixture.signings["thumbnail"] = fixture.signings["thumbnail"]._replace(team="ZZZZZ99999")
        self.assertFailure(self.run_check(edit), "Signing teams differ")

    def test_an_unsigned_or_ad_hoc_item_has_no_team(self):
        def edit(fixture):
            fixture.signings["helper-app"] = fixture.signings["helper-app"]._replace(team=None)
        self.assertFailure(self.run_check(edit), "Not signed by a team", "Contents/Helpers/CADWorker")

    def test_a_team_must_have_ten_characters(self):
        def edit(fixture):
            for label, signing in list(fixture.signings.items()):
                fixture.signings[label] = signing._replace(team="TEAM")
            fixture.infos["cad-service"]["CADAllowedClientTeamIdentifier"] = "TEAM"
        self.assertFailure(self.run_check(edit), "not a ten-character team identifier")


class CADServiceTests(ArchiveCase):
    def test_the_accepted_client_must_be_the_preview_extension(self):
        def edit(fixture):
            fixture.infos["cad-service"]["CADAllowedClientIdentifier"] = BASE + ".thumbnail"
        self.assertFailure(self.run_check(edit), "CAD service accepts client", "org.example.spacepane.preview")

    def test_the_accepted_team_must_be_the_signing_team(self):
        def edit(fixture):
            fixture.infos["cad-service"]["CADAllowedClientTeamIdentifier"] = "ZZZZZ99999"
        self.assertFailure(self.run_check(edit), "CAD service accepts team 'ZZZZZ99999'")

    def test_values_outside_the_allow_list_would_make_the_service_refuse_everyone(self):
        def edit(fixture):
            fixture.infos["cad-service"]["CADAllowedClientIdentifier"] = BASE + ".pre view"
        self.assertFailure(self.run_check(edit), "only letters, digits, dot and hyphen")

    def test_the_preview_extension_must_connect_to_the_embedded_service(self):
        def edit(fixture):
            fixture.infos["preview"]["CADImportServiceIdentifier"] = BASE + ".other-service"
        self.assertFailure(self.run_check(edit), "connects to 'org.example.spacepane.other-service'")


class PrivacyManifestArchiveTests(ArchiveCase):
    def test_every_bundle_needs_its_manifest(self):
        for role in BUNDLE_ROLES:
            with self.subTest(role=role):
                report = self.run_check(lambda fixture: fixture.manifests.update({role: None}))
                self.assertFailure(report, "no Contents/Resources/PrivacyInfo.xcprivacy")

    def test_an_unreadable_manifest_is_reported(self):
        def after(fixture):
            (fixture.paths["thumbnail"] / "Contents/Resources/PrivacyInfo.xcprivacy").write_text("not a plist")
        self.assertFailure(self.run_check(after=after), "PrevThumbnailExtension.appex", "not a readable property list")

    def test_a_manifest_that_tracks_or_collects_is_refused(self):
        def edit(fixture):
            fixture.manifests["preview"] = {**MANIFESTS["preview"], "NSPrivacyTracking": True,
                                            "NSPrivacyCollectedDataTypes": [{"NSPrivacyCollectedDataType": "x"}]}
        report = self.run_check(edit)
        self.assertFailure(report, "NSPrivacyTracking must be false")
        self.assertFailure(report, "NSPrivacyCollectedDataTypes must be an empty array")

    def test_a_role_must_declare_the_categories_its_code_reaches(self):
        def edit(fixture):
            fixture.manifests["app"] = manifest(*SHARED_APIS)
            fixture.manifests["thumbnail"] = manifest(SHARED_APIS[0])
        report = self.run_check(edit)
        self.assertFailure(report, "SpacePane.app", "NSPrivacyAccessedAPICategoryUserDefaults")
        self.assertFailure(report, "PrevThumbnailExtension.appex", "NSPrivacyAccessedAPICategorySystemBootTime")

    def test_the_cad_service_declares_nothing_it_does_not_use_but_may_declare_more(self):
        fixture_edit = lambda fixture: fixture.manifests.update({"cad-service": manifest(SHARED_APIS[0])})  # noqa: E731
        self.assertClean(self.run_check(fixture_edit))


class ToolAndFileTests(ArchiveCase):
    def test_a_quarantine_attribute_is_refused(self):
        def edit(fixture):
            fixture.quarantine = "SpacePane.app/Contents/MacOS/x: com.apple.quarantine: 0083;..."
        self.assertFailure(self.run_check(edit), "com.apple.quarantine")

    def test_every_mach_o_file_must_be_arm64_only(self):
        def edit(fixture):
            fixture.architectures["preview-binary"] = {"arm64", "x86_64"}
        self.assertFailure(self.run_check(edit), "preview-binary", "x86_64")

    def test_a_failed_deep_verification_is_reported(self):
        def edit(fixture):
            fixture.verify = (False, "a sealed resource is missing")
        self.assertFailure(self.run_check(edit), "codesign --verify --deep --strict failed", "a sealed resource is missing")

    def test_missing_notices_and_symbols_are_reported(self):
        def after(fixture):
            (fixture.app / "Contents/Resources/OCCT-Notices/LICENSE_LGPL_21.txt").unlink()
            (fixture.app / "Contents/Resources/ColorSchemes-Notices/NOTICE.md").unlink()
            (fixture.archive / "dSYMs/SpacePane.app.dSYM").rmdir()
        report = self.run_check(after=after)
        self.assertFailure(report, "OCCT license notices")
        self.assertFailure(report, "color scheme palette notice")
        self.assertFailure(report, "no dSYMs")

    def test_embedded_frameworks_are_a_note_about_their_own_manifests(self):
        def after(fixture):
            (fixture.app / "Contents/Frameworks/PreviewCore.framework").mkdir(parents=True)
        report = self.run_check(after=after)
        self.assertClean(report)
        self.assertTrue(any("PreviewCore.framework" in note for note in report.notes))


class MainTests(ArchiveCase):
    def run_main(self, edit=None):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Fixture(Path(directory))
            if edit:
                edit(fixture)
            fixture.write()
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                status = archive_check.main(fixture.archive, fixture.tools)
        return status, out.getvalue(), err.getvalue()

    def test_a_passing_archive_prints_the_summary_and_notes(self):
        status, out, err = self.run_main()
        self.assertEqual((status, err), (0, ""))
        self.assertIn("Release archive checks passed for SpacePane.app 1.0.0 (1)", out)
        self.assertIn("note: CAD peer requirement", out)

    def test_a_failing_archive_lists_each_problem_on_stderr(self):
        status, out, err = self.run_main(lambda fixture: fixture.entitlements["preview"].update(
            {"com.apple.security.network.client": True}))
        self.assertEqual(status, 1)
        self.assertIn("Release archive check failed (1):", err)
        self.assertIn(" - PrevPreviewExtension.appex declares network access", err)

    def test_the_command_line_rejects_a_wrong_argument_list_and_an_empty_archive(self):
        script = str(SCRIPT_DIRECTORY / "check_release_archive.py")
        usage = subprocess.run([sys.executable, "-I", script, "not-an-archive"], capture_output=True, text=True)
        self.assertNotEqual(usage.returncode, 0)
        self.assertIn("usage: check_release_archive.py PATH.xcarchive", usage.stderr)
        with tempfile.TemporaryDirectory() as directory:
            empty = Path(directory) / "Empty.xcarchive"
            empty.mkdir()
            result = subprocess.run([sys.executable, "-I", script, str(empty)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Archive must contain exactly one application", result.stderr)


class HelperFunctionTests(unittest.TestCase):
    SIGNED = (b"Executable=/x/SpacePane.app/Contents/MacOS/SpacePane\nIdentifier=org.example.spacepane\n"
              b"Format=app bundle with Mach-O thin (arm64)\n"
              b"CodeDirectory v=20500 size=22847 flags=0x10000(runtime) hashes=700+7 location=embedded\n"
              b"Authority=Apple Development: Someone (ABCDE12345)\nTeamIdentifier=ABCDE12345\n")
    AD_HOC = (b"Identifier=org.example.spacepane\n"
              b"CodeDirectory v=20400 size=500 flags=0x20002(adhoc,linker-signed) hashes=10+0 location=embedded\n"
              b"Signature=adhoc\nTeamIdentifier=not set\n")

    def test_parse_signing_reads_identifier_team_and_flags(self):
        signing = archive_check.parse_signing(self.SIGNED)
        self.assertEqual((signing.identifier, signing.team, signing.flags), ("org.example.spacepane", "ABCDE12345", 0x10000))
        self.assertTrue(signing.hardened_runtime)

    def test_parse_signing_treats_ad_hoc_code_as_having_no_team_and_no_runtime(self):
        signing = archive_check.parse_signing(self.AD_HOC)
        self.assertEqual((signing.team, signing.hardened_runtime), (None, False))
        self.assertEqual(signing.flags, 0x20002)

    def test_parse_signing_of_nothing_is_empty(self):
        self.assertEqual(archive_check.parse_signing(b""), Signing())

    def test_system_tools_decode_codesign_output_and_tolerate_failures(self):
        tools = archive_check.SystemTools()
        entitlements = plistlib.dumps({SANDBOX: True})
        completed = subprocess.CompletedProcess
        with mock.patch.object(archive_check.SystemTools, "_run", return_value=completed([], 0, entitlements, b"")):
            self.assertEqual(tools.entitlements(Path("x")), {SANDBOX: True})
        with mock.patch.object(archive_check.SystemTools, "_run", return_value=completed([], 1, entitlements, b"")):
            self.assertEqual(tools.entitlements(Path("x")), {})
        with mock.patch.object(archive_check.SystemTools, "_run", return_value=completed([], 0, b"<plist><dict>", b"")):
            self.assertEqual(tools.entitlements(Path("x")), {})
        with mock.patch.object(archive_check.SystemTools, "_run", return_value=completed([], 0, b"", self.SIGNED)):
            self.assertEqual(tools.signing(Path("x")).team, "ABCDE12345")
        with mock.patch.object(archive_check.SystemTools, "_run", return_value=completed([], 0, b"arm64 x86_64\n", b"")):
            self.assertEqual(tools.architectures(Path("x")), {"arm64", "x86_64"})
        with mock.patch.object(archive_check.SystemTools, "_run", return_value=completed([], 1, b"", b" bad \n")):
            self.assertEqual(tools.verify(Path("x")), (False, "bad"))

    def test_unresolved_settings_walks_nested_values(self):
        value = {"A": "ok", "B": {"C": ["x", "$(Y)"]}, "D": "a $(Z) b"}
        self.assertEqual(list(archive_check.unresolved_settings(value)), ["B.C[1]: $(Y)", "D: a $(Z) b"])

    def test_entitlement_problems_name_each_class_of_extra_key(self):
        granted = {SANDBOX: True, GROUPS: ["g"], "com.apple.security.network.server": True,
                   "com.apple.security.cs.disable-library-validation": True,
                   "com.apple.security.temporary-exception.files.absolute-path.read-only": ["/"], "com.example.x": 1}
        problems = archive_check.entitlement_problems("preview", granted)
        self.assertEqual(len(problems), 4)
        self.assertTrue(any("com.example.x" in problem for problem in problems))

    def test_the_cad_peer_alphabet_matches_the_swift_allow_list(self):
        accepted = ["org.example.preview", "A-b.9", "Z0z-."]
        rejected = ["", "a b", 'a"b', "a\\b", "a\nb", "a/b", "a(b)", "é", "a٣", "a_b"]
        for value in accepted:
            self.assertTrue(archive_check.CAD_PEER_VALUE.fullmatch(value), value)
        for value in rejected:
            self.assertFalse(archive_check.CAD_PEER_VALUE.fullmatch(value), repr(value))


class PrivacyManifestFunctionTests(unittest.TestCase):
    def problems(self, value, role="preview"):
        return archive_check.privacy_manifest_problems(value, role)

    def test_a_suitable_manifest_has_no_problems_for_each_role(self):
        for role, value in MANIFESTS.items():
            with self.subTest(role=role):
                self.assertEqual(self.problems(value, role), [])

    def test_only_apples_reason_codes_for_each_category_are_accepted(self):
        value = manifest(api(archive_check.FILE_TIMESTAMP, ["3B52.1", "CA92.1"]), SHARED_APIS[1])
        self.assertTrue(any("CA92.1" in problem for problem in self.problems(value)))

    def test_every_listed_reason_code_belongs_to_exactly_the_category_it_is_listed_under(self):
        owners = {}
        for category, codes in archive_check.API_REASONS.items():
            for code in codes:
                self.assertNotIn(code, owners, f"{code} is listed under two categories")
                owners[code] = category
        self.assertEqual(set(archive_check.API_REASONS), {archive_check.FILE_TIMESTAMP, archive_check.SYSTEM_BOOT_TIME,
                                                          archive_check.DISK_SPACE, archive_check.ACTIVE_KEYBOARDS,
                                                          archive_check.USER_DEFAULTS})

    def test_unknown_categories_empty_or_repeated_reasons_and_duplicates_are_refused(self):
        self.assertTrue(self.problems(manifest(api("NSPrivacyAccessedAPICategoryMadeUp", ["X"]), *SHARED_APIS)))
        self.assertTrue(self.problems(manifest(api(archive_check.FILE_TIMESTAMP, []), SHARED_APIS[1])))
        self.assertTrue(self.problems(manifest(api(archive_check.FILE_TIMESTAMP, ["3B52.1", "3B52.1"]), SHARED_APIS[1])))
        self.assertTrue(self.problems(manifest(*SHARED_APIS, SHARED_APIS[0])))
        self.assertTrue(self.problems(manifest({"NSPrivacyAccessedAPIType": archive_check.FILE_TIMESTAMP}, SHARED_APIS[1])))

    def test_malformed_manifests_are_refused_without_raising(self):
        for value in [[], "text", {}, {"NSPrivacyAccessedAPITypes": "x"}, {**MANIFESTS["app"], "NSPrivacyAccessedAPITypes": [3]}]:
            with self.subTest(value=value):
                self.assertTrue(self.problems(value, "app"))

    def test_unknown_top_level_keys_are_reported(self):
        self.assertTrue(any("NSPrivacyExtra" in problem for problem in self.problems({**MANIFESTS["preview"], "NSPrivacyExtra": 1})))


def synchronized_folders(project_text):
    """Target name to the folders its synchronized root groups cover, read from the project file's text."""
    paths = dict(re.findall(r"^\s*(\w+) /\* [^*]+ \*/ = \{isa = PBXFileSystemSynchronizedRootGroup;.*?\bpath = ([^;]+);",
                            project_text, re.MULTILINE))
    folders = {}
    for block in re.findall(r"isa = PBXNativeTarget;(.*?)\n\t\t\};", project_text, re.DOTALL):
        name = re.search(r"\bname = (\w+);", block).group(1)
        listed = re.search(r"fileSystemSynchronizedGroups = \((.*?)\);", block, re.DOTALL)
        identifiers = re.findall(r"(\w{24})", listed.group(1)) if listed else []
        folders[name] = [paths[identifier] for identifier in identifiers]
    return folders


class ProjectValidatorTests(unittest.TestCase):
    """validate_project.validate_privacy_manifests over a synthetic root, and over this repository's own files."""

    def make_root(self, directory, edits=None):
        root = Path(directory)
        for target, (role, relative) in validate_project.PRIVACY_MANIFESTS.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(plistlib.dumps(MANIFESTS[role]))
        for relative, text in (edits or {}).items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        return root

    def synthetic_project(self, exceptions=None):
        objects, targets = {}, {}
        for index, (target, (role, relative)) in enumerate(validate_project.PRIVACY_MANIFESTS.items()):
            folder = "Apps/PrevApp" if target == "Prev" else str(Path(relative).parent)
            group = {"isa": "PBXFileSystemSynchronizedRootGroup", "path": folder}
            if exceptions and target in exceptions:
                group["exceptions"] = [f"E{index}"]
                objects[f"E{index}"] = {"isa": "PBXFileSystemSynchronizedBuildFileExceptionSet",
                                        "membershipExceptions": exceptions[target]}
            objects[f"G{index}"] = group
            targets[target] = {"fileSystemSynchronizedGroups": [f"G{index}"]}
        return objects, targets

    def validate(self, root, objects, targets):
        validate_project.validate_privacy_manifests(root, objects, targets)

    def test_a_complete_synthetic_project_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            objects, targets = self.synthetic_project()
            self.validate(self.make_root(directory), objects, targets)

    def test_a_missing_manifest_is_reported_by_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.make_root(directory)
            (root / "Native/CADImportService/PrivacyInfo.xcprivacy").unlink()
            objects, targets = self.synthetic_project()
            with self.assertRaisesRegex(ValueError, "CADImportService needs a privacy manifest"):
                self.validate(root, objects, targets)

    def test_an_unreadable_manifest_is_a_validation_error_not_a_crash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.make_root(directory, {"Extensions/PrevPreviewExtension/PrivacyInfo.xcprivacy": "<plist><dict>"})
            objects, targets = self.synthetic_project()
            with self.assertRaisesRegex(ValueError, "not a readable property list"):
                self.validate(root, objects, targets)

    def test_manifest_content_problems_name_the_file(self):
        with tempfile.TemporaryDirectory() as directory:
            bad = plistlib.dumps({**MANIFESTS["thumbnail"], "NSPrivacyTracking": True}).decode()
            root = self.make_root(directory, {"Extensions/PrevThumbnailExtension/PrivacyInfo.xcprivacy": bad})
            objects, targets = self.synthetic_project()
            with self.assertRaisesRegex(ValueError, r"PrevThumbnailExtension/PrivacyInfo.xcprivacy: NSPrivacyTracking must be false"):
                self.validate(root, objects, targets)

    def test_a_folder_the_target_does_not_synchronize_would_leave_the_manifest_out_of_the_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            objects, targets = self.synthetic_project()
            objects["G1"]["path"] = "Extensions/SomewhereElse"
            with self.assertRaisesRegex(ValueError, "PrevPreviewExtension target synchronizes"):
                self.validate(self.make_root(directory), objects, targets)

    def test_a_membership_exception_would_also_leave_it_out(self):
        with tempfile.TemporaryDirectory() as directory:
            objects, targets = self.synthetic_project(exceptions={"Prev": ["Resources/PrivacyInfo.xcprivacy"]})
            with self.assertRaisesRegex(ValueError, "excluded from the Prev target by a membership exception"):
                self.validate(self.make_root(directory), objects, targets)

    def test_this_repositorys_manifests_suit_their_roles(self):
        for target, (role, relative) in validate_project.PRIVACY_MANIFESTS.items():
            with self.subTest(target=target):
                with (ROOT / relative).open("rb") as handle:
                    value = plistlib.load(handle)
                self.assertEqual(archive_check.privacy_manifest_problems(value, role), [])

    def test_this_repositorys_project_synchronizes_each_manifest_folder_into_its_target(self):
        folders = synchronized_folders((ROOT / "Prev.xcodeproj/project.pbxproj").read_text(encoding="utf-8"))
        for target, (role, relative) in validate_project.PRIVACY_MANIFESTS.items():
            with self.subTest(target=target):
                covering = [folder for folder in folders[target] if Path(relative).parts[:len(Path(folder).parts)] == Path(folder).parts]
                self.assertTrue(covering, f"{relative} is not inside a synchronized folder of {target}: {folders[target]}")
        self.assertNotIn("membershipExceptions", (ROOT / "Prev.xcodeproj/project.pbxproj").read_text(encoding="utf-8"),
                         "the project now has membership exceptions; validate_project.py checks them with the plist form")


if __name__ == "__main__":
    unittest.main()
