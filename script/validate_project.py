#!/usr/bin/env python3
"""Validate catalog/manifest consistency and the actual Xcode target graph."""
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from xml.parsers.expat import ExpatError

from build_cad_worker import NOTICE_FOLDERS
from build_metadata import compile_metadata, shipped_languages
from cad_mode import include_cad as configured_include_cad
from check_release_archive import PRIVACY_MANIFEST, privacy_manifest_problems

ROOT = Path(__file__).resolve().parents[1]
# The two catalog entries version 1.0 leaves out (decision 028); Configuration/CADFormatCatalogEntries.json keeps them
# verbatim for the day PREV_INCLUDE_CAD is YES again.
CAD_FORMAT_IDS = {"cad.iges", "cad.step"}
PARKED_CAD_ENTRIES = "Configuration/CADFormatCatalogEntries.json"
# What the project's CAD settings resolve to for each value of PREV_INCLUDE_CAD.
CAD_SETTINGS = {
    "YES": {"PREV_CAD_SWIFT_CONDITION": "PREV_INCLUDE_CAD", "PREV_CAD_EXCLUDED_SOURCE_NAMES": "",
            "PREV_CAD_SERVICE_DEBUG_FORMAT": "dwarf-with-dsym",
            "PREV_CAD_BUNDLE_INPUTS": "$(SRCROOT)/.build/cad/bundle-inputs.xcfilelist",
            "PREV_CAD_BUNDLE_OUTPUTS": "$(SRCROOT)/.build/cad/bundle-outputs.xcfilelist"},
    "NO": {"PREV_CAD_SWIFT_CONDITION": "", "PREV_CAD_EXCLUDED_SOURCE_NAMES": "CADImportService.xpc",
           "PREV_CAD_SERVICE_DEBUG_FORMAT": "dwarf",
           "PREV_CAD_BUNDLE_INPUTS": "$(SRCROOT)/script/notices-inputs.xcfilelist",
           "PREV_CAD_BUNDLE_OUTPUTS": "$(SRCROOT)/script/notices-outputs.xcfilelist"},
}
CAD_EMBED_SCRIPT = ('if [ "${PREV_INCLUDE_CAD}" = YES ]; then\n  /usr/bin/python3 "${SRCROOT}/script/embed_cad_worker.py"\n'
                    'else\n  /usr/bin/python3 "${SRCROOT}/script/embed_notices.py"\nfi')
# Targets that compile the CAD registration under the PREV_INCLUDE_CAD condition, and the one that would embed the service.
CAD_CONDITION_TARGETS = {"Prev", "PrevPreviewExtension"}
CAD_SERVICE_PRODUCT = "CADImportService.xpc"
# Identifier namespaces of other developers' products. They are never listed, as optional aliases or otherwise: the
# identifiers belong to that product and App Review may read them as targeting it (decision 004, amended 2026-10-17).
FOREIGN_IDENTIFIER_PREFIXES = ("com.quicklookpro.",)
# macOS declares these two system types with no UTTypeConformsTo, so they reach neither public.data nor public.item.
# Launch Services resolves a file's type only among types that conform to public.data, so an imported declaration
# that stops at one of them is never chosen for its extension and Quick Look never asks this app
# (docs/validation/uti-resolution-2026-10-17.md). Such a declaration must list public.data as a parent as well.
PARENTS_WITHOUT_DATA = ("public.database", "public.archive")
# Each bundle's privacy manifest sits in a folder the project synchronizes into that target, so the build copies it
# into Contents/Resources without a build-file entry (decision 027, Q-45). The roles are the ones
# check_release_archive.py uses for the manifest's required categories.
PRIVACY_MANIFESTS = {
    "Prev": ("app", "Apps/PrevApp/Resources/" + PRIVACY_MANIFEST),
    "PrevPreviewExtension": ("preview", "Extensions/PrevPreviewExtension/" + PRIVACY_MANIFEST),
    "PrevThumbnailExtension": ("thumbnail", "Extensions/PrevThumbnailExtension/" + PRIVACY_MANIFEST),
    "CADImportService": ("cad-service", "Native/CADImportService/" + PRIVACY_MANIFEST),
}


def check(condition, message):
    if not condition:
        raise ValueError(message)


def plist(path):
    with path.open("rb") as handle:
        return plistlib.load(handle)


def xcconfig(path):
    """Read plain KEY = value assignments; comments start at a line's leading //."""
    values = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith(("//", "#")) and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def resolve_setting(values, name):
    """Expand `$(NAME)` references, innermost first, so `$(A_$(MODE))` selects by value as Xcode does."""
    text = values.get(name, "")
    for _ in range(20):
        # References to settings the xcconfig does not define (SRCROOT, TARGET_BUILD_DIR) stay as written.
        match = next((item for item in re.finditer(r"\$\(([A-Za-z0-9_]+)\)", text) if item[1] in values), None)
        if not match:
            return text.strip()
        text = text[:match.start()] + values[match[1]] + text[match.end():]
    raise ValueError(f"{name} does not resolve")


def validate_cad_catalog(root, formats, include_cad):
    """The catalog carries the CAD entries exactly when PREV_INCLUDE_CAD is YES; the other mode keeps them parked."""
    present = [item for item in formats if item["id"].startswith("cad.")]
    parked_path = root / PARKED_CAD_ENTRIES
    parked = json.loads(parked_path.read_text()) if parked_path.is_file() else None
    if include_cad:
        check({item["id"] for item in present} == CAD_FORMAT_IDS and len(present) == len(CAD_FORMAT_IDS),
              "PREV_INCLUDE_CAD is YES: the format catalog must contain exactly the cad.iges and cad.step entries "
              f"(found {sorted(item['id'] for item in present)}); restore them from {PARKED_CAD_ENTRIES}")
        check(parked is None or sorted(parked, key=lambda item: item["id"]) == sorted(present, key=lambda item: item["id"]),
              f"The catalog's CAD entries differ from {PARKED_CAD_ENTRIES}")
        return present
    check(not present, "PREV_INCLUDE_CAD is NO: the format catalog must have no cad.* entry, found "
                       f"{sorted(item['id'] for item in present)}; they belong in {PARKED_CAD_ENTRIES}")
    check(parked_path.is_file(), f"{PARKED_CAD_ENTRIES} must keep the removed cad.iges and cad.step entries")
    check(isinstance(parked, list) and all(isinstance(item, dict) for item in parked)
          and sorted(item.get("id") for item in parked) == sorted(CAD_FORMAT_IDS),
          f"{PARKED_CAD_ENTRIES} must be an array holding exactly the cad.iges and cad.step descriptors")
    return parked


def cad_service_key_problems(info, base, service_identifier):
    """The preview Info.plist names the CAD service through PREV_CAD_SERVICE_IDENTIFIER: the service's identity when
    the product carries CAD, an empty value when it does not (review finding 22). `base` holds Base.xcconfig; both
    modes are resolved here, whichever one the current build uses."""
    problems = []
    if info.get("CADImportServiceIdentifier") != "$(PREV_CAD_SERVICE_IDENTIFIER)":
        problems.append("Preview-Info.plist must set CADImportServiceIdentifier to $(PREV_CAD_SERVICE_IDENTIFIER), "
                        "so the service is named only when PREV_INCLUDE_CAD is YES")
    for mode, wanted in (("YES", service_identifier), ("NO", "")):
        values = {**base, "PREV_INCLUDE_CAD": mode, "__SERVICE__": service_identifier}
        expected = resolve_setting(values, "__SERVICE__") if wanted else ""
        if resolve_setting(values, "PREV_CAD_SERVICE_IDENTIFIER") != expected:
            problems.append("PREV_CAD_SERVICE_IDENTIFIER must resolve to the embedded CAD service's identity when "
                            "PREV_INCLUDE_CAD is YES and to nothing when it is NO "
                            f"(found {resolve_setting(values, 'PREV_CAD_SERVICE_IDENTIFIER')!r} for {mode})")
    return problems


def validate_cad_wiring(root, objects, targets, include_cad):
    """The Xcode project and the configuration drop or keep the CAD product, helper and notices as the setting says."""
    mode = "YES" if include_cad else "NO"
    base = xcconfig(root / "Configuration/Base.xcconfig")
    check(base.get("PREV_INCLUDE_CAD") in ("YES", "NO"), "Configuration/Base.xcconfig must set PREV_INCLUDE_CAD to YES or NO")
    check("SWIFT_ACTIVE_COMPILATION_CONDITIONS" not in base,
          "The compilation condition belongs to the companion and the preview extension only; do not set it in the xcconfig")
    values = {**base, "PREV_INCLUDE_CAD": mode}
    for name, expected in CAD_SETTINGS[mode].items():
        check(resolve_setting(values, name) == expected, f"{name} must resolve to {expected!r} when PREV_INCLUDE_CAD is {mode}")
    # Only the companion and the preview extension get the Swift condition; only the preview extension would embed the service.
    for name, target in targets.items():
        for configuration in objects[target["buildConfigurationList"]]["buildConfigurations"]:
            settings = objects[configuration]["buildSettings"]
            conditions = settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS")
            check((conditions == "$(inherited) $(PREV_CAD_SWIFT_CONDITION)") == (name in CAD_CONDITION_TARGETS),
                  f"{name} must {'add' if name in CAD_CONDITION_TARGETS else 'not add'} the PREV_INCLUDE_CAD compilation condition")
            check("PREV_INCLUDE_CAD" not in (conditions or "").replace("PREV_CAD_SWIFT_CONDITION", ""),
                  f"{name} must not name PREV_INCLUDE_CAD in its compilation conditions; the xcconfig selects it")
            if name == "CADImportService" and objects[configuration]["name"] == "Release":
                check(settings.get("DEBUG_INFORMATION_FORMAT") == "$(PREV_CAD_SERVICE_DEBUG_FORMAT)",
                      "The CAD service's release build must take its debug format from PREV_CAD_SERVICE_DEBUG_FORMAT, "
                      "so the build without CAD leaves no dSYM for it in the archive")
            check((settings.get("EXCLUDED_SOURCE_FILE_NAMES") == "$(PREV_CAD_EXCLUDED_SOURCE_NAMES)") == (name == "PrevPreviewExtension"),
                  f"Only PrevPreviewExtension excludes the CAD service from its copy phase through PREV_CAD_EXCLUDED_SOURCE_NAMES ({name})")
    for item in objects.values():
        if item["isa"] == "PBXBuildFile" and item.get("fileRef") and objects[item["fileRef"]].get("path") == CAD_SERVICE_PRODUCT:
            check(resolve_setting(values, "PREV_CAD_EXCLUDED_SOURCE_NAMES") == ("" if include_cad else CAD_SERVICE_PRODUCT),
                  f"The extension's copy phase must {'embed' if include_cad else 'exclude'} {CAD_SERVICE_PRODUCT}")
    # The file lists the no-CAD phase reads and writes name the colour-scheme notice and nothing else, so a clean
    # checkout needs no .build/cad, and they follow the folder's contents.
    check((root / "script/embed_notices.py").is_file(), "script/embed_notices.py is missing")
    colour = [pair for pair in NOTICE_FOLDERS if pair[0] == "ColorSchemes"]
    check(len(colour) == 1, "script/build_cad_worker.py NOTICE_FOLDERS must still name the ColorSchemes pair")
    folder, name = colour[0]
    files = sorted(path.name for path in (root / "ThirdPartyNotices" / folder).iterdir() if path.is_file())
    check("NOTICE.md" in files, "ThirdPartyNotices/ColorSchemes/NOTICE.md is the notice every build must carry")
    check("ColorSchemes-Notices" in (root / "script/embed_notices.py").read_text() and name == "ColorSchemes-Notices",
          "script/embed_notices.py must copy ColorSchemes into ColorSchemes-Notices")
    resources = "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/" + name
    inputs = sorted((root / "script/notices-inputs.xcfilelist").read_text().split())
    outputs = sorted((root / "script/notices-outputs.xcfilelist").read_text().split())
    check(inputs == sorted(f"$(SRCROOT)/ThirdPartyNotices/{folder}/{file}" for file in files),
          "script/notices-inputs.xcfilelist must list every file of ThirdPartyNotices/ColorSchemes and nothing else")
    check(outputs == sorted([resources] + [f"{resources}/{file}" for file in files]),
          "script/notices-outputs.xcfilelist must list the ColorSchemes-Notices folder and each file in it, and nothing else")
    for target_name in ("Prev", "CADImportService"):
        phases = [objects[phase] for phase in targets[target_name]["buildPhases"] if objects[phase].get("name") == "Embed CAD worker"]
        check(len(phases) == 1, f"{target_name} needs its Embed CAD worker phase")
        phase = phases[0]
        check(phase["inputFileListPaths"] == ["$(PREV_CAD_BUNDLE_INPUTS)"] and phase["outputFileListPaths"] == ["$(PREV_CAD_BUNDLE_OUTPUTS)"],
              f"{target_name}: the embed phase must read its file lists through PREV_CAD_BUNDLE_INPUTS and PREV_CAD_BUNDLE_OUTPUTS")
        check(phase["shellScript"].strip() == CAD_EMBED_SCRIPT,
              f"{target_name}: the embed phase must run embed_cad_worker.py for YES and embed_notices.py for NO")
        check(phase["inputPaths"] == ["$(SRCROOT)/script/embed_cad_worker.py", "$(SRCROOT)/script/embed_notices.py",
                                      "$(SRCROOT)/Configuration/CADWorker.entitlements"],
              f"{target_name}: the embed phase must declare both scripts and the helper entitlements as inputs")


def validate_cad_graph(objects, targets, include_cad):
    """Keep the byte-only CAD service private to the preview's target graph."""
    products = {name: {objects[item]["productName"] for item in target["packageProductDependencies"]}
                for name, target in targets.items()}
    check(products["CADImportService"] == {"PreviewCADFormats", "PreviewContracts"},
          "CAD service must link only CAD formats and numeric contracts")
    # The companion and the preview extension link the CAD importer client only in a build with CAD. Without it the
    # client would be dormant code in two shipped executables (App Review Guideline 2.5.19), so bringing CAD back
    # adds the product to both targets again (decision 028, "Bringing CAD back").
    for target_name in ("Prev", "PrevPreviewExtension"):
        linked = "PreviewCADFormats" in products[target_name]
        files = [objects[item] for phase in targets[target_name]["buildPhases"]
                 if objects[phase]["isa"] == "PBXFrameworksBuildPhase" for item in objects[phase]["files"]]
        linked_in_phase = any(objects.get(item.get("productRef"), {}).get("productName") == "PreviewCADFormats" for item in files)
        if include_cad:
            check(linked and linked_in_phase, f"{target_name} must link PreviewCADFormats when PREV_INCLUDE_CAD is YES: "
                  "add the package product to the target and its Frameworks phase (decision 028, \"Bringing CAD back\")")
        else:
            check(not linked and not linked_in_phase, f"{target_name} must not link PreviewCADFormats when PREV_INCLUDE_CAD "
                  "is NO: the CAD importer client would ship as dormant code (Guideline 2.5.19)")
    # Content thumbnails run the shared pipeline with the standard adapters; CAD thumbnails stay generic,
    # so the thumbnail extension must never link the CAD importer client.
    check(products["PrevThumbnailExtension"] == {"PreviewContracts", "PreviewCore", "PreviewFileAccess", "PreviewFormats",
                                                 "PreviewPreferences", "PreviewRenderers", "PreviewThumbnails"},
          "Thumbnails must link the content pipeline and drawing products, and never the CAD importer client")
    check(all("PreviewFileAccess" in products[name] for name in ("PrevPreviewExtension", "PrevThumbnailExtension")),
          "Both Quick Look extensions must directly link their file-access policy bootstrap")
    expected_dependencies = {
        "Prev": {"PrevPreviewExtension", "PrevThumbnailExtension"},
        "PrevPreviewExtension": {"CADImportService"},
        "PrevThumbnailExtension": set(), "CADImportService": set(),
    }
    service_product = targets["CADImportService"]["productReference"]
    service_reference = objects[service_product]
    check(service_reference.get("path") == "CADImportService.xpc"
          and service_reference.get("explicitFileType") == "wrapper.xpc-service"
          and service_reference.get("sourceTree") == "BUILT_PRODUCTS_DIR", "Incorrect CAD service product reference")
    for name, target in targets.items():
        dependencies = set()
        for dependency_id in target["dependencies"]:
            dependency = objects[dependency_id]
            check(dependency["isa"] == "PBXTargetDependency", "Incorrect target dependency type")
            dependencies.add(objects[dependency["target"]]["name"])
            proxy = objects[dependency["targetProxy"]]
            check(proxy["isa"] == "PBXContainerItemProxy" and proxy["remoteGlobalIDString"] == dependency["target"],
                  f"{name} dependency proxy must identify the same target")
        check(dependencies == expected_dependencies[name], f"{name} target dependencies drifted from the CAD service graph")
        phases = [objects[phase] for phase in target["buildPhases"]]
        linked_products = {objects[objects[build_file]["productRef"]]["productName"]
                           for phase in phases if phase["isa"] == "PBXFrameworksBuildPhase"
                           for build_file in phase["files"] if "productRef" in objects[build_file]}
        check(linked_products == products[name], f"{name} package products must also be linked in Frameworks")
        worker_phases = [phase for phase in phases if phase.get("name") == "Embed CAD worker"]
        expected_worker_count = 1 if name in {"Prev", "CADImportService"} else 0
        check(len(worker_phases) == expected_worker_count, "CAD helper belongs only in companion and sandboxed service")
        for phase in worker_phases:
            check(phase["isa"] == "PBXShellScriptBuildPhase", "CAD helper must use its audited embedding script")
            # The file lists, the inputs and the script are checked per mode by validate_cad_wiring.
            check(phase["inputFileListPaths"] and phase["outputFileListPaths"], "CAD helper inputs and outputs must be explicit")
        copies = [phase for phase in phases if phase["isa"] == "PBXCopyFilesBuildPhase"]
        service_copies = [(phase, build_file) for phase in copies for build_file in phase["files"]
                          if objects[build_file].get("fileRef") == service_product]
        check(len(service_copies) == (1 if name == "PrevPreviewExtension" else 0), "CAD service must be embedded only in the preview")
        if name == "PrevPreviewExtension":
            check(len(copies) == 1, "Preview must have only its explicit CAD service copy phase")
            phase, build_file = service_copies[0]
            check(str(phase["dstSubfolderSpec"]) == "16" and phase["dstPath"] == "$(CONTENTS_FOLDER_PATH)/XPCServices",
                  "CAD service must be embedded in preview Contents/XPCServices")
            check(phase["files"] == [build_file], "Preview XPC copy phase must contain only the owned CAD service")
            check("CodeSignOnCopy" in objects[build_file].get("settings", {}).get("ATTRIBUTES", []), "CAD service must be signed on copy")
        elif name in {"PrevThumbnailExtension", "CADImportService"}:
            check(not copies, f"{name} must not embed other products")


def validate_privacy_manifests(root, objects, targets):
    """Every bundle has a suitable privacy manifest that the project copies into it (decision 027, Q-45)."""
    for target_name, (role, relative) in PRIVACY_MANIFESTS.items():
        path = root / relative
        check(path.is_file(), f"{target_name} needs a privacy manifest at {relative}")
        try:
            manifest = plist(path)
        except (OSError, ValueError, ExpatError) as error:
            raise ValueError(f"{relative} is not a readable property list: {error}")
        problems = privacy_manifest_problems(manifest, role)
        check(not problems, f"{relative}: " + "; ".join(problems))
        containing = []
        for group_id in targets[target_name].get("fileSystemSynchronizedGroups", []):
            group = objects[group_id]
            try:
                containing.append((group, Path(relative).relative_to(group["path"]).as_posix()))
            except ValueError:
                continue
        check(containing, f"{relative} must sit in a folder that the {target_name} target synchronizes, "
                          "or the project does not copy it into the bundle")
        for group, inside in containing:
            for exception_id in group.get("exceptions", []):
                check(inside not in objects[exception_id].get("membershipExceptions", []),
                      f"{relative} is excluded from the {target_name} target by a membership exception")


def declared_parents(declaration):
    """The parents of an imported declaration: `conformsTo` is one identifier or a non-empty list of distinct ones."""
    value = declaration["conformsTo"]
    parents = [value] if isinstance(value, str) else value
    identifier = declaration["identifier"]
    check(isinstance(parents, list) and parents and all(isinstance(item, str) and item for item in parents)
          and len(set(parents)) == len(parents),
          f"{identifier}: conformsTo must be an identifier or a list of distinct identifiers")
    check("public.data" in parents or not set(parents).intersection(PARENTS_WITHOUT_DATA),
          f"{identifier}: parents {parents} stop at a system type with no parent, so the type never reaches public.data "
          "and Launch Services never resolves its extension; list public.data as well")
    return parents


def validate_catalog(formats):
    """Check the catalog by itself; returns the preview types, the thumbnail types and the imported declarations."""
    check(len({item["id"] for item in formats}) == len(formats), "Duplicate format IDs")
    types = [content_type for item in formats for content_type in item["contentTypes"]]
    owners = {}
    for item in formats:
        for content_type in item["contentTypes"]:
            if content_type in owners:
                check(item.get("filenameAliases") and not item["extensions"],
                      "A shared content type requires explicit filename-specific routing without suffix fallback")
            else:
                owners[content_type] = item["id"]
    types = list(dict.fromkeys(types))
    # macOS types every file without an extension as exactly public.data. One text-only format may
    # claim it for previews; it has no suffixes or names and never registers thumbnails, so system
    # icons stay. Quick Look matches identifiers exactly, so this does not capture conforming types.
    check(not {"public.item", "public.content"}.intersection(types), "Blanket content-type registration is prohibited")
    root_owners = [item for item in formats if "public.data" in item["contentTypes"]]
    check(len(root_owners) <= 1 and all(
        item["contentTypes"] == ["public.data"] and not item["extensions"] and not item.get("filenameAliases")
        and not item.get("filenamePrefixes") and item["thumbnail"] == "none" and item["presentation"] == "text"
        for item in root_owners), "public.data may identify only the extension-free text format, without thumbnails")
    # Only the `content` policy registers a type with the thumbnail extension. A `generic` format would receive
    # SpacePane's glyph instead of the system icon with no observed benefit (decision 022, amended 2026-10-17).
    thumbnail_types = list(dict.fromkeys(content_type for item in formats if item["thumbnail"] == "content"
                                         for content_type in item["contentTypes"]))
    imported = []
    for item in formats:
        optional = item.get("optionalContentTypes", [])
        check(set(optional).issubset(item["contentTypes"]), "Optional types must be explicit catalog aliases")
        check(item["contentTypes"][0] not in optional, "The canonical type cannot be optional")
        foreign = [t for t in item["contentTypes"] if t.startswith(FOREIGN_IDENTIFIER_PREFIXES)]
        check(not foreign, f"{item['id']}: never list another developer's content type identifier ({foreign[:1]}); "
                           "files are reached through system and owner-declared types (decision 004)")
        for declaration in item.get("importedContentTypes", []):
            identifier = declaration["identifier"]
            check(identifier in item["contentTypes"], "Imported types must belong to their format")
            check(not identifier.startswith(("public.", "dyn.", "com.apple.")), "Do not import a system type as a custom declaration")
            check(set(declaration["extensions"]).issubset(item["extensions"]), "Imported suffixes must belong to their format")
            imported.append({
                "UTTypeIdentifier": identifier,
                "UTTypeConformsTo": declared_parents(declaration),
                "UTTypeDescription": declaration["descriptionKey"],
                "UTTypeReferenceURL": declaration["referenceURL"],
                "UTTypeTagSpecification": {"public.filename-extension": declaration["extensions"]},
            })
    check(len({item["UTTypeIdentifier"] for item in imported}) == len(imported), "Duplicate imported content type declarations")
    return types, thumbnail_types, imported


def validate():
    catalog = json.loads((ROOT / "Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json").read_text())
    formats = catalog["formats"]
    include_cad = configured_include_cad()
    check(formats, "Format catalog cannot be empty")
    cad_entries = validate_cad_catalog(ROOT, formats, include_cad)
    types, thumbnail_types, imported = validate_catalog(formats)
    package = json.loads(subprocess.check_output(["/usr/bin/xcrun", "swift", "package", "--package-path", str(ROOT / "Packages/PreviewCore"), "dump-package"]))
    exported_products = {item["name"] for item in package["products"]}
    check(exported_products == {"PreviewContracts", "PreviewFileAccess", "PreviewCore", "PreviewFormats", "PreviewCADFormats", "PreviewPreferences", "PreviewRenderers", "PreviewThumbnails"}, "Swift package exported-product inventory drifted")
    for target in package["targets"]:
        if target["type"] != "regular":
            continue
        flags = [flag for setting in target["settings"] if setting["kind"].get("unsafeFlags") for flag in setting["kind"]["unsafeFlags"]["_0"]]
        extension_flag = "-fapplication-extension" if target.get("publicHeadersPath") else "-application-extension"
        check(extension_flag in flags, f"Shared target {target['name']} must enforce extension-safe APIs")
        if target.get("resources"):
            expected_name = f"{package['name']}_{target['name']}"
            resource_names = set()
            for source in (ROOT / "Packages/PreviewCore/Sources" / target["name"]).rglob("*.swift"):
                names = re.findall(r'\bbundle(?:Name|Filename)\s*=\s*"([^\"]+)"', source.read_text())
                resource_names.update(name[:-7] if name.endswith(".bundle") else name for name in names)
            check(resource_names == {expected_name}, f"Owned resource bundle name for {target['name']} must match the SwiftPM manifest")
    for filename, point, principal in [("Preview-Info.plist", "preview", "PreviewViewController"), ("Thumbnail-Info.plist", "thumbnail", "ThumbnailProvider")]:
        info = plist(ROOT / "Configuration" / filename)
        extension = info["NSExtension"]
        declared = extension["NSExtensionAttributes"]["QLSupportedContentTypes"]
        expected_types = types if point == "preview" else thumbnail_types
        check(len(declared) == len(set(declared)) and set(declared) == set(expected_types), f"{filename} content types drifted from FormatCatalog.json")
        check(extension["NSExtensionPointIdentifier"] == f"com.apple.quicklook.{point}", f"Incorrect {point} extension point")
        check(extension["NSExtensionPrincipalClass"] == f"$(PRODUCT_MODULE_NAME).{principal}", f"Incorrect {point} principal class")
        if not include_cad:
            # Version 1.0 declares no STEP or IGES type: the Info.plists are generated from the catalog without them.
            parked_types = {content_type for item in cad_entries for content_type in item["contentTypes"]}
            check(not parked_types.intersection(declared), f"{filename} declares STEP or IGES content types although PREV_INCLUDE_CAD is NO")
            check(not {item["identifier"] for entry in cad_entries for item in entry.get("importedContentTypes", [])}
                  .intersection(item["UTTypeIdentifier"] for item in info.get("UTImportedTypeDeclarations", [])),
                  f"{filename} imports STEP or IGES type declarations although PREV_INCLUDE_CAD is NO")
        check(not info.get("UTExportedTypeDeclarations"), "Do not export ownership of system content types")
        check(info.get("UTImportedTypeDeclarations", []) == imported, f"{filename} imported type declarations drifted from the catalog")
        check(info["PreviewDisplayName"] == "$(PREV_DISPLAY_NAME)", "Branding must resolve through build configuration")
        check(info["PreviewAppGroupIdentifier"] == "$(APP_GROUP_IDENTIFIER)", "App Group must resolve through build configuration")
    for role in ["app", "preview", "thumbnail"]:
        entitlements = plist(ROOT / "Configuration" / f"{role}.entitlements")
        check(entitlements.get("com.apple.security.app-sandbox") is True, f"{role} must be sandboxed")
        check(entitlements.get("com.apple.security.application-groups") == ["$(APP_GROUP_IDENTIFIER)"], f"{role} must use the same configured group")
        check(not entitlements.get("com.apple.security.network.client") and not entitlements.get("com.apple.security.network.server"), "Prototype must not enable network access")
        if role == "app":
            check(entitlements.get("com.apple.security.files.user-selected.read-write") is True,
                  "Companion needs user-selected export access for inert appearance themes")
            check(not entitlements.get("com.apple.security.files.user-selected.read-only"), "Do not declare conflicting companion access keys")
        else:
            check(not entitlements.get("com.apple.security.files.user-selected.read-write"), "Extension source access must remain read-only")
    check(plist(ROOT / "Configuration/CADWorker.entitlements") == {
        "com.apple.security.app-sandbox": True, "com.apple.security.inherit": True
    }, "CAD helper must use only sandbox inheritance entitlements")
    check(plist(ROOT / "Configuration/CADImportService.entitlements") == {"com.apple.security.app-sandbox": True},
          "CAD service must use only its own App Sandbox entitlement")
    service_info = plist(ROOT / "Configuration/CADImportService-Info.plist")
    check(service_info.get("CFBundlePackageType") == "XPC!" and service_info.get("XPCService", {}).get("ServiceType") == "Application",
          "CAD service must be a private application XPC service")
    service_identifier = service_info["CFBundleIdentifier"]
    check(service_identifier == "$(PREVIEW_BASE_BUNDLE_IDENTIFIER).cad-import", "CAD service identity must derive from the configured base")
    problems = cad_service_key_problems(plist(ROOT / "Configuration/Preview-Info.plist"),
                                        xcconfig(ROOT / "Configuration/Base.xcconfig"), service_identifier)
    check(not problems, "; ".join(problems))
    check(service_info.get("CADAllowedClientIdentifier") == "$(PREVIEW_BASE_BUNDLE_IDENTIFIER).preview"
          and service_info.get("CADAllowedClientTeamIdentifier") == "$(DEVELOPMENT_TEAM)",
          "CAD service peer requirements must derive from the preview identity and signing team")
    app = plist(ROOT / "Configuration/App-Info.plist")
    check(not app.get("UTExportedTypeDeclarations"), "Do not export ownership of supported third-party content types")
    check(app.get("UTImportedTypeDeclarations", []) == imported, "App imported type declarations drifted from the catalog")
    check(app["PreviewDisplayName"] == "$(PREV_DISPLAY_NAME)" and app["PreviewAppGroupIdentifier"] == "$(APP_GROUP_IDENTIFIER)", "App host configuration drift")
    check(app.get("ITSAppUsesNonExemptEncryption") is False, "Declare export compliance: the app uses no non-exempt encryption")
    check(app.get("LSApplicationCategoryType") == "$(PREV_APP_CATEGORY)" and app.get("NSHumanReadableCopyright") == "$(PREV_COPYRIGHT)",
          "App Store category and copyright must resolve through branding configuration")
    branding = xcconfig(ROOT / "Configuration/Branding.xcconfig")
    check(re.fullmatch(r"public\.app-category\.[a-z-]+", branding.get("PREV_APP_CATEGORY", "")), "PREV_APP_CATEGORY must be a Mac App Store category UTI")
    check(branding.get("PREV_COPYRIGHT", "").strip(), "PREV_COPYRIGHT must name the rights holder")
    project = json.loads(subprocess.check_output(["/usr/bin/plutil", "-convert", "json", "-o", "-", str(ROOT / "Prev.xcodeproj/project.pbxproj")]))
    objects = project["objects"]
    targets = {item["name"]: item for item in objects.values() if item["isa"] == "PBXNativeTarget"}
    target_product_types = {"Prev": "application", "PrevPreviewExtension": "app-extension",
                            "PrevThumbnailExtension": "app-extension", "CADImportService": "xpc-service"}
    check(set(targets) == set(target_product_types), "Expected companion, preview, thumbnail and private CAD service targets")
    validate_cad_graph(objects, targets, include_cad)
    validate_cad_wiring(ROOT, objects, targets, include_cad)
    validate_privacy_manifests(ROOT, objects, targets)
    for target_name, target in targets.items():
        is_app = target_name == "Prev"
        is_service = target_name == "CADImportService"
        check(target["productType"] == "com.apple.product-type." + target_product_types[target_name], "Incorrect product type")
        for configuration in objects[target["buildConfigurationList"]]["buildConfigurations"]:
            settings = objects[configuration]["buildSettings"]
            check(settings["APPLICATION_EXTENSION_API_ONLY"] == ("NO" if is_app else "YES"), "Extension-safe API checking must be enabled")
            check((ROOT / settings["INFOPLIST_FILE"]).is_file(), "Missing Info.plist reference")
            if is_service:
                check(settings["INFOPLIST_FILE"] == "Configuration/CADImportService-Info.plist"
                      and settings.get("CODE_SIGN_ENTITLEMENTS") == "Configuration/CADImportService.entitlements",
                      "CAD service must use its own Info.plist and sandbox-only entitlements in every configuration")
                check(settings["PRODUCT_BUNDLE_IDENTIFIER"] == service_identifier, "CAD service target and Info.plist identities must match")
                check(settings.get("ENABLE_APP_SANDBOX", "YES") == "YES" and settings["SKIP_INSTALL"] == "YES",
                      "CAD service must stay sandboxed and installed only through the preview")
            elif is_app:
                check(settings.get("ASSETCATALOG_COMPILER_APPICON_NAME") == "AppIcon"
                      and (ROOT / "Apps/PrevApp/Assets.xcassets/AppIcon.appiconset/Contents.json").is_file(),
                      "Companion must compile its AppIcon asset catalog; run script/generate_app_icon.swift")
            elif target_name == "PrevPreviewExtension":
                check(settings["PRODUCT_BUNDLE_IDENTIFIER"] == service_info["CADAllowedClientIdentifier"],
                      "CAD service's accepted peer identity must match the preview target")
        metadata_languages = set(json.loads((ROOT / "Configuration/Metadata.xcstrings").read_text())["strings"]["metadata.app.name"]["localizations"])
        policy = json.loads((ROOT / "tools/localization/languages.json").read_text())
        check(metadata_languages == set(policy["languages"]), "Bundle metadata must be translated for exactly the chosen languages")
        shipped = shipped_languages()
        metadata_phases = [objects[phase] for phase in target["buildPhases"]
                           if objects[phase].get("name") == "Compile localized branding metadata"]
        expected_outputs = {f"$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/{language}.lproj/InfoPlist.strings"
                            for language in shipped}
        if is_service:
            check(not metadata_phases, "Private CAD service does not compile app-facing branding metadata")
            check({objects[group]["path"] for group in target["fileSystemSynchronizedGroups"]} == {"Native/CADImportService"},
                  "CAD service must compile its own listener sources")
        else:
            check(len(metadata_phases) == 1 and set(metadata_phases[0]["outputPaths"]) == expected_outputs,
                  f"{target_name} must declare exactly the shipped languages' metadata outputs for script sandbox access")
            check("$(SRCROOT)/tools/localization/languages.json" in metadata_phases[0]["inputPaths"],
                  f"{target_name} must read the language ship list as a declared script input")
            info_plist = plistlib.loads((ROOT / settings["INFOPLIST_FILE"]).read_bytes())
            check(info_plist.get("CFBundleLocalizations") == shipped,
                  f"{target_name} must declare the shipped languages in CFBundleLocalizations")
        for group_id in target["fileSystemSynchronizedGroups"]:
            check((ROOT / objects[group_id]["path"]).is_dir(), "Missing synchronized source folder")
        for dependency_id in target["packageProductDependencies"]:
            dependency = objects[dependency_id]
            check(dependency["isa"] == "XCSwiftPackageProductDependency", "Incorrect package dependency type")
            package_path = objects[dependency["package"]]["relativePath"]
            check(package_path == "Packages/PreviewCore" and (ROOT / package_path / "Package.swift").is_file(), "Missing local package")
            check((ROOT / package_path / "Sources" / dependency["productName"]).is_dir(), "Missing package product sources")
    host = targets["Prev"]
    embeds = [objects[phase] for phase in host["buildPhases"] if objects[phase]["isa"] == "PBXCopyFilesBuildPhase"]
    check(len(embeds) == 1 and str(embeds[0]["dstSubfolderSpec"]) == "13", "App extensions must be embedded in PlugIns")
    embedded = {objects[objects[build_file]["fileRef"]]["path"] for build_file in embeds[0]["files"]}
    check(embedded == {"PrevPreviewExtension.appex", "PrevThumbnailExtension.appex"}, "Both app extensions must be embedded")
    for build_file in embeds[0]["files"]:
        check("CodeSignOnCopy" in objects[build_file]["settings"]["ATTRIBUTES"], "Embedded extensions must be signed on copy")
    for item in objects.values():
        if item["isa"] == "PBXFileReference" and item.get("sourceTree") == "<group>":
            check((ROOT / "Configuration" / item["path"]).is_file(), f"Missing referenced configuration: {item['path']}")
    scheme = ET.parse(ROOT / "Prev.xcodeproj/xcshareddata/xcschemes/Prev.xcscheme")
    scheme_targets = {entry.attrib["BlueprintName"] for entry in scheme.findall("./BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference")}
    check(scheme_targets == set(targets), "Shared scheme must include all targets for resolved signing settings")
    with tempfile.TemporaryDirectory() as directory:
        strings = json.loads((ROOT / "Packages/PreviewCore/Sources/PreviewRenderers/Resources/Localizable.xcstrings").read_text())["strings"]
        for role in ["app", "preview", "thumbnail"]:
            compile_metadata(Path(directory) / role, role, 'Renamed "Example"')
            check({item.name for item in (Path(directory) / role).iterdir()} == {f"{language}.lproj" for language in shipped},
                  "Generated bundle metadata must cover the shipped languages and nothing else")
            metadata = json.loads(subprocess.check_output(["/usr/bin/plutil", "-convert", "json", "-o", "-", str(Path(directory) / role / "en.lproj/InfoPlist.strings")]))
            check('Renamed "Example"' in metadata["CFBundleDisplayName"], "Generated branding must preserve the configured name")
            for declaration in imported:
                key = declaration["UTTypeDescription"]
                expected = strings[key]["localizations"]["en"]["stringUnit"]["value"]
                check(metadata.get(key) == expected, f"{role} imported type description must use the owning localized catalog name")
    print(f"Validated {len(targets)} Xcode targets, {len(embedded)} embedded extensions, sandboxed CAD service graph "
          f"(PREV_INCLUDE_CAD is {'YES' if include_cad else 'NO: not embedded'}), "
          f"{len(PRIVACY_MANIFESTS)} privacy manifests, {len(formats)} catalog formats and localized branding metadata.")


def main():
    try:
        validate()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"Project validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
