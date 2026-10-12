#!/usr/bin/env python3
"""Inspect an Xcode archive for Mac App Store upload problems before Organizer validation.

usage: check_release_archive.py PATH.xcarchive

These checks mirror upload validation and App Review requirements that can be read locally: store
metadata keys, the compiled icon, quarantine attributes, architectures, nested code signatures with
the hardened-runtime flag and one signing team, the exact entitlement set of every bundle role, one
App Group everywhere, the accepted-client values of the private CAD service against the preview
extension's identity, the privacy manifest of every bundle, and helper identity (decision 027, Q-27,
Q-44 and Q-45). They do not replace Xcode's Validate App, which also checks provisioning and the
distribution signature, and only a TestFlight install proves the store-signed runtime, including the
CAD service's peer requirement (decision 027, D27).

The system tools (codesign, lipo, xattr) are reached through `SystemTools`; script/test_check_release_archive.py
substitutes a fake and runs this module over synthetic bundle trees on any host. Plain Python 3.9 and the
standard library only: the build script runs it with the system interpreter.
"""
from __future__ import annotations

from pathlib import Path
import plistlib
import re
import subprocess
import sys
from typing import Any, Dict, Iterator, List, NamedTuple, Optional, Set, Tuple
from xml.parsers.expat import ExpatError

EXPECTED_ARCHITECTURES = {"arm64"}

SANDBOX = "com.apple.security.app-sandbox"
INHERIT = "com.apple.security.inherit"
USER_SELECTED_READ_WRITE = "com.apple.security.files.user-selected.read-write"
APP_GROUPS = "com.apple.security.application-groups"
GET_TASK_ALLOW = "com.apple.security.get-task-allow"
APPLICATION_IDENTIFIER = "com.apple.application-identifier"
DEVELOPER_TEAM_IDENTIFIER = "com.apple.developer.team-identifier"

# The exact entitlements of each bundle role (security review R11). The App Group array of the three roles in
# GROUP_ROLES is compared across bundles and with each Info.plist instead of being listed here. A role grants
# nothing beyond its row: no network, no temporary exception, no hardened-runtime exception (`cs.*`).
ROLE_ENTITLEMENTS: Dict[str, Dict[str, Any]] = {
    "app": {SANDBOX: True, USER_SELECTED_READ_WRITE: True},
    "preview": {SANDBOX: True},
    "thumbnail": {SANDBOX: True},
    "cad-service": {SANDBOX: True},
    "helper": {SANDBOX: True, INHERIT: True},
}
GROUP_ROLES = ("app", "preview", "thumbnail")
# Entries that signing adds around a role's set and that grant no capability: development signing adds
# get-task-allow, and a provisioning profile adds the two identity keys. Their values are checked where present.
# A bare helper is signed with exactly its entitlements file and tolerates nothing.
SIGNING_ADDED = frozenset({GET_TASK_ALLOW, APPLICATION_IDENTIFIER, DEVELOPER_TEAM_IDENTIFIER})

PREVIEW_POINT = "com.apple.quicklook.preview"
THUMBNAIL_POINT = "com.apple.quicklook.thumbnail"
HARDENED_RUNTIME = 0x10000
HELPER_SUFFIX = ".CADWorker"

PRIVACY_MANIFEST = "PrivacyInfo.xcprivacy"
FILE_TIMESTAMP = "NSPrivacyAccessedAPICategoryFileTimestamp"
SYSTEM_BOOT_TIME = "NSPrivacyAccessedAPICategorySystemBootTime"
DISK_SPACE = "NSPrivacyAccessedAPICategoryDiskSpace"
ACTIVE_KEYBOARDS = "NSPrivacyAccessedAPICategoryActiveKeyboards"
USER_DEFAULTS = "NSPrivacyAccessedAPICategoryUserDefaults"

# Apple's required-reason codes per accessed-API category, as listed on Apple's NSPrivacyAccessedAPIType page
# (developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/
# nsprivacyaccessedapitype, read 2026-10-06). Recheck them against Apple's current page before every
# submission: a code outside its category's list is rejected at upload.
API_REASONS: Dict[str, Set[str]] = {
    FILE_TIMESTAMP: {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    SYSTEM_BOOT_TIME: {"35F9.1", "8FFB.1", "3D61.1"},
    DISK_SPACE: {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    ACTIVE_KEYBOARDS: {"3EC4.1", "54BD.1"},
    USER_DEFAULTS: {"CA92.1", "1C8F.1", "C56D.1", "AC6B.1"},
}
# The categories each role's manifest must declare because its code reaches them (decision 027, Q-45). The
# extensions link the same readers as the companion and the elapsed-time clock of the MIDI renderer; only the
# companion keeps defaults; the CAD service links no required-reason API. A manifest may declare more.
REQUIRED_API_CATEGORIES: Dict[str, Set[str]] = {
    "app": {FILE_TIMESTAMP, SYSTEM_BOOT_TIME, USER_DEFAULTS},
    "preview": {FILE_TIMESTAMP, SYSTEM_BOOT_TIME},
    "thumbnail": {FILE_TIMESTAMP, SYSTEM_BOOT_TIME},
    "cad-service": set(),
}
MANIFEST_KEYS = {"NSPrivacyTracking", "NSPrivacyTrackingDomains", "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"}

# Mirrors CADPeerRequirement.isAllowedValue: the service refuses every connection when its accepted-client
# identifier or team falls outside this alphabet, so the archive must not ship such a value.
CAD_PEER_VALUE = re.compile(r"[A-Za-z0-9.-]+")
TEAM_IDENTIFIER = re.compile(r"[A-Z0-9]{10}")
CODE_DIRECTORY_FLAGS = re.compile(r"^CodeDirectory\b.*?\bflags=0x([0-9a-fA-F]+)", re.MULTILINE)
PROTOTYPE_IDENTITY = "invalid.example"


class Signing(NamedTuple):
    """What `codesign --display` reports about one signed item; empty fields when it is unsigned."""
    identifier: Optional[str] = None
    team: Optional[str] = None
    flags: int = 0

    @property
    def hardened_runtime(self) -> bool:
        return bool(self.flags & HARDENED_RUNTIME)


def parse_signing(output: bytes) -> Signing:
    """Parse the text `codesign --display --verbose=2` prints (on stderr)."""
    text = output.decode("utf-8", errors="replace")
    identifier = re.search(r"^Identifier=(.+)$", text, re.MULTILINE)
    team = re.search(r"^TeamIdentifier=(.+)$", text, re.MULTILINE)
    flags = CODE_DIRECTORY_FLAGS.search(text)
    team_value = team.group(1).strip() if team else None
    return Signing(identifier=identifier.group(1).strip() if identifier else None,
                   team=None if team_value in (None, "", "not set") else team_value,
                   flags=int(flags.group(1), 16) if flags else 0)


class SystemTools:
    """The Apple command-line tools the check calls. Tests substitute an object with the same methods."""

    @staticmethod
    def _run(*arguments: str) -> "subprocess.CompletedProcess[bytes]":
        return subprocess.run(arguments, capture_output=True, text=False)

    def entitlements(self, path: Path) -> Dict[str, Any]:
        result = self._run("/usr/bin/codesign", "--display", "--entitlements", "-", "--xml", str(path))
        if result.returncode != 0 or not result.stdout.strip():
            return {}
        try:
            return plistlib.loads(result.stdout)
        except (ValueError, ExpatError):
            return {}

    def signing(self, path: Path) -> Signing:
        result = self._run("/usr/bin/codesign", "--display", "--verbose=2", str(path))
        return parse_signing(result.stdout + b"\n" + result.stderr)

    def architectures(self, path: Path) -> Set[str]:
        return set(self._run("/usr/bin/lipo", "-archs", str(path)).stdout.decode(errors="replace").split())

    def quarantine(self, path: Path) -> str:
        return self._run("/usr/bin/xattr", "-r", "-l", str(path)).stdout.decode(errors="replace")

    def verify(self, path: Path) -> Tuple[bool, str]:
        result = self._run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(path))
        return result.returncode == 0, result.stderr.decode(errors="replace").strip()


class Report:
    def __init__(self) -> None:
        self.failures: List[str] = []
        self.notes: List[str] = []
        self.summary = ""

    def check(self, condition: Any, message: str) -> bool:
        if not condition:
            self.failures.append(message)
        return bool(condition)

    def fail(self, message: str) -> None:
        self.failures.append(message)

    def note(self, message: str) -> None:
        self.notes.append(message)


class Bundle(NamedTuple):
    role: str
    path: Path
    info: Dict[str, Any]
    name: str


def read_plist(path: Path) -> Optional[Dict[str, Any]]:
    try:
        value = plistlib.loads(path.read_bytes())
    except (OSError, ValueError, ExpatError):
        return None
    return value if isinstance(value, dict) else None


def read_info(bundle: Path) -> Optional[Dict[str, Any]]:
    return read_plist(bundle / "Contents/Info.plist")


def is_macho(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            magic = handle.read(4)
    except OSError:
        return False
    return magic in {b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}


def unresolved_settings(value: Any, path: str = "") -> Iterator[str]:
    """Yield `key path: value` for every string below `value` that still holds a build-setting reference."""
    if isinstance(value, str):
        if "$(" in value:
            yield f"{path or '(root)'}: {value[:80]}"
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from unresolved_settings(item, f"{path}.{key}" if path else str(key))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from unresolved_settings(item, f"{path}[{index}]")


# ---------------------------------------------------------------------------------------------------
# Privacy manifests (shared with script/validate_project.py)
# ---------------------------------------------------------------------------------------------------

def privacy_manifest_problems(manifest: Any, role: str) -> List[str]:
    """Why a decoded PrivacyInfo.xcprivacy does not suit a bundle role, as sentences; empty when it does.

    SpacePane tracks nothing and collects nothing, so the tracking flag is false, both tracking lists are
    empty, and every accessed-API category carries only Apple's own reason codes for that category. The role's
    required categories (REQUIRED_API_CATEGORIES) must all be declared.
    """
    if not isinstance(manifest, dict):
        return ["is not a property list dictionary"]
    problems: List[str] = []
    if manifest.get("NSPrivacyTracking") is not False:
        problems.append("NSPrivacyTracking must be false")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        problems.append("NSPrivacyTrackingDomains must be an empty array")
    if manifest.get("NSPrivacyCollectedDataTypes") != []:
        problems.append("NSPrivacyCollectedDataTypes must be an empty array: the app collects no data")
    unexpected = sorted(str(key) for key in manifest if key not in MANIFEST_KEYS)
    if unexpected:
        problems.append(f"has keys this check does not know: {unexpected}")
    declared = manifest.get("NSPrivacyAccessedAPITypes")
    if not isinstance(declared, list):
        problems.append("NSPrivacyAccessedAPITypes must be an array")
        return problems
    seen: Set[str] = set()
    for entry in declared:
        category = entry.get("NSPrivacyAccessedAPIType") if isinstance(entry, dict) else None
        reasons = entry.get("NSPrivacyAccessedAPITypeReasons") if isinstance(entry, dict) else None
        if not isinstance(category, str) or category not in API_REASONS:
            problems.append(f"accessed API category {category!r} is not one Apple defines")
            continue
        if category in seen:
            problems.append(f"{category} is declared more than once")
        seen.add(category)
        if not isinstance(reasons, list) or not reasons or not all(isinstance(reason, str) for reason in reasons):
            problems.append(f"{category} needs a non-empty array of reason codes")
            continue
        if len(set(reasons)) != len(reasons):
            problems.append(f"{category} repeats a reason code")
        outside = sorted(reason for reason in set(reasons) if reason not in API_REASONS[category])
        if outside:
            problems.append(f"{category} has reason codes outside Apple's list for that category: {outside}")
    missing = sorted(REQUIRED_API_CATEGORIES.get(role, set()) - seen)
    if missing:
        problems.append(f"does not declare the API categories the {role} code reaches: {missing}")
    return problems


# ---------------------------------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------------------------------

def check_app_info(report: Report, info: Dict[str, Any], app: Path) -> None:
    version = info.get("CFBundleShortVersionString", "")
    report.check(re.fullmatch(r"\d+\.\d+(\.\d+)?", version if isinstance(version, str) else ""),
                 "CFBundleShortVersionString must be a release version")
    report.check(not str(version).startswith("0."), "Marketing version is still a 0.x prerelease")
    report.check(re.fullmatch(r"public\.app-category\.[a-z-]+", str(info.get("LSApplicationCategoryType", ""))),
                 "LSApplicationCategoryType is missing or invalid")
    report.check(info.get("ITSAppUsesNonExemptEncryption") is False, "ITSAppUsesNonExemptEncryption must be declared")
    report.check(info.get("NSHumanReadableCopyright"), "NSHumanReadableCopyright is missing")
    icon = info.get("CFBundleIconFile")
    report.check(info.get("CFBundleIconName") and isinstance(icon, str) and icon
                 and (app / "Contents/Resources" / (icon if icon.endswith(".icns") else icon + ".icns")).is_file(),
                 "Compiled app icon (CFBundleIconName/CFBundleIconFile and .icns) is missing")


def find_bundles(report: Report, app: Path, app_info: Dict[str, Any]) -> List[Bundle]:
    """The app, its Quick Look extensions by role and the CAD service, reporting any other layout."""
    bundles = [Bundle("app", app, app_info, app.name)]
    found: Dict[str, List[Bundle]] = {"preview": [], "thumbnail": []}
    for appex in sorted(app.glob("Contents/PlugIns/*.appex")):
        info = read_info(appex)
        if info is None:
            report.fail(f"{appex.name} has no readable Contents/Info.plist")
            continue
        extension = info.get("NSExtension")
        point = extension.get("NSExtensionPointIdentifier") if isinstance(extension, dict) else None
        role = {PREVIEW_POINT: "preview", THUMBNAIL_POINT: "thumbnail"}.get(point)
        if role is None:
            report.fail(f"{appex.name} is an extension of an unexpected kind: {point!r}")
            continue
        found[role].append(Bundle(role, appex, info, appex.name))
    for role in ("preview", "thumbnail"):
        report.check(len(found[role]) == 1, f"Expected exactly one {role} extension, found {len(found[role])}")
        bundles.extend(found[role][:1])
    services = sorted(app.rglob("*.xpc"))
    parent = found["preview"][0].path / "Contents/XPCServices" if found["preview"] else None
    inside = [service for service in services if service.parent == parent]
    report.check(len(services) == 1 and len(inside) == 1,
                 "Expected the CAD import service once, inside the preview extension only; found "
                 f"{[str(service.relative_to(app)) for service in services]}")
    if len(inside) == 1:
        info = read_info(inside[0])
        if info is None:
            report.fail(f"{inside[0].name} has no readable Contents/Info.plist")
        else:
            bundles.append(Bundle("cad-service", inside[0], info, inside[0].name))
    return bundles


def check_info_plists(report: Report, bundles: List[Bundle]) -> None:
    app = bundles[0]
    for bundle in bundles:
        for problem in unresolved_settings(bundle.info):
            report.fail(f"Unresolved build setting in {bundle.name} Info.plist {problem}")
        identifier = bundle.info.get("CFBundleIdentifier")
        report.check(isinstance(identifier, str) and identifier and PROTOTYPE_IDENTITY not in identifier,
                     f"{bundle.name} has no real CFBundleIdentifier ({identifier!r}); build with Configuration/Local.xcconfig")
        if bundle is not app:
            for key in ("CFBundleShortVersionString", "CFBundleVersion"):
                report.check(bundle.info.get(key) == app.info.get(key),
                             f"{bundle.name} {key} {bundle.info.get(key)!r} differs from the app's {app.info.get(key)!r}")
        if bundle.role in ("preview", "thumbnail"):
            report.check(isinstance(identifier, str) and isinstance(app.info.get("CFBundleIdentifier"), str)
                         and identifier.startswith(app.info["CFBundleIdentifier"] + "."),
                         f"{bundle.name} identifier must be prefixed with the app's identifier")
    for bundle in bundles:
        if bundle.role in GROUP_ROLES:
            group = bundle.info.get("PreviewAppGroupIdentifier")
            report.check(isinstance(group, str) and group and PROTOTYPE_IDENTITY not in group,
                         f"{bundle.name} has no real PreviewAppGroupIdentifier ({group!r})")


def check_extension_attributes(report: Report, bundles: List[Bundle]) -> None:
    for bundle in bundles:
        if bundle.role not in ("preview", "thumbnail"):
            continue
        extension = bundle.info.get("NSExtension")
        attributes = extension.get("NSExtensionAttributes") if isinstance(extension, dict) else None
        attributes = attributes if isinstance(attributes, dict) else {}
        types = attributes.get("QLSupportedContentTypes")
        report.check(isinstance(types, list) and types and all(isinstance(item, str) and item for item in types)
                     and len(types) == len(set(types)),
                     f"{bundle.name} must list each supported content type once in QLSupportedContentTypes")
        if bundle.role == "preview":
            report.check(attributes.get("QLSupportsSearchableItems") is False,
                         f"{bundle.name} must set QLSupportsSearchableItems to false")
        else:
            dimension = attributes.get("QLThumbnailMinimumDimension")
            report.check(isinstance(dimension, (int, float)) and not isinstance(dimension, bool) and dimension > 0,
                         f"{bundle.name} must set a positive QLThumbnailMinimumDimension")


def entitlement_problems(role: str, granted: Dict[str, Any]) -> List[str]:
    """Why a granted entitlement set differs from its role's exact set; empty when it matches."""
    problems: List[str] = []
    required = ROLE_ENTITLEMENTS[role]
    for key, value in required.items():
        if granted.get(key) is not value:
            problems.append(f"must grant {key} = {str(value).lower()}")
    allowed = set(required) | (set(SIGNING_ADDED) if role != "helper" else set())
    if role in GROUP_ROLES:
        allowed.add(APP_GROUPS)
        groups = granted.get(APP_GROUPS)
        if not (isinstance(groups, list) and len(groups) == 1 and isinstance(groups[0], str) and groups[0]):
            problems.append(f"must grant exactly one App Group in {APP_GROUPS}")
    extras = sorted(key for key in granted if key not in allowed)
    cs = [key for key in extras if key.startswith("com.apple.security.cs.")]
    temporary = [key for key in extras if "temporary-exception" in key]
    network = [key for key in extras if key.startswith("com.apple.security.network.")]
    other = [key for key in extras if key not in cs and key not in temporary and key not in network]
    if cs:
        problems.append(f"weakens the hardened runtime with {cs}")
    if temporary:
        problems.append(f"requests temporary exceptions {temporary}")
    if network:
        problems.append(f"declares network access {network}")
    if other:
        problems.append(f"carries entitlements outside its {role} role: {other}")
    return problems


def check_entitlements_and_signatures(report: Report, tools: Any, bundles: List[Bundle]) -> Dict[str, Signing]:
    """Entitlements, hardened runtime and signing identity of every bundle; returns each bundle's signing by name."""
    signings: Dict[str, Signing] = {}
    groups: Dict[str, Tuple[Any, ...]] = {}
    for bundle in bundles:
        granted = tools.entitlements(bundle.path)
        for problem in entitlement_problems(bundle.role, granted):
            report.fail(f"{bundle.name} {problem}")
        if granted.get(GET_TASK_ALLOW):
            report.note(f"{bundle.name} carries get-task-allow from development signing; distribution export removes it")
        signing = tools.signing(bundle.path)
        signings[bundle.name] = signing
        report.check(signing.hardened_runtime, f"{bundle.name} is not signed with the hardened runtime (codesign flags 0x{signing.flags:x})")
        identifier = bundle.info.get("CFBundleIdentifier")
        report.check(signing.identifier == identifier,
                     f"{bundle.name} signing identifier {signing.identifier!r} differs from its CFBundleIdentifier {identifier!r}")
        team = signing.team
        if APPLICATION_IDENTIFIER in granted:
            report.check(isinstance(identifier, str) and team and granted[APPLICATION_IDENTIFIER] == f"{team}.{identifier}",
                         f"{bundle.name} {APPLICATION_IDENTIFIER} does not equal the team and bundle identifier")
        if DEVELOPER_TEAM_IDENTIFIER in granted:
            report.check(team and granted[DEVELOPER_TEAM_IDENTIFIER] == team,
                         f"{bundle.name} {DEVELOPER_TEAM_IDENTIFIER} does not equal its signing team")
        if bundle.role in GROUP_ROLES and isinstance(granted.get(APP_GROUPS), list):
            groups[bundle.name] = tuple(str(item) for item in granted[APP_GROUPS])
            declared = bundle.info.get("PreviewAppGroupIdentifier")
            report.check(groups[bundle.name] == (declared,),
                         f"{bundle.name} App Group {granted[APP_GROUPS]} differs from its PreviewAppGroupIdentifier {declared!r}")
            for group in granted[APP_GROUPS]:
                report.check(isinstance(group, str) and "$(" not in group and PROTOTYPE_IDENTITY not in group,
                             f"{bundle.name} App Group {group!r} is unresolved or a prototype identity")
    report.check(len(set(groups.values())) <= 1, f"The app and both extensions must share one App Group: {sorted(groups.values())}")
    return signings


def check_signing_teams(report: Report, signings: Dict[str, Signing]) -> Optional[str]:
    """Every signed item must come from one real team; returns it."""
    teams = {name: signing.team for name, signing in signings.items()}
    missing = sorted(name for name, team in teams.items() if not team)
    report.check(not missing, f"Not signed by a team (ad hoc or unsigned): {missing}")
    present = {team for team in teams.values() if team}
    report.check(len(present) <= 1, f"Signing teams differ across the bundle: {teams}")
    report.check(all(TEAM_IDENTIFIER.fullmatch(team) for team in present), f"Signing team is not a ten-character team identifier: {sorted(present)}")
    return next(iter(present)) if len(present) == 1 else None


def check_cad_service(report: Report, bundles: List[Bundle], signings: Dict[str, Signing]) -> None:
    """The accepted-client values the service reads at runtime must describe this archive's preview extension."""
    by_role = {bundle.role: bundle for bundle in bundles}
    preview, service = by_role.get("preview"), by_role.get("cad-service")
    if preview is None or service is None:
        return
    identifier = service.info.get("CADAllowedClientIdentifier")
    team = service.info.get("CADAllowedClientTeamIdentifier")
    report.check(isinstance(identifier, str) and CAD_PEER_VALUE.fullmatch(identifier)
                 and isinstance(team, str) and CAD_PEER_VALUE.fullmatch(team),
                 "CAD service accepted-client values must use only letters, digits, dot and hyphen: "
                 f"{identifier!r}, {team!r}; the service refuses every connection otherwise")
    report.check(identifier == preview.info.get("CFBundleIdentifier") and identifier == signings[preview.name].identifier,
                 f"CAD service accepts client {identifier!r} but the preview extension is "
                 f"{preview.info.get('CFBundleIdentifier')!r}")
    report.check(team == signings[preview.name].team and team == signings[service.name].team,
                 f"CAD service accepts team {team!r} but the preview extension is signed by "
                 f"{signings[preview.name].team!r} and the service by {signings[service.name].team!r}")
    report.check(preview.info.get("CADImportServiceIdentifier") == service.info.get("CFBundleIdentifier"),
                 f"The preview extension connects to {preview.info.get('CADImportServiceIdentifier')!r} but the embedded "
                 f"service is {service.info.get('CFBundleIdentifier')!r}")
    report.note("CAD peer requirement accepts the team's certificate, the Mac App Store marker or the TestFlight marker; "
                "only an installed TestFlight or App Store build proves the store-signed forms (decision 027, D27)")


def check_helpers(report: Report, tools: Any, app: Path, bundles: List[Bundle]) -> Dict[str, Signing]:
    """The two CAD worker copies; returns each one's signing by its path inside the app."""
    helpers = sorted(app.rglob("Contents/Helpers/CADWorker"))
    owners = {helper.parents[2] for helper in helpers}
    expected = {bundle.path for bundle in bundles if bundle.role in ("app", "cad-service")}
    report.check(len(helpers) == 2 and owners == expected,
                 "Expected the CAD worker in the companion and the CAD service only, found "
                 f"{[str(helper.relative_to(app)) for helper in helpers]}")
    signings: Dict[str, Signing] = {}
    for helper in helpers:
        owner_info = read_info(helper.parents[2]) or {}
        owner_identifier = owner_info.get("CFBundleIdentifier")
        relative = str(helper.relative_to(app))
        signing = tools.signing(helper)
        signings[relative] = signing
        report.check(isinstance(owner_identifier, str) and signing.identifier == owner_identifier + HELPER_SUFFIX,
                     f"{relative} signing identifier must be {owner_identifier}{HELPER_SUFFIX}")
        report.check(signing.hardened_runtime, f"{relative} is not signed with the hardened runtime")
        for problem in entitlement_problems("helper", tools.entitlements(helper)):
            report.fail(f"{relative} {problem}")
    return signings


def check_privacy_manifests(report: Report, bundles: List[Bundle]) -> int:
    present = 0
    for bundle in bundles:
        location = bundle.path / "Contents/Resources" / PRIVACY_MANIFEST
        if not location.is_file():
            report.fail(f"{bundle.name} has no Contents/Resources/{PRIVACY_MANIFEST}; if the project's synchronized "
                        "folder did not copy it, register the file by hand in the target's Resources phase")
            continue
        manifest = read_plist(location)
        if manifest is None:
            report.fail(f"{bundle.name} {PRIVACY_MANIFEST} is not a readable property list dictionary")
            continue
        present += 1
        for problem in privacy_manifest_problems(manifest, bundle.role):
            report.fail(f"{bundle.name} {PRIVACY_MANIFEST} {problem}")
    return present


def inspect_archive(archive: Path, tools: Any) -> Report:
    report = Report()
    applications = sorted((archive / "Products/Applications").glob("*.app"))
    report.check(len(applications) == 1, "Archive must contain exactly one application")
    if len(applications) != 1:
        return report
    app = applications[0]
    stray = [item for item in (archive / "Products").rglob("*") if item.is_file() and app not in item.parents]
    report.check(not stray, f"Archive contains products outside the app (enable SKIP_INSTALL): {[str(item) for item in stray[:5]]}")

    info = read_info(app)
    if info is None:
        report.fail(f"{app.name} has no readable Contents/Info.plist")
        return report
    check_app_info(report, info, app)
    bundles = find_bundles(report, app, info)
    check_info_plists(report, bundles)
    check_extension_attributes(report, bundles)

    report.check("com.apple.quarantine" not in tools.quarantine(app),
                 "Remove com.apple.quarantine attributes; App Store Connect rejects them")
    machos = [path for path in app.rglob("*") if path.is_file() and not path.is_symlink() and is_macho(path)]
    for path in machos:
        architectures = tools.architectures(path)
        report.check(architectures == EXPECTED_ARCHITECTURES,
                     f"{path.relative_to(app)} architectures {sorted(architectures)} != {sorted(EXPECTED_ARCHITECTURES)}")
    valid, message = tools.verify(app)
    report.check(valid, "codesign --verify --deep --strict failed: " + message)

    signings = check_entitlements_and_signatures(report, tools, bundles)
    helper_signings = check_helpers(report, tools, app, bundles)
    check_signing_teams(report, {**signings, **helper_signings})
    check_cad_service(report, bundles, signings)
    manifests = check_privacy_manifests(report, bundles)
    frameworks = sorted(app.glob("Contents/Frameworks/*.framework"))
    if frameworks:
        report.note("Embedded frameworks are scanned for required-reason APIs on their own; confirm each has a privacy "
                    f"manifest or that the app's covers it: {[framework.name for framework in frameworks]}")

    report.check(any(app.rglob("OCCT-Notices/LICENSE_LGPL_21.txt")), "OCCT license notices are not bundled")
    report.check((app / "Contents/Resources/ColorSchemes-Notices/NOTICE.md").is_file(),
                 "The color scheme palette notice is not bundled")
    report.check(any((archive / "dSYMs").glob("*.dSYM")), "Archive has no dSYMs for crash symbolication")
    report.summary = (f"Release archive checks passed for {app.name} {info.get('CFBundleShortVersionString')} "
                      f"({info.get('CFBundleVersion')}): {len(machos)} Mach-O files, {len(bundles)} sandboxed bundles, "
                      f"{len(helper_signings)} helpers, {manifests} privacy manifests. Run Validate App in Organizer next.")
    return report


def main(archive: Path, tools: Optional[Any] = None) -> int:
    report = inspect_archive(archive, tools if tools is not None else SystemTools())
    for note in report.notes:
        print("note:", note)
    if report.failures:
        print(f"Release archive check failed ({len(report.failures)}):", file=sys.stderr)
        for failure in report.failures:
            print(" -", failure, file=sys.stderr)
        return 1
    print(report.summary)
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2 or not sys.argv[1].endswith(".xcarchive"):
        raise SystemExit("usage: check_release_archive.py PATH.xcarchive")
    raise SystemExit(main(Path(sys.argv[1])))
