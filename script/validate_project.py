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

from build_metadata import compile_metadata
from check_release_archive import PRIVACY_MANIFEST, privacy_manifest_problems

ROOT = Path(__file__).resolve().parents[1]
# Identifier namespaces of other installed products whose file types this app also accepts.
THIRD_PARTY_ALIAS_PREFIXES = ("com.quicklookpro.",)
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


def validate_cad_graph(objects, targets):
    """Keep the byte-only CAD service private to the preview's target graph."""
    products = {name: {objects[item]["productName"] for item in target["packageProductDependencies"]}
                for name, target in targets.items()}
    check(products["CADImportService"] == {"PreviewCADFormats", "PreviewContracts"},
          "CAD service must link only CAD formats and numeric contracts")
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
            check(phase["inputFileListPaths"] == ["$(SRCROOT)/.build/cad/bundle-inputs.xcfilelist"], "CAD helper inputs must be explicit")
            check(phase["outputFileListPaths"] == ["$(SRCROOT)/.build/cad/bundle-outputs.xcfilelist"], "CAD helper outputs must be explicit")
            check(phase["inputPaths"] == ["$(SRCROOT)/script/embed_cad_worker.py", "$(SRCROOT)/Configuration/CADWorker.entitlements"],
                  "CAD helper script and inherited entitlements must be declared inputs")
            check(phase["shellScript"].strip() == '/usr/bin/python3 "${SRCROOT}/script/embed_cad_worker.py"',
                  "CAD helper must use the owned embedding script")
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


def validate():
    catalog = json.loads((ROOT / "Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json").read_text())
    formats = catalog["formats"]
    check(formats, "Format catalog cannot be empty")
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
    thumbnail_types = list(dict.fromkeys(content_type for item in formats if item["thumbnail"] != "none"
                                         for content_type in item["contentTypes"]))
    imported = []
    for item in formats:
        optional = item.get("optionalContentTypes", [])
        check(set(optional).issubset(item["contentTypes"]), "Optional types must be explicit catalog aliases")
        check(item["contentTypes"][0] not in optional, "The canonical type cannot be optional")
        # Another product's identifiers (decision 004) are accepted only as optional aliases, so a
        # file that app has typed still reaches this format; they are never canonical or declared.
        foreign = [t for t in item["contentTypes"] if t.startswith(THIRD_PARTY_ALIAS_PREFIXES)]
        check(set(foreign).issubset(optional), f"{item['id']}: third-party aliases must be optional")
        check(not {d["identifier"] for d in item.get("importedContentTypes", [])}.intersection(foreign),
              f"{item['id']}: never declare another product's type")
        for declaration in item.get("importedContentTypes", []):
            identifier = declaration["identifier"]
            check(identifier in item["contentTypes"], "Imported types must belong to their format")
            check(not identifier.startswith(("public.", "dyn.", "com.apple.")), "Do not import a system type as a custom declaration")
            check(set(declaration["extensions"]).issubset(item["extensions"]), "Imported suffixes must belong to their format")
            imported.append({
                "UTTypeIdentifier": identifier,
                "UTTypeConformsTo": [declaration["conformsTo"]],
                "UTTypeDescription": declaration["descriptionKey"],
                "UTTypeReferenceURL": declaration["referenceURL"],
                "UTTypeTagSpecification": {"public.filename-extension": declaration["extensions"]},
            })
    check(len({item["UTTypeIdentifier"] for item in imported}) == len(imported), "Duplicate imported content type declarations")
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
    check(plist(ROOT / "Configuration/Preview-Info.plist").get("CADImportServiceIdentifier") == service_identifier,
          "Preview must connect to the embedded CAD service's configured identity")
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
    validate_cad_graph(objects, targets)
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
        metadata_phases = [objects[phase] for phase in target["buildPhases"]
                           if objects[phase].get("name") == "Compile localized branding metadata"]
        expected_outputs = {f"$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/{language}.lproj/InfoPlist.strings"
                            for language in metadata_languages}
        if is_service:
            check(not metadata_phases, "Private CAD service does not compile app-facing branding metadata")
            check({objects[group]["path"] for group in target["fileSystemSynchronizedGroups"]} == {"Native/CADImportService"},
                  "CAD service must compile its own listener sources")
        else:
            check(len(metadata_phases) == 1 and set(metadata_phases[0]["outputPaths"]) == expected_outputs,
                  f"{target_name} must declare every localized metadata output for script sandbox access")
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
            metadata = json.loads(subprocess.check_output(["/usr/bin/plutil", "-convert", "json", "-o", "-", str(Path(directory) / role / "en.lproj/InfoPlist.strings")]))
            check('Renamed "Example"' in metadata["CFBundleDisplayName"], "Generated branding must preserve the configured name")
            for declaration in imported:
                key = declaration["UTTypeDescription"]
                expected = strings[key]["localizations"]["en"]["stringUnit"]["value"]
                check(metadata.get(key) == expected, f"{role} imported type description must use the owning localized catalog name")
    print(f"Validated {len(targets)} Xcode targets, {len(embedded)} embedded extensions, sandboxed CAD service graph, "
          f"{len(PRIVACY_MANIFESTS)} privacy manifests, {len(formats)} catalog formats and localized branding metadata.")


def main():
    try:
        validate()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"Project validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
