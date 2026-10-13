#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/Packages/PreviewCore"
DERIVED_DIR="$ROOT_DIR/.build/xcode"
MODE="${1:-run}"
CONFIGURATION="${PREVIEW_BUILD_CONFIGURATION:-Debug}"
SWIFT_PACKAGE_ARGS=(--package-path "$PACKAGE_DIR" --build-system native)

usage() {
  cat <<'HELP'
usage: ./script/build_and_run.sh [mode]
  run (default)      Stop, build and launch the signed companion and embedded extensions
  --debug           Launch signed app and attach LLDB
  --logs            Launch signed app and stream its process logs
  --telemetry       Launch signed app and stream its bundle subsystem logs
  --verify          Launch signed app and verify its process exists
  --check           Validate project, manifests, catalog and localization resources (runs --check-static first)
  --check-static    Portable static gate, no Xcode needed: manifests, samples, localization, shell syntax,
                    decision numbers, wall-clock test names, ownership tool and Swift syntax (tree-sitter)
  --test            Run SwiftPM tests and isolated companion model checks (CLT supported)
  --test-cad        Prepare the pinned native CAD worker and run its geometry/process checks (an explicit developer
                    command: it works while PREV_INCLUDE_CAD is NO, and nothing else builds the worker then)
  --check-compiler  Build shared package and typecheck all host/extension Swift sources
  --build-companion Link/stage a CLT-only companion prototype in dist/PrevPrototype.app
  --run-companion   Build and launch that prototype (private settings; no extensions)
  --build-unsigned  Compile the actual Xcode app/extension targets without installing
  --archive         Archive the signed Release app for Apple silicon and check it for upload problems
  --archive-unsigned Archive the Release app without signing: proves the project, the CAD helper (when
                    PREV_INCLUDE_CAD is YES) and the archive composition on a host without certificates
                    (the hosted runner's dry run)
  --export          Export the signed archive for App Store Connect into .build/export and read back the
                    helper identities that survive the distribution re-signing
  --upload          Export the signed archive again with the upload destination: App Store Connect receives
                    the build and TestFlight processes it
  --help            Show this usage

App Store Connect API key (optional, for --archive/--export/--upload on a machine without a signed-in Xcode):
set PREV_ASC_KEY_PATH (the .p8 file), PREV_ASC_KEY_ID and PREV_ASC_ISSUER_ID; xcodebuild then runs with
-allowProvisioningUpdates and that key. --upload requires the three values. On a Mac whose Xcode is signed in
to the team, PREV_ALLOW_PROVISIONING_UPDATES=1 passes -allowProvisioningUpdates alone so the signed-in account
fetches or creates the distribution profiles; it does not satisfy --upload.

Full Xcode providing Swift 6.2+ is required for actual app/extension builds. Set DEVELOPER_DIR to a full
Xcode installation if the system selection is Command Line Tools. The script
does not change that selection. Signed launch requires Configuration/Local.xcconfig
with your team and identifiers; copy Local.xcconfig.example as a starting point.
PREVIEW_BUILD_CONFIGURATION selects Debug (default) or Release.

PREV_INCLUDE_CAD (Configuration/Base.xcconfig, overridden by Local.xcconfig or the environment) says whether the
product carries the IGES and STEP previews. NO (version 1.0, decision 028) builds without the CAD helper, the CAD
service and the OCCT notices and never prepares the OCCT kernel; YES restores them and needs script/build_cad_worker.py.
HELP
}

# The portable static gate is plain Python 3 and also runs on Linux. Use the interpreter the other modes use
# and fall back to python3 on PATH where /usr/bin/python3 does not exist.
run_static_gate() {
  local python="/usr/bin/python3"
  [[ -x "$python" ]] || python="$(command -v python3 || true)"
  if [[ -z "$python" ]]; then echo "python3 was not found." >&2; return 1; fi
  "$python" "$ROOT_DIR/script/check_static.py"
}

# YES or NO from PREV_INCLUDE_CAD, read in one place (script/cad_mode.py). It is passed to xcodebuild so that Xcode
# and these scripts agree even when the environment, not a file, chose the value.
include_cad() {
  /usr/bin/python3 "$ROOT_DIR/script/cad_mode.py"
}

if [[ $# -gt 1 ]]; then usage >&2; exit 2; fi
case "$CONFIGURATION" in Debug|Release) ;; *) echo "Configuration must be Debug or Release." >&2; exit 2 ;; esac
case "$MODE" in
  --help|-h) usage; exit 0 ;;
  --check-static)
    run_static_gate
    exit 0
    ;;
  --check)
    run_static_gate
    /usr/bin/python3 "$ROOT_DIR/script/sync_manifests.py" --check
    /usr/bin/python3 "$ROOT_DIR/script/validate_project.py"
    /usr/bin/python3 "$ROOT_DIR/tools/validate_localization.py"
    /usr/bin/python3 "$ROOT_DIR/tools/test_localization.py"
    /usr/bin/python3 "$ROOT_DIR/script/generate_appearance_samples.py" --check
    /usr/bin/xcrun swift "$ROOT_DIR/script/generate_app_icon.swift" --check
    /bin/bash -n "$ROOT_DIR/script/build_and_run.sh"
    exit 0
    ;;
  --test-cad)
    /usr/bin/python3 "$ROOT_DIR/script/build_cad_worker.py" --architecture "$(uname -m)" --test
    exit 0
    ;;
  --test)
    TEST_ARGS=("${SWIFT_PACKAGE_ARGS[@]}" --scratch-path "$PACKAGE_DIR/.build/validation")
    PREVIEW_DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
    PREVIEW_SWIFT_BIN="$(dirname "$(/usr/bin/xcrun --find swiftc)")"
    PREVIEW_TEST_FRAMEWORKS="$PREVIEW_DEVELOPER_DIR/Library/Developer/Frameworks"
    PREVIEW_TEST_PLUGIN_DIR="$PREVIEW_SWIFT_BIN/../lib/swift/host/plugins/testing"
    # CLT 6.4 does not discover its own Testing framework/plugin in native builds.
    # Full Xcode uses SwiftPM's normal SDK discovery; no global paths are changed.
    if [[ "$PREVIEW_DEVELOPER_DIR" == */CommandLineTools && -d "$PREVIEW_TEST_FRAMEWORKS/Testing.framework" && -d "$PREVIEW_TEST_PLUGIN_DIR" ]]; then
      TEST_ARGS+=(-Xswiftc -F -Xswiftc "$PREVIEW_TEST_FRAMEWORKS" -Xswiftc -external-plugin-path -Xswiftc "$PREVIEW_TEST_PLUGIN_DIR#$PREVIEW_SWIFT_BIN/swift-plugin-server" -Xlinker -F -Xlinker "$PREVIEW_TEST_FRAMEWORKS" -Xlinker -rpath -Xlinker "$PREVIEW_TEST_FRAMEWORKS")
    fi
    # Tests with real timing requirements (reply liveness, the production parser deadline, file-monitor
    # debounce windows and page-decode scheduling with five-second waits) run alone in a serial pass:
    # CPU-bound tests from other suites can otherwise hold the shared thread pool. Hosted runs 109 and 111
    # lost two and four of the live-reload and image-page waits to that contention.
    WALL_CLOCK_SUITES='PipelineWallClockTests|ThumbnailWallClockTests|ThumbnailHostLivenessTests|MermaidWallClockTests|LiveReload|ImagePageSchedulerTests|NativeImagePagesViewTests'
    EXPECTED_SERIAL_TESTS=74
    SERIAL_FILTER="\.($WALL_CLOCK_SUITES)/"
    SERIAL_INVENTORY="$PACKAGE_DIR/.build/validation/serial-test-inventory.txt"
    mkdir -p "$(dirname "$SERIAL_INVENTORY")"
    /usr/bin/xcrun swift test list "${TEST_ARGS[@]}" > "$SERIAL_INVENTORY"
    /usr/bin/python3 "$ROOT_DIR/script/check_serial_test_inventory.py" "$SERIAL_INVENTORY" --suites "$WALL_CLOCK_SUITES" --expected "$EXPECTED_SERIAL_TESTS"
    /usr/bin/xcrun swift test "${TEST_ARGS[@]}" --skip-build --skip "$SERIAL_FILTER"
    /usr/bin/xcrun swift test "${TEST_ARGS[@]}" --skip-build --no-parallel --filter "$SERIAL_FILTER"
    TEST_BIN_DIR="$(/usr/bin/xcrun swift build "${SWIFT_PACKAGE_ARGS[@]}" --scratch-path "$PACKAGE_DIR/.build/validation" --show-bin-path)"
    /usr/bin/python3 "$ROOT_DIR/script/test_companion_models.py" "$TEST_BIN_DIR"
    /usr/bin/python3 "$ROOT_DIR/script/test_appearance_interactions.py" "$TEST_BIN_DIR"
    /usr/bin/python3 "$ROOT_DIR/script/check_adversarial_corpus.py" "$TEST_BIN_DIR"
    exit 0
    ;;
  --check-compiler)
    /usr/bin/xcrun swift build "${SWIFT_PACKAGE_ARGS[@]}"
    BIN_DIR="$(/usr/bin/xcrun swift build "${SWIFT_PACKAGE_ARGS[@]}" --show-bin-path)"
    SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
    ARCHITECTURE="$(uname -m)"
    CAD_MODE="$(include_cad)"
    for SOURCE_DIR in Apps/PrevApp Extensions/PrevPreviewExtension Extensions/PrevThumbnailExtension Native/CADImportService; do
      SOURCES=()
      while IFS= read -r SOURCE; do SOURCES+=("$SOURCE"); done < <(find "$ROOT_DIR/$SOURCE_DIR" -type f -name '*.swift' | sort)
      if [[ ${#SOURCES[@]} -eq 0 ]]; then echo "No Swift sources in $SOURCE_DIR" >&2; exit 1; fi
      FLAGS=(-typecheck -sdk "$SDK_PATH" -target "$ARCHITECTURE-apple-macosx15.0" -swift-version 6 -strict-concurrency=complete -default-isolation nonisolated -I "$BIN_DIR" -I "$BIN_DIR/Modules")
      while IFS= read -r FLAG; do [[ -z "$FLAG" ]] || FLAGS+=("$FLAG"); done < <(/usr/bin/python3 "$ROOT_DIR/script/package_link.py" "$BIN_DIR")
      if [[ "$SOURCE_DIR" != Native/CADImportService ]]; then FLAGS+=(-parse-as-library); fi
      if [[ "$SOURCE_DIR" != Apps/* ]]; then FLAGS+=(-application-extension); fi
      # The companion and the preview extension register the CAD adapters under this condition.
      if [[ "$CAD_MODE" == YES && ( "$SOURCE_DIR" == Apps/PrevApp || "$SOURCE_DIR" == Extensions/PrevPreviewExtension ) ]]; then FLAGS+=(-D PREV_INCLUDE_CAD); fi
      /usr/bin/xcrun swiftc "${FLAGS[@]}" "${SOURCES[@]}"
      echo "Typechecked $SOURCE_DIR (does not validate Xcode resource linking/signing/Finder)."
    done
    exit 0
    ;;
  --build-companion|--run-companion)
    # stage_companion.py reads the same setting: it adds the helper and compiles the CAD registration only for YES.
    if [[ "$(include_cad)" == YES ]]; then
      /usr/bin/python3 "$ROOT_DIR/script/build_cad_worker.py" --architecture "$(uname -m)"
    fi
    if [[ "$MODE" == --run-companion ]]; then pkill -u "$(id -u)" -x PrevPrototype >/dev/null 2>&1 || true; fi
    /usr/bin/xcrun swift build "${SWIFT_PACKAGE_ARGS[@]}"
    BIN_DIR="$(/usr/bin/xcrun swift build "${SWIFT_PACKAGE_ARGS[@]}" --show-bin-path)"
    /usr/bin/python3 "$ROOT_DIR/script/stage_companion.py" "$BIN_DIR"
    if [[ "$MODE" == --run-companion ]]; then
      /usr/bin/open -n "$ROOT_DIR/dist/PrevPrototype.app"
      sleep 1
      pgrep -u "$(id -u)" -x PrevPrototype >/dev/null
      echo "Companion prototype process verified; Quick Look extensions are absent."
    fi
    exit 0
    ;;
  run|--debug|--logs|--telemetry|--verify|--build-unsigned|--archive|--archive-unsigned|--export|--upload) ;;
  *) usage >&2; exit 2 ;;
esac

if ! /usr/bin/xcrun --find xcodebuild >/dev/null 2>&1; then
  echo "Full Xcode is unavailable in the selected developer directory. Install/select Xcode providing Swift 6.2+ or set DEVELOPER_DIR; --test and --check-compiler work with Command Line Tools providing Swift 6.2+." >&2
  exit 1
fi
# App Store Connect API key, when supplied: automatic signing fetches or creates the distribution profiles.
ASC_ARGS=()
if [[ -n "${PREV_ASC_KEY_PATH:-}" || -n "${PREV_ASC_KEY_ID:-}" || -n "${PREV_ASC_ISSUER_ID:-}" ]]; then
  if [[ ! -f "${PREV_ASC_KEY_PATH:-}" || -z "${PREV_ASC_KEY_ID:-}" || -z "${PREV_ASC_ISSUER_ID:-}" ]]; then
    echo "PREV_ASC_KEY_PATH (an existing .p8 file), PREV_ASC_KEY_ID and PREV_ASC_ISSUER_ID must all be set together." >&2
    exit 2
  fi
  ASC_ARGS=(-allowProvisioningUpdates -authenticationKeyPath "$PREV_ASC_KEY_PATH" -authenticationKeyID "$PREV_ASC_KEY_ID" -authenticationKeyIssuerID "$PREV_ASC_ISSUER_ID")
elif [[ -n "${PREV_ALLOW_PROVISIONING_UPDATES:-}" ]]; then
  # Signed-in Xcode account instead of a key: the profiles come from that session.
  ASC_ARGS=(-allowProvisioningUpdates)
fi
ARCHIVE_PATH="$ROOT_DIR/.build/archive/Release.xcarchive"
ARCHIVE_SETTINGS="$ROOT_DIR/.build/archive/build-settings.json"
# Release 1.0 ships for Apple silicon only (Base.xcconfig ARCHS); archive that slice on any host.
CAD_MODE="$(include_cad)"
ARCHIVE_ARGS=(-project "$ROOT_DIR/Prev.xcodeproj" -scheme Prev -configuration Release -destination "generic/platform=macOS" -derivedDataPath "$ROOT_DIR/.build/xcode-archive" ARCHS=arm64 PREV_INCLUDE_CAD="$CAD_MODE")

# Writes the export options for App Store Connect. $1 is the destination: export (a signed package and app
# under .build/export for inspection) or upload (App Store Connect receives the build; TestFlight processes it).
write_export_options() {
  local destination="$1" team
  team="$(/usr/bin/python3 "$ROOT_DIR/script/validate_signing.py" "$ARCHIVE_SETTINGS" team)"
  EXPORT_OPTIONS="$ROOT_DIR/.build/archive/ExportOptions-$destination.plist"
  cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>$destination</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>$team</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST
}

if [[ "$MODE" == --archive || "$MODE" == --archive-unsigned ]]; then
  # With NO nothing here needs the OCCT kernel, the pinned archive or the generated file lists.
  if [[ "$CAD_MODE" == YES ]]; then
    /usr/bin/python3 "$ROOT_DIR/script/build_cad_worker.py" --architecture arm64
  fi
  mkdir -p "$ROOT_DIR/.build/archive"
  UNSIGNED_ARGS=()
  if [[ "$MODE" == --archive ]]; then
    /usr/bin/xcrun xcodebuild "${ARCHIVE_ARGS[@]}" -showBuildSettings -json > "$ARCHIVE_SETTINGS"
    /usr/bin/python3 "$ROOT_DIR/script/validate_signing.py" "$ARCHIVE_SETTINGS"
  else
    # No identity is needed to prove that the project archives: a helper (YES only) is embedded unsigned and the
    # archive is never uploaded. The signing-dependent checks are skipped, not weakened.
    UNSIGNED_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=)
  fi
  # A signed archive is the only local copy of a build's debug symbols, and an uploaded build cannot be archived
  # again. Set the previous one aside under its version and build number instead of deleting it; an unsigned
  # archive is a throwaway proof and is replaced.
  if [[ -f "$ARCHIVE_PATH/Info.plist" ]]; then
    PREVIOUS_IDENTITY="$(/usr/bin/plutil -extract ApplicationProperties.SigningIdentity raw "$ARCHIVE_PATH/Info.plist" 2>/dev/null || true)"
    if [[ -n "$PREVIOUS_IDENTITY" ]]; then
      PREVIOUS_VERSION="$(/usr/bin/plutil -extract ApplicationProperties.CFBundleShortVersionString raw "$ARCHIVE_PATH/Info.plist")"
      PREVIOUS_BUILD="$(/usr/bin/plutil -extract ApplicationProperties.CFBundleVersion raw "$ARCHIVE_PATH/Info.plist")"
      KEPT_ARCHIVE="$ROOT_DIR/.build/archive/SpacePane-$PREVIOUS_VERSION-build$PREVIOUS_BUILD.xcarchive"
      if [[ -e "$KEPT_ARCHIVE" ]]; then KEPT_ARCHIVE="${KEPT_ARCHIVE%.xcarchive}-$(/bin/date +%Y%m%d-%H%M%S).xcarchive"; fi
      /bin/mv "$ARCHIVE_PATH" "$KEPT_ARCHIVE"
      echo "Kept the previous signed archive: $KEPT_ARCHIVE"
    fi
  fi
  rm -rf "$ARCHIVE_PATH"
  /usr/bin/xcrun xcodebuild "${ARCHIVE_ARGS[@]}" ${ASC_ARGS[@]+"${ASC_ARGS[@]}"} ${UNSIGNED_ARGS[@]+"${UNSIGNED_ARGS[@]}"} -archivePath "$ARCHIVE_PATH" archive
  # Xcode registers the archive's intermediate app with Launch Services and its Quick Look extensions with
  # PlugInKit. They would then compete with the development build (and later an installed store build) in
  # Finder, so unregister both and remove that copy. PlugInKit keeps a record of a deleted path otherwise.
  # Xcode usually moves the intermediate app into the archive itself, so the records name a path that no longer
  # exists: unregister by the recorded path, not by what is on disk.
  INTERMEDIATE_APP="$ROOT_DIR/.build/xcode-archive/Build/Intermediates.noindex/ArchiveIntermediates/Prev/InstallationBuildProductsLocation/Applications"
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  /usr/bin/pluginkit -mADvvv 2>/dev/null | sed -n 's/^[[:space:]]*Path = //p' | while IFS= read -r STALE_EXTENSION; do
    [[ "$STALE_EXTENSION" == "$ROOT_DIR/.build/xcode-archive/"* ]] || continue
    /usr/bin/pluginkit -r "$STALE_EXTENSION" || true
  done
  for ARCHIVED_PRODUCT in "$ARCHIVE_PATH"/Products/Applications/*.app; do
    "$LSREGISTER" -u "$INTERMEDIATE_APP/$(basename "$ARCHIVED_PRODUCT")" >/dev/null 2>&1 || true
  done
  for STALE_APP in "$INTERMEDIATE_APP"/*.app; do
    [[ -d "$STALE_APP" ]] || continue
    "$LSREGISTER" -u "$STALE_APP" || true
    rm -rf "$STALE_APP"
  done
  if [[ "$MODE" == --archive ]]; then
    /usr/bin/python3 "$ROOT_DIR/script/check_release_archive.py" "$ARCHIVE_PATH"
    echo "Archive: $ARCHIVE_PATH (next: --export to inspect the distribution signing, --upload for TestFlight)."
  else
    ARCHIVED_APP="$(/bin/ls -d "$ARCHIVE_PATH"/Products/Applications/*.app | head -n 1)"
    echo "Unsigned archive composition of $ARCHIVED_APP:"
    /usr/bin/find "$ARCHIVED_APP" \( -name "*.appex" -o -name "*.xpc" -o -name "CADWorker" -o -name "PrivacyInfo.xcprivacy" -o -name "embedded.provisionprofile" \) | sed "s|$ARCHIVED_APP/||" | sort
    for PLIST in "$ARCHIVED_APP"/Contents/Info.plist "$ARCHIVED_APP"/Contents/PlugIns/*.appex/Contents/Info.plist; do
      printf '%s: %s (%s) minimum %s\n' "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$PLIST")" "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$PLIST")" "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$PLIST")" "$(/usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "$PLIST" 2>/dev/null || true)"
    done
    if [[ "$CAD_MODE" == YES ]]; then
      echo "Unsigned archive completed: the project, the CAD helper and the archive composition build on this host. Nothing about signing, provisioning or upload was validated."
    else
      echo "Unsigned archive completed: the project and the archive composition build on this host; PREV_INCLUDE_CAD is NO, so the archive carries no CAD helper, service or OCCT notices. Nothing about signing, provisioning or upload was validated."
    fi
  fi
  exit 0
fi
if [[ "$MODE" == --export || "$MODE" == --upload ]]; then
  if [[ ! -d "$ARCHIVE_PATH" || ! -f "$ARCHIVE_SETTINGS" ]]; then
    echo "No signed archive at $ARCHIVE_PATH; run --archive first." >&2
    exit 1
  fi
  if [[ "$MODE" == --upload ]]; then
    if [[ -z "${PREV_ASC_KEY_ID:-}" ]]; then
      echo "--upload needs PREV_ASC_KEY_PATH, PREV_ASC_KEY_ID and PREV_ASC_ISSUER_ID (an App Store Connect API key)." >&2
      exit 2
    fi
    write_export_options upload
    rm -rf "$ROOT_DIR/.build/upload"
    /usr/bin/xcrun xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportOptionsPlist "$EXPORT_OPTIONS" -exportPath "$ROOT_DIR/.build/upload" ${ASC_ARGS[@]+"${ASC_ARGS[@]}"}
    echo "Uploaded to App Store Connect. TestFlight processes the build; export compliance and the test information are answered in App Store Connect."
    exit 0
  fi
  write_export_options export
  rm -rf "$ROOT_DIR/.build/export"
  /usr/bin/xcrun xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportOptionsPlist "$EXPORT_OPTIONS" -exportPath "$ROOT_DIR/.build/export" ${ASC_ARGS[@]+"${ASC_ARGS[@]}"}
  # `ls` fails when nothing matches; under pipefail that would end the script before the package branch.
  EXPORTED_APP="$(/bin/ls -d "$ROOT_DIR"/.build/export/*.app 2>/dev/null | head -n 1 || true)"
  if [[ -z "$EXPORTED_APP" ]]; then
    # An App Store Connect export is a signed installer package only: expand it to read the bundles back.
    EXPORTED_PKG="$(/bin/ls -d "$ROOT_DIR"/.build/export/*.pkg 2>/dev/null | head -n 1 || true)"
    if [[ -z "$EXPORTED_PKG" ]]; then
      echo "The export produced neither an .app nor a .pkg under .build/export." >&2
      /bin/ls -la "$ROOT_DIR/.build/export"
      exit 1
    fi
    /usr/sbin/pkgutil --check-signature "$EXPORTED_PKG" | grep -E "Status|^ +1\. "
    rm -rf "$ROOT_DIR/.build/export-expanded"
    /usr/sbin/pkgutil --expand-full "$EXPORTED_PKG" "$ROOT_DIR/.build/export-expanded"
    EXPORTED_APP="$(/usr/bin/find "$ROOT_DIR/.build/export-expanded" -maxdepth 3 -name "*.app" | head -n 1)"
    if [[ -z "$EXPORTED_APP" ]]; then
      echo "No .app inside $EXPORTED_PKG." >&2
      exit 1
    fi
  fi
  echo "Exported app: $EXPORTED_APP (build $(/usr/bin/plutil -extract CFBundleVersion raw -o - "$EXPORTED_APP/Contents/Info.plist"))"
  # Distribution re-signs every bundle: confirm the helper identities and the sandbox survived it.
  for BUNDLE in "$EXPORTED_APP" "$EXPORTED_APP"/Contents/PlugIns/*.appex "$EXPORTED_APP"/Contents/PlugIns/*.appex/Contents/XPCServices/*.xpc; do
    [[ -e "$BUNDLE" ]] || continue
    /usr/bin/codesign --verify --strict "$BUNDLE"
    /usr/bin/codesign -d --verbose=2 "$BUNDLE" 2>&1 | grep -E "^(Identifier|TeamIdentifier|Authority)=" | head -n 4
  done
  WORKERS_FOUND=0
  for WORKER in "$EXPORTED_APP"/Contents/Helpers/CADWorker "$EXPORTED_APP"/Contents/PlugIns/*.appex/Contents/XPCServices/*.xpc/Contents/Helpers/CADWorker; do
    [[ -f "$WORKER" ]] || continue
    WORKERS_FOUND=$((WORKERS_FOUND + 1))
    /usr/bin/codesign -d --verbose=2 --entitlements - "$WORKER" 2>&1 | grep -E "^(Identifier|TeamIdentifier)=|app-sandbox|inherit" | head -n 6
  done
  if [[ "$CAD_MODE" == YES ]]; then
    [[ "$WORKERS_FOUND" -eq 2 ]] || { echo "Expected the CAD worker in the companion and the CAD service, found $WORKERS_FOUND." >&2; exit 1; }
  else
    # Version 1.0 (decision 028): the export must carry no CAD helper at all, so finding one is the failure.
    [[ "$WORKERS_FOUND" -eq 0 ]] || { echo "PREV_INCLUDE_CAD is NO but the export carries $WORKERS_FOUND CAD worker(s)." >&2; exit 1; }
    echo "This build carries no CAD helper (PREV_INCLUDE_CAD is NO): no CADWorker, no CADImportService.xpc."
  fi
  echo "Export: $ROOT_DIR/.build/export (Validate App in Organizer, or --upload for TestFlight)."
  exit 0
fi
if [[ "$CAD_MODE" == YES ]]; then
  /usr/bin/python3 "$ROOT_DIR/script/build_cad_worker.py" --architecture "$(uname -m)"
fi
mkdir -p "$DERIVED_DIR"
# Only the host CAD worker (YES only) is prepared above. Xcode 27 rejects `-arch` combined with a destination,
# so the destination names the host architecture and ARCHS keeps Release builds single-architecture.
XCODE_ARGS=(-project "$ROOT_DIR/Prev.xcodeproj" -scheme Prev -configuration "$CONFIGURATION" -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$DERIVED_DIR" ARCHS="$(uname -m)" PREV_INCLUDE_CAD="$CAD_MODE")
if [[ "$MODE" == --build-unsigned ]]; then
  /usr/bin/xcrun xcodebuild "${XCODE_ARGS[@]}" CODE_SIGNING_ALLOWED=NO build
  echo "Unsigned build completed; no extension installation or Finder routing was validated."
  exit 0
fi

SETTINGS_PATH="$DERIVED_DIR/build-settings.json"
/usr/bin/xcrun xcodebuild "${XCODE_ARGS[@]}" -showBuildSettings -json > "$SETTINGS_PATH"
/usr/bin/python3 "$ROOT_DIR/script/validate_signing.py" "$SETTINGS_PATH"
APP_BUNDLE="$(/usr/bin/python3 "$ROOT_DIR/script/validate_signing.py" "$SETTINGS_PATH" bundle)"
APP_PROCESS="$(/usr/bin/python3 "$ROOT_DIR/script/validate_signing.py" "$SETTINGS_PATH" executable)"
BUNDLE_ID="$(/usr/bin/python3 "$ROOT_DIR/script/validate_signing.py" "$SETTINGS_PATH" identifier)"
pkill -u "$(id -u)" -x "$APP_PROCESS" >/dev/null 2>&1 || true
/usr/bin/xcrun xcodebuild "${XCODE_ARGS[@]}" build
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
for EXTENSION in "$APP_BUNDLE"/Contents/PlugIns/*.appex; do /usr/bin/codesign --verify --strict "$EXTENSION"; done
/usr/bin/open -n "$APP_BUNDLE"
case "$MODE" in
  run) ;;
  --debug)
    sleep 1
    APP_PID="$(pgrep -u "$(id -u)" -x "$APP_PROCESS" | head -n 1)"
    /usr/bin/xcrun lldb -p "$APP_PID"
    ;;
  --logs) /usr/bin/log stream --debug --style compact --predicate "process == \"$APP_PROCESS\" OR subsystem == \"$BUNDLE_ID\" OR subsystem BEGINSWITH \"$BUNDLE_ID.\"" ;;
  --telemetry) /usr/bin/log stream --debug --style compact --predicate "subsystem == \"$BUNDLE_ID\" OR subsystem BEGINSWITH \"$BUNDLE_ID.\"" ;;
  --verify) sleep 1; pgrep -u "$(id -u)" -x "$APP_PROCESS" >/dev/null; echo "Companion process verified. Finder routing still requires host checks." ;;
esac
